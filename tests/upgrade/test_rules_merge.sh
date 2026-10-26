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

# A second run on an upgraded folder changes nothing.
v1f="$work/v1keep"
mkdir -p "$v1f"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$v1f/"
rm -rf "$work/template"
git -C "$v1f" init -q
git -C "$v1f" checkout -q -b main
commit_all "$v1f" "v0 start"
"$upgrade" --root "$v1f" --template "$root/template" --level solo > "$work/v1-first.out"
grep -q 'upgrade: ok' "$work/v1-first.out" || team_fail "first upgrade failed"
python3 - << PY
import hashlib, os
from pathlib import Path
root = Path("$v1f")
out = Path("$work/v1-hashes")
lines = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or path.is_symlink():
        continue
    if ".git" in path.parts:
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    lines.append(f"{digest} {path.relative_to(root)}")
out.write_text("\n".join(lines) + "\n")
PY
head_before=$(git -C "$v1f" rev-parse HEAD)
"$upgrade" --root "$v1f" --template "$root/template" --level solo > "$work/v1.out"
grep -q 'upgrade: pending upgrade/v1' "$work/v1.out" || team_fail "second run did not say pending"
[ "$(git -C "$v1f" rev-parse HEAD)" = "$head_before" ] || team_fail "second run made a commit"
git -C "$v1f" status --porcelain | grep -q . && team_fail "second run left a dirty tree"
python3 - << PY
import hashlib
from pathlib import Path
root = Path("$v1f")
want = Path("$work/v1-hashes").read_text().splitlines()
got = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or path.is_symlink():
        continue
    if ".git" in path.parts:
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    got.append(f"{digest} {path.relative_to(root)}")
if got != want:
    raise SystemExit("a file changed on the second run")
print("hashes-ok")
PY
git -C "$v1f" checkout -q main
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$v1f" merge --no-ff --no-edit upgrade/v1 -m "Merge upgrade" >/dev/null
"$upgrade" --root "$v1f" --template "$root/template" --level solo > "$work/v1-merged.out"
grep -q 'upgrade: already v1' "$work/v1-merged.out" || team_fail "merged main did not say already v1"

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
# shellcheck disable=SC2034
DIR="$root/template/skills/upgrade"
# shellcheck disable=SC2034
ROOT="$work"
# shellcheck disable=SC2034
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

# COMPANY_SLUG comes only from an area rules file. No answers, no profile key, no remote, folder name is not <slug>-os.
slugco="$work/slugonly"
mkdir -p "$slugco/areas/shop"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$slugco/"
rm -rf "$work/template"
fill_company "$slugco"
printf '%s\n' 'Use only files inside ~/acme-os/.' > "$slugco/areas/shop/AGENTS.md"
git -C "$slugco" init -q
git -C "$slugco" checkout -q -b main
commit_all "$slugco" "v0 slug"
git -C "$slugco/areas/shop" init -q
git -C "$slugco/areas/shop" checkout -q -b main
commit_all "$slugco/areas/shop" "area"
"$upgrade" --root "$slugco" --template "$root/template" --level solo > "$work/slug.out"
grep -q 'acme-os/me' "$slugco/AGENTS.md" || team_fail "slug was not taken from the area file"
grep -q 'todo: fill {{COMPANY_SLUG}}' "$work/slug.out" && team_fail "todo for a slug the area file held"
grep -q 'todo: fill {{APP}}' "$work/slug.out" && team_fail "todo for a marker the template keeps"

# Answers can fill a value the old file never filled.
plain="$work/plainco"
mkdir -p "$plain"
cp "$root/template/skills/upgrade/v0/AGENTS.md" "$plain/AGENTS.md"
cp "$root/template/skills/upgrade/v0/CLAUDE.md" "$plain/CLAUDE.md"
cp "$root/template/company-profile.md" "$plain/company-profile.md"
git -C "$plain" init -q
git -C "$plain" checkout -q -b main
commit_all "$plain" "v0 plain"
printf '%s\n' 'one_liner=Acme Co makes widgets.' 'areas=the shop' > "$work/plain.answers"
"$upgrade" --dry-run --root "$plain" --template "$root/template" --level solo \
  --answers "$work/plain.answers" > "$work/plain.out"
grep -q 'todo: fill {{ONE_LINER}}' "$work/plain.out" && team_fail "todo for a filled one_liner"
grep -q 'todo: fill {{AREAS}}' "$work/plain.out" && team_fail "todo for filled areas"
"$upgrade" --root "$plain" --template "$root/template" --level solo \
  --answers "$work/plain.answers" > "$work/plain-apply.out"
grep -q 'Acme Co makes widgets.' "$plain/AGENTS.md" || team_fail "answers one_liner was not filled"
grep -q 'the shop' "$plain/AGENTS.md" || team_fail "answers areas was not filled"

