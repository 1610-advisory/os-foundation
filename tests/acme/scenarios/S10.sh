#!/usr/bin/env bash
# S10 — a private fact reaches main because this one push uses an always-commit engine.
# The secret scan does not match it. The product default engine is not changed.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S10
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S10 team template/skills/remove-leak/remove-leak.sh
osf_need_product S10 sync template/skills/sync/sync.sh

if ! git filter-repo --version >/dev/null 2>&1; then
  osf_result "S10 BLOCKED git-filter-repo is not installed"
fi

slug="acme2-s10"
org="acme2-s10"
root=$(osf_acme_root)
work=$(osf_work s10)
cleanup() { osf_delete_org "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_create_org "$org" || osf_result "S10 FAIL could not create org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S10 FAIL admin token missing"
export OS_ORG="$org"
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S10 FAIL team-on"

mkdir -p "$dest/notes"
printf '%s\n' "Ada keeps a piano at home." > "$dest/notes/leak.md"
export OS_COMPANY_ROOT="$dest"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine-commit.sh"
export OS_SECRET_SCAN=bundled
bash "$dest/skills/sync/sync.sh" push >"$work/push.log" 2>&1 || osf_result "S10 FAIL push"
osf_api "$(osf_token_file acme-admin)" GET "/api/v1/repos/${org}/${slug}-os/pulls?state=open"
if [ "$OSF_HTTP_CODE" = "200" ]; then
  number=$(jq -r '.[0].number // empty' "$OSF_HTTP_BODY")
  osf_api_discard
  if [ -n "$number" ]; then
    osf_approve "$org" "${slug}-os" "$number" acme-director || osf_result "S10 FAIL director approval"
  fi
else
  osf_api_discard
  osf_result "S10 FAIL host error reading pull requests"
fi
i=0
while [ "$i" -lt 40 ]; do
  if osf_results file "$org" "${slug}-os" notes/leak.md >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 5
done
osf_host S10 file "$org" "${slug}-os" notes/leak.md --ref main
leak=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -ne 0 ] || ! printf '%s\n' "$leak" | grep -q 'piano'; then
  osf_result "S10 FAIL private fact did not reach main"
fi

other="$work/other"
osf_clone_as acme-member-a "$(osf_acme_url)/${org}/${slug}-os.git" "$other" >"$work/clone.log" 2>&1 \
  || osf_result "S10 FAIL could not clone for the other seat"

bash "$dest/skills/remove-leak/remove-leak.sh" --repo "${slug}-os" --path notes/leak.md --root "$dest" \
  >"$work/leak.log" 2>&1 || osf_result "S10 FAIL remove-leak"
osf_host S10 file "$org" "${slug}-os" notes/leak.md --ref main
gone=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -ne 2 ] || ! printf '%s\n' "$gone" | grep -q '"found": false'; then
  osf_result "S10 FAIL private fact still on main"
fi
osf_host S10 tags "$org" "${slug}-os"
tags=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -ne 0 ] || ! printf '%s\n' "$tags" | grep -q 'os-rewrite-'; then
  osf_result "S10 FAIL rewrite tag missing"
fi

osf_host S10 commits "$org" "${slug}-os" --ref main --limit 1
commits=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -ne 0 ]; then
  osf_result "S10 FAIL could not read rewritten main"
fi
host_sha=$(printf '%s\n' "$commits" | python3 -c 'import json,sys; print(json.load(sys.stdin)["commits"][0]["sha"])')
if [ -z "$host_sha" ]; then
  osf_result "S10 FAIL could not read rewritten main"
fi
osf_use_seat "$slug" mia acme-member-a || osf_result "S10 FAIL member token missing"
export OS_COMPANY_ROOT="$other"
bash "$other/skills/sync/sync.sh" pull >"$work/pull.log" 2>&1 || osf_result "S10 FAIL pull"
clone_sha=$(git -C "$other" rev-parse HEAD)
if [ "$clone_sha" != "$host_sha" ]; then
  osf_result "S10 FAIL other seat HEAD is not the rewritten main"
fi

osf_result "S10 PASS"
