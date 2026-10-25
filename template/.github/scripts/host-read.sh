#!/bin/bash
# Read pull request comments through the host HTTP API.
# host.sh can post a comment. It has no verb to list them.
# This script pages every list call. The token stays in a mode-600 file.
# It is never a command argument and it is never printed.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: host-read.sh comments OWNER REPO NUMBER

Print a JSON array of {login, body} for the pull request comments.
Follows pages until a short page. Reads the job token from JOB_TOKEN,
FORGEJO_TOKEN or GH_TOKEN. Never prints the token.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "${1:-}" != "comments" ]; then
  usage >&2
  exit 1
fi
shift
owner=${1:-}
repo=${2:-}
number=${3:-}
if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$number" ] || [ $# -ne 3 ]; then
  usage >&2
  exit 1
fi

token=${JOB_TOKEN:-${FORGEJO_TOKEN:-${GH_TOKEN:-}}}
if [ -z "$token" ]; then
  ci_die 1 "could not list comments: the job token is missing"
fi

base=$(ci_api_base)
limit=50
page=1
combined=$(ci_mktemp)
printf '%s\n' '[]' > "$combined"

while true; do
  page_file=$(ci_mktemp)
  err=$(ci_mktemp)
  cfg=$(ci_mktemp)
  url="${base}/repos/${owner}/${repo}/issues/${number}/comments?limit=${limit}&per_page=${limit}&page=${page}"
  case "$url" in
    *'token='*) ci_die 1 "could not list comments: refusing a token in a URL" ;;
  esac
  auth=$(ci_auth_header "$token")
  {
    printf '%s\n' "header = \"${auth}\""
    printf '%s\n' 'header = "Accept: application/json"'
    printf '%s\n' "url = \"${url}\""
    printf '%s\n' 'request = "GET"'
    printf '%s\n' "output = \"${page_file}\""
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
  if [ "$curl_rc" -ne 0 ] || [ "$http" != "200" ]; then
    ci_die 1 "could not list comments"
  fi
  if ! jq -e 'type == "array"' "$page_file" >/dev/null 2>&1; then
    ci_die 1 "could not list comments"
  fi
  count=$(jq 'length' "$page_file")
  next=$(ci_mktemp)
  jq -s '.[0] + .[1]' "$combined" "$page_file" > "$next"
  combined=$next
  if [ "$count" -lt "$limit" ]; then
    break
  fi
  page=$((page + 1))
  if [ "$page" -gt 40 ]; then
    break
  fi
done

jq '[.[] | {login: (.user.login // ""), body: (.body // "")}]' "$combined"
