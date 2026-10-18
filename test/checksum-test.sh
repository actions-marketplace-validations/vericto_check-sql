#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vericto S.A.S.
# SPDX-License-Identifier: Apache-2.0

# Self-test for the install-time integrity gate. Downloads the pinned release
# asset for linux x86_64 and checks that scripts/verify-checksum.sh, the gate
# install.sh relies on, accepts the real checksum and rejects every tampered
# variant; then that install.sh replaces a tampered cached archive.
#
# Usage: test/checksum-test.sh VERSION
set -euo pipefail

version=${1:?usage: $0 VERSION}
root=$(cd "$(dirname "$0")/.." && pwd)
verify="$root/scripts/verify-checksum.sh"
asset=vericto-cli-x86_64-unknown-linux-musl.tar.xz
url="https://github.com/vericto/vericto-cli/releases/download/v$version"

work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/checksum-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
cd "$work"
curl --proto '=https' -fsSL --retry 3 -o "$asset" "$url/$asset"
curl --proto '=https' -fsSL --retry 3 -o "$asset.sha256" "$url/$asset.sha256"

failures=0
expect() { # pass|fail DESCRIPTION FILE SUMFILE
  local want=$1 what=$2 got
  if bash "$verify" "$3" "$4" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    echo "ok   - $what ($got)"
  else
    echo "FAIL - $what: expected $want, got $got"
    failures=$((failures + 1))
  fi
}

expect pass "real archive, real checksum" "$asset" "$asset.sha256"

# Tampered checksum: flip the first hex digit.
first=$(cut -c1 "$asset.sha256")
if [ "$first" = 0 ]; then flip=1; else flip=0; fi
sed "1s/^./$flip/" "$asset.sha256" >tampered.sha256
expect fail "tampered checksum" "$asset" tampered.sha256

# Tampered archive: same name, one extra byte.
mkdir tampered
cp "$asset" tampered/
printf 'x' >>"tampered/$asset"
expect fail "tampered archive" "tampered/$asset" "$asset.sha256"

# A checksum for a different asset must not be accepted.
sed "s/x86_64-unknown-linux-musl/aarch64-unknown-linux-musl/" "$asset.sha256" >other.sha256
expect fail "checksum names another file" "$asset" other.sha256

printf 'not a checksum\n' >garbage.sha256
expect fail "malformed checksum file" "$asset" garbage.sha256
: >empty.sha256
expect fail "empty checksum file" "$asset" empty.sha256

# install.sh must not trust a poisoned cache: it re-downloads and verifies.
cache="$work/cache"
mkdir -p "$cache"
cp "tampered/$asset" "$cache/$asset"
out="$work/out"
: >"$out"
if GITHUB_OUTPUT="$out" GITHUB_PATH="$work/path" RUNNER_TEMP="$work" \
  VA_VERSION="$version" VA_ASSET="$asset" VA_CACHE_DIR="$cache" \
  bash "$root/scripts/install.sh" >"$work/install.log" 2>&1 &&
  bash "$verify" "$cache/$asset" "$asset.sha256" >/dev/null 2>&1 &&
  grep -q 'does not match the release checksum' "$work/install.log"; then
  echo "ok   - poisoned cache is replaced by a verified download"
else
  echo "FAIL - poisoned cache"
  cat "$work/install.log"
  failures=$((failures + 1))
fi

# A release that does not exist must fail the install.
if GITHUB_OUTPUT="$out" RUNNER_TEMP="$work" VA_VERSION=0.0.0 VA_ASSET="$asset" \
  VA_CACHE_DIR="$work/none" bash "$root/scripts/install.sh" >/dev/null 2>&1; then
  echo "FAIL - a missing release installed"
  failures=$((failures + 1))
else
  echo "ok   - a missing release fails the install"
fi

[ "$failures" -eq 0 ] || {
  echo "::error::$failures checksum test(s) failed"
  exit 1
}
