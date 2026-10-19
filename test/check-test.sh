#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vericto S.A.S.
# SPDX-License-Identifier: Apache-2.0

# Offline tests for scripts/check.sh with a stand-in CLI
# (test/fixtures/fake-cli/vericto): input validation, credentials, which SQL
# is selected (files, directories, globs, changed files), report formats,
# exit codes, outputs, annotations and the job summary.
#
# Usage: bash test/check-test.sh
set -euo pipefail

# shellcheck source=test/harness.sh
. "$(dirname "$0")/harness.sh"

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "::error::test/check-test.sh needs jq and git (GitHub-hosted runners have both)"
  exit 1
fi

mkdir -p "$TMP/bin" "$TMP/log"
cp "$FIXTURES/fake-cli/vericto" "$TMP/bin/vericto"
chmod +x "$TMP/bin/vericto"
FAKE="$TMP/bin/vericto"
SUMMARY="$TMP/summary.md"
KEY=vtro_unit_test_key_0123456789

# A workspace outside git with the SQL fixtures, a hidden directory, a name
# with a space and a file that is not SQL.
ws="$TMP/ws"
mkdir -p "$ws/.hidden" "$ws/spaced"
cp -R "$FIXTURES/migrations" "$FIXTURES/nested" "$ws/"
printf 'DELETE FROM secrets;\n' >"$ws/.hidden/secret.sql"
printf 'SELECT 1;\n' >"$ws/spaced/with space.sql"
printf 'not sql\n' >"$ws/migrations/README.txt"

# check DIR [VAR=VALUE ...]: runs check.sh from DIR with the stand-in CLI.
# VA_FILES is always set, possibly empty, as action.yml always sets it.
check() {
  local dir=$1 here=$PWD
  shift
  rm -f "$TMP/log/"*
  : >"$SUMMARY"
  cd "$dir"
  run VA_BIN="$FAKE" FAKE_LOG_DIR="$TMP/log" GITHUB_STEP_SUMMARY="$SUMMARY" VA_FILES= "$@" bash "$SCRIPTS/check.sh"
  cd "$here"
}
logged() { if [ -f "$TMP/log/$1" ]; then cat "$TMP/log/$1"; else printf '<not run>'; fi; }
summary() { cat "$SUMMARY"; }

expect_usage_error() { # DESCRIPTION MESSAGE
  expect_rc 2 "$1"
  expect_out "$2" "$1: says why"
  expect_output exit-code 2 "$1: exit-code output"
  expect_output result fail "$1: result output"
  expect_eq "$(logged args)" "<not run>" "$1: the CLI did not run"
}

echo "# input validation (exit 2, the CLI never runs)"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_FORMAT=html
expect_usage_error "unknown format" "input 'format' must be sarif, json, text, gitlab-codequality or gitlab-sast (got 'html')"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_OIDC=yes
expect_usage_error "oidc not a boolean" "input 'oidc' must be true or false (got 'yes')"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_UPLOAD_SARIF=1
expect_usage_error "upload-sarif not a boolean" "input 'upload-sarif' must be true or false (got '1')"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_CHANGED=maybe
expect_usage_error "changed not a boolean" "input 'changed' must be true or false (got 'maybe')"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_DIALECT='postgres"; touch "pwned'
expect_usage_error "hostile dialect" "input 'dialect' must be a dialect name"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_DIALECT=Postgres
expect_usage_error "upper-case dialect" "input 'dialect' must be a dialect name"
for t in 0 -1 1.5 30s 100000; do
  check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_TIMEOUT="$t"
  expect_usage_error "timeout '$t'" "input 'timeout' must be a whole number of seconds (got '$t')"
