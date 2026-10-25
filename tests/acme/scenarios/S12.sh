#!/usr/bin/env bash
# S12 — two companies on one computer. A cross-company read is held. A root session is not collected.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S12
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S12 sync template/skills/sync/sync.sh
if [ ! -f "$(osf_acme_root)/template/skills/sync/collect.sh" ]; then
  osf_result "S12 BLOCKED cut: traces collector"
fi

root=$(osf_acme_root)
work=$(osf_work s12)
osf_sandbox "$work/box"
acme="$work/acme"
bravo="$work/bravo"
osf_setup_solo "$acme" acme >/dev/null
osf_setup_solo "$bravo" bravo >/dev/null
python3 - "$acme/company-profile.md" "$bravo/company-profile.md" << 'PY'
import pathlib, sys
for name in sys.argv[1:]:
    path = pathlib.Path(name)
    text = path.read_text(encoding="utf-8")
    text = text.replace("level: solo", "level: app")
    text = text.replace("switches: []", "switches: [traces]")
    path.write_text(text, encoding="utf-8")
PY
mkdir -p "$XDG_CONFIG_HOME"
printf '%s\n' "$root/template" > "$XDG_CONFIG_HOME/os-shared-list"
acme_target="$work/target-acme"
bravo_target="$work/target-bravo"
mkdir -p "$acme_target" "$bravo_target" "$HOME/.pi/agent/sessions"
session="$HOME/.pi/agent/sessions/s12.jsonl"
printf '%s\n' '{"cwd":"'"$acme"'","tool":"read","path":"'"$bravo/notes/secret.md"'"}' > "$session"
mkdir -p "$bravo/notes"
printf '%s\n' "bravo only" > "$bravo/notes/secret.md"
export OS_TRACES_TARGET="$acme_target"
export OS_COMPANY_ROOT="$acme"
bash "$acme/skills/sync/sync.sh" collect >"$work/cross.log" 2>&1 || true
if find "$acme_target" "$bravo_target" -type f | grep -q .; then
  osf_result "S12 FAIL cross-company session was uploaded"
fi

printf '%s\n' '{"cwd":"'"$acme"'","tool":"read","path":"'"$root/template/AGENTS.md"'"}' > "$session"
bash "$acme/skills/sync/sync.sh" collect >"$work/shared.log" 2>&1 || osf_result "S12 FAIL collect"
if ! find "$acme_target" -type f | grep -q .; then
  osf_result "S12 FAIL shared-list session was not uploaded to acme"
fi
if find "$bravo_target" -type f | grep -q .; then
  osf_result "S12 FAIL acme session reached bravo"
fi

printf '%s\n' '{"cwd":"'"$work"'","tool":"read","path":"'"$acme/AGENTS.md"'"}' > "$session"
before=$(find "$acme_target" -type f | wc -l | tr -d ' ')
export OS_COMPANY_ROOT="$work"
bash "$acme/skills/sync/sync.sh" collect >"$work/root.log" 2>&1 || true
after=$(find "$acme_target" -type f | wc -l | tr -d ' ')
if [ "$after" -gt "$before" ]; then
  osf_result "S12 FAIL a session started at the root was collected"
fi

osf_result "S12 PASS"
