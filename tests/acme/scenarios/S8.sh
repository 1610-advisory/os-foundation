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
engine=$root/tests/acme/fixtures/engine.sh
EOF
bash "$dest/skills/add-bot/add-bot.sh" --answers "$work/bot-answers" --root "$dest" >"$work/add-bot.log" 2>&1 \
  || osf_result "S8 FAIL add-bot"
export OS_COMPANY_ROOT="$dest"
bash "$dest/skills/sync/sync.sh" propose add-bot-helper "bots/helper/BOT.md" >"$work/propose.log" 2>&1 \
  || osf_result "S8 FAIL propose bot page"

trace="$work/token-trace"
export OS_BOT=helper
export OS_BOT_TOKEN_TTL=60
export OS_BOT_TOKEN_TRACE="$trace"
export OS_NOW=1000
bash "$dest/skills/add-bot/git-credential-os-bot" get >/dev/null << 'EOF'
protocol=https
host=localhost

EOF
export OS_NOW=1070
bash "$dest/skills/add-bot/git-credential-os-bot" get >/dev/null << 'EOF'
protocol=https
host=localhost

EOF
if ! grep -q 'refresh' "$trace"; then
  osf_result "S8 FAIL token did not refresh after forced expiry"
fi

routine="$dest/bots/helper/routines/note.md"
mkdir -p "$(dirname "$routine")"
printf '%s\n' "Write one line to notes/bot.md: the bot ran." > "$routine"
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
if ! grep -q 'Reverts:' "$work/undo.log" && ! osf_results branches "$org" "${slug}-os" | grep -q "undo/"; then
  osf_result "S8 FAIL undo branch missing"
fi
if osf_results file "$org" "${slug}-marketing" notes/widget.md --ref main >/dev/null 2>&1; then
  :
fi
if ! osf_results clone-denied acme-bot "$org" "${slug}-marketing" >/dev/null; then
  osf_result "S8 FAIL bot could read an area outside its grant"
fi

osf_result "S8 PASS"
