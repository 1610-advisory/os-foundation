#!/usr/bin/env bash
# S3 — daily work and the nightly push. Holds come from sync status and the host.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S3
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S3 sync template/skills/sync/sync.sh
osf_need_product S3 team template/skills/add-teammate/team-on.sh

slug="acme2-s3"
org="acme2-s3"
root=$(osf_acme_root)
work=$(osf_work s3)
cleanup() { osf_delete_org "$org"; }
trap cleanup EXIT

osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_create_org "$org" || osf_result "S3 FAIL could not create org"
answers="$work/answers"
osf_write_team_answers "$answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S3 FAIL admin token missing"
export OS_ORG="$org"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
export OS_SECRET_SCAN=bundled
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
bash "$dest/skills/add-teammate/team-on.sh" --answers "$answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S3 FAIL team-on"

# Member A writes a company note. The nightly job is sync.sh push in this sandbox.
note="$dest/areas/marketing/notes/widget.md"
mkdir -p "$(dirname "$note")"
printf '%s\n' "The widget ships on Tuesdays." > "$note"
secret="$dest/areas/marketing/notes/leak.md"
osf_fake_pat > "$secret"
life="$dest/areas/marketing/notes/life.md"
printf '%s\n' "OSF-LIFE Ada's child has a piano lesson on Tuesdays." > "$life"
private="$dest/areas/marketing/notes/dm.md"
printf '%s\n' "source: private" > "$private"
printf '%s\n' "OSF-DM Max said in a DM that the date moved." >> "$private"
log="$dest/memory/logs/$(osf_today)-mia.md"
mkdir -p "$dest/memory/logs"
printf '%s\n' "Filed the widget note." > "$log"

osf_me "$slug" mia
osf_write_token_file "$slug" acme-member-a
export OS_COMPANY_ROOT="$dest"
set +e
bash "$dest/skills/sync/sync.sh" push >"$work/push.log" 2>&1
rc=$?
set -e
status=$(bash "$dest/skills/sync/sync.sh" status)
for name in leak.md life.md dm.md; do
  if ! printf '%s\n' "$status" | grep -q "$name"; then
    osf_result "S3 FAIL status does not name $name"
  fi
done
if osf_results file "$org" "${slug}-marketing" notes/leak.md --ref main >/dev/null 2>&1; then
  osf_result "S3 FAIL secret reached main"
fi
if osf_results file "$org" "${slug}-marketing" notes/life.md --ref main >/dev/null 2>&1; then
  osf_result "S3 FAIL personal-life fact reached main"
fi
if osf_results file "$org" "${slug}-marketing" notes/dm.md --ref main >/dev/null 2>&1; then
  osf_result "S3 FAIL private-source quote reached main"
fi
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  osf_result "S3 FAIL push exit $rc"
fi

osf_result "S3 PASS"
