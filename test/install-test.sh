#!/usr/bin/env bash
# Offline tests for scripts/install.sh: download, checksum gate, cache reuse
# and poisoning, network failures, archive contents, the version check and the
# advisory build attestation.
#
# No network: a `curl` stand-in first on PATH maps
# https://github.com/vericto/vericto-cli/releases/download/<tag>/<file> to
# file://$RELEASES/<tag>/<file> and runs the real curl (without --proto, which
# would refuse file://). A missing fixture file is a failed download, as a
# network error or a missing release would be. A `gh` stand-in plays the
# attestation check.
#
# Usage: bash test/install-test.sh
set -euo pipefail

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

RELEASES="$TMP/releases"
SHIM="$TMP/shim"
CURL_LOG="$TMP/curl.log"
GH_LOG="$TMP/gh.log"
mkdir -p "$RELEASES" "$SHIM"
real_curl=$(command -v curl)

cat >"$SHIM/curl" <<'EOF'
#!/usr/bin/env bash
# curl stand-in: serves release downloads from $FAKE_RELEASES over file://.
set -euo pipefail
args=() url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --proto) shift ;;
    https://github.com/vericto/vericto-cli/releases/download/*)
      url=$1
      args+=("file://$FAKE_RELEASES/${1#https://github.com/vericto/vericto-cli/releases/download/}")
      ;;
    https://* | http://*) echo "curl stand-in: refusing a real URL: $1" >&2; exit 7 ;;
    *) args+=("$1") ;;
  esac
  shift
done
printf '%s\n' "$url" >>"$FAKE_CURL_LOG"
exec "$REAL_CURL" "${args[@]}"
EOF
cat >"$SHIM/gh" <<'EOF'
#!/usr/bin/env bash
# gh stand-in: `gh attestation verify` succeeds or fails as FAKE_GH says.
printf '%s|GH_TOKEN=%s\n' "$*" "${GH_TOKEN:-}" >>"$FAKE_GH_LOG"
if [ "${FAKE_GH:-ok}" = ok ]; then echo "Verification succeeded"; exit 0; fi
printf 'line one\nline two\nno attestations found\n' >&2
exit 1
EOF
chmod +x "$SHIM/curl" "$SHIM/gh"

# release TAG ASSET [REPORTED_VERSION] [LAYOUT]: writes ASSET and ASSET.sha256
# under $RELEASES/TAG. LAYOUT: ok (default), no-binary.
release() {
  local tag=$1 asset=$2 reported=${3:-${1#v}} layout=${4:-ok} stage name
  stage=$(mktemp -d "$TMP/stage.XXXXXX")
  mkdir -p "$RELEASES/$tag"
  case "$asset" in
    *.tar.xz | *.tar.gz)
      name=${asset%.tar.*}
      mkdir -p "$stage/$name"
      if [ "$layout" = ok ]; then
        printf '#!/bin/sh\necho "vericto %s"\n' "$reported" >"$stage/$name/vericto"
      else
        printf 'readme\n' >"$stage/$name/README.md"
      fi
      chmod +x "$stage/$name/"* 2>/dev/null || true
      case "$asset" in
        *.tar.xz) (cd "$stage" && COPYFILE_DISABLE=1 tar -cJf "$RELEASES/$tag/$asset" "$name") ;;
        *) (cd "$stage" && COPYFILE_DISABLE=1 tar -czf "$RELEASES/$tag/$asset" "$name") ;;
      esac
      ;;
    *.zip)
      printf '#!/bin/sh\necho "vericto %s"\n' "$reported" >"$stage/vericto.exe"
      python3 -c 'import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z: z.write(sys.argv[2], "vericto.exe")' "$RELEASES/$tag/$asset" "$stage/vericto.exe"
      ;;
  esac
  printf '%s *%s\n\n' "$(bash -c '. "$1"; sha256_of "$2"' lib "$SCRIPTS/lib.sh" "$RELEASES/$tag/$asset")" "$asset" \
    >"$RELEASES/$tag/$asset.sha256"
  rm -rf "$stage"
}

install() { # [VAR=VALUE ...]
  : >"$CURL_LOG"
  : >"$GITHUB_PATH_FILE"
  TEST_PATH="${INSTALL_PATH:-$SHIM:$PATH}" run REAL_CURL="$real_curl" FAKE_RELEASES="$RELEASES" FAKE_CURL_LOG="$CURL_LOG" \
    FAKE_GH_LOG="$GH_LOG" GITHUB_PATH="$GITHUB_PATH_FILE" "$@" bash "$SCRIPTS/install.sh"
}
GITHUB_PATH_FILE="$TMP/github_path"

