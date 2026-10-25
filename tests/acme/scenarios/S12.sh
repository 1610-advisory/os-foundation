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
root=$(CDPATH='' cd -- "$root" && pwd -P)
work=$(osf_work s12)
osf_sandbox "$work/box"
osf_setup_solo "$work/acme" acme >/dev/null
osf_setup_solo "$work/bravo" bravo >/dev/null
acme=$(CDPATH='' cd -- "$work/acme" && pwd -P)
bravo=$(CDPATH='' cd -- "$work/bravo" && pwd -P)
python3 - "$acme/company-profile.md" "$bravo/company-profile.md" << 'PY'
import pathlib, sys
for name in sys.argv[1:]:
    path = pathlib.Path(name)
    text = path.read_text(encoding="utf-8")
    text = text.replace("level: solo", "level: app")
    text = text.replace("switches: []", "switches: [traces]")
    path.write_text(text, encoding="utf-8")
PY
mkdir -p "$XDG_CONFIG_HOME" "$bravo/notes" "$HOME/.pi/agent/sessions"
printf '%s\n' "$root/template" > "$XDG_CONFIG_HOME/os-shared-list"
printf '%s\n' "bravo only" > "$bravo/notes/secret.md"
acme_target="$work/target-acme"
bravo_target="$work/target-bravo"
mkdir -p "$acme_target" "$bravo_target"

write_session() {
  local name="$1"
  local cwd="$2"
  local path="$3"
  jq -nc --arg cwd "$cwd" --arg path "$path" \
    '{type:"session", cwd:$cwd}, {message:{content:[{type:"toolCall", arguments:{path:$path}}]}}' \
    > "$HOME/.pi/agent/sessions/${name}.jsonl"
}

collect_as() {
  local company="$1"
  local target="$2"
  local log="$3"
  export OS_TRACES_TARGET="$target"
  export OS_COMPANY_ROOT="$company"
  bash "$company/skills/sync/sync.sh" collect >"$log" 2>&1
}

write_session cross "$acme" "$bravo/notes/secret.md"
collect_as "$acme" "$acme_target" "$work/cross-acme.log" || osf_result "S12 FAIL collect acme"
collect_as "$bravo" "$bravo_target" "$work/cross-bravo.log" || osf_result "S12 FAIL collect bravo"
if find "$acme_target" "$bravo_target" -type f | grep -q .; then
  osf_result "S12 FAIL cross-company session was uploaded"
fi

rm -f "$HOME/.pi/agent/sessions/cross.jsonl"
write_session shared "$acme" "$root/template/AGENTS.md"
collect_as "$acme" "$acme_target" "$work/shared.log" || osf_result "S12 FAIL collect shared"
if [ ! -f "$acme_target/shared.jsonl" ]; then
  osf_result "S12 FAIL shared-list session was not uploaded to acme"
fi
collect_as "$bravo" "$bravo_target" "$work/shared-bravo.log" || true
if find "$bravo_target" -type f | grep -q .; then
  osf_result "S12 FAIL acme session reached bravo"
fi

rm -f "$HOME/.pi/agent/sessions/shared.jsonl"
write_session root "$work" "$acme/AGENTS.md"
before=$(find "$acme_target" -type f | wc -l | tr -d ' ')
collect_as "$acme" "$acme_target" "$work/root.log" || osf_result "S12 FAIL collect root"
after=$(find "$acme_target" -type f | wc -l | tr -d ' ')
if [ "$after" -gt "$before" ]; then
  osf_result "S12 FAIL a session started at the root was collected"
fi
if [ -f "$acme_target/root.jsonl" ]; then
  osf_result "S12 FAIL a session started at the root was collected"
fi

osf_result "S12 PASS"
