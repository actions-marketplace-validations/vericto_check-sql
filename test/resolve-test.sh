#!/usr/bin/env bash
# Offline tests for scripts/resolve.sh: the CLI version (pinned, never
# "latest"), the release asset for each runner OS/arch, unsupported runners and
# the cache location.
#
# Usage: bash test/resolve-test.sh
set -euo pipefail

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

resolve() { run "$@" bash "$SCRIPTS/resolve.sh"; }

pin=$(bash "$ROOT/test/pinned-version.sh")
pin=${pin#version=}

echo "# version"
resolve VA_CLI_VERSION="$pin" RUNNER_OS=Linux RUNNER_ARCH=X64 RUNNER_TOOL_CACHE=/opt/hostedtoolcache
expect_rc 0 "the pinned version from action.yml ($pin)"
expect_output version "$pin" "version output"
expect_output cache-key "vericto-cli-$pin-x86_64-unknown-linux-musl" "cache key names version and target"
expect_output cache-dir "/opt/hostedtoolcache/vericto-cli/$pin/x86_64-unknown-linux-musl" "cache dir under RUNNER_TOOL_CACHE"
expect_out "Vericto CLI $pin, asset vericto-cli-x86_64-unknown-linux-musl.tar.xz" "logs what it resolved"

resolve VA_CLI_VERSION=v1.8.2 RUNNER_OS=Linux RUNNER_ARCH=X64
expect_output version 1.8.2 "a leading v is accepted and dropped"
resolve VA_CLI_VERSION=2.0.0-rc.1 RUNNER_OS=Linux RUNNER_ARCH=X64
expect_output version 2.0.0-rc.1 "a pre-release version is accepted"

for bad in latest LATEST "" 1.8 1.8.2.2 "1.8.2; touch pwned" "1.8.2 " "../1.8.2" "v"; do
  resolve VA_CLI_VERSION="$bad" RUNNER_OS=Linux RUNNER_ARCH=X64
  expect_rc 2 "rejects cli-version '$bad'"
  expect_eq "$outputs" "" "no outputs for cli-version '$bad'"
done
resolve VA_CLI_VERSION=latest RUNNER_OS=Linux RUNNER_ARCH=X64
expect_out "'latest' is not accepted: pin a version." "explains why latest is refused"
expect_out "::error title=Vericto SQL Check::" "as an error annotation"
run RUNNER_OS=Linux RUNNER_ARCH=X64 bash "$SCRIPTS/resolve.sh"
expect_rc 2 "rejects a missing cli-version"

# A value with a line break is an input error even when its first line is a
# valid version (LF, CRLF, a trailing LF or CR).
for bad in $'1.8.2\n../../evil' $'1.8.2\r\n../../evil' $'1.8.2\n' $'1.8.2\r' $'\n1.8.2'; do
  label=$(printf '%q' "$bad")
  resolve VA_CLI_VERSION="$bad" RUNNER_OS=Linux RUNNER_ARCH=X64
  expect_rc 2 "rejects multi-line cli-version $label"
  expect_out "cli-version must be an exact release such as 1.8.2" "multi-line cli-version $label: the input error"
  expect_no_out "refusing a multi-line value" "multi-line cli-version $label: stopped before set_output"
  expect_eq "$outputs" "" "multi-line cli-version $label: no outputs"
done

echo "# runner OS and architecture"
while read -r os arch target ext; do
  resolve VA_CLI_VERSION=1.8.2 RUNNER_OS="$os" RUNNER_ARCH="$arch"
  expect_rc 0 "$os/$arch is supported"
  expect_output target "$target" "$os/$arch target $target"
  expect_output asset "vericto-cli-$target.$ext" "$os/$arch asset .$ext"
done <<'EOF'
Linux X64 x86_64-unknown-linux-musl tar.xz
Linux ARM64 aarch64-unknown-linux-musl tar.xz
macOS X64 x86_64-apple-darwin tar.xz
macOS ARM64 aarch64-apple-darwin tar.xz
Windows X64 x86_64-pc-windows-msvc zip
EOF

for combo in Windows/ARM64 Linux/X86 Linux/ARM macOS/X86 FreeBSD/X64; do
  resolve VA_CLI_VERSION=1.8.2 RUNNER_OS="${combo%/*}" RUNNER_ARCH="${combo#*/}"
  expect_rc 2 "$combo is unsupported"
  expect_out "unsupported runner '$combo'. Supported: Linux X64/ARM64, macOS X64/ARM64, Windows X64." "names $combo and the supported runners"
done

echo "# OS and arch from uname (self-hosted runners without RUNNER_OS/RUNNER_ARCH)"
fake_uname() { # DIR KERNEL MACHINE
  mkdir -p "$1"
  # shellcheck disable=SC2016 # $1 belongs to the generated script
  printf '#!/bin/sh\ncase "$1" in -s) echo %s ;; -m) echo %s ;; esac\n' "$2" "$3" >"$1/uname"
  chmod +x "$1/uname"
}
while read -r kernel machine target; do
  fake_uname "$TMP/uname-$kernel-$machine" "$kernel" "$machine"
  TEST_PATH="$TMP/uname-$kernel-$machine:$PATH" resolve VA_CLI_VERSION=1.8.2
  expect_output target "$target" "uname $kernel $machine is $target"
done <<'EOF'
Linux x86_64 x86_64-unknown-linux-musl
Linux aarch64 aarch64-unknown-linux-musl
Darwin arm64 aarch64-apple-darwin
Darwin x86_64 x86_64-apple-darwin
MINGW64_NT-10.0 amd64 x86_64-pc-windows-msvc
EOF
fake_uname "$TMP/uname-sunos" SunOS sparc
TEST_PATH="$TMP/uname-sunos:$PATH" resolve VA_CLI_VERSION=1.8.2
expect_rc 2 "an unknown uname is unsupported"
expect_out "unsupported runner '/'." "with empty OS and arch in the message"

echo "# cache location"
resolve VA_CLI_VERSION=1.8.2 RUNNER_OS=Linux RUNNER_ARCH=X64
expect_output cache-dir "$TMP/vericto-cli/1.8.2/x86_64-unknown-linux-musl" "falls back to RUNNER_TEMP without a tool cache"

echo "# without GITHUB_OUTPUT (local runs)"
out=$(env -i PATH="$PATH" VA_CLI_VERSION=1.8.2 RUNNER_OS=macOS RUNNER_ARCH=ARM64 RUNNER_TOOL_CACHE=/c bash "$SCRIPTS/resolve.sh")
expect_out "output asset=vericto-cli-aarch64-apple-darwin.tar.xz" "prints the outputs"

finish
