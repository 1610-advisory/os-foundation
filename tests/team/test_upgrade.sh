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
before_notes=$(team_sha "$company/notes/ours.md")
before_skill=$(team_sha "$company/skills/lint/SKILL.md")

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
printf '%s\n' "$dry" | grep -q 'change: tier-table' || team_fail "missing tier table"
printf '%s\n' "$dry" | grep -q 'keep: 90 days' || team_fail "missing 90 day note"
git -C "$company" status --porcelain | grep -q . && team_fail "dry-run changed the tree"

"$upgrade" --root "$company" --template "$root/template" --level team > "$work/apply.out"
grep -q 'upgrade: ok' "$work/apply.out" || team_fail "upgrade did not finish"
git -C "$company" rev-parse --abbrev-ref HEAD | grep -qx 'upgrade/v1' || team_fail "not on upgrade/v1"
parents=$(git -C "$company" rev-list --parents -n 1 HEAD | awk '{print NF}')
[ "$parents" -ge 3 ] || team_fail "upgrade commit is not a merge"
git -C "$company" log --format='%s' -- memory/logs/2026-10-01-ada.md | grep -q 'Logs: day one' || team_fail "logs history missing"
git -C "$company" tag --list 'logs-archive-*' | grep -q . || team_fail "logs archive tag missing"
grep -q '^level: team$' "$company/company-profile.md" || team_fail "level not set"
[ -L "$company/.agents/skills" ] || team_fail "link missing"
[ "$(readlink "$company/.agents/skills")" = "../skills" ] || team_fail "link target wrong"
grep -q '/memory/logs/' "$company/.gitignore" && team_fail "logs ignore line remains"
[ "$(team_sha "$company/notes/ours.md")" = "$before_notes" ] || team_fail "company note changed"
[ "$(team_sha "$company/skills/lint/SKILL.md")" = "$before_skill" ] || team_fail "edited skill changed"
grep -q 'Approval tiers' "$company/AGENTS.md" || team_fail "tier table missing"

# One-commit revert restores the old state.
old=$(git -C "$company" rev-parse HEAD^1)
git -C "$company" revert -m 1 --no-edit HEAD >/dev/null
[ "$(git -C "$company" rev-parse HEAD:notes/ours.md)" = "$(git -C "$company" rev-parse "$old:notes/ours.md")" ] || team_fail "revert lost the note"
git -C "$company" cat-file -e HEAD:memory/logs/2026-10-01-ada.md 2>/dev/null && team_fail "revert kept logs files"
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

printf '%s\n' "PASS upgrade"