done
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_API_URL=ftp://api.vericto.com
expect_usage_error "api-url not http(s)" "input 'api-url' must be an http(s) URL"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_API_URL='https://api.vericto.com/ x'
expect_usage_error "api-url with a space" "input 'api-url' must be an http(s) URL"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_WORKSPACE='ws_1;rm'
expect_usage_error "workspace with a ;" "input 'workspace' must be a workspace ID such as ws_123"
check "$ws" VA_API_KEY="$KEY" VA_SINCE=--output=/etc/passwd
expect_usage_error "since that looks like an option" "input 'since' must be a git ref, e.g. origin/main"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_BASELINE="$(printf 'a.json\nb.json')"
expect_usage_error "multi-line baseline" "input 'baseline' must be a single path"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_CHANGED=true
expect_usage_error "files and changed" "set either files or changed: true, not both"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_SINCE=origin/main
expect_usage_error "files and since" "set either files or since, not both"
check "$ws" VA_API_KEY="$KEY" VA_CHANGED=false
expect_usage_error "nothing to check" "nothing to check: set files, or leave changed on"
expect_out "::error title=Vericto SQL Check::" "usage errors are error annotations"
case "$(summary)" in
  *"### Vericto SQL Check: FAIL"*"| Exit code | \`2\` (usage error) |"*) ok "usage errors are in the job summary" ;;
  *) not_ok "summary for a usage error" "$(summary)" ;;
esac
run FAKE_LOG_DIR="$TMP/log" bash "$SCRIPTS/check.sh"
expect_rc 1 "fails without the install step's binary"
expect_out "the install step did not provide a binary" "says so"

# A value with a line break is an input error even when its first line is
# valid: LF, CRLF, a trailing LF and a trailing CR, on every validated input.
# (Validation used to match line by line, so these reached the CLI as one
# argument with a newline in it.)
while read -r var good second msg <&3; do
  for v in "$good"$'\n'"$second" "$good"$'\r\n'"$second" "$good"$'\n' "$good"$'\r'; do
    label="multi-line $var $(printf '%q' "$v")"
    if [ "$var" = VA_SINCE ]; then
      check "$ws" VA_API_KEY="$KEY" "$var=$v"
    else
      check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations "$var=$v"
    fi
    expect_usage_error "$label" "$msg"
  done
done 3<<'EOF'
VA_DIALECT postgres --format=text input 'dialect' must be a dialect name
VA_TIMEOUT 5 9 input 'timeout' must be a whole number of seconds
VA_API_URL https://api.vericto.com http://evil.example input 'api-url' must be an http(s) URL
VA_WORKSPACE ws_1 ws_2 input 'workspace' must be a workspace ID such as ws_123
VA_SINCE origin/main --x input 'since' must be a git ref, e.g. origin/main
EOF
check "$ws" VA_OIDC=true ACTIONS_ID_TOKEN_REQUEST_URL=https://token.example VA_FILES=migrations/0001_create_users.sql \
  VA_WORKSPACE=$'ws_1\nws_2'
expect_usage_error "multi-line workspace under oidc" "input 'workspace' must be a workspace ID such as ws_123"
for v in $'a.json\r\nb.json' $'a.json\n' $'a.json\r'; do
  check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations VA_BASELINE="$v"
  expect_usage_error "multi-line baseline $(printf '%q' "$v")" "input 'baseline' must be a single path"
done

# Every optional input unset (a direct run, not through action.yml): set -u
# must not abort, and no option is passed for them.
rm -f "$TMP/log/"*
cd "$ws"
run VA_BIN="$FAKE" FAKE_LOG_DIR="$TMP/log" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql bash "$SCRIPTS/check.sh"
cd "$ROOT"
expect_rc 0 "every optional input unset"
expect_no_out "unbound variable" "every optional input unset: no set -u abort"
case "$(logged args)" in
  *--dialect* | *--baseline* | *--timeout* | *--api-url* | *--since* | *--oidc*) not_ok "unset inputs add flags" "$(logged args)" ;;
  *--stdin-file-list*) ok "every optional input unset: no flags for them" ;;
  *) not_ok "unset inputs: files mode" "$(logged args)" ;;
esac

