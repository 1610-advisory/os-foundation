#!/usr/bin/env bash
# S9 — offboard Member D. The device helper uses a faked clock. An offline seat is not wiped.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S9
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S9 team template/skills/remove-teammate/remove.sh
osf_need_product S9 sync template/skills/sync/sync.sh

slug="acme2-s9"
org="acme2-s9"
root=$(osf_acme_root)
work=$(osf_work s9)
cleanup() { osf_keep_on_fail "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_need_org S9 "$org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S9 FAIL admin token missing"
export OS_ORG="$org"
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S9 FAIL team-on"

export OS_NOW=2026-10-24
bash "$dest/skills/remove-teammate/remove.sh" --person sam --root "$dest" --date 2026-10-24 \
  >"$work/remove.log" 2>&1 || osf_result "S9 FAIL remove"
osf_host S9 clone-denied acme-member-d "$org" "${slug}-os" >/dev/null
if [ "$OSF_HOST_RC" -ne 0 ]; then
  osf_result "S9 FAIL access was not revoked"
fi
if ! grep -q 'left: 2026-10-24' "$dest/people/"*.md; then
  osf_result "S9 FAIL people page was not marked left"
fi

# Count 14 days on the removed seat's sandbox. A second sandbox stays offline and must remain.
seat_home="$work/sam-home"
mkdir -p "$seat_home/company"
cp -R "$dest/." "$seat_home/company/"
export HOME="$seat_home"
export XDG_CONFIG_HOME="$work/sam-xdg"
export OS_TEST_MODE=1
mkdir -p "$XDG_CONFIG_HOME"
osf_use_seat "$slug" sam acme-member-d || osf_result "S9 FAIL member token missing"
export OS_COMPANY_ROOT="$seat_home/company"
n=0
while [ "$n" -lt 14 ]; do
  OS_NOW=$(python3 -c "import datetime; print((datetime.date(2026,10,24)+datetime.timedelta(days=$n)).isoformat())")
  export OS_NOW
  bash "$seat_home/company/skills/sync/sync.sh" helper >"$work/helper-$n.log" 2>&1 || true
  n=$((n + 1))
done
if [ -d "$seat_home/company" ]; then
  osf_result "S9 FAIL folder was not deleted after 14 counted days"
fi

offline="$work/offline-home/company"
mkdir -p "$(dirname "$offline")"
rm -rf "$offline"
cp -R "$dest" "$offline"
printf '%s\n' keep > "$offline/keep.txt"
export HOME="$work/offline-home"
export XDG_CONFIG_HOME="$work/offline-xdg"
mkdir -p "$XDG_CONFIG_HOME"
export OS_HOST_URL="http://127.0.0.1:9"
export OS_COMPANY_ROOT="$offline"
export OS_NOW=2026-11-20
bash "$offline/skills/sync/sync.sh" helper >"$work/offline.log" 2>&1 || true
if ! grep -q 'helper offline' "$work/offline.log" "$work/offline-xdg/${slug}-os/state/sync.log" 2>/dev/null; then
  osf_result "S9 FAIL offline helper did not record a no-wipe decision"
fi
if [ ! -f "$offline/keep.txt" ]; then
  osf_result "S9 FAIL offline seat was wiped"
fi

osf_result "S9 PASS"
