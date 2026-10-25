#!/usr/bin/env bash
# S5 — a skill fix by PR. Cursor is blocked, so another vendor proposes. Director approves by API.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S5
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S5 ci template/.github/scripts/model-review.sh
osf_need_product S5 sync template/skills/sync/sync.sh
osf_need_product S5 team template/skills/add-teammate/team-on.sh

sub=""
proposer="member-c"
if ! osf_seat_line member-c >/dev/null; then
  if ! osf_seat_line member-d >/dev/null; then
    osf_result "S5 BLOCKED no vendor seat for the proposal"
  fi
  proposer="member-d"
  sub="sub: member-d for member-c, cursor BLOCKED"
fi

slug="acme2-s5"
org="acme2-s5"
root=$(osf_acme_root)
work=$(osf_work s5)
cleanup() { osf_delete_org "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_create_org "$org" || osf_result "S5 FAIL could not create org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S5 FAIL admin token missing"
export OS_ORG="$org"
osf_use_seat "$slug" ada acme-admin || osf_result "S5 FAIL admin token missing"
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S5 FAIL team-on"

skill="$dest/areas/marketing/skills/sample/SKILL.md"
mkdir -p "$(dirname "$skill")"
printf '%s\n' "Step 1. Ship the widget on Monday." > "$skill"
prompt="$work/prompt.txt"
printf '%s\n' "The skill at areas/marketing/skills/sample/SKILL.md has a wrong step. Change Monday to Tuesday. Propose it with skills/sync/sync.sh propose skill-fix and that file. Do not write to main." > "$prompt"
user="acme-member-d"
me="sam"
if [ "$proposer" = "member-c" ]; then
  user="acme-member-c"
  me="noa"
fi
osf_use_seat "$slug" "$me" "$user" || osf_result "S5 FAIL proposer token missing"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
export OS_COMPANY_ROOT="$dest"
# The model review reads OS_REVIEW_FAKE from the Tier A runner, not from this process.
bash "$root/tests/acme/seat.sh" "$proposer" "$prompt" --cwd "$dest" >"$work/seat.log" 2>&1 \
  || osf_result "S5 FAIL proposer seat"

# Director approval is an API call with the director token. The engine is not required.
osf_api "$(osf_token_file acme-director)" GET "/api/v1/repos/${org}/${slug}-marketing/pulls?state=open"
number=$(jq -r '.[0].number // empty' "$OSF_HTTP_BODY")
osf_api_discard
if [ -z "$number" ]; then
  osf_result "S5 FAIL no skill pull request"
fi
if ! osf_approve "$org" "${slug}-marketing" "$number" acme-director; then
  osf_result "S5 FAIL director approval"
fi
if ! osf_results wait-check "$org" "${slug}-marketing" "$(osf_results pr "$org" "${slug}-marketing" "$number" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("head_sha",""))')" --timeout 180 >/dev/null; then
  osf_result "S5 FAIL checks did not pass (OS_REVIEW_FAKE must be in the runner env)"
fi

osf_use_seat "$slug" mia acme-member-a || osf_result "S5 FAIL member token missing"
bash "$dest/skills/sync/sync.sh" pull >"$work/pull.log" 2>&1 || osf_result "S5 FAIL pull"
if ! grep -q 'Tuesday' "$dest/areas/marketing/skills/sample/SKILL.md"; then
  osf_result "S5 FAIL next pull did not pick up the new step"
fi

if [ -n "$sub" ]; then
  osf_result "S5 PASS ($sub)"
fi
osf_result "S5 PASS"
