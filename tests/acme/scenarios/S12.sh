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
org="acme2-s12"
cleanup() { osf_keep_on_fail "$org"; }
trap cleanup EXIT
osf_need_org S12 "$org"
osf_export_token acme-admin || osf_result "S12 FAIL clean start failed"
for repo in acme2-s12-acme acme2-s12-bravo; do
  body=$(mktemp)
  chmod 600 "$body"
  jq -n --arg name "$repo" '{name:$name, private:true, auto_init:true, default_branch:"main"}' > "$body"
  osf_api "$(osf_token_file acme-admin)" POST "/api/v1/orgs/${org}/repos" "$body"
  code="$OSF_HTTP_CODE"
  rm -f "$body"
  osf_api_discard
  if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    osf_result "S12 FAIL clean start failed"
  fi
done
port_file="$work/traces.port"
python3 "$root/tests/acme/fixtures/traces-host.py" \
  "$(osf_token_file acme-admin)" "$(osf_acme_url)" "$port_file" &
traces_pid=$!
trap 'kill "$traces_pid" 2>/dev/null || true; osf_keep_on_fail "$org"' EXIT
i=0
while [ ! -s "$port_file" ] && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
if [ ! -s "$port_file" ]; then
  osf_result "S12 FAIL traces host did not start"
fi
traces_port=$(tr -d '[:space:]' < "$port_file")
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
  local repo="$4"
  local name="$5"
  export OS_TRACES_TARGET="$target"
  export OS_COMPANY_ROOT="$company"
  export OS_TRACES_UPLOAD_URL="http://127.0.0.1:${traces_port}/${org}/${repo}/traces/${name}.jsonl"
  bash "$company/skills/sync/sync.sh" collect >"$log" 2>&1
}

host_has() {
  local id="$1"
  local repo="$2"
  local name="$3"
  local needle="$4"
  local rc
  osf_host "$id" file "$org" "$repo" "traces/${name}.jsonl" --ref main
  if [ "$OSF_HOST_RC" -ne 0 ]; then
    return 1
  fi
  set +e
  grep -q "$needle" "$OSF_HOST_JSON"
  rc=$?
  set -e
  return "$rc"
}

host_absent() {
  local id="$1"
  local repo="$2"
  local name="$3"
  local page rc
  osf_host "$id" file "$org" "$repo" "traces/${name}.jsonl" --ref main
  page=$(cat "$OSF_HOST_JSON")
  rc=1
  if [ "$OSF_HOST_RC" -eq 2 ]; then
    set +e
    printf '%s\n' "$page" | grep -q '"found": false'
    rc=$?
    set -e
  fi
  if [ "$rc" -ne 0 ]; then
    osf_result "$id FAIL ${name} was not a clean miss on ${repo}"
  fi
}

write_session cross "$acme" "$bravo/notes/secret.md"
collect_as "$acme" "$acme_target" "$work/cross-acme.log" acme2-s12-acme cross || osf_result "S12 FAIL collect acme"
collect_as "$bravo" "$bravo_target" "$work/cross-bravo.log" acme2-s12-bravo cross || osf_result "S12 FAIL collect bravo"
host_absent S12 acme2-s12-acme cross
host_absent S12 acme2-s12-bravo cross

rm -f "$HOME/.pi/agent/sessions/cross.jsonl"
write_session shared "$acme" "$root/template/AGENTS.md"
collect_as "$acme" "$acme_target" "$work/shared.log" acme2-s12-acme shared || osf_result "S12 FAIL collect shared"
if ! host_has S12 acme2-s12-acme shared AGENTS.md; then
  osf_result "S12 FAIL shared-list session is not on the acme host"
fi
collect_as "$bravo" "$bravo_target" "$work/shared-bravo.log" acme2-s12-bravo shared || true
host_absent S12 acme2-s12-bravo shared

rm -f "$HOME/.pi/agent/sessions/shared.jsonl"
write_session root "$work" "$acme/AGENTS.md"
collect_as "$acme" "$acme_target" "$work/root.log" acme2-s12-acme root || osf_result "S12 FAIL collect root"
host_absent S12 acme2-s12-acme root

osf_result "S12 PASS"
