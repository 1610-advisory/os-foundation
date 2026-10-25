#!/usr/bin/env bash
# S6 — tiers. A 25-file edit logs Decision:. Rules files wait for the director or a logged override.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S6
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S6 sync template/skills/sync/sync.sh
osf_need_product S6 ci template/.github/scripts/override.sh

slug="acme2-s6"
org="acme2-s6"
root=$(osf_acme_root)
work=$(osf_work s6)
cleanup() { osf_keep_on_fail "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_need_org S6 "$org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S6 FAIL admin token missing"
export OS_ORG="$org"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
osf_use_seat "$slug" ada acme-admin || osf_result "S6 FAIL admin token missing"
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S6 FAIL team-on"

prompt="$work/prompt.txt"
printf '%s\n' "Create 25 files notes/n-01.md through notes/n-25.md in areas/marketing. Each file is one plain sentence. Append a line that starts with Decision: to memory/logs for today and the slug mia. Do not change AGENTS.md." > "$prompt"
export OS_COMPANY_ROOT="$dest"
export OSF_ACME_SEAT_TIMEOUT=900
osf_use_seat "$slug" mia acme-member-a || osf_result "S6 FAIL member token missing"
osf_run_seat S6 member-a "$prompt" "$dest" \
  || osf_result "S6 FAIL member seat"
count=$(find "$dest/areas/marketing/notes" -name 'n-*.md' | wc -l | tr -d ' ')
if [ "$count" -lt 25 ]; then
  osf_result "S6 FAIL expected 25 files, found $count"
fi
if ! grep -R -q '^Decision:' "$dest/memory/logs"; then
  osf_result "S6 FAIL Decision line missing"
fi

printf '%s\n' "A member must not change this line." >> "$dest/areas/marketing/AGENTS.md"
bash "$dest/skills/sync/sync.sh" push >"$work/push-rules.log" 2>&1 || true
status=$(bash "$dest/skills/sync/sync.sh" status)
if ! printf '%s\n' "$status" | grep -q 'AGENTS.md'; then
  osf_result "S6 FAIL member AGENTS.md change was not held"
fi
bash "$dest/skills/sync/sync.sh" propose agents-fix areas/marketing/AGENTS.md >"$work/propose.log" 2>&1 \
  || osf_result "S6 FAIL propose"
# Director approval is an API call with the director token.
osf_api "$(osf_token_file acme-director)" GET "/api/v1/repos/${org}/${slug}-marketing/pulls?state=open"
number=$(jq -r '.[0].number // empty' "$OSF_HTTP_BODY")
osf_api_discard
if [ -z "$number" ]; then
  osf_result "S6 FAIL no rules pull request"
fi
merged_before=$(osf_results pr "$org" "${slug}-marketing" "$number" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("merged"))')
if [ "$merged_before" = "True" ]; then
  osf_result "S6 FAIL rules PR merged before the director approved"
fi
osf_approve "$org" "${slug}-marketing" "$number" acme-director || osf_result "S6 FAIL director approval"

printf '%s\n' "OSF_REVIEW_FAIL" >> "$dest/AGENTS.md"
osf_use_seat "$slug" ada acme-admin || osf_result "S6 FAIL admin token missing"
bash "$dest/skills/sync/sync.sh" propose root-rules AGENTS.md >"$work/propose-root.log" 2>&1 \
  || osf_result "S6 FAIL admin propose"
osf_api "$(osf_token_file acme-admin)" GET "/api/v1/repos/${org}/${slug}-os/pulls?state=open"
root_n=$(jq -r '.[0].number // empty' "$OSF_HTTP_BODY")
osf_api_discard
if [ -z "$root_n" ]; then
  osf_result "S6 FAIL no company-root rules pull request"
fi
reason="the test marker is not a real finding"
body="$work/override.txt"
printf '%s\n' "/override $reason" > "$body"
jq -n --rawfile b "$body" '{body:$b}' > "$work/comment.json"
osf_api "$(osf_token_file acme-admin)" POST "/api/v1/repos/${org}/${slug}-os/issues/${root_n}/comments" "$work/comment.json"
if [ "$OSF_HTTP_CODE" != "201" ] && [ "$OSF_HTTP_CODE" != "200" ]; then
  osf_api_discard
  osf_result "S6 FAIL could not post the override"
fi
osf_api_discard
osf_api "$(osf_token_file acme-admin)" GET "/api/v1/repos/${org}/${slug}-os/issues/${root_n}/comments"
if [ "$OSF_HTTP_CODE" != "200" ]; then
  osf_api_discard
  osf_result "S6 FAIL host error reading comments"
fi
if ! jq -e --arg reason "$reason" '[.[] | .body] | join("\n") | contains("/override") and contains($reason)' "$OSF_HTTP_BODY" >/dev/null; then
  osf_api_discard
  osf_result "S6 FAIL override reason is not on the host"
fi
osf_api_discard

osf_result "S6 PASS"