asset=vericto-cli-x86_64-unknown-linux-musl.tar.xz
release v1.7.1 "$asset"
cache="$TMP/cache/vericto-cli/1.7.1/x86_64-unknown-linux-musl"

echo "# fresh download"
install VA_VERSION=1.7.1 VA_ASSET="$asset" VA_CACHE_DIR="$cache"
expect_rc 0 "installs the pinned release"
bin=$(output_of bin)
expect_eq "$(basename "$bin")" vericto "bin output names the binary"
if [ -x "$bin" ] && [ "$("$bin" --version)" = "vericto 1.7.1" ]; then ok "the binary is executable and is the release"; else not_ok "installed binary" "$bin"; fi
expect_output version 1.7.1 "version output"
expect_eq "$(cat "$GITHUB_PATH_FILE")" "$(dirname "$bin")" "adds the binary's directory to GITHUB_PATH"
expect_out "SHA-256 OK: $asset" "verifies the checksum before extracting"
expect_out "Installed vericto 1.7.1 to" "logs the install"
expect_eq "$(cat "$CURL_LOG")" "https://github.com/vericto/vericto-cli/releases/download/v1.7.1/$asset.sha256
https://github.com/vericto/vericto-cli/releases/download/v1.7.1/$asset" "downloads the checksum, then the archive, from the release"
if [ -f "$cache/$asset" ]; then ok "keeps the verified archive in the cache dir"; else not_ok "cache populated"; fi
expect_out "no token; skipped the build attestation check (the SHA-256 check passed)." "attestation is skipped without a token"
case "$bin" in "$TMP"/vericto-bin.*) ok "the binary lives in a fresh directory under RUNNER_TEMP" ;; *) not_ok "bin location" "$bin" ;; esac
leftover=$(find "$TMP" -maxdepth 1 -name 'vericto-install.*')
expect_eq "$leftover" "" "removes its work directory"

echo "# cache"
install VA_VERSION=1.7.1 VA_ASSET="$asset" VA_CACHE_DIR="$cache"
expect_rc 0 "installs from the cache"
expect_out "Using the cached archive (checksum re-verified)." "re-verifies the cached archive"
expect_eq "$(cat "$CURL_LOG")" "https://github.com/vericto/vericto-cli/releases/download/v1.7.1/$asset.sha256" "downloads only the checksum"
expect_no_out "attestation" "no attestation check for a cached archive"

printf 'x' >>"$cache/$asset"
install VA_VERSION=1.7.1 VA_ASSET="$asset" VA_CACHE_DIR="$cache"
expect_rc 0 "a poisoned cache is replaced"
expect_out "::warning title=Vericto SQL Check::the cached $asset does not match the release checksum; downloading it again." "warns about the poisoned cache"
if run bash "$SCRIPTS/verify-checksum.sh" "$cache/$asset" "$RELEASES/v1.7.1/$asset.sha256" && [ "$rc" = 0 ]; then
  ok "the cache now holds the verified archive"
else
  not_ok "cache after re-download" "$out"
fi

echo "# checksum gate"
release v1.7.2 "$asset"
printf '%s *%s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$asset" >"$RELEASES/v1.7.2/$asset.sha256"
cache2="$TMP/cache-bad"
install VA_VERSION=1.7.2 VA_ASSET="$asset" VA_CACHE_DIR="$cache2"
expect_rc 1 "a checksum mismatch stops the install"
expect_out "checksum mismatch for $asset" "says so"
expect_output bin "" "no bin output"
expect_eq "$(cat "$GITHUB_PATH_FILE")" "" "nothing added to PATH"
if [ -e "$cache2/$asset" ]; then not_ok "an unverified archive was cached"; else ok "the unverified archive is not cached"; fi