# shellcheck disable=SC1091
. "$root/template/skills/sync/lib.sh"
sync_is_rules "company-rules.md" || team_fail "company-rules.md is not a rules file"
sync_is_rules "areas/shop/area-rules.md" || team_fail "area-rules.md is not a rules file"

# A copy folder that differs from both the live skill and the v0 hash stays a folder.
conf="$work/conflict"
mkdir -p "$conf"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$conf/"
rm -rf "$work/template"
mkdir -p "$conf/.claude/skills/lint"
cp "$conf/skills/lint/SKILL.md" "$conf/.claude/skills/lint/SKILL.md"
printf '%s\n' 'company-changed-this-copy' >> "$conf/.claude/skills/lint/SKILL.md"
git -C "$conf" init -q
git -C "$conf" checkout -q -b main
commit_all "$conf" "v0 copies"
"$upgrade" --root "$conf" --template "$root/template" --level solo > "$work/conflict.out"
grep -q 'conflict: .claude/skills/lint/SKILL.md' "$work/conflict.out" || team_fail "missing copy conflict"
grep -q 'conflict: .claude/skills left:' "$work/conflict.out" || team_fail "did not say the folder stays"
[ -d "$conf/.claude/skills" ] && [ ! -L "$conf/.claude/skills" ] || team_fail "conflict folder was replaced"
[ ! -e "$conf/.claude/skills/skills" ] || team_fail "link was nested inside the copy folder"

# A company line that contains {{ is kept, including in the one-liner section.
braces="$work/braces.md"
cp "$root/template/skills/upgrade/v0/AGENTS.md" "$braces"
python3 - << PY
from pathlib import Path
p = Path("$braces")
text = p.read_text()
text = text.replace("{{ONE_LINER}}\n", "{{ONE_LINER}}\nNever paste {{secrets}}.\n", 1)
text = text.replace("## Safety\n", "## Safety\nKeep the {{token}} out of notes.\n", 1)
text += "\n## Acme notes\n\n- first note\n\n## Acme notes\n\n- second note\n"
p.write_text(text)
PY
"$merge" --base "$root/template/skills/upgrade/v0/AGENTS.md" --real "$braces" \
  --v1 "$root/template/AGENTS.md" --scope company --values "$work/stock.values" \
  --out "$work/braces-out.md" > "$work/braces.stats"
grep -F -q 'Never paste {{secrets}}.' "$work/braces-out.md" || team_fail "one-liner company line with braces was dropped"
grep -F -q 'Keep the {{token}} out of notes.' "$work/braces-out.md" || team_fail "other company line with braces was dropped"
# Each same heading is kept, not folded into the first.
awk 'BEGIN{n=0} $0=="## Acme notes"{n++} END{if(n!=2) exit 1}' "$work/braces-out.md" || team_fail "same heading was collapsed"
grep -F -q -- '- first note' "$work/braces-out.md" || team_fail "first company section lost"
grep -F -q -- '- second note' "$work/braces-out.md" || team_fail "second company section lost"

# An untracked copy folder with a company-only skill is left in place.
untracked="$work/untracked"
mkdir -p "$untracked"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$untracked/"
rm -rf "$work/template"
git -C "$untracked" init -q
git -C "$untracked" checkout -q -b main
commit_all "$untracked" "v0 clean"
mkdir -p "$untracked/.claude/skills/acme-only"
printf '%s\n' 'only in the untracked copy' > "$untracked/.claude/skills/acme-only/SKILL.md"
"$upgrade" --dry-run --root "$untracked" --template "$root/template" --level solo > "$work/untracked.out"
grep -q 'conflict: .claude/skills (untracked; commit it first)' "$work/untracked.out" || team_fail "missing untracked conflict"
[ -f "$untracked/.claude/skills/acme-only/SKILL.md" ] || team_fail "untracked company skill was deleted"
[ ! -f "$untracked/skills/acme-only/SKILL.md" ] || team_fail "untracked company skill was moved"

# A dirty area is refused before checkout, same message as a dirty company root.
dirty="$work/dirtyarea"
mkdir -p "$dirty/areas/shop"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$dirty/"
rm -rf "$work/template"
python3 - << PY
from pathlib import Path
p = Path("$dirty/company-profile.md")
text = p.read_text()
text = text.replace("---\n", "---\ncompany_slug: acme\n", 1)
p.write_text(text)
PY
git -C "$dirty" init -q
git -C "$dirty" checkout -q -b main
commit_all "$dirty" "v0 dirty"
printf '%s\n' '# Shop' > "$dirty/areas/shop/AGENTS.md"
git -C "$dirty/areas/shop" init -q
git -C "$dirty/areas/shop" checkout -q -b main
commit_all "$dirty/areas/shop" "area"
printf '%s\n' 'uncommitted area note' > "$dirty/areas/shop/note.md"
printf '%s\n' 'host=forgejo' 'org=acme' 'slug=acme' > "$work/dirty.answers"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$work/host.sh"
chmod +x "$work/host.sh"
set +e
OS_HOST_SH="$work/host.sh" "$upgrade" --root "$dirty" --template "$root/template" --level solo \
  --answers "$work/dirty.answers" > "$work/dirty.out" 2>&1
