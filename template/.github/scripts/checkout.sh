#!/bin/bash
# Find the pull request's commits and copy the check tools from its base.
# actions/checkout has already fetched the full history and checked out the head.
# The head is data, not code (D26): every script the checks run is copied out of
# the base commit here, and the workflow copied this file from main.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: checkout.sh

Find the pull request head and base in the checked-out folder.
Copy the check tools from the base commit to the runner temp directory.
Reads GITHUB_EVENT_NAME, GITHUB_EVENT_PATH and GITHUB_REPOSITORY.
An /override comment reads its pull request with JOB_TOKEN. The token is never printed.
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

save_base_tools() {
  local base_commit=$1 tools path dest list
  tools="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/os-checks"
  rm -rf "$tools"
  mkdir -p "$tools"
  list=$(ci_mktemp)
  git ls-tree -r --name-only "$base_commit" > "$list"
  while IFS= read -r path; do
    case "$path" in
      .github/scripts/*|.github/review.conf|review-rules.md)
        dest="${tools}/${path}"
        mkdir -p "$(dirname "$dest")"
        git show "${base_commit}:${path}" > "$dest"
        ;;
    esac
  done < "$list"
  find "$tools" -name '*.sh' -exec chmod 700 {} \;
  ci_write_state tools-dir "$tools"
}

event_name=${GITHUB_EVENT_NAME:-}
event_file=${GITHUB_EVENT_PATH:-}
if [ -z "$event_file" ] || [ ! -f "$event_file" ]; then
  ci_die 1 "checkout failed: the job has no event file"
fi

cd "${GITHUB_WORKSPACE:-$(pwd)}"
if ! git rev-parse --verify --quiet HEAD >/dev/null; then
  ci_die 1 "checkout failed: the pull request head is not checked out"
fi

case "$event_name" in
  pull_request|pull_request_review)
    pr_number=$(jq -r '.pull_request.number // empty' "$event_file")
    head_ref=$(jq -r '.pull_request.head.ref // empty' "$event_file")
    base_ref=$(jq -r '.pull_request.base.ref // "main"' "$event_file")
    head_sha=$(jq -r '.pull_request.head.sha // empty' "$event_file")
    base_sha=$(jq -r '.pull_request.base.sha // empty' "$event_file")
    ;;
  issue_comment)
    pr_number=$(jq -r '.issue.number // empty' "$event_file")
    case "$pr_number" in
      ''|*[!0-9]*) ci_die 1 "checkout failed: the comment has no pull request number" ;;
    esac
    # A comment event has no commits. Take them from the pull request itself (B49).
    pr_json=$(ci_mktemp)
    if [ -z "${JOB_TOKEN:-}" ] || ! ci_api_get "/repos/${GITHUB_REPOSITORY}/pulls/${pr_number}" "$pr_json"; then
      ci_die 1 "checkout failed: could not read pull request ${pr_number} from the host"
    fi
    head_ref=$(jq -r '.head.ref // empty' "$pr_json")
    base_ref=$(jq -r '.base.ref // "main"' "$pr_json")
    head_sha=$(jq -r '.head.sha // empty' "$pr_json")
    base_sha=$(jq -r '.base.sha // empty' "$pr_json")
    ;;
  *)
    ci_die 1 "checkout failed: the checks run only for a pull request"
    ;;
esac

if [ -z "$head_sha" ]; then
  ci_die 1 "checkout failed: the pull request has no head commit"
fi
if ! git cat-file -e "${head_sha}^{commit}" 2>/dev/null; then
  ci_die 1 "checkout failed: commit ${head_sha} is not in the checkout (the pull request changed; run the checks again)"
fi
if [ "$(git rev-parse HEAD)" != "$head_sha" ]; then
  git checkout -f -q --detach "$head_sha"
fi

# The tools, the owners and the review rules come from the base branch as fetched now.
# The host's base commit for the pull request can be far older than the branch (GitHub
# keeps it from when the pull request opened), and a re-run must see today's tools.
tools_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/${base_ref}^{commit}" || true)
tools_sha=${tools_sha:-$base_sha}
if [ -z "$tools_sha" ] || ! git cat-file -e "${tools_sha}^{commit}" 2>/dev/null; then
  ci_die 1 "checkout failed: the base branch ${base_ref} is not in the checkout"
fi
# A branch need not hold the newest main: a person may push before they pull. The range
# starts at the merge base, so main's newer changes are not read as the branch's own.
range_base=$(git merge-base "$tools_sha" "$head_sha") || ci_die 1 "checkout failed: the head and the base share no history"

save_base_tools "$tools_sha"

ci_write_state event-name "$event_name"
ci_write_state pr-number "$pr_number"
ci_write_state head-sha "$head_sha"
ci_write_state base-sha "$range_base"
ci_write_state tools-sha "$tools_sha"
ci_write_state head-ref "$head_ref"
ci_write_state base-ref "$base_ref"
printf '%s\n' "checked out ${head_sha}"
