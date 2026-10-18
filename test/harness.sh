# shellcheck shell=bash
# Shared helpers for the offline unit tests (test/*-test.sh other than
# checksum-test.sh). Sourced, never executed. Compatible with bash 3.2.
#
# Every script under test runs through `run`, with a clean environment
# (`env -i`): variables the runner sets (GITHUB_*, RUNNER_*, VERICTO_API_KEY,
# ACTIONS_ID_TOKEN_REQUEST_URL...) never leak into a case. Nothing here, or in
# the tests, touches the network.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC2034 # SCRIPTS and FIXTURES are used by the scripts that source this file
SCRIPTS="$ROOT/scripts"
# shellcheck disable=SC2034
FIXTURES="$ROOT/test/fixtures"

tmp_base=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
TMP=$(mktemp -d "${tmp_base%/}/check-sql-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

failures=0
passes=0
out="" rc=0 outputs=""

ok() {
  passes=$((passes + 1))
  echo "ok   - $1"
}

not_ok() {
  failures=$((failures + 1))
  echo "FAIL - $1"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" | sed 's/^/       | /'; fi
}

# run [VAR=VALUE ...] COMMAND [ARG ...]
# Runs COMMAND with only PATH, HOME, TMPDIR, RUNNER_TEMP and GITHUB_OUTPUT set,
# plus the VAR=VALUE pairs. Sets $out (stdout and stderr), $rc and $outputs
# (what the command wrote to GITHUB_OUTPUT).
run() {
  local gho="$TMP/github_output" cov=()
  : >"$gho"
  # Under kcov (coverage runs), keep the variables its bash tracing needs.
  if [ -n "${KCOV_BASH_XTRACEFD:-}" ]; then
    cov=(BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" KCOV_BASH_XTRACEFD="$KCOV_BASH_XTRACEFD")
  fi
  set +e
  out=$(env -i ${cov[@]+"${cov[@]}"} PATH="${TEST_PATH:-$PATH}" HOME="$HOME" TMPDIR="$TMP" RUNNER_TEMP="$TMP" \
    GITHUB_OUTPUT="$gho" "$@" 2>&1)
  rc=$?
  set -e
  outputs=$(cat "$gho")
}

# output_of NAME: the last value written for step output NAME.
output_of() {
  printf '%s\n' "$outputs" | sed -n "s/^$1=//p" | tail -n 1
}

expect_rc() { # WANT DESCRIPTION
  if [ "$rc" = "$1" ]; then ok "$2 (exit $rc)"; else not_ok "$2: expected exit $1, got $rc" "$out"; fi
}

expect_out() { # TEXT DESCRIPTION: the output contains TEXT (fixed string)
  case "$out" in
    *"$1"*) ok "$2" ;;
    *) not_ok "$2: output lacks '$1'" "$out" ;;
  esac
}

expect_no_out() { # TEXT DESCRIPTION: the output does not contain TEXT
  case "$out" in
    *"$1"*) not_ok "$2: output contains '$1'" "$out" ;;
    *) ok "$2" ;;
  esac
}

expect_output() { # NAME VALUE DESCRIPTION: step output NAME equals VALUE
  local got
  got=$(output_of "$1")
  if [ "$got" = "$2" ]; then ok "$3"; else not_ok "$3: output '$1' is '$got', expected '$2'" "$outputs"; fi
}

expect_eq() { # GOT WANT DESCRIPTION
  if [ "$1" = "$2" ]; then ok "$3"; else not_ok "$3" "expected: $2"$'\n'"got:      $1"; fi
}

# minimal_path DIR CMD...: a directory holding links to only these commands, to
# run a script where some tool (gh, jq, sha256sum...) is not installed.
minimal_path() {
  local dir=$1 cmd p
  shift
  mkdir -p "$dir"
  for cmd in "$@"; do
    p=$(command -v "$cmd" 2>/dev/null) || continue
    ln -sf "$p" "$dir/$cmd"
  done
  printf '%s' "$dir"
}

xfails=0

# known_bug DESCRIPTION EXPECT_CALL...: an expect_* call that fails today
# because of a reported bug. Counted as "xfail"; once the bug is fixed it
# passes, and the suite fails until this is turned into a plain assertion.
known_bug() {
  local desc=$1 before_f=$failures before_p=$passes
  shift
  "$@" >/dev/null
  if [ "$failures" -gt "$before_f" ]; then
    failures=$before_f
    xfails=$((xfails + 1))
    echo "xfail - $desc"
  else
    passes=$before_p
    not_ok "XPASS - $desc: the known bug looks fixed; make this a plain assertion"
  fi
}

finish() {
  echo "# $passes passed, $failures failed, $xfails expected failure(s) (known bugs)"
  if [ "$failures" -ne 0 ]; then
    echo "::error::$failures test(s) failed in $(basename "$0")"
    exit 1
  fi
}
