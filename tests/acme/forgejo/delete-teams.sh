#!/bin/bash
# Test cleanup only. Delete the teams a test company made in the local Forgejo:
# <slug>-company and <slug>-area-<a>, for each slug given. A new company's teams carry its
# slug (B24), so a run that only deletes its repos leaves them behind.
# usage: delete-teams.sh <token-file> <base-url> <org> <slug>...
set -uo pipefail

token_file=$1
base=${2%/}
org=$3
shift 3
[ -f "$token_file" ] || exit 0
[ $# -gt 0 ] || exit 0

api() {
  local method=$1 path=$2
  # The token goes in a header read from the file. It never reaches argv or a log.
  curl -sS -X "$method" -H @<(printf 'Authorization: token %s\n' "$(tr -d '[:space:]' < "$token_file")") \
    "${base}/api/v1${path}"
}

page=1
ids=""
while true; do
  chunk=$(api GET "/orgs/${org}/teams?limit=50&page=${page}") || exit 0
  n=$(printf '%s' "$chunk" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)
  for slug in "$@"; do
    [ -n "$slug" ] || continue
    ids="${ids} $(printf '%s' "$chunk" | jq -r --arg s "$slug" \
      '.[]? | select(.name == ($s + "-company") or (.name | startswith($s + "-area-"))) | .id' | tr '\n' ' ')"
  done
  [ "$n" -ge 50 ] || break
  page=$((page + 1))
done
for id in $ids; do
  api DELETE "/teams/${id}" >/dev/null || true
done
exit 0
