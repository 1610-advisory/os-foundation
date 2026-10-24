#!/bin/bash
# Set the required check status on one commit.
# A push with the job token does not start a new workflow run, so an override
# sets this status on the same commit after the checks run again.
# The token stays in a mode-600 file. It is never a command argument.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: set-status.sh SHA success|failure|pending MESSAGE

Set the required checks status on a commit.
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

token=${JOB_TOKEN:-${FORGEJO_TOKEN:-${GH_TOKEN:-}}}
if [ -z "$token" ]; then
  ci_die 1 "could not set the check status: the job token is missing"
fi
owner=${GITHUB_REPOSITORY%%/*}
repo=${GITHUB_REPOSITORY#*/}
if ci_is_github; then
  context="checks"
else
  context="checks / checks (pull_request)"
fi

base=$(ci_api_base)
body=$(ci_mktemp)
jq -nc --arg context "$context" --arg state "$state" --arg description "$message" \
  '{context:$context, state:$state, description:$description}' > "$body"
out=$(ci_mktemp)
err=$(ci_mktemp)
cfg=$(ci_mktemp)
url="${base}/repos/${owner}/${repo}/statuses/${sha}"
auth=$(ci_auth_header "$token")
{
  printf '%s\n' "header = \"${auth}\""
  printf '%s\n' 'header = "Accept: application/json"'
  printf '%s\n' 'header = "Content-Type: application/json"'
  printf '%s\n' "url = \"${url}\""
  printf '%s\n' 'request = "POST"'
  printf '%s\n' "data-binary = \"@${body}\""
  printf '%s\n' "output = \"${out}\""
  printf '%s\n' 'silent'
  printf '%s\n' 'show-error'
  printf '%s\n' 'connect-timeout = 10'
  printf '%s\n' 'max-time = 60'
  printf '%s\n' 'write-out = "%{http_code}"'
} > "$cfg"
set +e
http=$(curl --config "$cfg" 2>"$err")
curl_rc=$?
set -e
if [ "$curl_rc" -ne 0 ] || { [ "$http" != "201" ] && [ "$http" != "200" ]; }; then
  ci_die 1 "could not set the check status"
fi
printf '%s\n' "status ${state}"
