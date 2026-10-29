#!/bin/bash
# B15: scripts that commit in a shared folder stage only the paths they changed.
# B14: they leave the folder on main after pushing their branch.
# B18: join turns on auto-merge for the terms pull request.
# Round 3 (37): a refused checkout back to main never stops the run before open-pr, and a
# retry still opens the pull request.
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
# The lib sets its own EXIT trap. Run both.
trap 'rm -rf "$work"; os_cleanup' EXIT
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
terms_accepted: ""
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
# Round 3 (42): the person running remove sees the page marked left, as a local change on
# main. main itself gets it only by the offboard pull request.
grep -qx 'left: 2026-10-28' "$co/people/Sam Member.md" || team_fail "remove: the local page is not marked left"
git -C "$co" show "main:people/Sam Member.md" | grep -q '^left: 2026' && team_fail "remove committed to main"

# A git that refuses the checkout back to main, like a local change in the way would.
mkdir -p "$work/shim"
real_git=$(command -v git)
cat > "$work/shim/git" << EOF
#!/bin/bash
if [ -n "\${FAKE_REFUSE_WTREMOVE:-}" ]; then
  case " \$* " in
    *" worktree remove "*) printf '%s\n' "error: could not remove a file (locked)" >&2; exit 1 ;;
  esac
fi
if [ -n "\${FAKE_REFUSE_FETCH:-}" ]; then
  case " \$* " in
    *" fetch "*) printf '%s\n' "fatal: unable to access the host" >&2; exit 1 ;;
  esac
fi
if [ -n "\${FAKE_REFUSE_PUSH:-}" ]; then
  case " \$* " in
    *" push -q origin HEAD:refs/heads/sync/"*)
      printf '%s\n' "error: failed to push some refs" >&2
      exit 1 ;;
  esac
fi
if [ -n "\${FAKE_REFUSE_MAIN:-}" ]; then
  case " \$* " in
    *" checkout -q main "*|*" checkout -q -b main origin/main "*)
      printf '%s\n' "error: Your local changes would be overwritten by checkout" >&2
      exit 1 ;;
  esac
fi
exec "$real_git" "\$@"
EOF
chmod 700 "$work/shim/git"

# remove.sh: the refused checkout still opens the pull request. A retry replaces the
# branch and opens it again.
for try in 1 2; do
  set +e
  PATH="$work/shim:$PATH" FAKE_REFUSE_MAIN=$([ "$try" -eq 1 ] && printf 1) OS_HOST_SH="$work/bin/host.sh" \
    "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person sam \
    --date 2026-10-28 > "$work/rm$try.out" 2> "$work/rm$try.err"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { cat "$work/rm$try.out" "$work/rm$try.err" >&2; team_fail "remove try $try exit $rc"; }
  grep -qx 'pr: 4' "$work/rm$try.out" || team_fail "remove try $try opened no pull request"
done
grep -q '^main: could not go back to main' "$work/rm1.err" || team_fail "remove did not say it stayed off main"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "remove retry left the folder off main"

# add-person.sh: the same.
cat > "$work/add-answers" << EOF
root=$co
person.bo.name=Bo Baker
person.bo.github=acme-member-b
person.bo.role=writer
EOF
for try in 1 2; do
  set +e
  PATH="$work/shim:$PATH" FAKE_REFUSE_MAIN=$([ "$try" -eq 1 ] && printf 1) OS_HOST_SH="$work/bin/host.sh" \
    "$root/template/skills/add-teammate/add-person.sh" --answers "$work/add-answers" \
    > "$work/add$try.out" 2> "$work/add$try.err"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { cat "$work/add$try.out" "$work/add$try.err" >&2; team_fail "add-person try $try exit $rc"; }
done
grep -q '^main: could not go back to main' "$work/add1.err" || team_fail "add-person did not say it stayed off main"
git --git-dir "$work/origin.git" show "rules/ada/add-bo:people/Bo Baker.md" >/dev/null 2>&1 \
  || team_fail "add-person branch has no page"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "add-person retry left the folder off main"
