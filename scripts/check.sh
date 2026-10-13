#!/usr/bin/env bash
# Runs `vericto check` with the action's inputs and mirrors its verdict.
#
# Every input arrives as an environment variable (VA_*), never interpolated
# into this script, and reaches the CLI as a single quoted argument or an env
# var. The API key is passed to the CLI only through VERICTO_API_KEY, never on
# the command line, and is masked in the log first.
#
# Out (step outputs): exit-code, result, sarif-file, report-file, blocked,
# flagged, monitored, parse-errors, checkout-path. Exits with the CLI's code.
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

# Mask credentials before anything else can print them.
[ -n "${VA_API_KEY:-}" ] && gh_mask "$VA_API_KEY"
[ -n "${VERICTO_API_KEY:-}" ] && gh_mask "$VERICTO_API_KEY"

mode=""
selection=""
cli_version=""
code=""
result=""
blocked="" flagged="" monitored="" parse_errors=""

exit_meaning() {
  case "$1" in
    0) echo "nothing at or above fail_on" ;;
    1) echo "a finding at or above fail_on" ;;
    2) echo "usage error" ;;
    3) echo "authentication or plan error" ;;
    4) echo "backend or network error, no verdict" ;;
    *) echo "unexpected exit code" ;;
  esac
}

# Keeps user-controlled text (refs, paths) inert in the Markdown summary.
md_safe() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._/@-' '_'; }