echo "# credentials"
check "$ws" VA_FILES=migrations/0001_create_users.sql
expect_rc 3 "no api-key, no VERICTO_API_KEY, no oidc"
expect_out "no credentials: set 'api-key: \${{ secrets.VERICTO_API_KEY }}', or 'oidc: true' with 'workspace'" "explains the options"
expect_output exit-code 3 "exit-code 3"
expect_output result fail "result fail"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql
expect_rc 0 "an api-key"
expect_eq "$(printf '%s\n' "$out" | head -n 1)" "::add-mask::$KEY" "masks the key before anything else is printed"
expect_eq "$(logged api-key)" "$KEY" "passes it to the CLI as VERICTO_API_KEY"
case "$(logged args)$(printf '%s' "$out" | sed 1d)" in
  *"$KEY"*) not_ok "the key appears on the command line or in the log" ;;
  *) ok "the key is never on the command line or in the log" ;;
esac
check "$ws" VERICTO_API_KEY=vtro_job_level VA_FILES=migrations/0001_create_users.sql
expect_rc 0 "a job-level VERICTO_API_KEY"
expect_out "::add-mask::vtro_job_level" "is masked too"
expect_eq "$(logged api-key)" vtro_job_level "and reaches the CLI"
check "$ws" VA_API_KEY="$KEY" VERICTO_API_KEY=vtro_job_level VA_FILES=migrations/0001_create_users.sql
expect_eq "$(logged api-key)" "$KEY" "the api-key input wins over the job-level variable"
check "$ws" VA_OIDC=true VA_API_KEY="$KEY" VA_FILES=migrations
expect_usage_error "api-key and oidc" "set either api-key or oidc: true, not both"
check "$ws" VA_OIDC=true VA_WORKSPACE=ws_1 VA_FILES=migrations
expect_rc 3 "oidc without id-token: write"
expect_out "oidc: true needs 'permissions: id-token: write' on the job" "explains the permission"
check "$ws" VA_OIDC=TRUE VA_WORKSPACE=ws_123 VERICTO_API_KEY=vtro_job_level ACTIONS_ID_TOKEN_REQUEST_URL=https://token.example \
  VA_FILES=migrations/0001_create_users.sql
expect_rc 0 "oidc with a token endpoint"
case "$(logged args)" in *--oidc*) ok "passes --oidc" ;; *) not_ok "--oidc" "$(logged args)" ;; esac
expect_eq "$(logged api-key)" "<unset>" "a job-level static key does not reach the CLI with oidc"
expect_eq "$(logged workspace-id)" ws_123 "exports VERICTO_WORKSPACE_ID"
check "$ws" VA_OIDC=true ACTIONS_ID_TOKEN_REQUEST_URL=https://token.example VA_FILES=migrations/0001_create_users.sql
expect_eq "$(logged workspace-id)" "<unset>" "no workspace input: left to the CLI (.vericto.toml)"

echo "# CLI arguments"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql VA_DIALECT=mysql VA_BASELINE="base line.json" \
  VA_TIMEOUT=45 VA_API_URL=https://eu.vericto.example
expect_rc 0 "optional inputs"
args=$(logged args)
expect_eq "$(printf '%s\n' "$args" | sed -n '1,5p')" "--format=sarif
--dialect=mysql
--baseline=base line.json
--timeout=45
--api-url=https://eu.vericto.example" "each input is one argument, spaces included"
expect_no_out "plain http" "no warning for https"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql VA_API_URL=http://127.0.0.1:8080
expect_rc 0 "a plain http api-url is allowed"
expect_out "::warning title=Vericto SQL Check::api-url uses plain http: the API key and the SQL travel unencrypted." "with a warning"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql
case "$(logged args)" in *--dialect* | *--baseline* | *--timeout* | *--api-url*) not_ok "empty inputs add flags" "$(logged args)" ;; *) ok "empty inputs add no flags (CLI defaults)" ;; esac