rm -rf "$co/users/bo"

# join.sh: the terms pull request gets auto-merge, and the folder is back on main.
mkdir -p "$co/users/sam" "$work/home/.claude"
git -C "$co/users/sam" init -q -b main
printf '%s\n' "areas=" > "$work/join-answers"
cat > "$work/bin/host.sh" << EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$work/host.log"
case "\$1" in
  open-pr) [ -z "\${FAKE_NO_OPENPR:-}" ] || exit 5; printf '%s\n' '{"number":7,"url":"http://example.test/7"}' ;;
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
# logsfix (54): the dated page is also a local change on main, so the next push keeps it.
grep -Eq '^terms_accepted: [0-9]{4}-' "$co/people/Sam Member.md" || team_fail "the local page is not dated"
git -C "$co" show-ref --verify --quiet refs/heads/sync/sam && team_fail "join made a local sync/sam (55: temp worktree only)"

# A refused auto-merge is one plain line, not a failure.
git --git-dir "$work/origin.git" branch -q -D sync/sam
git -C "$co" update-ref -d refs/remotes/origin/sync/sam
FAKE_NO_AUTOMERGE=1 join_run > "$work/join2.out"
grep -q '^auto-merge is off on acme-os: pull request 7 stays open' "$work/join2.out" \
  || team_fail "join did not say auto-merge is off"

# Round 3 (37): the checkout back to main is refused after the terms push. The run still
# opens the pull request. A retry (terms on origin/sync/sam, not on main, and the clone
# still on sync/sam) opens it again and goes back to main. Since logsfix (55) join never
# leaves main itself; a clone an older join left on sync/sam is the case here.
git --git-dir "$work/origin.git" branch -q -D sync/sam
git -C "$co" update-ref -d refs/remotes/origin/sync/sam
git -C "$co" checkout -q -b sync/sam
: > "$work/host.log"
PATH="$work/shim:$PATH" FAKE_REFUSE_MAIN=1 join_run > "$work/join4.out"
grep -qx 'terms: proposed' "$work/join4.out" || team_fail "refused checkout: no terms"
grep -qx 'pr: 7' "$work/join4.out" || team_fail "refused checkout: no pull request"
grep -q '^main: could not go back to main' "$work/join.err" || team_fail "join did not say it stayed off main"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "sync/sam" ] || team_fail "the shim did not refuse"
: > "$work/host.log"
join_run > "$work/join5.out"
grep -qx 'terms: already' "$work/join5.out" || team_fail "retry did not see the pending terms"
grep -q '^open-pr acme-os --head sync/sam ' "$work/host.log" || team_fail "retry did not open the pull request"
grep -qx 'pr: 7' "$work/join5.out" || team_fail "retry printed no pull request"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "retry left the folder off main"

# Round 4 (43): a join that stopped after the terms commit, or after the push, opens the
# pull request on the next run.
reset_sync_sam() {
  git --git-dir "$work/origin.git" branch -q -D sync/sam
  git -C "$co" checkout -q main 2>/dev/null || true
  git -C "$co" branch -q -D sync/sam 2>/dev/null || true
  git -C "$co" update-ref -d refs/remotes/origin/sync/sam
}
join_try() {
  HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE=true OS_HOST_SH="$work/bin/host.sh" \
    "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" 2>"$work/join.err"
}
# The terms push fails: nothing is on the host. The retry proposes again and opens it.
reset_sync_sam
if PATH="$work/shim:$PATH" FAKE_REFUSE_PUSH=1 join_try > "$work/join6.out"; then
  team_fail "join with a refused terms push exited 0"