write_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  local label counts=""
  case "$result" in
    pass) label=PASS ;;
    warn) label=WARN ;;
    *) label=FAIL ;;
  esac
  if [ -n "$blocked" ]; then
    counts="| Blocked / flagged / monitored / parse errors | $blocked / $flagged / $monitored / $parse_errors |"
  fi
  {
    echo "### Vericto SQL Check: $label"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Result | \`$result\` |"
    echo "| Exit code | \`$code\` ($(exit_meaning "$code")) |"
    [ -n "$counts" ] && echo "$counts"
    [ -n "$selection" ] && echo "| SQL checked | $selection |"
    [ -n "$cli_version" ] && echo "| CLI | \`$cli_version\` |"
    echo
  } >>"$GITHUB_STEP_SUMMARY"
}

# Fails before the CLI runs: 2 for bad inputs, 3 for missing credentials,
# the same meanings the CLI uses.
fail() {
  code=$1
  shift
  result=fail
  gh_error "$*"
  set_output exit-code "$code"
  set_output result "$result"
  write_summary
  exit "$code"
}

bool_input() { # NAME VALUE VAR: stores true/false in VAR
  case "$2" in
    true | True | TRUE) printf -v "$3" true ;;
    false | False | FALSE) printf -v "$3" false ;;
    *) fail 2 "input '$1' must be true or false (got '$2')" ;;
  esac
}

matches() { printf '%s' "$2" | grep -Eq "$1"; }

: "${VA_BIN:?the install step did not provide a binary}"

# ── Validate inputs ──────────────────────────────────────────────────────────
format=${VA_FORMAT:-sarif}
case "$format" in
  sarif) ext=sarif ;;
  json) ext=json ;;
  gitlab-codequality) ext=gl-code-quality.json ;;
  gitlab-sast) ext=gl-sast-report.json ;;
  text) ext="" ;;
  *) fail 2 "input 'format' must be sarif, json, text, gitlab-codequality or gitlab-sast (got '$format')" ;;
esac
oidc=false changed=""
bool_input oidc "${VA_OIDC:-false}" oidc
# upload-sarif drives the upload step in action.yml; validated here so a typo
# fails loudly instead of silently skipping the upload.
case "${VA_UPLOAD_SARIF:-true}" in
  true | True | TRUE | false | False | FALSE) ;;
  *) fail 2 "input 'upload-sarif' must be true or false (got '$VA_UPLOAD_SARIF')" ;;
esac
if [ -n "${VA_CHANGED:-}" ]; then bool_input changed "$VA_CHANGED" changed; fi

dialect=${VA_DIALECT:-}
if [ -n "$dialect" ] && ! matches '^[a-z][a-z0-9_]{0,31}$' "$dialect"; then
  fail 2 "input 'dialect' must be a dialect name such as postgres, mysql, oracle or mssql (got '$dialect')"
fi
timeout=${VA_TIMEOUT:-}
if [ -n "$timeout" ] && ! matches '^[1-9][0-9]{0,4}$' "$timeout"; then
  fail 2 "input 'timeout' must be a whole number of seconds (got '$timeout')"
fi
api_url=${VA_API_URL:-}
if [ -n "$api_url" ]; then
  matches '^https?://[^[:space:]]+$' "$api_url" || fail 2 "input 'api-url' must be an http(s) URL"
  case "$api_url" in http://*) gh_warning "api-url uses plain http: the API key and the SQL travel unencrypted." ;; esac
fi
workspace=${VA_WORKSPACE:-}
if [ -n "$workspace" ] && ! matches '^[A-Za-z0-9_.:-]{1,128}$' "$workspace"; then
  fail 2 "input 'workspace' must be a workspace ID such as ws_123"
fi
since=${VA_SINCE:-}
if [ -n "$since" ] && ! matches '^[^-[:space:][:cntrl:]][^[:space:][:cntrl:]]*$' "$since"; then
  fail 2 "input 'since' must be a git ref, e.g. origin/main (got '$since')"
fi
baseline=${VA_BASELINE:-}
case "$baseline" in *$'\n'* | *$'\r'*) fail 2 "input 'baseline' must be a single path" ;; esac

# ── Credentials ──────────────────────────────────────────────────────────────
args=(check "--format=$format")
if [ "$oidc" = true ]; then
  [ -n "${VA_API_KEY:-}" ] && fail 2 "set either api-key or oidc: true, not both"
  # A job-level static key must not win over the OIDC login asked for here.
  unset VERICTO_API_KEY
  if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
    fail 3 "oidc: true needs 'permissions: id-token: write' on the job (no OIDC token is available)"
  fi
  args+=(--oidc)
  [ -n "$workspace" ] && export VERICTO_WORKSPACE_ID="$workspace"
elif [ -n "${VA_API_KEY:-}" ]; then
  export VERICTO_API_KEY="$VA_API_KEY"
elif [ -z "${VERICTO_API_KEY:-}" ]; then
  fail 3 "no credentials: set 'api-key: \${{ secrets.VERICTO_API_KEY }}', or 'oidc: true' with 'workspace'"
fi
unset VA_API_KEY

[ -n "$dialect" ] && args+=("--dialect=$dialect")
[ -n "$baseline" ] && args+=("--baseline=$baseline")
[ -n "$timeout" ] && args+=("--timeout=$timeout")
[ -n "$api_url" ] && args+=("--api-url=$api_url")

work=$(make_temp_dir check)
trap 'rm -rf "$work"' EXIT

in_git=false
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=true

# ── What to check ────────────────────────────────────────────────────────────
expand_files() { # OUT
  local out=$1 pat m n f i
  local -a pats found
  [ "${BASH_VERSINFO[0]}" -ge 4 ] && shopt -s globstar
  shopt -s nullglob
  read -r -d '' -a pats <<<"$VA_FILES" || true
  [ "${#pats[@]}" -gt 0 ] || fail 2 "input 'files' holds no patterns"
  # From here on, expand globs without word splitting.
  local IFS=''
  : >"$out.raw"
  for pat in "${pats[@]}"; do
    case "$pat" in -*) fail 2 "file pattern '$pat' must not start with '-'" ;; esac
    case "$pat" in
      *'**'*) [ "${BASH_VERSINFO[0]}" -ge 4 ] || fail 2 "'**' patterns need bash 4 or later on the runner" ;;
    esac
    found=()
    # Intentional: expand the glob (IFS is empty, so nothing is split).
    # shellcheck disable=SC2206
    found=($pat)
    n=0 i=0
    # An index loop: bash 3.2 joins "${found[@]}" when IFS is empty.
    while [ "$i" -lt "${#found[@]}" ]; do
      m=${found[$i]}
      i=$((i + 1))
      case "$m" in *$'\n'* | *$'\r'*) fail 2 "file names with line breaks are not supported" ;; esac
      m=${m#./}
      if [ -d "$m" ]; then
        while IFS= read -r f; do
          printf '%s\n' "${f#./}" >>"$out.raw"
          n=$((n + 1))
        done < <(find "$m" -type f -name '*.sql' | LC_ALL=C sort)
      elif [ -f "$m" ]; then
        printf '%s\n' "$m" >>"$out.raw"
        n=$((n + 1))
      fi
    done
    [ "$n" -gt 0 ] || fail 2 "no SQL files match '$pat' (relative to $(md_safe "$(pwd)"))"
  done
  awk '!seen[$0]++' "$out.raw" >"$out"
}

if [ -n "${VA_FILES//[[:space:]]/}" ]; then
  [ "$changed" = true ] && fail 2 "set either files or changed: true, not both"
  [ -n "$since" ] && fail 2 "set either files or since, not both"
  mode=files
  list="$work/files.txt"
  expand_files "$list"
  count=$(wc -l <"$list" | tr -d ' ')
  selection="$count file(s) from \`files\`"
  args+=(--stdin-file-list)
else
  [ "$changed" = false ] && fail 2 "nothing to check: set files, or leave changed on"
  mode=changed
  [ "$in_git" = true ] || fail 2 "changed needs a git checkout: use actions/checkout with fetch-depth: 0"
  if [ -n "$(git rev-parse --show-prefix)" ]; then
    fail 2 "changed must run from the root of the git checkout (git reports paths from there); set working-directory to it, or use files"
  fi
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    gh_warning "shallow clone: the base commit may be missing. Use actions/checkout with fetch-depth: 0."
  fi
  is_commit() { matches '^([0-9a-f]{40}|[0-9a-f]{64})$' "$1" && git cat-file -e "$1^{commit}" 2>/dev/null; }
  if [ -z "$since" ] && [ -z "${GITHUB_BASE_REF:-}" ]; then
    # Not a pull request: pick the base the CLI cannot infer on its own.
    if [ "${VA_EVENT_NAME:-}" = merge_group ] && is_commit "${VA_MERGE_GROUP_BASE:-}"; then
      since=$VA_MERGE_GROUP_BASE
    elif [ "${VA_EVENT_NAME:-}" = push ] && is_commit "${VA_EVENT_BEFORE:-}"; then
      since=$VA_EVENT_BEFORE
    elif [ -n "${VA_DEFAULT_BRANCH:-}" ] && git rev-parse -q --verify "refs/remotes/origin/$VA_DEFAULT_BRANCH" >/dev/null; then
      since="origin/$VA_DEFAULT_BRANCH"
    fi
  fi
  if [ -n "$since" ]; then
    args+=("--since=$since")
    selection="*.sql changed since \`$(md_safe "$since")\`"
  else
    args+=(--changed)
    selection="*.sql changed vs \`origin/$(md_safe "${GITHUB_BASE_REF:-HEAD}")\`"
  fi
fi

report=""
if [ -n "$ext" ]; then
  report_dir=$(make_temp_dir report)
  report="$report_dir/vericto.$ext"
  args+=("--output=$(native_path "$report")")
fi

cli_version=$("$VA_BIN" --version | tr -d '\r')

# ── Run ──────────────────────────────────────────────────────────────────────
echo "Running: vericto ${args[*]}"
set +e
if [ "$mode" = files ]; then
  "$VA_BIN" "${args[@]}" <"$list"
else
  "$VA_BIN" "${args[@]}" </dev/null
fi
code=$?
set -e

# ── Results ──────────────────────────────────────────────────────────────────
prefix=""
if [ "$in_git" = true ]; then
  set_output checkout-path "$(native_path "$(git rev-parse --show-toplevel)")"
  prefix=$(git rev-parse --show-prefix)
fi

have_jq=false
command -v jq >/dev/null 2>&1 && have_jq=true

if [ -n "$report" ] && [ -f "$report" ]; then
  set_output report-file "$(native_path "$report")"
  if [ "$format" = sarif ]; then
    # Files mode reports paths relative to working-directory; Code Scanning
    # wants them relative to the repository root.
    if [ "$mode" = files ] && [ -n "$prefix" ]; then
      if [ "$have_jq" = true ]; then
        jq --arg p "$prefix" '(.runs[]?.results[]?.locations[]?.physicalLocation.artifactLocation.uri)
          |= (if type == "string" and (test("^([A-Za-z][A-Za-z0-9+.-]*:|/|<)") | not) then $p + . else . end)' \
          "$report" >"$report.tmp" && mv "$report.tmp" "$report"
      else
        gh_warning "jq not found: SARIF paths stay relative to working-directory, so annotations may not attach to files."
      fi
    fi
    set_output sarif-file "$(native_path "$report")"
  fi
  if [ "$have_jq" = true ]; then
    counts=""
    case "$format" in
      sarif)
        counts=$(jq -r '[.runs[]?.results[]?.message.text // ""]
          | [(map(select(test("\\[BLOCKED\\]"))) | length),
             (map(select(test("\\[FLAGGED\\]"))) | length),
             (map(select(test("\\[MONITORED\\]"))) | length),
             (map(select(startswith("Could not parse"))) | length)] | @tsv' "$report" 2>/dev/null) || counts=""
        ;;
      json)
        counts=$(jq -r '.summary | [.blocked, .flagged, .monitored, .parse_errors] | map(. // 0) | @tsv' "$report" 2>/dev/null) || counts=""
        ;;
    esac
    counts=$(printf '%s' "$counts" | tr -d '\r')
    tab=$'\t'
    if matches "^[0-9]+${tab}[0-9]+${tab}[0-9]+${tab}[0-9]+\$" "$counts"; then
      IFS=$'\t' read -r blocked flagged monitored parse_errors <<<"$counts"
    fi
  fi
elif [ "$code" -eq 0 ] && [ -n "$ext" ]; then
  # Exit 0 without a report: nothing matched (e.g. no changed SQL).
  blocked=0 flagged=0 monitored=0 parse_errors=0
fi

if [ "$code" -ne 0 ]; then
  result=fail
elif [ -n "$blocked" ] && [ $((blocked + flagged + monitored + parse_errors)) -gt 0 ]; then
  result=warn
else
  result=pass
fi

set_output exit-code "$code"
set_output result "$result"
set_output blocked "$blocked"
set_output flagged "$flagged"
set_output monitored "$monitored"
set_output parse-errors "$parse_errors"
write_summary

case "$code" in
  0) ;;
  1) gh_error "Vericto found SQL at or above fail_on in this change. See the annotations above and in Code Scanning." ;;
  2)
    msg="vericto check failed with a usage error (exit 2); see the log above."
    if [ "$mode" = changed ] && [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
      msg="$msg The checkout is shallow: use actions/checkout with fetch-depth: 0."
    fi
    gh_error "$msg"
    ;;
  3) gh_error "Vericto rejected the credentials (exit 3): check the API key or the OIDC trust policy, its scope (ci_dryrun:execute) and the plan's monthly CLI allowance." ;;
  4) gh_error "The Vericto API was unreachable or returned an error (exit 4). No verdict was given and no result is assumed." ;;
  *) gh_error "vericto check exited with $code." ;;
esac
exit "$code"
