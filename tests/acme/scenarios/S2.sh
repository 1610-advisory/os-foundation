#!/usr/bin/env bash
# S2 — team setup. Admin token runs team-on. Checks come from the host API.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S2
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S2 team \
  template/skills/add-teammate/team-on.sh \
  template/skills/add-teammate/join.sh
osf_need_product S2 sync template/skills/sync/sync.sh

slug="acme2-s2"
org="acme2-s2"
root=$(osf_acme_root)
work=$(osf_work s2)
cleanup() {
  osf_delete_org "$org"
}
trap cleanup EXIT

osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
if ! osf_create_org "$org"; then
  osf_result "S2 FAIL could not create org"
fi
answers="$work/answers"
osf_write_team_answers "$answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
if ! osf_export_token acme-admin; then
  osf_result "S2 FAIL admin token missing"
fi
export OS_ORG="$org"
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
set +e
bash "$dest/skills/add-teammate/team-on.sh" --answers "$answers" >"$work/team-on.log" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  osf_result "S2 FAIL team-on exit $rc"
fi

owner="$org"
repo="${slug}-os"
if ! osf_results repo-exists "$owner" "$repo" >/dev/null; then
  osf_result "S2 FAIL company repo missing"
fi
if ! osf_results protection "$owner" "$repo" >/dev/null; then
  osf_result "S2 FAIL main is not protected"
fi
prot=$(osf_results protection "$owner" "$repo")
echo "$prot" | grep -q '"required_approvals": 0' || osf_result "S2 FAIL approvals are not 0"
echo "$prot" | grep -q '"push_blocked": true' || osf_result "S2 FAIL push is not blocked"
if ! osf_results file "$owner" "$repo" .github/CODEOWNERS >/dev/null; then
  osf_result "S2 FAIL CODEOWNERS missing"
fi
if ! osf_results repo-exists "$owner" "${slug}-user-mia" >/dev/null; then
  osf_result "S2 FAIL workspace repo missing"
fi
if ! osf_results clone-denied acme-member-c "$owner" "${slug}-marketing" >/dev/null; then
  osf_result "S2 FAIL member without marketing could read marketing"
fi
level=$(OS_PROFILE="$dest/company-profile.md" bash "$root/template/skills/_host/profile.sh" level)
if [ "$level" != "team" ]; then
  osf_result "S2 FAIL level is $level"
fi
if [ ! -f "$dest/privacy.md" ] || ! grep -q 'team' "$dest/privacy.md"; then
  osf_result "S2 FAIL privacy.md does not list the team places"
fi
if [ ! -f "$dest/joining-terms.md" ]; then
  osf_result "S2 FAIL joining terms missing"
fi
if [ ! -d "$OS_JOBS_DIR" ] || [ -z "$(find "$OS_JOBS_DIR" -type f | head -n 1)" ]; then
  osf_result "S2 FAIL OS jobs were not installed"
fi

osf_result "S2 PASS"