echo "# files: paths, directories and globs"
files_for() { # PATTERNS: prints the file list the CLI received, or the exit code
  check "$ws" VA_API_KEY="$KEY" VA_FILES="$1"
  if [ -f "$TMP/log/files" ]; then logged files; else printf 'exit %s' "$rc"; fi
}
expect_eq "$(files_for migrations/0001_create_users.sql)" "migrations/0001_create_users.sql" "one file"
expect_eq "$(files_for ./migrations/0001_create_users.sql)" "migrations/0001_create_users.sql" "a leading ./ is dropped"
expect_eq "$(files_for 'migrations/*.sql')" "migrations/0001_create_users.sql
migrations/0002_cleanup.sql" "a * glob"
expect_eq "$(files_for 'migrations/000?_*.sql')" "migrations/0001_create_users.sql
migrations/0002_cleanup.sql" "a ? glob"
expect_eq "$(files_for 'migrations/000[2-9]_*.sql')" "migrations/0002_cleanup.sql" "a [...] glob"
expect_eq "$(files_for migrations)" "migrations/0001_create_users.sql
migrations/0002_cleanup.sql" "a directory: its *.sql files only"
expect_eq "$(files_for spaced)" "spaced/with space.sql" "a file name with a space, found through a directory"
expect_eq "$(files_for '**/*.sql')" "migrations/0001_create_users.sql
migrations/0002_cleanup.sql
nested/deep/0003_index.sql
spaced/with space.sql" "** finds nested files, sorted, and skips hidden directories"
expect_eq "$(files_for 'nested/**/*.sql')" "nested/deep/0003_index.sql" "** below a literal base"
expect_eq "$(files_for '**/0003_index.sql')" "nested/deep/0003_index.sql" "**/ matches any depth"
expect_eq "$(files_for 'nested/**')" "nested/deep/0003_index.sql" "a trailing ** matches everything below"
expect_eq "$(files_for '**.sql')" "migrations/0001_create_users.sql
migrations/0002_cleanup.sql
nested/deep/0003_index.sql
spaced/with space.sql" "** without a slash crosses directories"
expect_eq "$(files_for '**/000[!12]_*.sql')" "nested/deep/0003_index.sql" "** with a negated bracket"
expect_eq "$(files_for '**/0001_create_users.s?l')" "migrations/0001_create_users.sql" "** with ?"
expect_eq "$(files_for "$(printf 'migrations\nmigrations/*.sql nested')")" "migrations/0001_create_users.sql
migrations/0002_cleanup.sql
nested/deep/0003_index.sql" "patterns on several lines; duplicates checked once"
expect_eq "$(files_for '**/0001_create_users_sql')" "exit 2" "a . in a ** pattern is literal"
expect_eq "$(files_for '**/[abc')" "exit 2" "an unclosed [ in a ** pattern is literal"
expect_eq "$(files_for 'missing/**/*.sql')" "exit 2" "a ** pattern under a missing directory matches nothing"
check "$ws" VA_API_KEY="$KEY" VA_FILES='nothing/*.sql'
expect_usage_error "no SQL files found" "no SQL files match 'nothing/*.sql'"
check "$ws" VA_API_KEY="$KEY" VA_FILES='migrations/*.sql nothing.sql'
expect_usage_error "every pattern must match" "no SQL files match 'nothing.sql'"
check "$ws" VA_API_KEY="$KEY" VA_FILES=--help
expect_usage_error "a pattern that looks like an option" "file pattern '--help' must not start with '-'"
check "$ws" VA_API_KEY="$KEY" VA_FILES="\$(touch $TMP/pwned-files) \`touch $TMP/pwned-files\`"
expect_rc 2 "hostile files"
if ls "$TMP"/pwned-* >/dev/null 2>&1; then not_ok "a files pattern was executed"; else ok "hostile files ran nothing"; fi
check "$ws" VA_API_KEY="$KEY" VA_FILES='   '
expect_usage_error "whitespace-only files means changed files, which needs git" "changed needs a git checkout"

