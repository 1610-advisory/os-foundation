#!/usr/bin/env bash
# S11 — upgrade a v0 Acme folder built from os-foundation c2034af.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S11
org="acme2-s11"
cleanup() {
  osf_keep_on_fail "$org"
}
trap 'echo "$OSF_ID FAIL unexpected error"' ERR
trap cleanup EXIT

osf_need_product S11 team template/skills/upgrade/upgrade.sh

root=$(osf_acme_root)
work=$(osf_work s11)
osf_sandbox "$work/box"
archive="$work/archive"
mkdir -p "$archive"
git -C "$root" archive c2034af template | tar -x -C "$archive"
dest="$work/company"
mv "$archive/template" "$dest"
day=$(osf_today)
OSF_DEST="$dest" OSF_DAY="$day" python3 - << 'PY'
import os
from pathlib import Path
dest = Path(os.environ["OSF_DEST"])
repl = {
    "{{COMPANY_NAME}}": "Acme Co",
    "{{COMPANY_SLUG}}": "acme",
    "{{OWNER_NAME}}": "Ada Admin",
    "{{OWNER_ROLE}}": "Owner",
    "{{DATE}}": os.environ["OSF_DAY"],
    "{{ONE_LINER}}": "Acme Co makes sample goods.",
    "{{AREAS}}": "none yet",
}
for path in dest.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    if "skills" in path.parts:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    new = text
    for key, value in repl.items():
        new = new.replace(key, value)
    if new != text:
        path.write_text(new, encoding="utf-8")
PY
python3 - << PY
from pathlib import Path
p = Path("$dest/AGENTS.md")
text = p.read_text(encoding="utf-8")
text = text.replace(
    "- (setup fills this in)\n",
    "- (setup fills this in)\n- Acme ships sample goods on Tuesdays.\n",
    1,
)
old = "- Before you send, post, publish, pay, or delete anything outside this folder, show it and ask.\n"
text = text.replace(old, old + "- Acme locks the shop at six.\n", 1)
text = text.replace("## Memory\n\n", "## Memory\n\n- Acme keeps a paper ledger.\n", 1)
text += "\n## Acme notes\n\n- Acme writes its own rules here.\n"
p.write_text(text, encoding="utf-8")
PY
mkdir -p "$dest/notes"
printf '%s\n' "Keep this company sentence." > "$dest/notes/keep.md"
before=$(cksum "$dest/notes/keep.md" | awk '{print $1}')
git -C "$dest" init -b main
git -C "$dest" add -A
git -C "$dest" -c user.name="Ada Admin" -c user.email="ada.admin@acme.test" \
  commit -m "Company OS: start"
git -C "$dest" checkout --orphan logs
git -C "$dest" rm -rf . >/dev/null 2>&1 || true
printf '%s\n' "Old log line." > "$dest/${day}-ada.md"
git -C "$dest" add "${day}-ada.md"
git -C "$dest" -c user.name="Ada Admin" -c user.email="ada.admin@acme.test" \
  commit -m "Log the day"
git -C "$dest" checkout main

area="$dest/areas/marketing"
mkdir -p "$area"
cp "$root/template/skills/upgrade/v0/areas/marketing/AGENTS.md" "$area/AGENTS.md"
python3 - << PY
from pathlib import Path
p = Path("$area/AGENTS.md")
text = p.read_text(encoding="utf-8")
repl = {
    "{{AREA_NAME}}": "Marketing",
    "{{COMPANY_NAME}}": "Acme Co",
    "{{COMPANY_SLUG}}": "acme",
    "{{PERSON_SLUG}}": "ada",
    "{{APP}}": "portal",
}
for key, value in repl.items():
    text = text.replace(key, value)
text = text.replace("## Skills\n", "## Skills\n- Acme posts one sample photo each week.\n", 1)
p.write_text(text, encoding="utf-8")
PY
git -C "$area" init -b main
git -C "$area" add -A
git -C "$area" -c user.name="Ada Admin" -c user.email="ada.admin@acme.test" \
  commit -m "Marketing area: start"
printf '%s\n' "slug=acme" > "$work/answers"

bash "$root/template/skills/upgrade/upgrade.sh" --dry-run --root "$dest" --template "$root/template" \
  --answers "$work/answers" >"$work/dry.log" 2>&1 || osf_result "S11 FAIL dry-run"
if ! grep -q 'upgrade: dry-run' "$work/dry.log"; then
  osf_result "S11 FAIL dry-run report missing"
fi
if ! grep -q 'change: rules-merge AGENTS.md' "$work/dry.log"; then
  osf_result "S11 FAIL dry-run did not plan a rules merge"
fi
if grep -q 'conflict: AGENTS.md' "$work/dry.log"; then
  osf_result "S11 FAIL dry-run still reports a rules conflict"
