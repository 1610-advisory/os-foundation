#!/bin/bash
# Item 29: the logs move finds origin/logs in a fresh clone, stops on a stale local logs,
# and never deletes the logs skill unless the move ran.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../team/common.sh"
root=$(team_root)
upgrade="$root/template/skills/upgrade/upgrade.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost"
export GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost"

# A v0 company with a logs branch, on a bare origin. Then a fresh clone: only origin/logs.
seed="$work/seed"
mkdir -p "$seed"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$seed/"
rm -rf "$work/template"
git -C "$seed" init -q -b main
git -C "$seed" add -A
git -C "$seed" commit -q -m "v0 start"
git -C "$seed" checkout -q --orphan logs
git -C "$seed" rm -rfq . >/dev/null
printf '%s\n' "worked on the shop" > "$seed/2026-10-01-ada.md"
git -C "$seed" add 2026-10-01-ada.md
git -C "$seed" commit -q -m "Logs: day one"
git -C "$seed" checkout -q main
git init -q --bare -b main "$work/origin.git"
git -C "$seed" remote add origin "$work/origin.git"
git -C "$seed" push -q origin main logs

fresh="$work/fresh"
git clone -q "$work/origin.git" "$fresh"
git -C "$fresh" show-ref --verify --quiet refs/heads/logs && team_fail "fresh clone has a local logs branch"
"$upgrade" --dry-run --root "$fresh" --template "$root/template" --level solo > "$work/dry.out" 2>&1 \
  || { cat "$work/dry.out" >&2; team_fail "dry run failed"; }
grep -qx 'v0: logs-branch' "$work/dry.out" || team_fail "dry run missed origin/logs"
grep -qx 'change: remove-logs-folder' "$work/dry.out" || team_fail "dry run did not plan the logs-folder removal"
# logsfix (51): the dry run asks for the log freeze before the real run.
grep -q '^log-freeze: before the real run, every teammate saves their logs' "$work/dry.out" || team_fail "no log-freeze step"
git -C "$fresh" show-ref --verify --quiet refs/heads/logs && team_fail "dry run made a local logs branch"
"$upgrade" --root "$fresh" --template "$root/template" --level solo > "$work/fresh.out" 2>&1 \
  || { cat "$work/fresh.out" >&2; team_fail "fresh clone upgrade failed"; }
git -C "$fresh" cat-file -e upgrade/v1:memory/logs/archive/2026-10-01-ada.md 2>/dev/null || team_fail "fresh clone skipped the logs move"
git -C "$fresh" log --format=%s upgrade/v1 -- memory/logs/archive/2026-10-01-ada.md | grep -qx 'Logs: day one' \
  || team_fail "logs history missing"
git -C "$fresh" ls-tree -r --name-only upgrade/v1 | grep -q '^skills/logs-folder/' && team_fail "logs-folder was kept after the move"

# A local logs that is not the same as origin/logs: stop with one line, change nothing.
stale="$work/stale"
git clone -q "$work/origin.git" "$stale"
git -C "$stale" branch -q logs origin/logs
other="$work/other"
git clone -q --branch logs "$work/origin.git" "$other"
printf '%s\n' "a later log" > "$other/2026-10-02-ada.md"
git -C "$other" add 2026-10-02-ada.md
git -C "$other" commit -q -m "Logs: day two"
git -C "$other" push -q origin logs
before=$(git -C "$stale" rev-parse HEAD)
set +e
"$upgrade" --root "$stale" --template "$root/template" --level solo > "$work/stale.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || { cat "$work/stale.out" >&2; team_fail "stale logs exit was $rc"; }
grep -q 'the company: the local logs branch is not the same as origin/logs' "$work/stale.out" || team_fail "stale logs line"
[ "$(git -C "$stale" rev-parse HEAD)" = "$before" ] || team_fail "stale logs run committed"
git -C "$stale" show-ref --verify --quiet refs/heads/upgrade/v1 && team_fail "stale logs run made upgrade/v1"
[ -d "$stale/skills/logs-folder" ] || team_fail "stale logs run deleted the logs skill"
"$upgrade" --dry-run --root "$stale" --template "$root/template" --level solo > "$work/stale-dry.out" 2>&1 || true
grep -q '^conflict: logs the company: the local logs branch is not the same as origin/logs' "$work/stale-dry.out" \
  || team_fail "dry run hid the stale logs"

# No logs branch anywhere: the logs skill stays.
nologs="$work/nologs"
mkdir -p "$nologs"
git -C "$root" archive c2034af template | tar -x -C "$work"
cp -R "$work/template/." "$nologs/"
rm -rf "$work/template"
git -C "$nologs" init -q -b main
git -C "$nologs" add -A
git -C "$nologs" commit -q -m "v0 no logs"
"$upgrade" --root "$nologs" --template "$root/template" --level solo > "$work/nologs.out" 2>&1 \
  || { cat "$work/nologs.out" >&2; team_fail "no-logs upgrade failed"; }
grep -q '^keep: skills/logs-folder' "$work/nologs.out" || team_fail "no keep line for the logs skill"
git -C "$nologs" ls-tree -r --name-only upgrade/v1 | grep -q '^skills/logs-folder/' || team_fail "no-logs run deleted the logs skill"
# Round 3 (35): no host answer and no host in the v0 profile writes host: none.
git -C "$nologs" show upgrade/v1:company-profile.md | grep -qx 'host: none' || team_fail "no host: none in the profile"

# logsfix (51): a v0 teammate runs a plain git pull after the upgrade merges. The old
# logs are on main under memory/logs/archive/, so nothing in the old worktree is written over.
grep -q '^teammates: in an old (v0) copy of this folder, do not run git pull' "$work/fresh.out" || team_fail "no teammates steps"
[ "$(tail -n 1 "$work/fresh.out")" = "upgrade: ok" ] || team_fail "upgrade: ok is not the last line"
mate="$work/mate"
git clone -q "$work/origin.git" "$mate"
git -C "$mate" fetch -q origin logs:refs/remotes/origin/logs
git -C "$mate" worktree add -q "$mate/memory/logs" -b logs origin/logs
printf '%s\n' "worked on the shop" "and a line not committed" > "$mate/memory/logs/2026-10-01-ada.md"
printf '%s\n' "a log committed after the snapshot" > "$mate/memory/logs/2026-10-03-ada.md"
git -C "$mate/memory/logs" add 2026-10-03-ada.md
git -C "$mate/memory/logs" commit -q -m "Logs: day three"
git -C "$fresh" push -q origin upgrade/v1:main
git -C "$mate" pull -q --no-rebase origin main > "$work/mate-pull.out" 2>&1 || { cat "$work/mate-pull.out" >&2; team_fail "plain pull failed"; }
git -C "$mate" cat-file -e HEAD:memory/logs/archive/2026-10-01-ada.md || team_fail "the pull did not bring the archive"
[ "$(cat "$mate/memory/logs/2026-10-01-ada.md")" = "$(printf '%s\n' "worked on the shop" "and a line not committed")" ] \
  || team_fail "a plain pull wrote over an uncommitted log"
[ "$(cat "$mate/memory/logs/2026-10-03-ada.md")" = "a log committed after the snapshot" ] || team_fail "a plain pull lost a later log"
[ -f "$mate/memory/logs/.git" ] || team_fail "the old worktree link is gone"

printf '%s\n' "PASS logs-source"
