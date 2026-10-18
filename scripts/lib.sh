# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Vericto S.A.S.
# SPDX-License-Identifier: Apache-2.0

# Helpers shared by the action's scripts. Sourced, never executed.
# Compatible with bash 3.2 (the macOS system bash) and Git Bash on Windows.

# Escapes a value for the message part of a workflow command
# (https://docs.github.com/actions/reference/workflow-commands-for-github-actions).
gh_escape() {
  local s=$1 pct='%' cr=$'\r' lf=$'\n'
  s=${s//"$pct"/%25}
  s=${s//"$cr"/%0D}
  s=${s//"$lf"/%0A}
  printf '%s' "$s"
}

gh_error() { printf '::error title=Vericto SQL Check::%s\n' "$(gh_escape "$*")"; }
gh_warning() { printf '::warning title=Vericto SQL Check::%s\n' "$(gh_escape "$*")"; }
gh_notice() { printf '::notice title=Vericto SQL Check::%s\n' "$(gh_escape "$*")"; }

# Masks every line of a value in the log.
gh_mask() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$line" ]; then printf '::add-mask::%s\n' "$(gh_escape "$line")"; fi
  done <<EOF
$1
EOF
}

# is_single_line VALUE: true when VALUE holds no line feed and no carriage
# return.
is_single_line() {
  case "$1" in
    *$'\n'* | *$'\r'*) return 1 ;;
  esac
  return 0
}

# matches ERE VALUE: true when VALUE is a single line and matches the extended
# regex ERE as a whole (anchor ERE with ^...$). Every input validator uses
# this. grep would not do: it matches line by line, so a multi-line value would
# pass as long as one of its lines matched. Bash's =~ matches the whole string,
# in bash 3.2 (the macOS runners' bash) and 5.x alike.
matches() {
  is_single_line "$2" || return 1
  [[ $2 =~ $1 ]]
}

# set_output NAME VALUE. Values are single-line by construction (paths and
# numbers); a newline would be rejected rather than allowed to forge an output.
set_output() {
  if ! is_single_line "$2"; then
    gh_error "internal: refusing a multi-line value for output '$1'"
    return 1
  fi
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  else
    printf 'output %s=%s\n' "$1" "$2"
  fi
}

is_windows() {
  case "${RUNNER_OS:-$(uname -s)}" in
    Windows | MINGW* | MSYS* | CYGWIN*) return 0 ;;
  esac
  return 1
}

# Path in the form other steps and native tools expect: C:/a/b on Windows
# (accepted by Node, the CLI and bash alike), unchanged elsewhere.
native_path() {
  if is_windows && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

# Path bash can operate on: /c/a/b on Windows, unchanged elsewhere.
unix_path() {
  if is_windows && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s' "$1"
  fi
}

# Prints the SHA-256 of a file in lowercase hex.
sha256_of() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then
    out=$(sha256sum "$1")
  elif command -v shasum >/dev/null 2>&1; then
    out=$(shasum -a 256 "$1")
  elif command -v openssl >/dev/null 2>&1; then
    out=$(openssl dgst -sha256 -r "$1")
  else
    gh_error "no SHA-256 tool found (sha256sum, shasum or openssl)"
    return 1
  fi
  printf '%s' "${out%% *}" | tr 'A-F' 'a-f'
}

# Temporary directory under the runner's temp dir.
make_temp_dir() {
  local base
  base=$(unix_path "${RUNNER_TEMP:-${TMPDIR:-/tmp}}")
  mktemp -d "${base%/}/vericto-$1.XXXXXX"
}
