#!/usr/bin/env bash
# Downloads the Vericto CLI release asset for this runner, verifies its
# SHA-256 against the release's .sha256 file BEFORE extracting it, and puts
# the binary on PATH.
#
# The archive is kept in VA_CACHE_DIR (saved by actions/cache). A cached
# archive is never trusted as is: it is re-verified against a freshly
# downloaded .sha256 on every run, and re-downloaded if it does not match.
# The binary is always extracted from the verified archive into a fresh
# directory, so nothing unverified reaches PATH.
#
# In:  VA_VERSION, VA_ASSET, VA_CACHE_DIR; VA_GH_TOKEN (optional, attestation).
# Out: bin (path to the vericto binary), version (step outputs).
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

: "${VA_VERSION:?}" "${VA_ASSET:?}" "${VA_CACHE_DIR:?}"
repo=vericto/vericto-cli
base_url="https://github.com/$repo/releases/download/v$VA_VERSION"

curl_get() { # URL DEST
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 2 \
    --connect-timeout 20 -o "$2" "$1"
}

cache_dir=$(unix_path "$VA_CACHE_DIR")
mkdir -p "$cache_dir"
work=$(make_temp_dir install)
trap 'rm -rf "$work"' EXIT

sumfile="$work/$VA_ASSET.sha256"
if ! curl_get "$base_url/$VA_ASSET.sha256" "$sumfile"; then
  gh_error "could not download $base_url/$VA_ASSET.sha256. Does release v$VA_VERSION exist?"
  exit 1
fi

archive="$cache_dir/$VA_ASSET"
fresh=false
if [ -f "$archive" ] && bash "$here/verify-checksum.sh" "$archive" "$sumfile"; then
  echo "Using the cached archive (checksum re-verified)."
else
  if [ -f "$archive" ]; then
    gh_warning "the cached $VA_ASSET does not match the release checksum; downloading it again."
    rm -f "$archive"
  fi
  if ! curl_get "$base_url/$VA_ASSET" "$work/$VA_ASSET"; then
    gh_error "could not download $base_url/$VA_ASSET"
    exit 1
  fi
  # Hard gate: a mismatch stops the action here, before anything is extracted.
  bash "$here/verify-checksum.sh" "$work/$VA_ASSET" "$sumfile"
  mv "$work/$VA_ASSET" "$archive"
  fresh=true
fi

# Build provenance (Sigstore). Advisory: the checksum above is the gate. This
# needs the GitHub CLI and a token, and is skipped (with a notice) without them.
if [ "$fresh" = true ]; then
  if ! command -v gh >/dev/null 2>&1; then
    gh_notice "gh not found; skipped the build attestation check (the SHA-256 check passed)."
  elif [ -z "${VA_GH_TOKEN:-}" ]; then
    gh_notice "no token; skipped the build attestation check (the SHA-256 check passed)."
  elif GH_TOKEN=$VA_GH_TOKEN gh attestation verify "$(native_path "$archive")" --repo "$repo" >"$work/attest.log" 2>&1; then
    echo "Build attestation verified: $VA_ASSET was built by $repo."
  else
    gh_warning "could not verify the build attestation of $VA_ASSET (the SHA-256 check passed): $(tail -n 3 "$work/attest.log" | tr '\n' ' ')"
  fi
fi

extract="$work/extract"
mkdir -p "$extract"
case "$VA_ASSET" in
  *.tar.xz)
    tar -xJf "$archive" -C "$extract"
    src="$extract/${VA_ASSET%.tar.xz}/vericto"
    exe=vericto
    ;;
  *.zip)
    if command -v unzip >/dev/null 2>&1; then
      unzip -q "$archive" -d "$extract"
    else
      # shellcheck disable=SC2016 # $args is PowerShell's, not ours
      pwsh -NoProfile -NonInteractive -Command \
        'Expand-Archive -LiteralPath $args[0] -DestinationPath $args[1]' \
        "$(native_path "$archive")" "$(native_path "$extract")"
    fi
    src="$extract/vericto.exe"
    exe=vericto.exe
    ;;
  *)
    gh_error "unknown archive type: $VA_ASSET"
    exit 1
    ;;
esac
if [ ! -f "$src" ]; then
  gh_error "the archive does not contain the expected binary ($(basename "$src"))"
  exit 1
fi

bin_dir=$(make_temp_dir bin)
cp "$src" "$bin_dir/$exe"
chmod 0755 "$bin_dir/$exe"

reported=$("$bin_dir/$exe" --version | tr -d '\r')
if [ "$reported" != "vericto $VA_VERSION" ]; then
  gh_error "the installed binary reports '$reported', expected 'vericto $VA_VERSION'"
  exit 1
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$(native_path "$bin_dir")" >>"$GITHUB_PATH"
fi
set_output bin "$bin_dir/$exe"
set_output version "$VA_VERSION"
echo "Installed $reported to $(native_path "$bin_dir")"
