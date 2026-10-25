#!/usr/bin/env bash
# S10 — a leak reaches main only because this test turns the nightly check off.
# The product default is not changed. OS_NIGHTLY_CHECK=off is set in this process only.
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
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S10 FAIL team-on"

# This env is the test switch. It is not a product default.
export OS_NIGHTLY_CHECK=off
secret_file="$dest/notes/leak.md"
mkdir -p "$dest/notes"
osf_fake_pat > "$secret_file"
if grep -q 'OS_NIGHTLY_CHECK' "$dest/skills/sync/sync.sh"; then
  export OS_COMPANY_ROOT="$dest"
  export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
  bash "$dest/skills/sync/sync.sh" push >"$work/push.log" 2>&1 || osf_result "S10 FAIL push with check off"
else
  # The product has no skip env yet. Plant the leak without calling the check.
  git -C "$dest" add notes/leak.md
  git -C "$dest" -c user.name="Ada Admin" -c user.email="ada.admin@acme.test" \
    commit -m "Add a note"
  git -C "$dest" push origin HEAD:main || osf_result "S10 FAIL could not plant the leak on main"
fi
if ! osf_results file "$org" "${slug}-os" notes/leak.md >/dev/null; then
  osf_result "S10 FAIL leak did not reach main"
fi

bash "$dest/skills/remove-leak/remove-leak.sh" --repo "${slug}-os" --path notes/leak.md --root "$dest" \
  >"$work/leak.log" 2>&1 || osf_result "S10 FAIL remove-leak"
if osf_results file "$org" "${slug}-os" notes/leak.md >/dev/null; then
  osf_result "S10 FAIL leak still on main"
fi
if ! osf_results tags "$org" "${slug}-os" | grep -q 'os-rewrite-'; then
  osf_result "S10 FAIL rewrite tag missing"
fi

other="$work/other"
osf_me "$slug" mia
osf_write_token_file "$slug" acme-member-a
export OS_COMPANY_ROOT="$dest"
bash "$dest/skills/sync/sync.sh" pull >"$work/pull.log" 2>&1 || osf_result "S10 FAIL pull"
if ! grep -q 're-clone\|reclone\|cloned' "$work/pull.log" "$XDG_CONFIG_HOME/${slug}-os/state/sync.log" 2>/dev/null; then
  osf_result "S10 FAIL other seat did not re-clone"
fi
rm -rf "$other"

osf_result "S10 PASS"