dirty_rc=$?
set -e
[ "$dirty_rc" -eq 2 ] || team_fail "dirty area exit was $dirty_rc"
grep -q 'the area areas/shop has uncommitted changes' "$work/dirty.out" || team_fail "dirty area message missing"
OS_HOST_SH="$work/host.sh" "$upgrade" --dry-run --root "$dirty" --template "$root/template" --level solo \
  --answers "$work/dirty.answers" > "$work/dirty-dry.out" 2>&1
grep -q 'the area areas/shop has uncommitted changes' "$work/dirty-dry.out" || team_fail "dry run hid the dirty area"
grep -q 'uncommitted area note' "$dirty/areas/shop/note.md" || team_fail "dirty area work was discarded"
git -C "$dirty" rev-parse --abbrev-ref HEAD | grep -qx main || team_fail "dirty area moved the company off main"
git -C "$dirty" show-ref --verify --quiet refs/heads/upgrade/v1 && team_fail "dirty area created upgrade/v1"
[ "$(git -C "$dirty" rev-parse HEAD)" = "$(git -C "$dirty" rev-parse main)" ] || team_fail "dirty area committed on main"

# Both rules files over the cap append into one spill file.
# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"
DIR="$root/template/skills/upgrade"
ROOT="$work/bothspill"
ANSWERS=""
mkdir -p "$ROOT"
printf '%s\n' '---' 'type: company-profile' '---' > "$ROOT/company-profile.md"
python3 - << PY
from pathlib import Path
root = Path("$root/template/skills/upgrade/v0")
dest = Path("$work/bothspill")
for name, marker in (("AGENTS.md", "AGENTS-SPILL-LINE"), ("CLAUDE.md", "CLAUDE-SPILL-LINE")):
    text = (root / name).read_text()
    line = f"- Acme {marker} keeps this long rule line so the file spills over the cap.\n"
    text += "\n## Acme notes\n\n" + (line * 200)
    (dest / name).write_text(text)
    (dest / f"{name}.line").write_text(line)
PY
rules_merge_one AGENTS.md "$ROOT/AGENTS.md" "$DIR/v0/AGENTS.md" "$root/template/AGENTS.md" company company "" 1 >/dev/null
rules_merge_one CLAUDE.md "$ROOT/CLAUDE.md" "$DIR/v0/CLAUDE.md" "$root/template/CLAUDE.md" claude company "" 1 >/dev/null
python3 - << PY
from pathlib import Path
root = Path("$work/bothspill")
spill = (root / "company-rules.md").read_text()
agents = (root / "AGENTS.md.line").read_text().rstrip("\n")
claude = (root / "CLAUDE.md.line").read_text().rstrip("\n")
head = "## From CLAUDE.md\n"
idx = spill.find(head)
if idx < 0:
    raise SystemExit("heading missing")
before, after = spill[:idx], spill[idx + len(head):]
if agents not in before:
    raise SystemExit("agents lines missing before the heading")
if claude not in after:
    raise SystemExit("claude lines missing after the heading")
if agents not in before.splitlines():
    raise SystemExit("agents line was not kept byte for byte")
if claude not in after.splitlines():
    raise SystemExit("claude line was not kept byte for byte")
print("spill-append-ok")
PY

# A spill file that already exists is company content. Do not overwrite it.
oldspill="$work/oldspill"
mkdir -p "$oldspill"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$oldspill/"
rm -rf "$work/template"
printf '%s\n' 'keep this company spill' > "$oldspill/company-rules.md"
before_spill=$(team_sha "$oldspill/company-rules.md")
git -C "$oldspill" init -q
git -C "$oldspill" checkout -q -b main
commit_all "$oldspill" "v0 spill"
head_spill=$(git -C "$oldspill" rev-parse HEAD)
set +e
"$upgrade" --root "$oldspill" --template "$root/template" --level solo > "$work/oldspill.out" 2>&1
oldspill_rc=$?
set -e
[ "$oldspill_rc" -eq 2 ] || team_fail "existing spill exit was $oldspill_rc"
grep -q 'conflict: company-rules.md exists' "$work/oldspill.out" || team_fail "missing existing spill conflict"
[ "$(team_sha "$oldspill/company-rules.md")" = "$before_spill" ] || team_fail "existing spill was rewritten"
[ "$(git -C "$oldspill" rev-parse HEAD)" = "$head_spill" ] || team_fail "existing spill made a commit"
git -C "$oldspill" show-ref --verify --quiet refs/heads/upgrade/v1 && team_fail "existing spill created upgrade/v1"

