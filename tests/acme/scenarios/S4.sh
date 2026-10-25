#!/usr/bin/env bash
# S4 — a fact learned by one vendor is used by another. Codex is blocked, so Pi stands in.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S4
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S4 sync template/skills/sync/sync.sh
osf_need_product S4 team template/skills/add-teammate/team-on.sh

sub=""
if ! osf_seat_line member-b >/dev/null; then
  if ! osf_seat_line member-d >/dev/null; then
    osf_result "S4 BLOCKED no second vendor seat"
  fi
  sub="sub: member-d for member-b, codex BLOCKED"
fi

slug="acme2-s4"
org="acme2-s4"
root=$(osf_acme_root)
work=$(osf_work s4)
cleanup() { osf_keep_on_fail "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_create_org "$org" || osf_result "S4 FAIL could not create org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S4 FAIL admin token missing"
export OS_ORG="$org"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S4 FAIL team-on"

fact="The sample widget code is W-14."
mkdir -p "$dest/areas/marketing/notes"
printf '%s\n' "$fact" > "$dest/areas/marketing/notes/learned.md"
osf_use_seat "$slug" mia acme-member-a || osf_result "S4 FAIL member token missing"
export OS_COMPANY_ROOT="$dest"
bash "$dest/skills/sync/sync.sh" push >"$work/push.log" 2>&1 || true
bash "$dest/skills/sync/sync.sh" pull >"$work/pull.log" 2>&1 || osf_result "S4 FAIL pull"

prompt="$work/prompt.txt"
printf '%s\n' "Read areas/marketing/notes/learned.md. Write areas/marketing/notes/used.md. Cite the widget code from that note. Do not invent a different code." > "$prompt"
second="member-d"
if [ -z "$sub" ]; then
  second="member-b"
fi
bash "$root/tests/acme/seat.sh" "$second" "$prompt" --cwd "$dest" >"$work/seat.log" 2>&1 \
  || osf_result "S4 FAIL second seat"
if ! grep -q 'W-14' "$dest/areas/marketing/notes/used.md"; then
  osf_result "S4 FAIL second seat did not cite the fact"
fi
if [ "$second" = "member-b" ]; then
  osf_use_seat "$slug" max acme-member-b || osf_result "S4 FAIL member token missing"
else
  osf_use_seat "$slug" sam acme-member-d || osf_result "S4 FAIL member token missing"
fi
bash "$dest/skills/sync/sync.sh" push >"$work/push2.log" 2>&1 || true
branch="sync/sam"
if [ "$second" = "member-b" ]; then
  branch="sync/max"
fi
osf_host S4 file "$org" "${slug}-marketing" notes/used.md --ref "$branch"
used=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -ne 0 ] || ! printf '%s\n' "$used" | grep -q 'W-14'; then
  osf_result "S4 FAIL used note is not on $branch"
fi

if [ -n "$sub" ]; then
  osf_result "S4 PASS ($sub)"
fi
osf_result "S4 PASS"
