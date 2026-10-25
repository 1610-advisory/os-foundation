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
cleanup() { osf_keep_on_fail "$org"; }
trap cleanup EXIT

osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_need_org S3 "$org"
answers="$work/answers"
osf_write_team_answers "$answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S3 FAIL admin token missing"
export OS_ORG="$org"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
export OS_SECRET_SCAN=bundled
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
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

osf_use_seat "$slug" mia acme-member-a || osf_result "S3 FAIL member token missing"
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
osf_host S3 file "$org" "${slug}-marketing" notes/widget.md --ref "sync/mia"
widget=$(cat "$OSF_HOST_JSON")
found=0
if [ "$OSF_HOST_RC" -eq 0 ]; then
  if printf '%s\n' "$widget" | grep -q 'Tuesdays'; then
    found=1
  fi
fi
if [ "$found" -ne 1 ]; then
  osf_result "S3 FAIL widget note is not on the host"
fi
for held in leak.md life.md dm.md; do
  osf_host S3 file "$org" "${slug}-marketing" "notes/$held" --ref "sync/mia"
  miss=$(cat "$OSF_HOST_JSON")
  if [ "$OSF_HOST_RC" -ne 2 ] || ! printf '%s\n' "$miss" | grep -q '"found": false'; then
    osf_result "S3 FAIL $held was not a clean miss on the host"
  fi
done
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  osf_result "S3 FAIL push exit $rc"
fi

osf_result "S3 PASS"
