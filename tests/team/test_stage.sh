#!/bin/bash
# B15: scripts that commit in a shared folder stage only the paths they changed.
# B14: they leave the folder on main after pushing their branch.
# B18: join turns on auto-merge for the terms pull request.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME="Ada Admin" GIT_AUTHOR_EMAIL="ada.admin@acme.test"
export GIT_COMMITTER_NAME="Ada Admin" GIT_COMMITTER_EMAIL="ada.admin@acme.test"

# os_git_commit: only the named path goes in. Untracked files stay untracked.
# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"
repo="$work/unit"
mkdir -p "$repo/people"
git -C "$repo" init -q -b main
printf '%s\n' "# Ada" > "$repo/people/Ada Admin.md"
git -C "$repo" add -A
git -C "$repo" commit -q -m seed
printf '%s\n' "left: 2026-10-28" >> "$repo/people/Ada Admin.md"
printf '%s\n' "a meeting note" > "$repo/meeting.md"
printf '%s\n' "held by sync" > "$repo/held.md"
os_git_commit "$repo" "People: update" "people/Ada Admin.md" >/dev/null
[ "$(git -C "$repo" show --name-only --format= HEAD)" = "people/Ada Admin.md" ] \
  || team_fail "os_git_commit committed more than the named path"
[ -z "$(git -C "$repo" ls-files meeting.md held.md)" ] || team_fail "untracked files were committed"
if (os_git_commit "$repo" "no paths") 2>/dev/null; then
  team_fail "os_git_commit with no paths did not stop"
fi

# remove.sh end to end: the offboard branch holds the person page only.
co="$work/co"
mkdir -p "$co/people" "$work/bin"
cat > "$co/company-profile.md" << 'EOF'
---
company_slug: acme
host: forgejo
host_url: "http://localhost:3300"
org: acme
level: team
---
# Acme Co
EOF
cat > "$co/people/Ada Admin.md" << 'EOF'
---
slug: ada
github: acme-admin
role: admin
left: ""
---
# Ada Admin
EOF
cat > "$co/people/Sam Member.md" << 'EOF'
---
slug: sam
github: acme-member-d
role: writer
left: ""
manager: ada
---
# Sam Member
EOF
git -C "$co" init -q -b main
git -C "$co" add -A
git -C "$co" commit -q -m seed
git init -q --bare "$work/origin.git"
git -C "$co" remote add origin "$work/origin.git"
git -C "$co" push -q origin main
mkdir -p "$co/meetings" "$co/inbox"
printf '%s\n' "kickoff notes" > "$co/meetings/2026-10-28 Kickoff.md"
printf '%s\n' "held by sync: a private note" > "$co/inbox/held.md"
cat > "$work/bin/host.sh" << 'EOF'
#!/bin/bash
case "$1" in
  user-access) printf '%s\n' '{"access":"none"}' ;;
  open-pr) printf '%s\n' '{"number":4,"url":"http://example.test/4"}' ;;
  get-token) printf '%s\n' local-token ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF
chmod 700 "$work/bin/host.sh"
set +e
OS_HOST_SH="$work/bin/host.sh" "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person sam \
  --date 2026-10-28 > "$work/rm.out" 2> "$work/rm.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/rm.out" "$work/rm.err" >&2; team_fail "remove exit $rc"; }
files=$(git --git-dir "$work/origin.git" diff --name-only main rules/ada/offboard-sam)
[ "$files" = "people/Sam Member.md" ] || team_fail "offboard branch has: $files"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "remove left the folder off main"
[ -f "$co/meetings/2026-10-28 Kickoff.md" ] || team_fail "untracked meeting note is gone"
[ -f "$co/inbox/held.md" ] || team_fail "held file is gone"
[ -z "$(git -C "$co" ls-files meetings inbox)" ] || team_fail "untracked files were committed"

# join.sh: the terms pull request gets auto-merge, and the folder is back on main.
mkdir -p "$co/users/sam" "$work/home/.claude"
git -C "$co/users/sam" init -q -b main
printf '%s\n' "areas=" > "$work/join-answers"
cat > "$work/bin/host.sh" << EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$work/host.log"
case "\$1" in
  open-pr) printf '%s\n' '{"number":7,"url":"http://example.test/7"}' ;;
  auto-merge) [ -z "\${FAKE_NO_AUTOMERGE:-}" ] || exit 1; printf '%s\n' '{"ok":true}' ;;
  get-token) printf '%s\n' local-token ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF
join_run() {
  HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE=true OS_HOST_SH="$work/bin/host.sh" \
    "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" 2>"$work/join.err" \
    || { cat "$work/join.err" >&2; team_fail "join exit $?"; }
}
printf '%s\n' "root=$co" "me=sam" >> "$work/join-answers"
: > "$work/host.log"
join_run > "$work/join.out"
grep -qx 'terms: proposed' "$work/join.out" || team_fail "join did not propose terms"
grep -qx 'auto-merge: on' "$work/join.out" || team_fail "join did not report auto-merge"
grep -qx 'auto-merge acme-os 7' "$work/host.log" || team_fail "join did not call auto-merge: $(cat "$work/host.log")"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "join left the folder off main"
git --git-dir "$work/origin.git" show "sync/sam:people/Sam Member.md" | grep -q '^terms_accepted: ' \
  || team_fail "terms date is not on sync/sam"

# A refused auto-merge is one plain line, not a failure.
git --git-dir "$work/origin.git" branch -q -D sync/sam
git -C "$co" branch -q -D sync/sam
git -C "$co" update-ref -d refs/remotes/origin/sync/sam
FAKE_NO_AUTOMERGE=1 join_run > "$work/join2.out"
grep -q '^auto-merge is off on acme-os: pull request 7 stays open' "$work/join2.out" \
  || team_fail "join did not say auto-merge is off"

# Round 3 (30): a v0 clone that pulled the upgrade. main tracks memory/logs/ while
# memory/logs is still a worktree of branch logs. join moves it out and keeps every log.
mkdir -p "$co/memory/logs"
printf '%s\n' "day one" > "$co/memory/logs/2026-10-01-sam.md"
git -C "$co" add memory/logs
git -C "$co" commit -q -m "Upgrade to v1"
git -C "$co" push -q origin main
git -C "$co" worktree add -q --detach "$work/lw"
git -C "$work/lw" checkout -q --orphan logs
git -C "$work/lw" rm -rfq .
printf '%s\n' "day one" > "$work/lw/2026-10-01-sam.md"
git -C "$work/lw" add 2026-10-01-sam.md
git -C "$work/lw" commit -q -m "Logs: day one"
git -C "$co" worktree remove "$work/lw"
git -C "$co" push -q origin logs
rm -rf "$co/memory/logs"
git -C "$co" worktree add -q "$co/memory/logs" logs
printf '%s\n' "day four, not committed" > "$co/memory/logs/2026-10-04-sam.md"
join_run > "$work/join3.out"
grep -qx 'v0-logs: moved, 1 files kept as local changes' "$work/join3.out" || team_fail "join did not move the v0 logs worktree"
[ ! -e "$co/memory/logs/.git" ] || team_fail "the logs worktree is still there"
[ "$(cat "$co/memory/logs/2026-10-04-sam.md")" = "day four, not committed" ] || team_fail "join lost an untracked log"
git -C "$co" diff --quiet -- memory/logs/2026-10-01-sam.md || team_fail "the tracked log changed"

printf '%s\n' "PASS stage"
