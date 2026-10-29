#!/bin/bash
# Upgrade a v0-shaped folder: dry-run, one commit, logs history, revert.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
upgrade="$root/template/skills/upgrade/upgrade.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

company="$work/acme"
mkdir -p "$company"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$company/"
rm -rf "$work/template"

# Company content and one edited stock skill. These must stay byte-identical.
mkdir -p "$company/notes"
printf '%s\n' "ours-keep-this" > "$company/notes/ours.md"
printf '%s\n' "edited-by-company" >> "$company/skills/lint/SKILL.md"
printf '%s\n' "company-added-skill-file" > "$company/skills/lint/ours.md"
before_notes=$(team_sha "$company/notes/ours.md")
before_skill=$(team_sha "$company/skills/lint/SKILL.md")
before_ours=$(team_sha "$company/skills/lint/ours.md")

git -C "$company" init -q
git -C "$company" checkout -q -b main
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" commit -q -m "v0 start"

git -C "$company" checkout -q --orphan logs
git -C "$company" rm -rfq . >/dev/null
printf '%s\n' "log-line-alpha" > "$company/2026-10-01-ada.md"
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" commit -q -m "Logs: day one"
git -C "$company" checkout -q main
git -C "$company" worktree add -q "$company/memory/logs" logs

dry=$("$upgrade" --dry-run --root "$company" --template "$root/template" --level team)
printf '%s\n' "$dry" | grep -q 'upgrade: dry-run' || team_fail "missing dry-run header"
printf '%s\n' "$dry" | grep -q 'v0: logs-branch' || team_fail "missing logs signal"
printf '%s\n' "$dry" | grep -q 'v0: no-level' || team_fail "missing level signal"
printf '%s\n' "$dry" | grep -q 'v0: logs-folder' || team_fail "missing logs-folder signal"
printf '%s\n' "$dry" | grep -q 'conflict: skills/lint/SKILL.md' || team_fail "missing conflict"
printf '%s\n' "$dry" | grep -q 'change: skill-files skills/add-teammate new=' || team_fail "missing new skill files"
printf '%s\n' "$dry" | grep -q 'change: tier-table' || team_fail "missing tier table"
printf '%s\n' "$dry" | grep -q 'keep: 90 days' || team_fail "missing 90 day note"
git -C "$company" status --porcelain | grep -q . && team_fail "dry-run changed the tree"

"$upgrade" --root "$company" --template "$root/template" --level team > "$work/apply.out"
grep -q 'upgrade: ok' "$work/apply.out" || team_fail "upgrade did not finish"
git -C "$company" rev-parse --abbrev-ref HEAD | grep -qx 'upgrade/v1' || team_fail "not on upgrade/v1"
parents=$(git -C "$company" rev-list --parents -n 1 HEAD | awk '{print NF}')
[ "$parents" -ge 3 ] || team_fail "upgrade commit is not a merge"
git -C "$company" log --format='%s' -- memory/logs/archive/2026-10-01-ada.md | grep -q 'Logs: day one' || team_fail "logs history missing"
git -C "$company" tag --list 'logs-archive-*' | grep -q . || team_fail "logs archive tag missing"
grep -q '^level: team$' "$company/company-profile.md" || team_fail "level not set"
[ -L "$company/.agents/skills" ] || team_fail "link missing"
[ "$(readlink "$company/.agents/skills")" = "../skills" ] || team_fail "link target wrong"
grep -q '/memory/logs/' "$company/.gitignore" && team_fail "logs ignore line remains"
[ "$(team_sha "$company/notes/ours.md")" = "$before_notes" ] || team_fail "company note changed"
[ "$(team_sha "$company/skills/lint/SKILL.md")" = "$before_skill" ] || team_fail "edited skill changed"
[ "$(team_sha "$company/skills/lint/ours.md")" = "$before_ours" ] || team_fail "company skill file changed"
[ -x "$company/skills/add-teammate/team-on.sh" ] || team_fail "new skill file was not copied"
[ -x "$company/skills/sync/sync.sh" ] || team_fail "new sync skill was not copied"
git -C "$company" show-ref --verify --quiet refs/heads/upgrade/work && team_fail "upgrade/work branch remains"
git -C "$company" ls-files | grep -q 'logs-folder' && team_fail "logs-folder is still in the commit"
grep -q 'Approval tiers' "$company/AGENTS.md" || team_fail "tier table missing"

