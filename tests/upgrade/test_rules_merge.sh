#!/bin/bash
# Rules merge: stock, filled placeholders, company lines, spill, v1, areas.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../team/common.sh"
root=$(team_root)
upgrade="$root/template/skills/upgrade/upgrade.sh"
merge="$root/template/skills/upgrade/rules-merge.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fill_company() {
  local dest=$1
  OSF_DEST="$dest" python3 - << 'PY'
import os
from pathlib import Path
dest = Path(os.environ["OSF_DEST"])
repl = {
    "{{COMPANY_NAME}}": "Acme Co",
    "{{COMPANY_SLUG}}": "acme",
    "{{OWNER_NAME}}": "Ada Admin",
    "{{OWNER_ROLE}}": "Owner",
    "{{DATE}}": "2026-10-24",
    "{{ONE_LINER}}": "Acme Co makes sample goods.",
    "{{AREAS}}": "none yet",
    "{{AREA_NAME}}": "Marketing",
    "{{AREA_SLUG}}": "marketing",
    "{{PERSON}}": "Ada",
    "{{PERSON_SLUG}}": "ada",
    "{{APP}}": "portal",
    "{{OS_VERSION}}": "v1.0.0",
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
}

commit_all() {
  local dir=$1 msg=$2
  git -C "$dir" add -A
  GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
    GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
    git -C "$dir" commit -q -m "$msg"
}

# Stock file becomes the plain v1 file. Zero company lines.
stock="$work/stock"
mkdir -p "$stock"
cp "$root/template/skills/upgrade/v0/AGENTS.md" "$stock/AGENTS.md"
cp "$root/template/skills/upgrade/v0/CLAUDE.md" "$stock/CLAUDE.md"
printf 'slug=acme\n' > "$work/stock.values"
out=$("$merge" --base "$root/template/skills/upgrade/v0/AGENTS.md" \
  --real "$stock/AGENTS.md" --v1 "$root/template/AGENTS.md" --scope company \
  --values "$work/stock.values" --out "$work/stock-out.md" --role company)
printf '%s\n' "$out" | grep -q 'company-lines=0' || team_fail "stock file kept company lines"
cmp -s "$work/stock-out.md" "$root/template/AGENTS.md" || team_fail "stock file is not pure v1"

# Placeholders filled only: v1 with the values, zero company lines, built check clean.
filled="$work/filled"
mkdir -p "$filled"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$filled/"
rm -rf "$work/template"
fill_company "$filled"
git -C "$filled" init -q
git -C "$filled" checkout -q -b main
commit_all "$filled" "v0 filled"
printf 'slug=acme\n' > "$work/filled.answers"
"$upgrade" --root "$filled" --template "$root/template" --level solo \
  --answers "$work/filled.answers" > "$work/filled.out"
grep -q 'company-lines=0' "$work/filled.out" || team_fail "filled file reported company lines"
grep -q '## 1. Level first' "$filled/AGENTS.md" || team_fail "filled file missed v1"
grep -q 'Ada Admin' "$filled/AGENTS.md" || team_fail "owner name was not filled"
grep -q 'acme-os/me' "$filled/AGENTS.md" || team_fail "slug was not filled"
if grep -q '{{' "$filled/AGENTS.md"; then
  team_fail "filled AGENTS.md still has a placeholder"
fi
bash "$root/tests/static/placeholders.sh" --built "$filled" > "$work/ph.out" || team_fail "placeholders.sh --built failed"

# Company lines in three sections, plus one company-only section.
custom="$work/custom"
mkdir -p "$custom"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$custom/"
rm -rf "$work/template"
fill_company "$custom"
python3 - << PY
from pathlib import Path
p = Path("$custom/AGENTS.md")
text = p.read_text()
text = text.replace(
    "- (setup fills this in)\\n",
    "- (setup fills this in)\\n- Acme ships sample goods on Tuesdays.\\n",
    1,
)
old = "- Before you send, post, publish, pay, or delete anything outside this folder, show it and ask.\\n"
text = text.replace(old, old + "- Acme locks the shop at six.\\n", 1)
text = text.replace("## Memory\\n\\n", "## Memory\\n\\n- Acme keeps a paper ledger.\\n", 1)
text += "\\n## Acme notes\\n\\n- Acme writes its own rules here.\\n"
p.write_text(text)
PY
before_agents=$(team_sha "$custom/AGENTS.md")
git -C "$custom" init -q
git -C "$custom" checkout -q -b main
commit_all "$custom" "v0 custom"
git -C "$custom" checkout -q --orphan logs
git -C "$custom" rm -rfq . >/dev/null
printf '%s\n' "log-line" > "$custom/day.md"
commit_all "$custom" "Logs: day"
git -C "$custom" checkout -q main
"$upgrade" --root "$custom" --template "$root/template" --level solo \
  --answers "$work/filled.answers" > "$work/custom.out"
