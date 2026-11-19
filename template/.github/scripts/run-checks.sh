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
# v1.0.4: /approve works the same way, with the line "approved by <login> for <head>: ".
# command_for_head override|approve
command_for_head() {
  local command=$1 prefix comments marker user note event_json decision
  case "$command" in
    override) prefix="override by" ;;
    approve) prefix="approved by" ;;
    *) return 1 ;;
  esac
  ci_is_github || return 1
  [ -n "$pr" ] || return 1
  comments=$(ci_mktemp)
  if ! bash "$DIR/host-read.sh" comments "$owner" "$repo" "$pr" > "$comments" 2>/dev/null; then
    return 1
  fi
  marker=$(jq -r --arg head "$head" --arg prefix "$prefix" '
    [.[] | select(.login == "github-actions[bot]") | (.body | rtrimstr("\n"))
      | select(split("\n") | length == 1)
      | select(test("^" + $prefix + " [A-Za-z0-9][A-Za-z0-9-]* for " + $head + ": "))] | last // empty' "$comments")
  [ -n "$marker" ] || return 1
  user=${marker#"$prefix" }
  user=${user%% *}
  note=$(ci_mktemp)
  event_json=$(ci_mktemp)
  jq -r --arg user "$user" --arg cmd "/$command" '[.[] | select((.login | ascii_downcase) == ($user | ascii_downcase))
    | select(.body | test("^\\s*" + $cmd + "(\\s|$)"))] | last // empty | .body' "$comments" > "$note"
  [ -s "$note" ] || return 1
  jq --arg user "$user" --arg cmd "/$command" '[.[] | select((.login | ascii_downcase) == ($user | ascii_downcase))
    | select(.body | test("^\\s*" + $cmd + "(\\s|$)"))] | last | {comment: {author_association: (.association // "")}}' \
    "$comments" > "$event_json"
  decision=$(bash "$DIR/override.sh" --command "$command" --user "$user" --comment-file "$note" --base "$tools_sha" --event-file "$event_json")
  case "$decision" in
    valid\ *)
      ci_summary_add "$marker"
      return 0
      ;;
  esac
  return 1
}

override_for_head() {
  command_for_head override
}

# v1.0.4 (B89): a rules file, or a new file at the shared company root, waits for an
# owner's yes. The reasons go to $GATE_FILE. Returns 0 when nothing waits.
GATE_FILE=""
owner_gate_clear() {
  local rc
  GATE_FILE=$(ci_mktemp)
  set +e
  bash "$DIR/owner-gate.sh" --range "${base}..${head}" --tools "$tools_sha" > "$GATE_FILE"
  rc=$?
  set -e
  case "$rc" in
    0) return 0 ;;
    10) return 1 ;;
  esac
  ci_die 1 "checks failed: the owner check did not run"
}

# Plain words for the person who reads the pull request. No file content, only paths.
write_waiting_text() {
  local kind path
  printf '%s\n\n' "WAITING FOR OWNER: this pull request does not merge by itself."
  printf '%s\n\n' "Why: it changes how the company OS works, or it puts something new where everyone in the company can read it."
  while IFS=' ' read -r kind path; do
    [ -n "$kind" ] || continue
    case "$kind" in
      rules) printf -- '- %s: a rules file. It changes how the agents work.\n' "$path" ;;
      root) printf -- '- %s: a file at the shared company root. Everyone with access to the company folder can read it.\n' "$path" ;;
    esac
  done < "$GATE_FILE"
  printf '\n%s\n' "Before you say yes, ask: should everyone in the company read this? If not, move it to an area. Leadership, systems and access, billing and ownership go in areas/admin/."
  printf '%s\n' "To say yes: an owner comments /approve on this pull request. An agent never types /approve. It asks its person and waits for a clear yes."
}

# The model review. Writes the review text to $REVIEW_OUT and sets REVIEW_RC.
REVIEW_OUT=""
REVIEW_RC=0
run_review() {
  local title_file=$1 body_file=$2 range diff_file rules
  range="${base}..${head}"
  diff_file=$(ci_mktemp)
  # A file exactly as a release shipped it is left out. The stock list comes from the base.
  bash "$DIR/review-diff.sh" "$range" "${tools}/.github/scripts/stock-current.txt" > "$diff_file"
  REVIEW_OUT=$(ci_mktemp)
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
  # The reviewer must know which repo it reads: check 7 is for the company repo only.
  if git cat-file -e "${tools_sha}:company-profile.md" 2>/dev/null; then
    REVIEW_REPO=company
  else
    REVIEW_REPO=area
  fi
  export REVIEW_REPO
  set +e
  bash "$DIR/model-review.sh" \
    --rules "$rules" \
    --title-file "$title_file" \
    --body-file "$body_file" \
    --diff-file "$diff_file" \
    --out "$REVIEW_OUT"
  REVIEW_RC=$?
  set -e
  if [ ! -s "$REVIEW_OUT" ] && [ "$REVIEW_RC" -ne 0 ]; then
    ci_die 1 "model review failed: no review text"
  fi
}

