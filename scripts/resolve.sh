#!/usr/bin/env bash
# Validates the requested CLI version and works out which release asset this
# runner needs and where its download is cached.
#
# In:  VA_CLI_VERSION; RUNNER_OS, RUNNER_ARCH, RUNNER_TOOL_CACHE (set by the runner).
# Out: version, target, asset, cache-dir, cache-key (step outputs).
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

version=${VA_CLI_VERSION:-}
version=${version#v}
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
  gh_error "cli-version must be an exact release such as 1.7.1 (got '${VA_CLI_VERSION:-}'). 'latest' is not accepted: pin a version."
  exit 2
fi

os=${RUNNER_OS:-}
arch=${RUNNER_ARCH:-}
if [ -z "$os" ]; then
  case "$(uname -s)" in
    Linux) os=Linux ;;
    Darwin) os=macOS ;;
    MINGW* | MSYS* | CYGWIN*) os=Windows ;;
  esac
fi
if [ -z "$arch" ]; then
  case "$(uname -m)" in
    x86_64 | amd64) arch=X64 ;;
    aarch64 | arm64) arch=ARM64 ;;
  esac
fi

case "$os/$arch" in
  Linux/X64) target=x86_64-unknown-linux-musl ext=tar.xz ;;
  Linux/ARM64) target=aarch64-unknown-linux-musl ext=tar.xz ;;
  macOS/X64) target=x86_64-apple-darwin ext=tar.xz ;;
  macOS/ARM64) target=aarch64-apple-darwin ext=tar.xz ;;
  Windows/X64) target=x86_64-pc-windows-msvc ext=zip ;;
  *)
    gh_error "unsupported runner '$os/$arch'. Supported: Linux X64/ARM64, macOS X64/ARM64, Windows X64."
    exit 2
    ;;
esac

asset="vericto-cli-$target.$ext"
cache_root=${RUNNER_TOOL_CACHE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}
cache_dir="$(native_path "$(unix_path "$cache_root")")/vericto-cli/$version/$target"

set_output version "$version"
set_output target "$target"
set_output asset "$asset"
set_output cache-dir "$cache_dir"
set_output cache-key "vericto-cli-$version-$target"
echo "Vericto CLI $version, asset $asset"