# One-commit revert restores the old state.
old=$(git -C "$company" rev-parse HEAD^1)
git -C "$company" revert -m 1 --no-edit HEAD >/dev/null
[ "$(git -C "$company" rev-parse HEAD:notes/ours.md)" = "$(git -C "$company" rev-parse "$old:notes/ours.md")" ] || team_fail "revert lost the note"
git -C "$company" cat-file -e HEAD:memory/logs/archive/2026-10-01-ada.md 2>/dev/null && team_fail "revert kept logs files"
git -C "$company" show HEAD:.gitignore | grep -q '/memory/logs/' || team_fail "revert did not restore gitignore"
git -C "$company" show HEAD:company-profile.md | grep -q '^level:' && team_fail "revert kept level"

# No logs branch: still one merge commit, and revert -m 1 restores it.
nologs="$work/nologs"
mkdir -p "$nologs"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$nologs/"
rm -rf "$work/template"
git -C "$nologs" init -q
git -C "$nologs" checkout -q -b main
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$nologs" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$nologs" commit -q -m "v0 no logs"
"$upgrade" --root "$nologs" --template "$root/template" --level solo >"$work/nologs.out"
grep -q 'upgrade: ok' "$work/nologs.out" || team_fail "no-logs upgrade failed"
nparents=$(git -C "$nologs" rev-list --parents -n 1 HEAD | awk '{print NF}')
[ "$nparents" -ge 3 ] || team_fail "no-logs upgrade is not a merge"
oldn=$(git -C "$nologs" rev-parse 'HEAD^1')
git -C "$nologs" revert -m 1 --no-edit HEAD >/dev/null
git -C "$nologs" rev-parse HEAD:company-profile.md >/dev/null
git -C "$nologs" show HEAD:company-profile.md | grep -q '^level:' && team_fail "no-logs revert kept level"
[ "$(git -C "$nologs" rev-parse "HEAD:company-profile.md")" = "$(git -C "$nologs" rev-parse "$oldn:company-profile.md")" ] || team_fail "no-logs revert did not restore the profile"

# Dry-run names an area pull request. It does not copy tools into the company commit.
plan="$work/plan"
mkdir -p "$plan/areas/marketing" "$plan/areas/finance"
printf '%s\n' '# Marketing' > "$plan/areas/marketing/AGENTS.md"
printf '%s\n' '# Finance' > "$plan/areas/finance/AGENTS.md"
printf '%s\n' 'keep-mine' > "$plan/areas/finance/review-rules.md"
git -C "$plan" init -q
git -C "$plan" checkout -q -b main
printf '%s\n' '/areas/' > "$plan/.gitignore"
cat > "$plan/company-profile.md" << 'EOF'
---
type: company-profile
summary: "Acme plan"
company_slug: acme
---
EOF
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$plan" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$plan" commit -q -m "v0 plan"
git -C "$plan/areas/marketing" init -q
git -C "$plan/areas/marketing" checkout -q -b main
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$plan/areas/marketing" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$plan/areas/marketing" commit -q -m "area start"
git -C "$plan/areas/finance" init -q
git -C "$plan/areas/finance" checkout -q -b main
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$plan/areas/finance" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$plan/areas/finance" commit -q -m "area start"
plan_out=$("$upgrade" --dry-run --root "$plan" --template "$root/template" --level team)
printf '%s\n' "$plan_out" | grep -q 'pr-plan: acme-marketing branch upgrade/scripts files .github/scripts review-rules.md auto-merge' || team_fail "missing area review-rules plan"
printf '%s\n' "$plan_out" | grep -q 'pr-plan: acme-finance branch upgrade/scripts files .github/scripts auto-merge' || team_fail "dry-run planned an overwrite of review-rules.md"
printf '%s\n' "$plan_out" | grep -q 'change: areas/' && team_fail "dry-run still claims an area working-tree change"
git -C "$plan" status --porcelain | grep -q . && team_fail "dry-run changed the plan tree"
git -C "$plan" ls-files | grep -q '^areas/' && team_fail "area files are in the company repo"

printf '%s\n' "PASS upgrade"
bash "$here/../upgrade/test_rules_merge.sh"
bash "$here/../upgrade/test_host_upgrade.sh"