fi
git --git-dir "$work/origin.git" rev-parse --verify --quiet refs/heads/sync/sam >/dev/null && team_fail "the shim did not refuse the push"
: > "$work/host.log"
join_try > "$work/join7.out" || { cat "$work/join.err" >&2; team_fail "retry after a refused push failed"; }
grep -qx 'terms: proposed' "$work/join7.out" || team_fail "retry after a refused push did not propose"
grep -qx 'pr: 7' "$work/join7.out" || team_fail "retry after a refused push opened no pull request"
git --git-dir "$work/origin.git" show "sync/sam:people/Sam Member.md" | grep -Eq '^terms_accepted: [0-9]{4}-' \
  || team_fail "retry did not push the terms"
# open-pr fails after the push: the terms are on origin/sync/sam only. The retry opens it.
reset_sync_sam
if FAKE_NO_OPENPR=1 join_try > "$work/join8.out"; then
  team_fail "join with a failed open-pr exited 0"
fi
grep -q '^pr: ' "$work/join8.out" && team_fail "a failed open-pr printed a pull request"
# Round 5 (50): offline, with a dated page in the folder (since logsfix 54, on main too).
# join must not guess "already": it stops with exit 3 and one line, and opens nothing.
grep -Eq '^terms_accepted: [0-9]{4}-' "$co/people/Sam Member.md" || team_fail "the folder page is not dated"
: > "$work/host.log"
rc=0
PATH="$work/shim:$PATH" FAKE_REFUSE_FETCH=1 join_try > "$work/join-off.out" || rc=$?
[ "$rc" -eq 3 ] || { cat "$work/join.err" >&2; team_fail "offline join exit was $rc, not 3"; }
grep -qx 'could not reach the host: run join again when online; the terms pull request may not be open yet' "$work/join.err" \
  || { cat "$work/join.err" >&2; team_fail "offline join line"; }
grep -q 'terms: already' "$work/join-off.out" && team_fail "offline join said terms: already"
grep -q 'join: ok' "$work/join-off.out" && team_fail "offline join said ok"
grep -q '^open-pr ' "$work/host.log" && team_fail "offline join called open-pr"
: > "$work/host.log"
join_try > "$work/join9.out" || { cat "$work/join.err" >&2; team_fail "retry after a failed open-pr failed"; }
grep -qx 'terms: already' "$work/join9.out" || team_fail "retry after open-pr did not see the pushed terms"
grep -q '^open-pr acme-os --head sync/sam ' "$work/host.log" || team_fail "retry after a failed open-pr did not open it"
grep -qx 'auto-merge acme-os 7' "$work/host.log" || team_fail "retry after a failed open-pr did not turn on auto-merge"

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
# Round 4 (48): the worktree remove stops. join says so and names the full copy.
if PATH="$work/shim:$PATH" FAKE_REFUSE_WTREMOVE=1 join_try > "$work/join-wt.out"; then
  team_fail "join with a failed worktree remove exited 0"
fi
grep -q 'could not remove the logs worktree, and some files may be gone from memory/logs. A full copy is in ' "$work/join.err" \
  || { cat "$work/join.err" >&2; team_fail "join did not name the copy"; }
grep -q 'Nothing was removed' "$work/join.err" && team_fail "join said nothing was removed after a partial remove"
wt_save=$(sed -n 's/.*A full copy is in \([^ ]*\)\. Keep that folder.*/\1/p' "$work/join.err" | head -n 1)
[ -f "$wt_save/2026-10-04-sam.md" ] || team_fail "the named copy has no day-four log"
rm -rf "$wt_save"
join_run > "$work/join3.out"
grep -qx 'v0-logs: moved, 1 files kept as local changes' "$work/join3.out" || team_fail "join did not move the v0 logs worktree"
[ ! -e "$co/memory/logs/.git" ] || team_fail "the logs worktree is still there"
[ "$(cat "$co/memory/logs/2026-10-04-sam.md")" = "day four, not committed" ] || team_fail "join lost an untracked log"
git -C "$co" diff --quiet -- memory/logs/2026-10-01-sam.md || team_fail "the tracked log changed"

printf '%s\n' "PASS stage"