echo "# network failures and missing releases"
install VA_VERSION=0.0.0 VA_ASSET="$asset" VA_CACHE_DIR="$TMP/cache-none"
expect_rc 1 "a missing checksum download fails"
expect_out "could not download https://github.com/vericto/vericto-cli/releases/download/v0.0.0/$asset.sha256. Does release v0.0.0 exist?" "names the URL and the release"
mkdir -p "$RELEASES/v1.7.3"
cp "$RELEASES/v1.7.1/$asset.sha256" "$RELEASES/v1.7.3/"
install VA_VERSION=1.7.3 VA_ASSET="$asset" VA_CACHE_DIR="$TMP/cache-3"
expect_rc 1 "a failed archive download fails"
expect_out "could not download https://github.com/vericto/vericto-cli/releases/download/v1.7.3/$asset" "names the archive URL"
run REAL_CURL="$real_curl" FAKE_RELEASES="$RELEASES" FAKE_CURL_LOG="$CURL_LOG" VA_ASSET="$asset" VA_CACHE_DIR="$TMP/c" bash "$SCRIPTS/install.sh"
expect_rc 1 "VA_VERSION is required"

echo "# archive contents"
release v1.7.4 "$asset" 1.7.4 no-binary
install VA_VERSION=1.7.4 VA_ASSET="$asset" VA_CACHE_DIR="$TMP/cache-4"
expect_rc 1 "an archive without the binary fails"
expect_out "the archive does not contain the expected binary (vericto)" "says what is missing"
release v1.7.5 "$asset" 9.9.9
install VA_VERSION=1.7.5 VA_ASSET="$asset" VA_CACHE_DIR="$TMP/cache-5"
expect_rc 1 "a binary reporting another version fails"
expect_out "the installed binary reports 'vericto 9.9.9', expected 'vericto 1.7.5'" "names both versions"
expect_eq "$(cat "$GITHUB_PATH_FILE")" "" "and is not added to PATH"
release v1.7.6 vericto-cli-x86_64-unknown-linux-musl.tar.gz
install VA_VERSION=1.7.6 VA_ASSET=vericto-cli-x86_64-unknown-linux-musl.tar.gz VA_CACHE_DIR="$TMP/cache-6"
expect_rc 1 "an unknown archive type fails after the checksum"
expect_out "unknown archive type: vericto-cli-x86_64-unknown-linux-musl.tar.gz" "names it"

if command -v unzip >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  zip_asset=vericto-cli-x86_64-pc-windows-msvc.zip
  release v1.7.1 "$zip_asset"
  install VA_VERSION=1.7.1 VA_ASSET="$zip_asset" VA_CACHE_DIR="$TMP/cache-zip"
  expect_rc 0 "installs a .zip asset (Windows layout)"
  expect_eq "$(basename "$(output_of bin)")" vericto.exe "bin output is vericto.exe"
else
  echo "skip - .zip install (needs unzip and python3)"
fi

echo "# build attestation (advisory)"
: >"$GH_LOG"
install VA_VERSION=1.7.1 VA_ASSET="$asset" VA_CACHE_DIR="$TMP/cache-a1" VA_GH_TOKEN=ghs_test FAKE_GH=ok
expect_rc 0 "a verified attestation"
expect_out "Build attestation verified: $asset was built by vericto/vericto-cli." "logs it"
case "$(cat "$GH_LOG")" in
  "attestation verify $TMP/cache-a1/$asset --repo vericto/vericto-cli|GH_TOKEN=ghs_test") ok "asks gh with the token for the cached archive" ;;
  *) not_ok "gh invocation" "$(cat "$GH_LOG")" ;;
esac
install VA_VERSION=1.7.1 VA_ASSET="$asset" VA_CACHE_DIR="$TMP/cache-a2" VA_GH_TOKEN=ghs_test FAKE_GH=fail
expect_rc 0 "a failed attestation only warns: the checksum is the gate"
expect_out "::warning title=Vericto SQL Check::could not verify the build attestation of $asset (the SHA-256 check passed): line one line two no attestations found" "with the tail of gh's output"
tools=(bash env curl tar xz gzip mkdir mktemp rm mv cp chmod grep tr sed basename dirname sha256sum shasum perl openssl cat tail uname)
minimal=$(minimal_path "$TMP/no-gh" "${tools[@]}")
ln -sf "$SHIM/curl" "$minimal/curl"
INSTALL_PATH="$minimal" install VA_VERSION=1.7.1 VA_ASSET="$asset" VA_CACHE_DIR="$TMP/cache-a3" VA_GH_TOKEN=ghs_test
expect_rc 0 "installs without gh"
expect_out "gh not found; skipped the build attestation check (the SHA-256 check passed)." "with a notice"

finish
