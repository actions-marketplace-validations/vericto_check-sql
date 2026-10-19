#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vericto S.A.S.
# SPDX-License-Identifier: Apache-2.0

# Offline tests for scripts/verify-checksum.sh, the install gate, with local
# fixtures generated here (test/checksum-test.sh does the same against the real
# release asset, over the network).
#
# Usage: bash test/verify-checksum-test.sh
set -euo pipefail

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

verify() { run bash "$SCRIPTS/verify-checksum.sh" "$@"; }

asset=vericto-cli-x86_64-unknown-linux-musl.tar.xz
dir="$TMP/release"
mkdir -p "$dir"
printf 'pretend this is a release archive\n' >"$dir/$asset"
sum=$(bash -c '. "$1"; sha256_of "$2"' lib "$SCRIPTS/lib.sh" "$dir/$asset")
upper=$(printf '%s' "$sum" | tr 'a-f' 'A-F')

sumfile() { # NAME CONTENT: writes a checksum file, prints its path
  printf '%b' "$2" >"$dir/$1"
  printf '%s' "$dir/$1"
}

echo "# accepted"
verify "$dir/$asset" "$(sumfile cargo-dist.sha256 "$sum *$asset\n\n")"
expect_rc 0 "cargo-dist format '<hash> *<name>' plus a blank line"
expect_out "SHA-256 OK: $asset ($sum)" "logs the verified digest"
verify "$dir/$asset" "$(sumfile coreutils.sha256 "$sum  $asset\n")"
expect_rc 0 "sha256sum format '<hash>  <name>'"
verify "$dir/$asset" "$(sumfile bare.sha256 "$sum\n")"
expect_rc 0 "a bare digest without a file name"
verify "$dir/$asset" "$(sumfile upper.sha256 "$upper *$asset\n")"
expect_rc 0 "an upper-case digest"
verify "$dir/$asset" "$(sumfile crlf.sha256 "$sum *$asset\r\n")"
expect_rc 0 "CRLF line endings"
verify "$dir/$asset" "$(sumfile leading-blank.sha256 "\n  \n$sum *$asset\n")"
expect_rc 0 "leading blank lines"

echo "# rejected"
first=${sum:0:1}
if [ "$first" = 0 ]; then flip=1; else flip=0; fi
verify "$dir/$asset" "$(sumfile tampered.sha256 "$flip${sum:1} *$asset\n")"
expect_rc 1 "a tampered digest"
expect_out "checksum mismatch for $asset: expected $flip${sum:1}, got $sum. Refusing to install." "says expected and actual"
cp "$dir/$asset" "$TMP/$asset"
printf 'x' >>"$TMP/$asset"
verify "$TMP/$asset" "$dir/cargo-dist.sha256"
expect_rc 1 "a tampered archive (one extra byte)"
verify "$dir/$asset" "$(sumfile other.sha256 "$sum *vericto-cli-aarch64-unknown-linux-musl.tar.xz\n")"
expect_rc 1 "a checksum for another asset"
expect_out "is for 'vericto-cli-aarch64-unknown-linux-musl.tar.xz', not '$asset'" "names both files"
verify "$dir/$asset" "$(sumfile short.sha256 "${sum:0:63} *$asset\n")"
expect_rc 1 "a 63-digit digest"
expect_out "does not hold a SHA-256 digest" "says the file is malformed"
verify "$dir/$asset" "$(sumfile garbage.sha256 "not a checksum\n")"
expect_rc 1 "a file that is not a checksum"
verify "$dir/$asset" "$(sumfile blank.sha256 "\n \n")"
expect_rc 1 "a checksum file with only blank lines"
verify "$dir/$asset" "$(sumfile empty.sha256 "")"
expect_rc 1 "an empty checksum file"
expect_out "checksum file missing or empty" "says it is empty"
verify "$dir/$asset" "$dir/does-not-exist.sha256"
expect_rc 1 "a missing checksum file"
verify "$dir/missing.tar.xz" "$dir/cargo-dist.sha256"
expect_rc 1 "a missing archive"
expect_out "checksum: file not found: $dir/missing.tar.xz" "names the missing archive"

echo "# usage"
verify "$dir/$asset"
expect_rc 2 "one argument is a usage error"
expect_out "usage:" "prints the usage"
verify "$dir/$asset" "$dir/cargo-dist.sha256" extra
expect_rc 2 "three arguments are a usage error"

finish