grep -q 'change: rules-merge AGENTS.md' "$work/custom.out" || team_fail "missing rules-merge line"
grep -q 'conflict: AGENTS.md' "$work/custom.out" && team_fail "still reports a rules conflict"
python3 - << PY
from pathlib import Path
text = Path("$custom/AGENTS.md").read_text()
checks = [
    ("## 10. Safety", "- Acme locks the shop at six."),
    ("### Right now", "- Acme ships sample goods on Tuesdays."),
    ("## Memory and logs", "- Acme keeps a paper ledger."),
    ("## Acme notes", "- Acme writes its own rules here."),
]
for heading, line in checks:
    start = text.find(heading)
    if start < 0:
        raise SystemExit("missing " + heading)
    nxt = text.find("\\n## ", start + 1)
    chunk = text[start:] if nxt < 0 else text[start:nxt]
    if line not in chunk:
        raise SystemExit(line + " not in " + heading)
print("lines-ok")
PY
git -C "$custom" log --format='%s' upgrade/v1^2 | grep -qx 'Upgrade: rules merge' || team_fail "rules commit is not separate"
old=$(git -C "$custom" rev-parse 'HEAD^1')
git -C "$custom" revert -m 1 --no-edit HEAD >/dev/null
[ "$(git -C "$custom" rev-parse HEAD:AGENTS.md)" = "$(git -C "$custom" rev-parse "$old:AGENTS.md")" ] || team_fail "revert did not restore AGENTS.md"
[ "$(git -C "$custom" rev-parse HEAD:AGENTS.md)" = "$(git -C "$custom" rev-parse "$old:AGENTS.md")" ] || team_fail "revert bytes differ"
git -C "$custom" show HEAD:AGENTS.md | grep -q 'Acme ships sample goods on Tuesdays.' || team_fail "revert lost the company line"
git -C "$custom" show HEAD:AGENTS.md | grep -q '## 1. Level first' && team_fail "revert kept v1 rules"

# Over the cap: spill file, link line, AGENTS.md under 10000.
spill="$work/spill"
mkdir -p "$spill"
cp "$root/template/skills/upgrade/v0/AGENTS.md" "$spill/AGENTS.md"
python3 - << PY
from pathlib import Path
p = Path("$spill/AGENTS.md")
text = p.read_text()
text += "\\n## Acme notes\\n\\n" + ("- Acme keeps this long rule line so the file spills over the cap.\\n" * 80)
p.write_text(text)
PY
line='- Acme keeps this long rule line so the file spills over the cap.'
"$merge" --base "$root/template/skills/upgrade/v0/AGENTS.md" \
  --real "$spill/AGENTS.md" --v1 "$root/template/AGENTS.md" --scope company \
  --values "$work/stock.values" --out "$spill/out.md" --spill "$spill/company-rules.md" \
  --role company --link company-rules.md > "$spill/stats"
grep -q 'spill=1' "$spill/stats" || team_fail "spill did not trigger"
chars=$(wc -c < "$spill/out.md" | tr -d ' ')
[ "$chars" -lt 10000 ] || team_fail "spilled AGENTS.md is still over the cap"
grep -q 'Read company-rules.md' "$spill/out.md" || team_fail "spill link missing"
grep -q '## This company' "$spill/out.md" || team_fail "spill link is not in This company"
grep -F -q -- "$line" "$spill/company-rules.md" || team_fail "spill file dropped a company line"
grep -F -q -- "$line" "$spill/out.md" && team_fail "spilled line stayed in AGENTS.md"