# /approve from an owner (v1.0.4). The yes holds for this head commit only.
# GitHub: leave the line, then re-run the failed checks run; that run reviews the
# change again and passes on the line (command_for_head). Forgejo: review here; a pass
# sets the required status.
approve_comment() {
  local decision msg note pr_json title_file body_file comment
  decision=$(bash "$DIR/override.sh" --command approve --user "$user" --comment-file "$comment_file" --base "$tools_sha" --event-file "$GITHUB_EVENT_PATH")
  case "$decision" in
    valid\ *) ;;
    *)
      msg="approve ignored: ${user} is not an owner"
      note=$(ci_mktemp)
      printf '%s\n' "$msg" > "$note"
      ci_summary_add "$msg"
      post_comment "$note"
      return 0
      ;;
  esac
  if ! run_gates; then
    exit 1
  fi
  msg="approved by ${user} for ${head}: yes"
  if ci_is_github; then
    note=$(ci_mktemp)
    printf '%s\n' "$msg" > "$note"
    ci_summary_add "$msg"
    # The line goes first: the re-run reads it.
    post_comment "$note"
    bash "$DIR/set-status.sh" "$head" success "$msg"
    return 0
  fi
  pr_json=$(ci_mktemp)
  title_file=$(ci_mktemp)
  body_file=$(ci_mktemp)
  if ci_api_get "/repos/${GITHUB_REPOSITORY}/pulls/${pr}" "$pr_json" 2>/dev/null; then
    jq -r '.title // empty' "$pr_json" > "$title_file"
    jq -r '.body // empty' "$pr_json" > "$body_file"
  fi
  run_review "$title_file" "$body_file"
  comment=$(ci_mktemp)
  if [ "$REVIEW_RC" -ne 0 ]; then
    { printf '%s\n\n' "$GATES_LINE"; cat "$REVIEW_OUT"; printf '\n%s\n' "approve noted, but the model review fails. Fix the finding, or an owner comments /override <reason>."; } > "$comment"
    ci_summary_add "approve: the model review fails"
    post_comment "$comment"
    bash "$DIR/set-status.sh" "$head" failure "model review failed" >/dev/null || true
    exit 1
  fi
  printf '%s\n' "$msg" > "$comment"
  ci_summary_add "$msg"
  post_comment "$comment"
  bash "$DIR/set-status.sh" "$head" success "$msg"
}

if [ "$event" = "issue_comment" ]; then
  comment_file=$(ci_mktemp)
  user=$(jq -r '.comment.user.login // empty' "$GITHUB_EVENT_PATH")
  jq -r '.comment.body // empty' "$GITHUB_EVENT_PATH" > "$comment_file"
  first=$(tr -d '\r' < "$comment_file" | head -n 1)
  first=$(ci_trim "$first")
  if [ "${first%%[[:space:]]*}" = "/approve" ]; then
    approve_comment
    exit 0
  fi
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
title_file=$(ci_mktemp)
body_file=$(ci_mktemp)
if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
  jq -r '.pull_request.title // empty' "$GITHUB_EVENT_PATH" > "$title_file"
  jq -r '.pull_request.body // empty' "$GITHUB_EVENT_PATH" > "$body_file"
fi
run_review "$title_file" "$body_file"

ci_summary_add "$(cat "$REVIEW_OUT")"
# The comment shows the gates too: the override line names them (v1.0.2).
comment=$(ci_mktemp)
{ printf '%s\n\n' "$GATES_LINE"; cat "$REVIEW_OUT"; } > "$comment"
waiting=no
if [ "$REVIEW_RC" -eq 0 ] && ! owner_gate_clear; then
  if command_for_head approve; then
    ci_summary_add "owner: approved"
  else
    waiting=yes
    { printf '\n'; write_waiting_text; } >> "$comment"
  fi
fi
post_comment "$comment"
if [ "$REVIEW_RC" -ne 0 ]; then
  # An /override may have come in while the review ran.
  if override_for_head; then
    exit 0
  fi
  exit 1
fi
if [ "$waiting" = yes ]; then
  # An /override or /approve may have come in while the review ran.
  if override_for_head || command_for_head approve; then
    exit 0
  fi
  ci_summary_add "waiting for owner: an owner comments /approve"
  printf '%s\n' "waiting for owner: an owner comments /approve on this pull request" >&2
  exit 1
fi
exit 0
