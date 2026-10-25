#!/usr/bin/env bash
# S13 — short admin run on each first-class engine. One line per engine, then a summary.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S13
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

root=$(osf_acme_root)
fail=0
blocked=0
for engine in claude codex cursor pi; do
  seat=$(osf_engine_name "$engine")
  if ! line=$(osf_seat_line "$seat"); then
    prefix="BLOCKED: ${seat} "
    reason=${line#"$prefix"}
    osf_line "S13 $engine BLOCKED $reason"
    blocked=$((blocked + 1))
    continue
  fi
  if [ ! -f "$root/template/skills/add-teammate/add-person.sh" ] \
    || [ ! -f "$root/template/skills/remove-teammate/remove.sh" ]; then
    osf_line "S13 $engine BLOCKED not merged: team"
    blocked=$((blocked + 1))
    continue
  fi
  work=$(osf_work "s13-$engine")
  osf_sandbox "$work/box"
  dest="$work/company"
  osf_setup_solo "$dest" "acme2-s13" >/dev/null || {
    osf_line "S13 $engine FAIL setup"
    fail=$((fail + 1))
    continue
  }
  prompt="$work/prompt.txt"
  printf '%s\n' "Read company-profile.md. Add one sentence to notes/admin.md: the admin run wrote this. Do not change git identity." > "$prompt"
  if ! bash "$root/tests/acme/seat.sh" "$seat" "$prompt" --cwd "$dest" >"$work/seat.log" 2>&1; then
    if grep -q '^BLOCKED:' "$work/seat.log"; then
      reason=$(sed -n 's/^BLOCKED: //p' "$work/seat.log" | head -n 1)
      osf_line "S13 $engine BLOCKED $reason"
      blocked=$((blocked + 1))
    else
      osf_line "S13 $engine FAIL seat"
      fail=$((fail + 1))
    fi
    continue
  fi
  if [ ! -f "$dest/notes/admin.md" ]; then
    osf_line "S13 $engine FAIL setup note missing"
    fail=$((fail + 1))
    continue
  fi
  osf_line "S13 $engine PASS"
done

if [ "$fail" -gt 0 ]; then
  osf_result "S13 FAIL"
fi
if [ "$blocked" -gt 0 ]; then
  osf_result "S13 BLOCKED engines not ready"
fi
osf_result "S13 PASS"