echo "# results, outputs and annotations"
check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql
expect_rc 0 "no findings: exit 0"
expect_output result pass "result pass"
expect_output blocked 0 "blocked 0"
expect_output flagged 0 "flagged 0"
expect_output monitored 0 "monitored 0"
expect_output parse-errors 0 "parse-errors 0"
sarif=$(output_of sarif-file)
if [ -s "$sarif" ]; then ok "sarif-file points at the report"; else not_ok "sarif-file" "$outputs"; fi
expect_output report-file "$sarif" "report-file is the same report"
expect_out "Running: vericto check --format=sarif --stdin-file-list --output=" "logs the command"
case "$(summary)" in
  *"### Vericto SQL Check: PASS"*"| Blocked / flagged / monitored / parse errors | 0 / 0 / 0 / 0 |"*"| SQL checked | 1 file(s) from \`files\` |"*"| CLI | \`vericto 1.8.2\` |"*)
    ok "job summary: result, counts, selection and CLI version" ;;
  *) not_ok "job summary" "$(summary)" ;;
esac

check "$ws" VA_API_KEY="$KEY" VA_FILES='migrations/*.sql'
expect_rc 1 "a BLOCKED finding: exit 1"
expect_output result fail "result fail"
expect_output blocked 1 "blocked 1"
expect_out "migrations/0002_cleanup.sql:2: [BLOCKED] VERICTO-001" "the CLI's findings are in the log"
expect_out "::error title=Vericto SQL Check::Vericto found SQL at or above fail_on in this change." "an error annotation"
if [ -s "$(output_of sarif-file)" ]; then ok "the SARIF is still uploaded on exit 1"; else not_ok "sarif-file on exit 1"; fi

check "$ws" VA_API_KEY="$KEY" VA_FILES='migrations/*.sql' FAKE_DECISION=FLAGGED
expect_rc 0 "FLAGGED findings below fail_on: exit 0"
expect_output result warn "result warn"
expect_output flagged 1 "flagged 1"
case "$(summary)" in *"### Vericto SQL Check: WARN"*) ok "WARN in the summary" ;; *) not_ok "WARN summary" "$(summary)" ;; esac

check "$ws" VA_API_KEY="$KEY" VA_FILES='migrations/*.sql' VA_FORMAT=json FAKE_DECISION=FLAGGED
expect_rc 0 "json format"
expect_output flagged 1 "counts come from the json summary"
expect_output result warn "result warn from json"
expect_output sarif-file "" "no sarif-file for json"
case "$(output_of report-file)" in *.json) ok "report-file is the json report" ;; *) not_ok "json report-file" "$outputs" ;; esac

for f in gitlab-codequality:gl-code-quality.json gitlab-sast:gl-sast-report.json; do
  check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql VA_FORMAT="${f%%:*}"
  case "$(output_of report-file)" in *"/vericto.${f#*:}") ok "${f%%:*}: report-file ends in .${f#*:}" ;; *) not_ok "${f%%:*} report-file" "$outputs" ;; esac
  expect_output sarif-file "" "${f%%:*}: no sarif-file"
  expect_output blocked "" "${f%%:*}: no counts"
  expect_output result pass "${f%%:*}: result from the exit code"
done

check "$ws" VA_API_KEY="$KEY" VA_FILES='migrations/*.sql' VA_FORMAT=text
expect_rc 1 "text format"
case "$(logged args)" in *--output*) not_ok "text has --output" ;; *) ok "text goes to the log, no --output" ;; esac
expect_output report-file "" "no report-file for text"
expect_output result fail "result from the exit code"

for c in 2:"vericto check failed with a usage error (exit 2); see the log above." \
  3:"Vericto rejected the credentials (exit 3): check the API key or the OIDC trust policy" \
  4:"The Vericto API was unreachable or returned an error (exit 4). No verdict was given and no result is assumed." \
  70:"vericto check exited with 70."; do
  code=${c%%:*}
  check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations FAKE_EXIT="$code"
  expect_rc "$code" "the CLI's exit $code is the step's"
  expect_output exit-code "$code" "exit-code $code"
  expect_output result fail "exit $code: result fail"
  expect_output sarif-file "" "exit $code: no report, no sarif-file"
  expect_output blocked "" "exit $code: no counts"
  expect_out "::error title=Vericto SQL Check::${c#*:}" "exit $code: annotation"