fi
bash "$root/template/skills/upgrade/upgrade.sh" --root "$dest" --template "$root/template" --level solo \
  --answers "$work/answers" >"$work/upgrade.log" 2>&1 || osf_result "S11 FAIL upgrade"
after=$(cksum "$dest/notes/keep.md" | awk '{print $1}')
if [ "$before" != "$after" ]; then
  osf_result "S11 FAIL company content changed"
fi
if ! git -C "$dest" cat-file -e "HEAD:memory/logs/${day}-ada.md" 2>/dev/null; then
  osf_result "S11 FAIL logs were not moved onto the branch"
fi
if ! git -C "$dest" tag --list 'logs-archive-*' | grep -q 'logs-archive-'; then
  osf_result "S11 FAIL old logs branch was not tagged"
fi
for heading in "## 1. Level first" "## 2. Pull before work" "## 4. Private sources" "## 5. Learning step" "## 6. Approval tiers" "## 11. Identity"; do
  if ! grep -q "$heading" "$dest/AGENTS.md"; then
    osf_result "S11 FAIL missing v1 section $heading"
  fi
done
for line in "Acme ships sample goods on Tuesdays." "Acme locks the shop at six." "Acme keeps a paper ledger." "Acme writes its own rules here."; do
  if ! grep -q "$line" "$dest/AGENTS.md"; then
    osf_result "S11 FAIL missing company line"
  fi
done
if ! grep -q '## Acme notes' "$dest/AGENTS.md"; then
  osf_result "S11 FAIL company section was dropped"
fi
if ! grep -q '## Must-have rules' "$dest/CLAUDE.md" || ! grep -q 'Level first' "$dest/CLAUDE.md"; then
  osf_result "S11 FAIL CLAUDE.md missed v1 rules"
fi
if ! grep -q '## Approval tiers' "$area/AGENTS.md" || ! grep -q 'Acme posts one sample photo each week.' "$area/AGENTS.md"; then
  osf_result "S11 FAIL area rules were not merged"
fi
for rules in "$dest/AGENTS.md" "$dest/CLAUDE.md" "$area/AGENTS.md"; do
  chars=$(wc -m < "$rules" | tr -d '[:space:]')
  if [ "$chars" -ge 10000 ]; then
    osf_result "S11 FAIL rules file is too long"
  fi
done
merge=$(git -C "$dest" rev-parse HEAD)
git -C "$dest" revert -m 1 "$merge" --no-edit || osf_result "S11 FAIL revert"
if git -C "$dest" cat-file -e "HEAD:memory/logs/${day}-ada.md" 2>/dev/null; then
  osf_result "S11 FAIL revert did not restore the old state"
fi
if ! git -C "$dest" show HEAD:AGENTS.md | grep -q 'Acme ships sample goods on Tuesdays.'; then
  osf_result "S11 FAIL revert lost a company line"
fi
git -C "$dest" reset --hard "$merge" >/dev/null

if ! curl -sf -o /dev/null -m 3 http://localhost:3300/api/v1/version; then
  osf_result "S11 BLOCKED Forgejo is not running"
fi
osf_need_org S11 "$org"
osf_write_team_answers "$work/team-answers" "$dest" "$org" "$org" "$root/tests/acme/fixtures/engine.sh"
if ! osf_export_token acme-admin; then
  osf_result "S11 FAIL admin token missing"
fi
export OS_ORG="$org"
osf_me "$org" ada
osf_write_token_file "$org" acme-admin
# v0 already has skills/add-teammate/, so upgrade does not copy the new team-on.sh into it.
bash "$root/template/skills/add-teammate/team-on.sh" --answers "$work/team-answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S11 FAIL team-on"
if ! grep -q '/company-rules.md' "$dest/.github/CODEOWNERS"; then
  osf_result "S11 FAIL code owners do not cover company-rules.md"
fi
if ! grep -q 'company-rules' "$dest/.gitea/CODEOWNERS"; then
  osf_result "S11 FAIL Forgejo code owners do not cover company-rules.md"
fi
# team-on commits area owners, then may switch branch. Accept the file on disk or in that commit.
if [ -f "$dest/areas/marketing/.github/CODEOWNERS" ]; then
  if ! grep -q '/area-rules.md' "$dest/areas/marketing/.github/CODEOWNERS"; then
    osf_result "S11 FAIL area code owners do not cover area-rules.md"
  fi
elif ! git -C "$dest/areas/marketing" log --all -S '/area-rules.md' --format='%h' -- .github/CODEOWNERS | grep -q .; then
  osf_result "S11 FAIL area code owners do not cover area-rules.md"
fi
if [ -f "$dest/company-rules.md" ] && ! grep -q 'company-rules.md' "$dest/.github/CODEOWNERS"; then
  osf_result "S11 FAIL spill file is not a code-owner path"
fi

osf_result "S11 PASS"
