#!/usr/bin/env bash
# Offline tests for scripts/lib.sh: workflow-command escaping, masking, step
# outputs, path helpers, SHA-256 and temporary directories.
#
# Usage: bash test/lib-test.sh
# shellcheck disable=SC2016 # the snippets are single-quoted on purpose: the child bash expands them
set -euo pipefail

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

# Runs a snippet with lib.sh sourced, in a clean environment.
lib() { # [VAR=VALUE ...] SNIPPET
  local snippet=${*: -1} vars=()
  while [ "$#" -gt 1 ]; do
    vars[${#vars[@]}]=$1
    shift
  done
  run ${vars[@]+"${vars[@]}"} bash -c ". \"\$1\"; $snippet" lib "$SCRIPTS/lib.sh"
}

echo "# gh_escape and annotations"
lib 'gh_escape "100% done"'
expect_eq "$out" "100%25 done" "escapes %"
lib 'gh_escape "$(printf "a\r\nb")"'
expect_eq "$out" "a%0D%0Ab" "escapes CR and LF, so a message cannot start a new workflow command"
lib 'gh_error "bad input: $(printf "x\n::add-mask::y")"'
expect_eq "$out" "::error title=Vericto SQL Check::bad input: x%0A::add-mask::y" "gh_error keeps a forged command on one line"
lib 'gh_warning "careful"; gh_notice "fyi"'
expect_eq "$out" "::warning title=Vericto SQL Check::careful"$'\n'"::notice title=Vericto SQL Check::fyi" "gh_warning and gh_notice"

echo "# gh_mask"
lib 'gh_mask "$(printf "line1\n\nline2")"'
expect_eq "$out" "::add-mask::line1"$'\n'"::add-mask::line2" "masks every non-empty line of a multi-line secret"
lib 'gh_mask "vtro_no_trailing_newline"'
expect_eq "$out" "::add-mask::vtro_no_trailing_newline" "masks a value without a trailing newline"
lib 'gh_mask "50%"'
expect_eq "$out" "::add-mask::50%25" "escapes the masked value"

echo "# set_output"
lib 'set_output exit-code 3; set_output result fail'
expect_output exit-code 3 "writes to GITHUB_OUTPUT"
expect_output result fail "appends further outputs"
expect_eq "$out" "" "prints nothing when GITHUB_OUTPUT is set"
run bash -c '. "$1"; unset GITHUB_OUTPUT; set_output bin /x/vericto' lib "$SCRIPTS/lib.sh"
expect_eq "$out" "output bin=/x/vericto" "prints the output without GITHUB_OUTPUT (local runs)"
lib 'set_output evil "$(printf "a\nexit-code=0")"'
expect_rc 1 "refuses a multi-line value"
expect_out "refusing a multi-line value for output 'evil'" "says why"
expect_eq "$outputs" "" "and writes nothing that could forge another output"
lib 'set_output evil "$(printf "a\rb")"'
expect_rc 1 "refuses a value with a CR"

echo "# is_single_line and matches (whole-value input validation)"
lib 'is_single_line "one line"; is_single_line ""'
expect_rc 0 "is_single_line: one line, and the empty string"
for v in $'a\nb' $'a\r\nb' $'a\n' $'a\r' $'\n'; do
  run bash -c '. "$1"; is_single_line "$2"' lib "$SCRIPTS/lib.sh" "$v"
  expect_rc 1 "is_single_line: rejects $(printf '%q' "$v")"
done
run bash -c '. "$1"; matches "$2" "$3"' lib "$SCRIPTS/lib.sh" '^[a-z]+$' postgres
expect_rc 0 "matches: a valid single-line value"
run bash -c '. "$1"; matches "$2" "$3"' lib "$SCRIPTS/lib.sh" '^[a-z]+$' Postgres
expect_rc 1 "matches: an invalid value"
run bash -c '. "$1"; matches "$2" "$3"' lib "$SCRIPTS/lib.sh" '[a-z]+' 'postgres;x'
expect_rc 0 "matches: an unanchored ERE matches a substring, so validators anchor theirs"
for v in $'postgres\nmysql' $'postgres\r\nmysql' $'postgres\n' $'postgres\r' $'\npostgres'; do
  run bash -c '. "$1"; matches "$2" "$3"' lib "$SCRIPTS/lib.sh" '^[a-z]+$' "$v"
  expect_rc 1 "matches: rejects $(printf '%q' "$v"), although each line matches"
done

echo "# is_windows, native_path, unix_path"
for os in Windows MINGW64_NT-10.0 MSYS_NT CYGWIN_NT-10.0; do
  lib "RUNNER_OS=$os" 'is_windows'
  expect_rc 0 "is_windows for RUNNER_OS=$os"
done
for os in Linux macOS; do
  lib "RUNNER_OS=$os" 'is_windows'
  expect_rc 1 "not is_windows for RUNNER_OS=$os"
done
lib 'is_windows'
expect_rc 1 "not is_windows from uname on this host"
lib RUNNER_OS=Linux 'native_path "/tmp/a b"; echo; unix_path "/tmp/a b"'
expect_eq "$out" "/tmp/a b"$'\n'"/tmp/a b" "paths are unchanged off Windows"
fake_bin="$TMP/fake-cygpath"
mkdir -p "$fake_bin"
cat >"$fake_bin/cygpath" <<'EOF'
#!/usr/bin/env bash
# cygpath stand-in: -m gives C:/..., -u gives /c/...
case "$1" in
  -m) printf 'C:%s' "${2#/c}" ;;
  -u) printf '/c%s' "${2#C:}" ;;
esac
EOF
chmod +x "$fake_bin/cygpath"
TEST_PATH="$fake_bin:$PATH" lib RUNNER_OS=Windows 'native_path /c/runner/tmp; echo; unix_path C:/runner/tmp'
expect_eq "$out" "C:/runner/tmp"$'\n'"/c/runner/tmp" "uses cygpath on Windows"

echo "# sha256_of"
printf 'abc' >"$TMP/abc"
abc=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
lib "sha256_of \"$TMP/abc\""
expect_eq "$out" "$abc" "SHA-256 of a known input, lowercase hex"
for tool in sha256sum shasum openssl; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "skip - $tool is not installed"
    continue
  }
  dir=$(minimal_path "$TMP/only-$tool" "$tool" bash cat tr printf perl)
  TEST_PATH="$dir" lib "sha256_of \"$TMP/abc\""
  expect_eq "$out" "$abc" "SHA-256 with only $tool installed"
done
dir=$(minimal_path "$TMP/no-sha" bash cat tr printf)
TEST_PATH="$dir" lib "sha256_of \"$TMP/abc\""
expect_rc 1 "fails without any SHA-256 tool"
expect_out "no SHA-256 tool found" "names the missing tools"

echo "# make_temp_dir"
lib 'd=$(make_temp_dir unit); test -d "$d" && printf "%s" "$d"'
case "$out" in
  "$TMP"/vericto-unit.*) ok "creates vericto-NAME.XXXXXX under RUNNER_TEMP" ;;
  *) not_ok "make_temp_dir under RUNNER_TEMP" "$out" ;;
esac

finish
