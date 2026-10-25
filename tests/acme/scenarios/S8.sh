#!/usr/bin/env bash
# S8 — company bot. Token expiry is forced with OS_NOW. undo-run uses the Run-Id trailer.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S8
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S8 bots \
  template/skills/add-bot/add-bot.sh \
  template/skills/undo-run/undo-run.sh
osf_need_product S8 sync template/skills/sync/sync.sh
osf_need_product S8 team template/skills/add-teammate/team-on.sh

slug="acme2-s8"
org="acme2-s8"
root=$(osf_acme_root)
work=$(osf_work s8)
cleanup() { osf_delete_org "$org"; }
trap cleanup EXIT
osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_create_org "$org" || osf_result "S8 FAIL could not create org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S8 FAIL admin token missing"
export OS_ORG="$org"
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S8 FAIL team-on"

python3 - "$dest/company-profile.md" << 'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines(True)
out = []
for line in lines:
    if line.startswith("switches:"):
        out.append("switches:\n")
        out.append("  - bots\n")
        continue
    out.append(line)
path.write_text("".join(out), encoding="utf-8")
PY
token_path="$work/bot-token"
cp "$(osf_token_file acme-bot)" "$token_path"
chmod 600 "$token_path"
cat > "$work/bot-answers" << EOF
kind=company
bot=helper
owner=ada
name=Acme Bot
bot_user=acme-bot
email=acme.bot@acme.test
repos=${slug}-os
company_repo=${slug}-os
token_path=${token_path}
box=no
engine=$root/tests/acme/fixtures/bot-engine.sh
EOF
bash "$dest/skills/add-bot/add-bot.sh" --answers "$work/bot-answers" --root "$dest" >"$work/add-bot.log" 2>&1 \
  || osf_result "S8 FAIL add-bot"
routine="$dest/bots/helper/routines/note.md"
mkdir -p "$(dirname "$routine")"
printf '%s\n' "Write one line to notes/bot.md: the bot ran." > "$routine"
export OS_COMPANY_ROOT="$dest"
bash "$dest/skills/sync/sync.sh" propose add-bot-helper \
  "company-profile.md" "bots/helper/BOT.md" "bots/helper/routines/note.md" >"$work/propose.log" 2>&1 \
  || osf_result "S8 FAIL propose bot page"
number=$(awk 'NF { n = $0 } END { print n }' "$work/propose.log")
if ! grep -q "propose ok .* add-bot-helper ${number}" "$XDG_CONFIG_HOME/${slug}-os/state/sync.log"; then
  osf_result "S8 FAIL propose did not open a pull request"
fi
if [ -z "$number" ]; then
  osf_result "S8 FAIL propose did not open a pull request"
fi
osf_approve "$org" "${slug}-os" "$number" acme-director || osf_result "S8 FAIL director approval"
head_sha=$(osf_results pr "$org" "${slug}-os" "$number" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("head_sha",""))')
if ! osf_results wait-check "$org" "${slug}-os" "$head_sha" --timeout 180 >/dev/null; then
  osf_result "S8 FAIL bot page checks did not pass"
fi
i=0
while [ "$i" -lt 24 ]; do
  osf_host S8 file "$org" "${slug}-os" bots/helper/routines/note.md --ref main
  if [ "$OSF_HOST_RC" -eq 0 ]; then
    break
  fi
  i=$((i + 1))
  sleep 5
done
if [ "$OSF_HOST_RC" -ne 0 ]; then
  osf_result "S8 FAIL routine is not on main"
fi
cfg=$(mktemp)
chmod 600 "$cfg"
cat > "$cfg" << EOF
[credential]
	helper = !$root/tests/acme/lib/git-credential-seat.sh
	useHttpPath = true
EOF
osf_export_token acme-admin || osf_result "S8 FAIL admin token missing"
GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND="$root/tests/acme/lib/ssh-off.sh" \
  GIT_ALLOW_PROTOCOL="http:https:file" \
  OSF_FORGEJO_TOKEN="$FORGEJO_TOKEN" OSF_GIT_USER="acme-admin" \
  git -C "$dest" fetch origin >"$work/fetch.log" 2>&1 \
  || osf_result "S8 FAIL could not fetch main"
rm -f "$cfg"
git -C "$dest" checkout -B main origin/main >"$work/checkout.log" 2>&1 \
  || osf_result "S8 FAIL could not match origin/main"

trace="$work/token-trace"
export OS_BOT=helper
export OS_ROOT="$dest"
export OS_PROFILE="$dest/company-profile.md"
export OS_BOT_TOKEN_TTL=60
export OS_BOT_TOKEN_TRACE="$trace"
export OS_NOW=1000
# The helper answers only when protocol and host match host_url.
bash "$dest/skills/add-bot/git-credential-os-bot" get >/dev/null << 'EOF'
protocol=http
host=localhost:3300

EOF
export OS_NOW=1070
bash "$dest/skills/add-bot/git-credential-os-bot" get >/dev/null << 'EOF'
protocol=http
host=localhost:3300

EOF
if ! grep -q 'refresh' "$trace"; then
  osf_result "S8 FAIL token did not refresh after forced expiry"
fi

export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
export OS_COMPANY_ROOT="$dest"
bash "$dest/skills/add-bot/run.sh" helper note --root "$dest" >"$work/run.log" 2>&1 \
  || osf_result "S8 FAIL bot run"
run_id=$(grep -o 'Run-Id: [^ ]*' "$work/run.log" | awk '{print $2}' | head -n 1)
if [ -z "$run_id" ]; then
  run_id=$(git -C "$dest" log -1 --format='%b' | awk -F': ' '/^Run-Id: /{print $2}')
fi
if [ -z "$run_id" ]; then
  osf_result "S8 FAIL no Run-Id"
fi
bash "$dest/skills/undo-run/undo-run.sh" "$run_id" --root "$dest" >"$work/undo.log" 2>&1 \
  || osf_result "S8 FAIL undo-run"
osf_host S8 branches "$org" "${slug}-os"
branches=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -ne 0 ] || ! printf '%s\n' "$branches" | grep -q "undo/${run_id}"; then
  osf_result "S8 FAIL undo branch is not on the host"
fi
osf_host S8 file "$org" "${slug}-os" notes/bot.md --ref "undo/${run_id}"
note=$(cat "$OSF_HOST_JSON")
if [ "$OSF_HOST_RC" -eq 0 ] && printf '%s\n' "$note" | grep -q 'the bot ran'; then
  osf_result "S8 FAIL undo branch still has the bot note"
fi
osf_host S8 clone-denied acme-bot "$org" "${slug}-marketing" >/dev/null
if [ "$OSF_HOST_RC" -ne 0 ]; then
  osf_result "S8 FAIL bot could read an area outside its grant"
fi

osf_result "S8 PASS"
