#!/bin/bash
# Turn the required check green on one commit after a valid /override.
# A push with the job token does not start a new workflow run, so the override job
# acts on the pull request's own check:
# - Forgejo: set the commit status the checks job wrote, under the same name.
# - GitHub: a second "checks" check run does not replace the failed one, and the
#   ruleset still blocks (B51). So re-run the failed pull_request run. That run reads
#   the override comment for its head commit and passes (run-checks.sh).
# The token stays in a mode-600 file. It is never a command argument.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: set-status.sh SHA success|failure|pending MESSAGE

Make the required checks status on a commit say STATE.
On GitHub, success re-runs the failed checks run for SHA.
Reads the job token from JOB_TOKEN. Never prints it.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

sha=${1:-}
state=${2:-}
message=${3:-}
if [ -z "$sha" ] || [ -z "$state" ] || [ -z "$message" ] || [ $# -ne 3 ]; then
  usage >&2
  exit 1
fi
case "$state" in
  success|failure|pending) ;;
  *) usage >&2; exit 1 ;;
esac

JOB_TOKEN=${JOB_TOKEN:-${FORGEJO_TOKEN:-${GH_TOKEN:-}}}
if [ -z "$JOB_TOKEN" ]; then
  ci_die 1 "could not set the check status: the job token is missing"
fi
repo_path="/repos/${GITHUB_REPOSITORY}"
out=$(ci_mktemp)

if ! ci_is_github; then
  body=$(ci_mktemp)
  jq -nc --arg context "checks / checks (pull_request)" --arg state "$state" --arg description "$message" \
    '{context:$context, state:$state, description:$description}' > "$body"
  if ! ci_api_call POST "${repo_path}/statuses/${sha}" "$out" "$body" 2>/dev/null; then
    ci_die 1 "could not set the check status"
  fi
  printf '%s\n' "status ${state}"
  exit 0
fi

if [ "$state" != "success" ]; then
  # The checks run itself reports failure and pending on GitHub.
  printf '%s\n' "status ${state}"
  exit 0
fi
case "$sha" in
  *[!0-9a-f]*|'') ci_die 1 "could not set the check status: ${sha} is not a commit" ;;
esac
if ! ci_api_get "${repo_path}/actions/runs?event=pull_request&head_sha=${sha}&per_page=50" "$out" 2>/dev/null; then
  ci_die 1 "could not set the check status: could not list the checks runs"
fi
# The newest run of this workflow for the commit.
run=$(jq -r '[.workflow_runs[]? | select((.path // "") | startswith(".github/workflows/checks.yml"))]
  | sort_by(.run_number, .run_attempt) | last // empty
  | "\(.id) \(.status) \(.conclusion // "none")"' "$out")
if [ -z "$run" ]; then
  ci_die 1 "could not set the check status: no checks run for ${sha}; push again, then comment /override again"
fi
read -r run_id run_status run_conclusion <<< "$run"
if [ "$run_status" != "completed" ]; then
  printf '%s\n' "the checks for ${sha} are still running; they will read the override when they reach the review"
  exit 0
fi
case "$run_conclusion" in
  success)
    printf '%s\n' "status success"
    exit 0
    ;;
esac
if ! ci_api_call POST "${repo_path}/actions/runs/${run_id}/rerun-failed-jobs" "$out" 2>/dev/null; then
  ci_die 1 "could not set the check status: could not re-run the checks"
fi
printf '%s\n' "re-running the checks for ${sha}; they pass with the override"