# Windows Git Bash must not commit a copy where a link was asked for.
win="$work/windows"
mkdir -p "$win"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$win/"
rm -rf "$work/template"
git -C "$win" init -q
git -C "$win" checkout -q -b main
commit_all "$win" "v0 win"
head_win=$(git -C "$win" rev-parse HEAD)
set +e
OS_UPGRADE_UNAME=MINGW64_NT-10.0 "$upgrade" --root "$win" --template "$root/template" --level solo > "$work/win.out" 2>&1
win_rc=$?
set -e
[ "$win_rc" -eq 2 ] || team_fail "windows guard exit was $win_rc"
grep -q 'run the upgrade from a Mac or Linux clone of the company repo' "$work/win.out" || team_fail "windows guard message missing"
[ "$(git -C "$win" rev-parse HEAD)" = "$head_win" ] || team_fail "windows guard wrote a commit"

# An existing team folder that spills keeps every old owner line and gains the spill paths.
own="$work/owners"
mkdir -p "$own/.github" "$own/.gitea" "$own/areas/shop/.github" "$own/areas/shop/.gitea"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$own/"
rm -rf "$work/template"
printf '%s\n' '# Rules files only. Notes have no code owner.' '/AGENTS.md @ada' '/CLAUDE.md @ada' '/skills/ @ada' > "$own/.github/CODEOWNERS"
printf '%s\n' '# Rules files only. Notes have no code owner.' '^AGENTS\.md$ @ada' '^CLAUDE\.md$ @ada' '^skills/.* @ada' > "$own/.gitea/CODEOWNERS"
cp "$own/.github/CODEOWNERS" "$own/areas/shop/.github/CODEOWNERS"
cp "$own/.gitea/CODEOWNERS" "$own/areas/shop/.gitea/CODEOWNERS"
python3 - << PY
from pathlib import Path
p = Path("$own/AGENTS.md")
text = p.read_text()
text += "\n## Acme notes\n\n" + ("- Acme keeps this long rule line so the file spills over the cap.\n" * 80)
p.write_text(text)
PY
git -C "$own" init -q
git -C "$own" checkout -q -b main
commit_all "$own" "v0 owners"
printf '%s\n' '# Shop' > "$own/areas/shop/AGENTS.md"
git -C "$own/areas/shop" init -q
git -C "$own/areas/shop" checkout -q -b main
commit_all "$own/areas/shop" "area owners"
old_gh=$(cat "$own/.github/CODEOWNERS")
old_gitea=$(cat "$own/.gitea/CODEOWNERS")
"$upgrade" --root "$own" --template "$root/template" --level solo > "$work/owners.out"
grep -q 'change: rules-spill AGENTS.md -> company-rules.md' "$work/owners.out" || team_fail "owners fixture did not spill"
printf '%s\n' "$old_gh" | while IFS= read -r line; do
  grep -F -x -q -- "$line" "$own/.github/CODEOWNERS" || team_fail "old github owner line changed"
done
grep -F -x -q -- '/company-rules.md @ada' "$own/.github/CODEOWNERS" || team_fail "github spill line missing"
grep -F -x -q -- '/area-rules.md @ada' "$own/.github/CODEOWNERS" || team_fail "github area spill line missing"
printf '%s\n' "$old_gitea" | while IFS= read -r line; do
  grep -F -x -q -- "$line" "$own/.gitea/CODEOWNERS" || team_fail "old forgejo owner line changed"
done
grep -F -x -q -- '^company-rules\.md$ @ada' "$own/.gitea/CODEOWNERS" || team_fail "forgejo spill line missing"
grep -F -x -q -- '^area-rules\.md$ @ada' "$own/.gitea/CODEOWNERS" || team_fail "forgejo area spill line missing"
grep -F -x -q -- '/company-rules.md @ada' "$own/areas/shop/.github/CODEOWNERS" || team_fail "area github spill line missing"
grep -F -x -q -- '^company-rules\.md$ @ada' "$own/areas/shop/.gitea/CODEOWNERS" || team_fail "area forgejo spill line missing"
old_area=$(git -C "$own/areas/shop" show HEAD:.github/CODEOWNERS)
printf '%s\n' "$old_area" | while IFS= read -r line; do
  grep -F -x -q -- "$line" "$own/areas/shop/.github/CODEOWNERS" || team_fail "old area owner line changed"
done

printf '%s\n' "PASS rules-merge"
