#!/bin/bash
# Run secret scan, lint and model review for one pull request.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: run-checks.sh

Run the checks for the current job.
Expects a checkout from checkout.sh and the job environment.
Posts one pull request comment through host.sh.
Never prints a token or a review key.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi
if [ $# -ne 0 ]; then
  usage >&2
  exit 1
fi

event=$(ci_read_state event-name)
pr=$(ci_read_state pr-number)
head=$(ci_read_state head-sha)
base=$(ci_read_state base-sha)
# Owners come from the base tip. An older checkout.sh writes no tools-sha.
tools_sha=$(ci_read_state tools-sha 2>/dev/null || true)
tools_sha=${tools_sha:-$base}
owner=${GITHUB_REPOSITORY%%/*}
repo=${GITHUB_REPOSITORY#*/}

tools=$(ci_read_state tools-dir || true)
if [ -z "$tools" ]; then
  ci_die 1 "checks failed: the base tools are missing"
fi
export OS_CHECK_TOOLS=$tools

if [ -z "${JOB_TOKEN:-}" ]; then
  ci_die 1 "checks failed: the job token is missing"
fi

prepare_host() {
  if ci_is_github; then
    export OS_HOST=github
  else
    export OS_HOST=forgejo
    export OS_HOST_URL="${GITHUB_SERVER_URL%/}"
  fi
  export OS_ORG="$owner"
  export OS_SLUG="${OS_SLUG:-$owner}"
  export FORGEJO_TOKEN="$JOB_TOKEN"
  export GH_TOKEN="$JOB_TOKEN"
}

post_comment() {
  local file=$1 host_bin out err rc
  host_bin="${tools}/.github/scripts/tools/host/host.sh"
  if [ ! -f "$host_bin" ]; then
    ci_die 1 "could not post the review comment: the host layer is missing"
  fi
  prepare_host
  out=$(ci_mktemp)
  err=$(ci_mktemp)
  set +e
  env -u OS_REVIEW_KEY bash "$host_bin" pr-comment "$repo" "$pr" --body-file "$file" >"$out" 2>"$err"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    ci_die 1 "could not post the review comment"
  fi
}

GATES_LINE=""
run_gates() {
  local range="${base}..${head}" scan_rc=0 lint_rc=0 scan lint
  scan="${tools}/.github/scripts/tools/secret-scan.sh"
  lint="${tools}/.github/scripts/tools/lint.sh"
  if [ -f "$scan" ]; then
    set +e
    bash "$scan" --range "$range"
    scan_rc=$?
    set -e
  elif command -v gitleaks >/dev/null 2>&1; then
    set +e
    gitleaks detect --redact --no-banner --log-opts "$range"
    scan_rc=$?
    set -e
  else
    ci_summary_add "secret scan failed: .github/scripts/tools/secret-scan.sh is missing and gitleaks is not installed"
    return 1
  fi
  if [ "$scan_rc" -ne 0 ]; then
    ci_summary_add "secret scan failed"
    return 1
  fi
  if [ -f "$lint" ]; then
    set +e
    bash "$lint" --ci --base "$base"
    lint_rc=$?
    set -e
    if [ "$lint_rc" -ne 0 ]; then
      ci_summary_add "lint failed"
      return 1
    fi
  else
    ci_summary_add "lint skipped: .github/scripts/tools/lint.sh is missing"
    GATES_LINE="secret scan: pass, lint: skipped"
    return 0
  fi
  GATES_LINE="secret scan: pass, lint: pass"
  return 0
}

# B51: on GitHub an /override re-runs this pull request's failed run (set-status.sh).
# That run passes when the override job left its line for this head commit, and the
# person it names wrote an /override that override.sh still accepts on the base.
# Only the job's own bot writes that line; a person's comment cannot stand in for it.
override_for_head() {
  local comments marker user note event_json decision
  ci_is_github || return 1
  [ -n "$pr" ] || return 1
  comments=$(ci_mktemp)
  if ! bash "$DIR/host-read.sh" comments "$owner" "$repo" "$pr" > "$comments" 2>/dev/null; then
    return 1
  fi
  marker=$(jq -r --arg head "$head" '
    [.[] | select(.login == "github-actions[bot]") | (.body | rtrimstr("\n"))
      | select(split("\n") | length == 1)
      | select(test("^override by [A-Za-z0-9][A-Za-z0-9-]* for " + $head + ": "))] | last // empty' "$comments")
  [ -n "$marker" ] || return 1
  user=${marker#override by }
  user=${user%% *}
  note=$(ci_mktemp)
  event_json=$(ci_mktemp)
  jq -r --arg user "$user" '[.[] | select((.login | ascii_downcase) == ($user | ascii_downcase))
    | select(.body | test("^\\s*/override"))] | last // empty | .body' "$comments" > "$note"
  [ -s "$note" ] || return 1
  jq --arg user "$user" '[.[] | select((.login | ascii_downcase) == ($user | ascii_downcase))
    | select(.body | test("^\\s*/override"))] | last | {comment: {author_association: (.association // "")}}' \
    "$comments" > "$event_json"
  decision=$(bash "$DIR/override.sh" --user "$user" --comment-file "$note" --base "$tools_sha" --event-file "$event_json")
  case "$decision" in
    valid\ *)
      ci_summary_add "$marker"
      return 0
      ;;
  esac
  return 1
}

if [ "$event" = "issue_comment" ]; then
  comment_file=$(ci_mktemp)
  user=$(jq -r '.comment.user.login // empty' "$GITHUB_EVENT_PATH")
  jq -r '.comment.body // empty' "$GITHUB_EVENT_PATH" > "$comment_file"
  decision=$(bash "$DIR/override.sh" --user "$user" --comment-file "$comment_file" --base "$tools_sha" --event-file "$GITHUB_EVENT_PATH")
  case "$decision" in
    valid\ *)
      reason=${decision#valid }
      if ! run_gates; then
        exit 1
      fi
      msg="override by ${user} for ${head}: ${reason}"
      note=$(ci_mktemp)
      printf '%s\n' "$msg" > "$note"
      ci_summary_add "$msg"
      # The line goes first: on GitHub the re-run reads it.
      post_comment "$note"
      bash "$DIR/set-status.sh" "$head" success "$msg"
      exit 0
      ;;
    ignored\ empty)
      msg="override ignored: reason is empty"
      ;;
    *)
      msg="override ignored: ${user} is not an owner"
      ;;
  esac
  note=$(ci_mktemp)
  printf '%s\n' "$msg" > "$note"
  ci_summary_add "$msg"
  post_comment "$note"
  exit 0
fi

if ! run_gates; then
  exit 1
fi
if override_for_head; then
  exit 0
fi
range="${base}..${head}"

title_file=$(ci_mktemp)
body_file=$(ci_mktemp)
diff_file=$(ci_mktemp)
if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
  jq -r '.pull_request.title // empty' "$GITHUB_EVENT_PATH" > "$title_file"
  jq -r '.pull_request.body // empty' "$GITHUB_EVENT_PATH" > "$body_file"
fi
# A file exactly as a release shipped it is left out. The stock list comes from the base.
bash "$DIR/review-diff.sh" "$range" "${tools}/.github/scripts/stock-current.txt" > "$diff_file"

review_rc=0
out=$(ci_mktemp)
# Base copies only. The head is data. A missing root file falls back to the
# default shipped with the check scripts, still from the base.
rules="${tools}/review-rules.md"
if [ ! -f "$rules" ]; then
  rules="${tools}/.github/scripts/review-rules.default.md"
  if [ ! -f "$rules" ]; then
    ci_die 1 "model review failed: review-rules.md is missing"
  fi
  ci_summary_add "model review: using default rules (review-rules.md is not on main yet)"
fi
set +e
bash "$DIR/model-review.sh" \
  --rules "$rules" \
  --title-file "$title_file" \
  --body-file "$body_file" \
  --diff-file "$diff_file" \
  --out "$out"
review_rc=$?
set -e
if [ ! -s "$out" ] && [ "$review_rc" -ne 0 ]; then
  ci_die 1 "model review failed: no review text"
fi

ci_summary_add "$(cat "$out")"
# The comment shows the gates too: the override line names them (v1.0.2).
comment=$(ci_mktemp)
{ printf '%s\n\n' "$GATES_LINE"; cat "$out"; } > "$comment"
post_comment "$comment"
if [ "$review_rc" -ne 0 ]; then
  # An /override may have come in while the review ran.
  if override_for_head; then
    exit 0
  fi
  exit 1
fi
exit 0
