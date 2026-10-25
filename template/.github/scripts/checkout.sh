#!/bin/bash
# Check out the pull request head with history.
# The job token stays in a mode-600 file. It is never a command argument.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: checkout.sh

Check out the pull request head with full history.
Reads JOB_TOKEN, GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_EVENT_NAME
and GITHUB_EVENT_PATH from the environment.
Writes head and base commits under the runner temp directory.
The token is never printed.
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
      .github/scripts/*.sh|.github/review.conf|review-rules.md|skills/sync/secret-scan.sh|skills/lint/lint.sh|skills/_host/*.sh)
        dest="${tools}/${path}"
        mkdir -p "$(dirname "$dest")"
        git show "${base_commit}:${path}" > "$dest"
        ;;
    esac
  done < "$list"
  find "$tools" -name '*.sh' -exec chmod 700 {} \;
  ci_write_state tools-dir "$tools"
}

if [ -z "${JOB_TOKEN:-}" ]; then
  ci_die 1 "checkout failed: the job token is missing"
fi
if [ -z "${GITHUB_SERVER_URL:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  ci_die 1 "checkout failed: the job did not set the repository"
fi

event_name=${GITHUB_EVENT_NAME:-}
event_file=${GITHUB_EVENT_PATH:-}
if [ -n "$event_file" ] && [ -f "$event_file" ] && [ "$event_name" = "issue_comment" ]; then
  trimmed=$(jq -r '.comment.body // empty' "$event_file" | sed 's/^[[:space:]]*//')
  case "$trimmed" in
    /override*) ;;
    *)
      ci_write_state event-name "$event_name"
      ci_write_state skip yes
      exit 0
      ;;
  esac
fi

work=${GITHUB_WORKSPACE:-$(pwd)}
mkdir -p "$work"
cd "$work"

url="${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}.git"
case "$url" in
  *'@'*) ci_die 1 "checkout failed: refusing a credential in a clone URL" ;;
esac

if [ -d .git ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$url"
  else
    git remote add origin "$url"
  fi
else
  git init -q .
  git remote add origin "$url"
fi

pr_number=""
head_ref=""
base_ref="main"
head_sha=""
base_sha=""

if [ -n "$event_file" ] && [ -f "$event_file" ]; then
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
      is_pr=$(jq -r 'if .issue.pull_request then "yes" else "no" end' "$event_file")
      if [ "$is_pr" != "yes" ]; then
        ci_die 1 "checkout failed: the comment is not on a pull request"
      fi
      ;;
  esac
fi

if [ -n "$pr_number" ]; then
  ci_git fetch --no-tags origin \
    "+refs/pull/${pr_number}/head:refs/remotes/pull/${pr_number}/head" \
    "+refs/heads/${base_ref}:refs/remotes/origin/${base_ref}"
  if [ -z "$head_sha" ]; then
    head_sha=$(git rev-parse "refs/remotes/pull/${pr_number}/head")
  fi
else
  ci_git fetch --no-tags origin \
    "+refs/heads/${base_ref}:refs/remotes/origin/${base_ref}"
  head_sha=${GITHUB_SHA:-}
fi

if [ -z "$head_sha" ]; then
  ci_die 1 "checkout failed: the pull request head is missing"
fi
if [ -f "$(git rev-parse --git-path shallow)" ]; then
  ci_git fetch --unshallow origin || true
fi

if [ -z "$head_ref" ] && [ -n "$pr_number" ]; then
  head_ref=$(ci_git ls-remote origin 'refs/heads/*' | awk -v sha="$head_sha" '
    $1 == sha {
      ref = $2
      sub(/^refs\/heads\//, "", ref)
      if (ref != "main") { print ref; exit }
    }
  ')
fi

git checkout -f -q --detach "$head_sha"

if [ -z "$base_sha" ]; then
  if git rev-parse --verify --quiet "refs/remotes/origin/${base_ref}" >/dev/null; then
    base_sha=$(git merge-base "refs/remotes/origin/${base_ref}" HEAD || true)
  fi
fi
if [ -z "$base_sha" ]; then
  ci_die 1 "checkout failed: the base commit is missing"
fi

save_base_tools "$base_sha"

ci_write_state event-name "$event_name"
ci_write_state skip no
ci_write_state pr-number "$pr_number"
ci_write_state head-sha "$head_sha"
ci_write_state base-sha "$base_sha"
ci_write_state head-ref "$head_ref"
ci_write_state base-ref "$base_ref"
printf '%s\n' "checked out ${head_sha}"