# A v1 folder is left alone.
v1f="$work/v1keep"
mkdir -p "$v1f"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$v1f/"
rm -rf "$work/template"
printf '%s\n' '## 1. Level first' > "$v1f/AGENTS.md"
printf '%s\n' '- Keep this v1 company line.' >> "$v1f/AGENTS.md"
before=$(team_sha "$v1f/AGENTS.md")
git -C "$v1f" init -q
git -C "$v1f" checkout -q -b main
commit_all "$v1f" "v1 already"
"$upgrade" --root "$v1f" --template "$root/template" --level solo > "$work/v1.out"
[ "$(team_sha "$v1f/AGENTS.md")" = "$before" ] || team_fail "v1 folder was rewritten"
grep -q 'change: rules-merge AGENTS.md' "$work/v1.out" && team_fail "v1 folder was planned for merge"

# Each area kind merges with its own v1 template.
for kind in _area apps finance marketing; do
  real="$work/area-$kind.md"
  cp "$root/template/skills/upgrade/v0/areas/$kind/AGENTS.md" "$real"
  printf '%s\n' "- Acme area line for ${kind}." >> "$real"
  "$merge" --base "$root/template/skills/upgrade/v0/areas/$kind/AGENTS.md" \
    --real "$real" --v1 "$root/template/skills/add-area/templates/$kind/AGENTS.md" \
    --scope area --values "$work/stock.values" --out "$work/area-$kind-out.md" \
    --role area > "$work/area-$kind.stats"
  grep -q 'company-lines=1' "$work/area-$kind.stats" || team_fail "$kind company line count"
  grep -q "Acme area line for $kind." "$work/area-$kind-out.md" || team_fail "$kind lost the line"
  grep -q '## Approval tiers \[team\]' "$work/area-$kind-out.md" || team_fail "$kind missed v1 tiers"
done
grep -q 'Marketing Toolkit' "$work/area-marketing-out.md" || team_fail "marketing used the wrong template"
grep -q 'Before building or hosting' "$work/area-apps-out.md" || team_fail "apps used the wrong template"
grep -q 'Rules for numbers' "$work/area-finance-out.md" || team_fail "finance used the wrong template"
grep -q 'Marketing Toolkit' "$work/area-_area-out.md" && team_fail "_area used the marketing template"

# Best match picks the area kind, not always _area.
DIR="$root/template/skills/upgrade"
ROOT="$work"
ANSWERS=""
# shellcheck disable=SC1091
. "$root/template/skills/upgrade/rules.sh"
kind=$(rules_best_kind "$work/area-marketing.md")
[ "$kind" = "marketing" ] || team_fail "best match was $kind"

# Line ends: a template fixture with .gitattributes is copied. Missing file is a no-op.
attrs="$work/attrs"
tpl="$work/tpl"
mkdir -p "$attrs"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$attrs/"
rm -rf "$work/template"
cp -R "$root/template" "$tpl"
printf '%s\n' '* text=auto' > "$tpl/.gitattributes"
printf '%s\n' '* text=auto' > "$tpl/skills/add-area/templates/marketing/.gitattributes"
mkdir -p "$attrs/areas/marketing"
cp "$root/template/skills/upgrade/v0/areas/marketing/AGENTS.md" "$attrs/areas/marketing/AGENTS.md"
git -C "$attrs" init -q
git -C "$attrs" checkout -q -b main
commit_all "$attrs" "v0 attrs"
git -C "$attrs/areas/marketing" init -q
git -C "$attrs/areas/marketing" checkout -q -b main
commit_all "$attrs/areas/marketing" "area"
"$upgrade" --root "$attrs" --template "$tpl" --level solo > "$work/attrs.out"
grep -q 'change: .gitattributes' "$work/attrs.out" || team_fail "dry-run missed gitattributes"
cmp -s "$attrs/.gitattributes" "$tpl/.gitattributes" || team_fail "company gitattributes was not copied"
cmp -s "$attrs/areas/marketing/.gitattributes" "$tpl/skills/add-area/templates/marketing/.gitattributes" || team_fail "area gitattributes was not copied"

printf '%s\n' "PASS rules-merge"