done
case "$(summary)" in *"| Exit code | \`70\` (unexpected exit code) |"*) ok "an unknown exit code is named in the summary" ;; *) not_ok "summary for exit 70" "$(summary)" ;; esac

check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql FAKE_NO_REPORT=1
expect_rc 0 "exit 0 without a report (nothing to check)"
expect_output blocked 0 "counts are 0"
expect_output sarif-file "" "and there is nothing to upload"
expect_output result pass "result pass"

check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql FAKE_REPORT="$FIXTURES/reports/mixed.sarif"
expect_output blocked 1 "SARIF counts: [BLOCKED]"
expect_output flagged 2 "SARIF counts: [FLAGGED]"
expect_output monitored 1 "SARIF counts: [MONITORED]"
expect_output parse-errors 1 "SARIF counts: Could not parse"
expect_output result warn "findings with exit 0 are a warning"
expect_output checkout-path "" "no checkout-path outside git"

tools=(bash env dirname grep git mktemp rm tr find sort awk wc cat cp sed head printf)
nojq=$(minimal_path "$TMP/no-jq" "${tools[@]}")
TEST_PATH="$nojq" check "$ws" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql
expect_rc 0 "runs without jq"
expect_output blocked "" "no counts without jq"
if [ -n "$(output_of sarif-file)" ]; then ok "the SARIF is still reported without jq"; else not_ok "sarif-file without jq"; fi

echo "# inside a git checkout"
repo="$TMP/repo"
mkdir -p "$repo/db"
cp -R "$FIXTURES/migrations" "$repo/db/"
g() { git -C "$repo" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }
g init -q
g add -A
g commit -q -m base
base=$(g rev-parse HEAD)
printf 'DELETE FROM users WHERE id = 1;\n' >"$repo/db/migrations/0003_fix.sql"
g add -A
g commit -q -m change
toplevel=$(cd "$repo" && git rev-parse --show-toplevel)

check "$repo/db" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql FAKE_REPORT="$FIXTURES/reports/mixed.sarif"
expect_rc 0 "files mode from a subdirectory"
expect_output checkout-path "$toplevel" "checkout-path is the repository root"
uris=$(jq -r '.runs[].results[].locations[].physicalLocation.artifactLocation.uri' "$(output_of sarif-file)" | tr '\n' ' ')
expect_eq "$uris" "db/migrations/0002_cleanup.sql /abs/path/report.sql file:///tmp/x.sql <stdin> C:/runner/x.sql " \
  "SARIF paths are made relative to the repository root; absolute paths and URIs are kept"
TEST_PATH="$nojq" check "$repo/db" VA_API_KEY="$KEY" VA_FILES=migrations/0001_create_users.sql
expect_out "jq not found: SARIF paths stay relative to working-directory" "warns when it cannot rewrite the paths"

