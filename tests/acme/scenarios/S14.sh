#!/usr/bin/env bash
# S14 — the profile loads, and a company fact in PROFILE.md is held.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S14
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S14 sync template/skills/sync/sync.sh
osf_need_product S14 team template/skills/add-teammate/team-on.sh

slug="acme2-s14"
org="acme2-s14"
root=$(osf_acme_root)
work=$(osf_work s14)
cleanup() { osf_delete_org "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_create_org "$org" || osf_result "S14 FAIL could not create org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S14 FAIL admin token missing"
export OS_ORG="$org"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S14 FAIL team-on"

profile="$dest/users/mia/profile/PROFILE.md"
if [ ! -f "$profile" ]; then
  osf_result "S14 FAIL profile missing"
fi
printf '%s\n' "Write short sentences." >> "$profile"
prompt="$work/prompt.txt"
printf '%s\n' "Read users/mia/profile/PROFILE.md. Write notes/styled.md in one short sentence, the way the profile asks. Do not add a company fact to the profile." > "$prompt"
osf_run_seat S14 member-a "$prompt" "$dest" \
  || osf_result "S14 FAIL member seat"
if [ ! -f "$dest/notes/styled.md" ]; then
  osf_result "S14 FAIL styled note missing"
fi
if grep -q '\.' "$dest/notes/styled.md" && grep -q ',' "$dest/notes/styled.md"; then
  osf_result "S14 FAIL style rule was not followed"
fi

printf '%s\n' "OSF-COMPANY-FACT Acme Co ships 40 widgets." >> "$profile"
osf_use_seat "$slug" mia acme-member-a || osf_result "S14 FAIL member token missing"
export OS_COMPANY_ROOT="$dest"
bash "$dest/skills/sync/sync.sh" push >"$work/push.log" 2>&1 || true
status=$(bash "$dest/skills/sync/sync.sh" status)
if ! printf '%s\n' "$status" | grep -q 'PROFILE.md'; then
  osf_result "S14 FAIL company fact in the profile was not held"
fi
if osf_results file "$org" "${slug}-user-mia" profile/PROFILE.md --ref main 2>/dev/null | grep -q 'OSF-COMPANY-FACT'; then
  osf_result "S14 FAIL company fact reached the workspace repo"
fi

osf_result "S14 PASS"
