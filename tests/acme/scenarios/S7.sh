#!/usr/bin/env bash
# S7 — nightly review and the director report. No workspace text, no profile text, no ranking.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S7
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S7 nightly \
  template/skills/nightly-review/run.sh \
  template/skills/reports/run.sh
osf_need_product S7 team template/skills/add-teammate/team-on.sh

slug="acme2-s7"
org="acme2-s7"
root=$(osf_acme_root)
work=$(osf_work s7)
day=$(osf_today)
cleanup() { osf_delete_org "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_create_org "$org" || osf_result "S7 FAIL could not create org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/review-engine.sh"
osf_export_token acme-admin || osf_result "S7 FAIL admin token missing"
export OS_ORG="$org"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/review-engine.sh"
export OS_NOW="$day"
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
printf '%s\n' "See [[Missing Person]] for the widget." > "$dest/areas/marketing/notes/widget.md"
printf '%s\n' "Confirm the sample price before we print it." > "$dest/areas/marketing/notes/price.md"
git -C "$dest/areas/marketing" add notes
git -C "$dest/areas/marketing" -c user.name="Mia Member" -c user.email="mia.member@acme.test" \
  commit -m "Add the widget notes" >&2
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S7 FAIL team-on"

export OS_COMPANY_ROOT="$dest"
bash "$dest/skills/nightly-review/run.sh" --date "$day" --root "$dest" >"$work/review.log" 2>&1 \
  || osf_result "S7 FAIL nightly review"
bash "$dest/skills/reports/run.sh" --date "$day" --root "$dest" >"$work/reports.log" 2>&1 \
  || osf_result "S7 FAIL reports"

week=$(date +%G-W%V)
decide="$dest/areas/marketing/reports/${day}-to-decide.md"
weekly="$dest/areas/marketing/reports/${week}.md"
if [ ! -f "$decide" ]; then
  osf_result "S7 FAIL to-decide file missing"
fi
osf_host S7 file "$org" "${slug}-marketing" notes/widget.md --ref "review/${day}"
fixed=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -ne 0 ]; then
  osf_host S7 file "$org" "${slug}-marketing" notes/widget.md --ref main
  fixed=$(cat "$OSF_HOST_JSON")
fi
if [ "$OSF_HOST_RC" -ne 0 ] || ! printf '%s\n' "$fixed" | grep -q 'Ada Admin'; then
  osf_result "S7 FAIL clear-error fix is not on the host"
fi
if printf '%s\n' "$fixed" | grep -q 'Missing Person'; then
  osf_result "S7 FAIL broken link is still on the host"
fi
if ! grep -q 'price' "$decide"; then
  osf_result "S7 FAIL judgment call is not in to-decide"
fi
if [ ! -f "$weekly" ]; then
  osf_result "S7 FAIL weekly report missing"
fi
if grep -Eiq 'rank|ranking|score|leaderboard|profile/PROFILE' "$weekly" "$decide"; then
  osf_result "S7 FAIL report contains ranking or profile text"
fi
if grep -q 'piano lesson' "$weekly" "$decide"; then
  osf_result "S7 FAIL report contains workspace content"
fi

osf_result "S7 PASS"