echo "# changed files"
changed_args() { logged args | grep -E '^--(since|changed)' || true; }
check "$repo" VA_API_KEY="$KEY"
expect_rc 0 "changed is the default when files is empty"
expect_eq "$(changed_args)" "--changed" "no base known: the CLI's --changed"
case "$(summary)" in *"| SQL checked | *.sql changed vs \`origin/HEAD\` |"*) ok "summary names the base" ;; *) not_ok "summary for --changed" "$(summary)" ;; esac
check "$repo" VA_API_KEY="$KEY" GITHUB_BASE_REF=main VA_EVENT_NAME=pull_request VA_EVENT_BEFORE="$base"
expect_eq "$(changed_args)" "--changed" "pull_request: the CLI diffs against the base branch"
case "$(summary)" in *"changed vs \`origin/main\`"*) ok "pull_request summary" ;; *) not_ok "pull_request summary" "$(summary)" ;; esac
check "$repo" VA_API_KEY="$KEY" VA_EVENT_NAME=push VA_EVENT_BEFORE="$base"
expect_eq "$(changed_args)" "--since=$base" "push: the previous commit"
check "$repo" VA_API_KEY="$KEY" VA_EVENT_NAME=push VA_EVENT_BEFORE=0000000000000000000000000000000000000000
expect_eq "$(changed_args)" "--changed" "push of a new branch (zero before): no --since"
check "$repo" VA_API_KEY="$KEY" VA_EVENT_NAME=merge_group VA_MERGE_GROUP_BASE="$base"
expect_eq "$(changed_args)" "--since=$base" "merge_group: the queue's base"
check "$repo" VA_API_KEY="$KEY" VA_EVENT_NAME=merge_group VA_MERGE_GROUP_BASE=not-a-sha
expect_eq "$(changed_args)" "--changed" "merge_group with an invalid base: no --since"
g update-ref refs/remotes/origin/main "$base"
check "$repo" VA_API_KEY="$KEY" VA_EVENT_NAME=workflow_dispatch VA_DEFAULT_BRANCH=main
expect_eq "$(changed_args)" "--since=origin/main" "other events: the default branch"
check "$repo" VA_API_KEY="$KEY" VA_DEFAULT_BRANCH=trunk
expect_eq "$(changed_args)" "--changed" "a default branch without a remote ref: no --since"
check "$repo" VA_API_KEY="$KEY" VA_SINCE="v1.0.0" VA_EVENT_NAME=push VA_EVENT_BEFORE="$base"
expect_eq "$(changed_args)" "--since=v1.0.0" "since wins over the event"
case "$(summary)" in *"| SQL checked | *.sql changed since \`v1.0.0\` |"*) ok "since in the summary" ;; *) not_ok "since summary" "$(summary)" ;; esac
check "$repo" VA_API_KEY="$KEY" VA_SINCE='main|x'
# shellcheck disable=SC2016 # literal backticks of the Markdown summary
case "$(summary)" in *'changed since `main_x`'*) ok "a ref is made inert in the Markdown summary" ;; *) not_ok "md_safe" "$(summary)" ;; esac
check "$repo" VA_API_KEY="$KEY" VA_CHANGED=true
expect_rc 0 "changed: true explicitly"
check "$repo/db" VA_API_KEY="$KEY"
expect_usage_error "changed from a subdirectory" "changed must run from the root of the git checkout"
check "$ws" VA_API_KEY="$KEY"
expect_usage_error "changed outside git" "changed needs a git checkout: use actions/checkout with fetch-depth: 0"
check "$repo" VA_API_KEY="$KEY" FAKE_NO_REPORT=1
expect_output result pass "no changed SQL: pass"
expect_output blocked 0 "no changed SQL: counts 0"
for v in $'origin/main\n--x' $'origin/main\r\n--x' $'origin/main\n'; do
  check "$repo" VA_API_KEY="$KEY" VA_SINCE="$v"
  expect_usage_error "multi-line since in a git checkout $(printf '%q' "$v")" "input 'since' must be a git ref, e.g. origin/main"
done

# VA_FILES unset (a direct run; action.yml always sets it), and every other
# optional input with it: changed files, on bash 3.2 and 4+ alike (set -u
# used to abort on bash 4+ with "VA_FILES: unbound variable").
rm -f "$TMP/log/"*
cd "$repo"
run VA_BIN="$FAKE" FAKE_LOG_DIR="$TMP/log" VA_API_KEY="$KEY" bash "$SCRIPTS/check.sh"
cd "$ROOT"
expect_rc 0 "an unset VA_FILES means changed files"
expect_no_out "unbound variable" "an unset VA_FILES: no set -u abort"
expect_eq "$(changed_args)" "--changed" "an unset VA_FILES: --changed"

shallow="$TMP/shallow"
git clone -q --depth 1 "file://$repo" "$shallow"
check "$shallow" VA_API_KEY="$KEY"
expect_out "::warning title=Vericto SQL Check::shallow clone: the base commit may be missing. Use actions/checkout with fetch-depth: 0." "warns about a shallow clone"
check "$shallow" VA_API_KEY="$KEY" FAKE_EXIT=2
expect_out "The checkout is shallow: use actions/checkout with fetch-depth: 0." "a usage error in a shallow clone says why"

finish
