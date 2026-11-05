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
# Join stops without the joining terms (B81).
printf '%s\n' "# Joining terms — Acme Co" > "$co/joining-terms.md"
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
# As the template's: each person's workspace and each area is its own repo.
printf '%s\n' "/areas/" "/users/" > "$co/.gitignore"
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
[ -z "${FAKE_LOG:-}" ] || printf '%s\n' "$*" >> "$FAKE_LOG"
case "$1" in
  auto-merge)
    # B45: FAKE_MERGED, the checks were green and it merged; FAKE_GREEN, that merge failed.
    if [ -n "${FAKE_MERGED:-}" ]; then printf '%s\n' '{"ok":true,"merge":"merged"}'; exit 0; fi
    if [ -n "${FAKE_GREEN:-}" ]; then printf '%s\n' "pull request 4 is green: merge it" >&2; exit 3; fi
    printf '%s\n' '{"ok":true}' ;;
  user-access) printf '%s\n' '{"access":"none"}' ;;
  org-membership) printf '%s\n' '{"state":"none"}' ;;
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
# The folder stays as main has it: the page is marked left only on the offboard branch,
# so the admin's next sync push cannot carry it past its own review.
git --git-dir "$work/origin.git" show "rules/ada/offboard-sam:people/Sam Member.md" | grep -qx 'left: 2026-10-28' \
  || team_fail "remove: the offboard branch does not mark the page left"
grep -qx 'left: 2026-10-28' "$co/people/Sam Member.md" && team_fail "remove: the folder page changed before the pull request merged"
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
    *" push -q origin HEAD:refs/heads/sync/"*|*" push origin HEAD:refs/heads/sync/"*)
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
# B37: the people-page pull request merges by itself, like join's.
grep -qx 'auto-merge: on' "$work/add2.out" || team_fail "B37: add-person did not turn on auto-merge"
# B45: auto-merge is asked for before the workspace. A green pull request merges at once,
# and a merge that fails says so, never "protection".
: > "$work/b45.log"
FAKE_LOG="$work/b45.log" FAKE_MERGED=1 OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/add-person.sh" --answers "$work/add-answers" > "$work/add3.out" 2> "$work/add3.err" \
  || { cat "$work/add3.out" "$work/add3.err" >&2; team_fail "B45: add-person exit"; }
first_am=$(grep -n '^auto-merge ' "$work/b45.log" | head -n 1 | cut -d: -f1)
first_ws=$(grep -n '^create-repo ' "$work/b45.log" | head -n 1 | cut -d: -f1)
[ -n "$first_am" ] && [ -n "$first_ws" ] && [ "$first_am" -lt "$first_ws" ] || team_fail "B45: auto-merge came after the workspace"
grep -qx 'merged: acme-os 4 (its checks were already green)' "$work/add3.out" || team_fail "B45: no merged line: $(cat "$work/add3.out")"
FAKE_GREEN=1 OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/add-person.sh" --answers "$work/add-answers" > "$work/add4.out" 2> "$work/add4.err" \
  || { cat "$work/add4.out" "$work/add4.err" >&2; team_fail "B45: add-person exit"; }
grep -qx 'pull request 4 is green: merge it' "$work/add4.out" || team_fail "B45: no green line: $(cat "$work/add4.out")"
grep -q 'protect' "$work/add4.out" && team_fail "B45: blamed protection for a green pull request"
git --git-dir "$work/origin.git" show "rules/ada/add-bo:people/Bo Baker.md" >/dev/null 2>&1 \
  || team_fail "add-person branch has no page"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "add-person retry left the folder off main"
rm -rf "$co/users/bo"

# B47: after a sync push, the admin's note sits untracked here while origin/main has it.
# add-person and remove build their branch in a temporary worktree, so git never stops.
note="meetings/2026-10-31 Kickoff.md"
trees=$(git -C "$co" worktree list --porcelain | grep -c '^worktree ')
main_was=$(git --git-dir "$work/origin.git" rev-parse main)
git clone -q -b main "$work/origin.git" "$work/b47"
mkdir -p "$work/b47/meetings" "$co/meetings"
printf '%s\n' "a note from sync" > "$work/b47/$note"
git -C "$work/b47" add -A
git -C "$work/b47" -c user.name=t -c user.email=t@example.test commit -q -m note
git -C "$work/b47" push -q origin HEAD:main
printf '%s\n' "a note from sync" > "$co/$note"
OS_HOST_SH="$work/bin/host.sh" "$root/template/skills/add-teammate/add-person.sh" --answers "$work/add-answers" \
  > "$work/b47.out" 2> "$work/b47.err" || { cat "$work/b47.out" "$work/b47.err" >&2; team_fail "B47: add-person stopped on an untracked note"; }
grep -q 'would be overwritten' "$work/b47.err" && team_fail "B47: raw git error"
git --git-dir "$work/origin.git" show "rules/ada/add-bo:$note" >/dev/null 2>&1 || team_fail "B47: branch not built on origin/main"
OS_HOST_SH="$work/bin/host.sh" "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person sam \
  --date 2026-10-28 > "$work/b47rm.out" 2> "$work/b47rm.err" \
  || { cat "$work/b47rm.out" "$work/b47rm.err" >&2; team_fail "B47: remove stopped on an untracked note"; }
[ "$(cat "$co/$note")" = "a note from sync" ] || team_fail "B47: the note changed"
[ "$(git -C "$co" worktree list --porcelain | grep -c '^worktree ')" -eq "$trees" ] || team_fail "B47: a worktree was left"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "B47: the folder left main"
rm -rf "$co/users/bo" "$co/meetings" "$work/b47"
# Later steps push this folder's main: put the host's main back.
git --git-dir "$work/origin.git" update-ref refs/heads/main "$main_was"
git -C "$co" fetch -q origin

# join.sh: the terms are a commit on main with this computer's Sync-Seat line, and sync push
# sends them to sync/<me>/<seat> with a pull request that gets auto-merge.
mkdir -p "$co/users/sam" "$work/home/.claude"
git -C "$co/users/sam" init -q -b main
printf '%s\n' "areas=" > "$work/join-answers"
cat > "$work/bin/host.sh" << EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$work/host.log"
case "\$1" in
  open-pr)
    [ -z "\${FAKE_NO_OPENPR:-}" ] || exit 5
    while [ \$# -gt 0 ]; do
      [ "\$1" = "--body-file" ] && cp "\$2" "$work/join-body.txt"
      shift
    done
    printf '%s\n' '{"number":7,"url":"http://example.test/7"}' ;;
  auto-merge) [ -z "\${FAKE_NO_AUTOMERGE:-}" ] || exit 1; printf '%s\n' '{"ok":true}' ;;
  get-token) printf '%s\n' local-token ;;
  whoami) printf '%s\n' '{"login":"acme-member-d"}' ;;
  open-prs) printf '%s\n' '[]' ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF
join_run() {
  HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="$root/tests/fakes/engine.sh" OS_HOST_SH="$work/bin/host.sh" \
    "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" 2>"$work/join.err" \
    || { cat "$work/join.err" >&2; team_fail "join exit $?"; }
}
printf '%s\n' "root=$co" "me=sam" >> "$work/join-answers"
: > "$work/host.log"
join_run > "$work/join.out"
grep -qx 'terms: proposed' "$work/join.out" || team_fail "join did not propose terms"
seat=$(tr -d '[:space:]' < "$work/home/.config/acme-os/seat")
[ -n "$seat" ] || team_fail "join made no seat id"
grep -q "^open-pr origin --head sync/sam/$seat --base main " "$work/host.log" \
  || team_fail "join did not open the seat pull request: $(cat "$work/host.log")"
grep -qx 'auto-merge origin 7' "$work/host.log" || team_fail "join did not call auto-merge: $(cat "$work/host.log")"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "join left the folder off main"
git --git-dir "$work/origin.git" show "sync/sam/$seat:people/Sam Member.md" | grep -q '^terms_accepted: ' \
  || team_fail "terms date is not on sync/sam/$seat"
git --git-dir "$work/origin.git" log -1 --format=%B "sync/sam/$seat" | grep -qx "Sync-Seat: $seat" \
  || team_fail "the terms commit has no Sync-Seat line"
[ "$(git -C "$co" rev-parse HEAD)" = "$(git --git-dir "$work/origin.git" rev-parse "sync/sam/$seat")" ] \
  || team_fail "the folder's main is not what went up"
git -C "$co" show-ref --verify --quiet refs/heads/sync/sam && team_fail "join made a local sync branch"

# B63 to B65, B69 and Grok r6: an old v0 copy, renamed beside the folder after it was
# made, the way section 11 says: it was built at this folder's path, with a "git worktree
# add" logs folder (git writes an absolute link), then renamed, and the new clone took
# the name. So memory/logs/.git in the old folder names this folder's .git. join brings
# each item the host lacks here itself: a new file or a log is copied, and a change to a
# file the host has is set aside for re-apply, so newer lines on main stay (B69). It
# never changes or deletes the old folder.
old="$work/co-old"
st_was_main=$(git --git-dir "$work/origin.git" rev-parse main)
st_was_head=$(git -C "$co" rev-parse HEAD)
st_was_seat=$(git --git-dir "$work/origin.git" rev-parse "sync/sam/$seat")
# A plan file on main that the old folder will change.
mkdir -p "$co/notes"
printf '%s\n' "# Plan" "- base line" > "$co/notes/plan.md"
printf '%s\n' "# Terms" "- base terms" > "$co/notes/terms.md"
git -C "$co" add notes/plan.md notes/terms.md
git -C "$co" -c user.name=t -c user.email=t@example.test commit -q -m plan
git -C "$co" push -q origin HEAD:main
mv "$co" "$work/co-new"
git clone -q -b main "$work/origin.git" "$co"
git -C "$co" remote set-url origin https://github.com/acme/acme-os.git
git -C "$co" config user.email sam@acme.test
git -C "$co" config user.name "Sam Member"
# The v0 logs branch, pushed once (the old copy's origin/logs), then a logs worktree.
git -C "$co" checkout -q --orphan logs
git -C "$co" rm -rq --cached .
git -C "$co" clean -fdqx
printf '%s\n' "day one" > "$co/2026-10-01-sam.md"
git -C "$co" add 2026-10-01-sam.md
git -C "$co" commit -q -m "Log: day one"
git -C "$co" update-ref refs/remotes/origin/logs HEAD
git -C "$co" checkout -q main
git -C "$co" worktree add -q "$co/memory/logs" logs
printf '%s\n' "/memory/logs/" >> "$co/.git/info/exclude"
# A log committed on the logs branch and never pushed, one never committed, and one
# renamed with git mv (Grok r6: the new path is listed).
printf '%s\n' "day two" > "$co/memory/logs/2026-10-31-sam.md"
git -C "$co/memory/logs" add 2026-10-31-sam.md
git -C "$co/memory/logs" commit -q -m "Log: sam"
printf '%s\n' "not saved" > "$co/memory/logs/2026-11-01-sam.md"
git -C "$co/memory/logs" mv 2026-10-01-sam.md 2026-10-01-sam-renamed.md
# A side branch with a commit the host never got (listed once, under the company).
git -C "$co" checkout -q -b price
printf '%s\n' "prices" > "$co/prices.md"
printf '%s\n' "- price: side terms" >> "$co/notes/terms.md"
git -C "$co" add prices.md notes/terms.md
git -C "$co" commit -q -m "Pat: draft price list"
git -C "$co" checkout -q main
printf '%s\n' "never pushed" > "$co/draft.md"
printf '%s\n' "- sam: from the old folder" >> "$co/notes/plan.md"
cp "$work/co-new/people/Ada Admin.md" "$co/people/same.md"
cp "$work/co-new/people/Ada Admin.md" "$work/co-new/people/same.md"
printf '%s\n' "a local commit" > "$co/notes/local.md"
git -C "$co" add notes/local.md
git -C "$co" commit -q -m "Local note"
mkdir -p "$co/areas/lab"
git -C "$co/areas/lab" init -q -b main
git -C "$co/areas/lab" remote add origin https://github.com/acme/acme-lab.git
printf '%s\n' "lab" > "$co/areas/lab/lab.md"
git -C "$co/areas/lab" add lab.md
git -C "$co/areas/lab" -c user.email=s@acme.test -c user.name=Sam commit -q -m "Lab note"
# The rename, then the new folder takes the usual name. Main moves on after the old copy
# was made: a colleague adds a line to the same plan file.
mv "$co" "$old"
mv "$work/co-new" "$co"
printf '%s\n' "- ada: newer on main" >> "$co/notes/plan.md"
git -C "$co" -c user.name=t -c user.email=t@example.test commit -q -am "newer plan line"
git -C "$co" push -q origin HEAD:main
# The new folder has joined the area too; a fresh v1 area has no memory/logs/ yet.
mkdir -p "$co/areas/lab"
git -C "$co/areas/lab" init -q -b main
git -C "$co/areas/lab" remote add origin https://github.com/acme/acme-lab.git
git -C "$old/memory/logs" status >/dev/null 2>&1 && team_fail "B64 setup: the old logs link still works after the rename"
old_snap() {
  (cd "$old" && git status --porcelain && git rev-parse HEAD && git for-each-ref \
    && find . -type f -print0 | sort -z | xargs -0 cksum)
}
old_state=$(old_snap)
join_run > "$work/old.out"
cp_line() { grep -qx "old-folder: $1 copied to $2: sync sends it." "$work/old.out" || { cat "$work/old.out" >&2; team_fail "$3"; }; }
cp_line "$old/draft.md" draft.md "B63: join did not copy the untracked file"
cp_line "$old branch price (last commit [0-9a-f]* \"Pat: draft price list\"): prices.md" prices.md "B65: join did not bring the side-branch file"
cp_line "$old/notes/local.md" notes/local.md "B63: join did not bring the local commit's file"
cp_line "$old/areas/lab/lab.md" areas/lab/lab.md "B63: join did not bring the area commit's file"
cp_line "$old/memory/logs/2026-11-01-sam.md" memory/logs/2026-11-01-sam.md "B64: join did not copy the unsaved log"
cp_line "$old/memory/logs/2026-10-31-sam.md" memory/logs/2026-10-31-sam.md "B64: join did not copy the unpushed log commit's log"
cp_line "$old/memory/logs/2026-10-01-sam-renamed.md" memory/logs/2026-10-01-sam-renamed.md "Grok r6: join did not list a renamed log"
[ "$(cat "$co/prices.md")" = "prices" ] || team_fail "item 3: prices.md has the wrong text"
[ "$(cat "$co/memory/logs/2026-10-31-sam.md")" = "day two" ] || team_fail "item 3: the log has the wrong text"
[ "$(cat "$co/areas/lab/lab.md")" = "lab" ] || team_fail "item 3: lab.md has the wrong text"
# B69: the changed tracked file is set aside, never copied over main's newer line.
grep -qx "old-folder: $old/notes/plan.md is set aside for notes/plan.md: the agent re-applies the change to the host's current text (skills/sync/sync.sh re-apply list). Nothing to copy." "$work/old.out" \
  || { cat "$work/old.out" >&2; team_fail "B69: join did not set the changed file aside"; }
grep -qx -- "- ada: newer on main" "$co/notes/plan.md" || team_fail "B69: join changed main's text"
grep -q 'sam: from the old folder' "$co/notes/plan.md" && team_fail "B69: join copied the old file over main"
grep -q "^old-folder: $old branch price (last commit [0-9a-f]* \"Pat: draft price list\"): notes/terms.md is set aside for notes/terms.md: " "$work/old.out" \
  || team_fail "B69: the side-branch change to a file main has is not set aside"
grep -q "same.md" "$work/old.out" && team_fail "B63: join listed a file the folder has with the same text"
grep -q '^old-folder:.*push' "$work/old.out" && team_fail "B65: join printed a push command"
grep -q 'Copy it into\|Copy the logs' "$work/old.out" && team_fail "item 3: join asked the person to copy"
grep -qx "old-folder: $old held 9 items the host lacks (listed above). join copied them here or set them aside for the agent. Nothing was deleted. Delete the old folder only after the agent has re-applied what was set aside and sync has sent it to the host." "$work/old.out" \
  || { cat "$work/old.out" >&2; team_fail "B63: join did not sum up the old folder"; }
[ "$old_state" = "$(old_snap)" ] || team_fail "B63: join changed the old folder"
[ ! -e "$co/.git/worktrees" ] || team_fail "B64: join wrote a worktree into the new folder"
grep -q 'join: ok' "$work/old.out" || team_fail "B63: join did not finish"
# B69: the agent re-applies on the host's text; both lines go up.
st_sync() {
  HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="$root/tests/fakes/engine.sh" OS_HOST_SH="$work/bin/host.sh" \
    OS_PROFILE_SH="$root/template/skills/_host/profile.sh" OS_COMPANY_ROOT="$co" bash "$root/template/skills/sync/sync.sh" "$@"
}
st_sync re-apply list > "$work/reapply.out"
grep -qx -- "- root notes/plan.md" "$work/reapply.out" || { cat "$work/reapply.out" >&2; team_fail "B69: no re-apply hold"; }
base=$(jq -r '.files[] | select(.path == "notes/plan.md") | .basefile' "$work/home/.config/acme-os/state/held.json")
mine=$(jq -r '.files[] | select(.path == "notes/plan.md") | .mine' "$work/home/.config/acme-os/state/held.json")
[ "$(cat "$base")" = "$(printf '%s\n' "# Plan" "- base line")" ] || team_fail "B69: the base is not the old folder's HEAD text"
grep -qx -- "- sam: from the old folder" "$mine" || team_fail "B69: the set-aside copy is not the person's text"
# The side branch's file: its base is the text where the branch left main.
held=$(jq -r '.files[] | select(.path == "notes/terms.md") | "\(.basefile) \(.mine)"' "$work/home/.config/acme-os/state/held.json")
[ "$(cat "${held% *}")" = "$(printf '%s\n' "# Terms" "- base terms")" ] || team_fail "B69: the side-branch base is not the merge-base text"
grep -qx -- "- price: side terms" "${held#* }" || team_fail "B69: the side-branch copy is not the branch's text"
printf '%s\n' "- sam: from the old folder" >> "$co/notes/plan.md"
st_sync re-apply "done" root notes/plan.md >/dev/null || team_fail "B69: re-apply done failed"
# The new folder's lab area has no host here: keep it out of this push.
mv "$co/areas/lab" "$work/lab-aside"
st_sync push > "$work/st-push.out" 2>&1 || { cat "$work/st-push.out" >&2; team_fail "B69: push after re-apply failed"; }
mv "$work/lab-aside" "$co/areas/lab"
up=$(git --git-dir "$work/origin.git" show "sync/sam/$seat:notes/plan.md")
grep -qx -- "- ada: newer on main" <<< "$up" || team_fail "B69: main's newer line is not on the host: $up"
grep -qx -- "- sam: from the old folder" <<< "$up" || team_fail "B69: the person's line is not on the host: $up"
# A second join: what was copied or re-applied is not brought again; an open hold says so.
join_run > "$work/old4.out"
grep -q "^old-folder: $old branch price .*: notes/terms.md is already set aside for notes/terms.md: the agent re-applies it" "$work/old4.out" \
  || { cat "$work/old4.out" >&2; team_fail "B69: a second join did not name the open hold"; }
grep -q "^old-folder: $old held 1 item the host lacks (listed above). join copied it here or set it aside" "$work/old4.out" || { cat "$work/old4.out" >&2; team_fail "B69: a second join brought something again"; }
st_sync re-apply "done" root notes/terms.md >/dev/null || team_fail "B69: re-apply done failed for terms"
join_run > "$work/old4.out"
grep -qx "old-folder: $old has nothing the host lacks. You may delete it." "$work/old4.out" \
  || { cat "$work/old4.out" >&2; team_fail "B69: a third join brought something again"; }
# B64: logs git cannot open: never "You may delete it", and no "holds 0 items" (low).
mv "$old/.git/worktrees/logs" "$work/wt-logs-aside"
join_run > "$work/old3.out"
grep -qx "old-folder: $old/memory/logs could not be checked (git cannot open it). Copy each log in it that memory/logs/ does not have into memory/logs/ by hand before deleting the old folder." "$work/old3.out" \
  || { cat "$work/old3.out" >&2; team_fail "B64: no could-not-check line for the logs"; }
grep -q 'You may delete it' "$work/old3.out" && team_fail "B64: said the old folder may go with its logs unchecked"
grep -qx "old-folder: $old: some of it could not be checked (listed above). Check that part by hand. Nothing was deleted. Do not delete it yet." "$work/old3.out" \
  || { cat "$work/old3.out" >&2; team_fail "low: the could-not-check summary"; }
mv "$work/wt-logs-aside" "$old/.git/worktrees/logs"
# Grok r6 stash: a stash is listed, and never "You may delete it".
printf '%s\n' "stashed edit" >> "$old/notes/local.md"
git -C "$old" stash -q
join_run > "$work/old5.out"
grep -q "^old-folder: $old has 1 stashed changes the host lacks" "$work/old5.out" || { cat "$work/old5.out" >&2; team_fail "Grok r6: the stash is not listed"; }
[ "$(grep -c 'stashed changes the host lacks' "$work/old5.out")" = "1" ] || team_fail "Grok r6: the shared stash is listed more than once"
grep -q 'You may delete it' "$work/old5.out" && team_fail "Grok r6: said the old folder may go with a stash in it"
# r8, B71: the closing line says the stash is only in the old folder, and the old folder
# goes only after each stash is redone. Never "join copied them" for a stash alone (low).
grep -qx "old-folder: $old has nothing else the host lacks, only the stash listed above. Its stashed changes are still only in the old folder: redo each one here first (git -C $old stash show -p). Nothing was deleted. Delete the old folder only after each stash is redone here." "$work/old5.out" \
  || { cat "$work/old5.out" >&2; team_fail "r8: the closing line does not keep the stash"; }
grep -q 'Delete the old folder only after the agent' "$work/old5.out" && team_fail "r8: the closing line allows a delete with a stash in the old folder"
grep -q 'join copied them' "$work/old5.out" && team_fail "r8 low: said join copied a stash"
# B71: sync status names the stash while the old folder has it, then stops once it is gone.
grep -qx "$old/.git	$old" "$work/home/.config/acme-os/state/old-stash" || team_fail "B71: join did not note the stash"
st_status=$(HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_COMPANY_ROOT="$co" OS_HOST_SH="$work/bin/host.sh" \
  OS_PROFILE_SH="$root/template/skills/_host/profile.sh" bash "$root/template/skills/sync/sync.sh" status 2>&1 || true)
grep -qx "old folder: $old still has stashed changes that are only there. Redo each one here first (git -C $old stash show -p). Do not delete the old folder until then." <<< "$st_status" \
  || { printf '%s\n' "$st_status" >&2; team_fail "B71: status does not name the stash"; }
git -C "$old" stash drop -q
st_status=$(HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_COMPANY_ROOT="$co" OS_HOST_SH="$work/bin/host.sh" \
  OS_PROFILE_SH="$root/template/skills/_host/profile.sh" bash "$root/template/skills/sync/sync.sh" status 2>&1 || true)
grep -q "still has stashed changes" <<< "$st_status" && team_fail "B71: status names a stash that was dropped"
# Grok r6 detached HEAD: a commit made while detached in the logs folder is listed.
git --git-dir "$old/.git/worktrees/logs" --work-tree "$old/memory/logs" checkout -q --detach
printf '%s\n' "detached" > "$old/memory/logs/2026-11-02-sam.md"
git --git-dir "$old/.git/worktrees/logs" --work-tree "$old/memory/logs" add 2026-11-02-sam.md
git --git-dir "$old/.git/worktrees/logs" --work-tree "$old/memory/logs" -c user.name=t -c user.email=t@example.test commit -q -m "Log: detached"
join_run > "$work/old6.out"
grep -qx "old-folder: $old/memory/logs/2026-11-02-sam.md copied to memory/logs/2026-11-02-sam.md: sync sends it." "$work/old6.out" \
  || { cat "$work/old6.out" >&2; team_fail "Grok r6: a commit on a detached logs HEAD is not brought"; }
# Nothing left: one line says so.
rm -rf "$old/draft.md" "$old/areas" "$old/memory/logs"
git -C "$old" worktree prune
git -C "$old" checkout -q -- notes/plan.md
git -C "$old" reset -q --hard origin/main
git -C "$old" branch -q -D price logs
rm -f "$old/people/same.md"
join_run > "$work/old2.out"
grep -qx "old-folder: $old has nothing the host lacks. You may delete it." "$work/old2.out" \
  || { cat "$work/old2.out" >&2; team_fail "B63: a clean old folder was not called clean"; }
rm -rf "$old" "$co/people/same.md" "$co/draft.md" "$co/prices.md" "$co/notes" "$co/areas/lab" \
  "$co/memory/logs/2026-11-01-sam.md" "$co/memory/logs/2026-10-31-sam.md" "$co/memory/logs/2026-10-01-sam-renamed.md" \
  "$co/memory/logs/2026-11-02-sam.md" "$work/home/.config/acme-os/state/reapply"
git -C "$co" reset -q --hard "$st_was_head"
git --git-dir "$work/origin.git" update-ref refs/heads/main "$st_was_main"
git --git-dir "$work/origin.git" update-ref "refs/heads/sync/sam/$seat" "$st_was_seat"
git -C "$co" fetch -q origin

# Item 11 (a): claude is in ~/.local/bin but not on PATH. Join says so, gives the step,
# and stops before the jobs. A PATH with no claude on it, even when this computer has one.
nocl="$work/nocl"
mkdir -p "$nocl" "$work/home/.local/bin"
path_nocl="$nocl"
old_ifs=$IFS
IFS=:
for d in $PATH; do
  if [ -e "$d/claude" ]; then
    for f in "$d"/*; do
      [ "$(basename "$f")" = "claude" ] || ln -sf "$f" "$nocl/" 2>/dev/null || true
    done
  else
    path_nocl="$path_nocl:$d"
  fi
done
IFS=$old_ifs
printf '%s\n' '#!/bin/sh' 'echo ok' > "$work/home/.local/bin/claude"
chmod 755 "$work/home/.local/bin/claude"
set +e
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="claude -p" SHELL=/bin/zsh \
  PATH="$path_nocl" OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" > "$work/path.out" 2> "$work/path.err"
rc=$?
set -e
[ "$rc" -eq 3 ] || { cat "$work/path.out" "$work/path.err" >&2; team_fail "item 11a: exit $rc, want 3"; }
grep -qx 'Claude Code is in ~/.local/bin, but that folder is not on PATH. Run this once, then open a new terminal and run join again:' "$work/path.err" \
  || team_fail "item 11a: no PATH line: $(cat "$work/path.err")"
grep -qxF "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc" "$work/path.err" || team_fail "item 11a: no PATH step"
grep -q 'install.sh' "$work/path.err" && team_fail "item 11a: printed the install line again"
grep -q '^join: ok' "$work/path.out" && team_fail "item 11a: join went on"
rm -rf "$work/home/.local"

# Item 11 (b): claude is on PATH but not signed in: one line, exit 3, no jobs. Signed in: on.
mkdir -p "$work/claude-bin"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  'case "${FAKE_CLAUDE:-}" in' \
  '  ok) cat > /dev/null; echo ok; exit 0 ;;' \
  '  echo) cat; exit 0 ;;' \
  "  hang) trap '' TERM; while :; do sleep 1; done ;;" \
  'esac' 'cat > /dev/null' \
  'echo "Invalid API key. Please run /login"' 'exit 1' > "$work/claude-bin/claude"
chmod 755 "$work/claude-bin/claude"
set +e
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="claude -p --model haiku" \
  PATH="$work/claude-bin:$path_nocl" OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" > "$work/sign.out" 2> "$work/sign.err"
rc=$?
set -e
[ "$rc" -eq 3 ] || { cat "$work/sign.out" "$work/sign.err" >&2; team_fail "item 11b: exit $rc, want 3"; }
grep -qx 'sign in once: run claude, sign in, then /exit' "$work/sign.err" || team_fail "item 11b: no sign-in line: $(cat "$work/sign.err")"
grep -q '^sync-jobs\|^join: ok' "$work/sign.out" && team_fail "item 11b: join went on to the jobs"
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="claude -p --model haiku" FAKE_CLAUDE=ok \
  PATH="$work/claude-bin:$path_nocl" OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" > "$work/sign2.out" 2> "$work/sign2.err" \
  || { cat "$work/sign2.out" "$work/sign2.err" >&2; team_fail "item 11b: signed in, join failed"; }
grep -q 'sign in once' "$work/sign2.err" && team_fail "item 11b: signed in, still asked to sign in"
# B43: with no OS_SYNC_ENGINE, the engine comes from <config>/engine, as sync reads it.
mkdir -p "$work/home/.config/acme-os"
printf '%s\n' "claude -p" > "$work/home/.config/acme-os/engine"
set +e
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" \
  PATH="$work/claude-bin:$path_nocl" OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" > "$work/eng.out" 2> "$work/eng.err"
rc=$?
set -e
[ "$rc" -eq 3 ] || team_fail "B43: exit $rc, want 3"
grep -qx 'sign in once: run claude, sign in, then /exit' "$work/eng.err" || team_fail "B43: the config engine was not checked: $(cat "$work/eng.err")"
rm -f "$work/home/.config/acme-os/engine"
# Round 2: an engine that repeats the question is not signed in.
set +e
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="claude -p" FAKE_CLAUDE=echo \
  PATH="$work/claude-bin:$path_nocl" OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" > "$work/sign3.out" 2> "$work/sign3.err"
rc=$?
set -e
[ "$rc" -eq 3 ] || team_fail "item 11b: an echo engine passed the sign-in check (exit $rc)"
grep -qx 'sign in once: run claude, sign in, then /exit' "$work/sign3.err" || team_fail "item 11b: echo engine, no sign-in line"
# Round 2: an engine that ignores TERM and never ends. Join still stops: limit + 5 s, then kill -9.
start=$(date +%s)
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="claude -p" FAKE_CLAUDE=hang \
  OS_ENGINE_TIMEOUT=2 PATH="$work/claude-bin:$path_nocl" OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" > "$work/sign4.out" 2> "$work/sign4.err" &
jpid=$!
n=0
while kill -0 "$jpid" 2>/dev/null && [ "$n" -lt 40 ]; do
  sleep 1
  n=$((n + 1))
done
if kill -0 "$jpid" 2>/dev/null; then
  kill -9 "$jpid" 2>/dev/null || true
  team_fail "item 11b: join hung on an engine that ignores TERM"
fi
set +e
wait "$jpid"
rc=$?
set -e
took=$(( $(date +%s) - start ))
[ "$rc" -eq 3 ] || team_fail "item 11b: hung engine, exit $rc, want 3"
grep -qx 'sign in once: run claude, sign in, then /exit' "$work/sign4.err" || team_fail "item 11b: hung engine, no sign-in line"
[ "$took" -le 12 ] || team_fail "item 11b: hung engine took ${took}s, want at most 12"
# JOIN-WIN: on Git Bash the forced stop also runs taskkill on the Windows process id.
# Stubs: uname says MINGW, taskkill logs its call. This machine has no /proc/<pid>/winpid,
# so this checks the Windows branch still stops in time and skips taskkill without an id.
# The taskkill call itself runs only on Windows.
mkdir -p "$work/win-bin"
printf '%s\n' '#!/bin/sh' 'echo MINGW64_NT-10.0' > "$work/win-bin/uname"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$TASKKILL_LOG"' > "$work/win-bin/taskkill"
chmod 755 "$work/win-bin/uname" "$work/win-bin/taskkill"
: > "$work/taskkill.log"
start=$(date +%s)
set +e
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="claude -p" FAKE_CLAUDE=hang \
  OS_ENGINE_TIMEOUT=2 TASKKILL_LOG="$work/taskkill.log" PATH="$work/win-bin:$work/claude-bin:$path_nocl" \
  OS_HOST_SH="$work/bin/host.sh" \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" > "$work/sign5.out" 2> "$work/sign5.err"
rc=$?
set -e
took=$(( $(date +%s) - start ))
[ "$rc" -eq 3 ] || { cat "$work/sign5.err" >&2; team_fail "JOIN-WIN: exit $rc, want 3"; }
grep -qx 'sign in once: run claude, sign in, then /exit' "$work/sign5.err" || team_fail "JOIN-WIN: no sign-in line"
[ "$took" -le 12 ] || team_fail "JOIN-WIN: took ${took}s, want at most 12"
if [ -r /proc/self/winpid ]; then
  grep -q '^//F //T //PID [0-9]' "$work/taskkill.log" || team_fail "JOIN-WIN: no taskkill call"
else
  [ -s "$work/taskkill.log" ] && team_fail "JOIN-WIN: taskkill ran with no Windows process id"
fi

join_try() {
  HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="$root/tests/fakes/engine.sh" OS_HOST_SH="$work/bin/host.sh" \
    "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" 2>"$work/join.err"
}
# Take the terms back off the host and out of the folder's main. The page goes back to
# undated; every other file stays in the folder.
reset_terms() {
  git --git-dir "$work/origin.git" update-ref -d "refs/heads/sync/sam/$seat"
  git -C "$co" update-ref -d "refs/remotes/origin/sync/sam/$seat"
  git -C "$co" checkout -q main 2>/dev/null || true
  git -C "$co" branch -q -D sync/sam 2>/dev/null || true
  git -C "$co" reset -q origin/main
  git -C "$co" checkout -q origin/main -- "people/Sam Member.md"
}

# A refused auto-merge is one plain line, not a failure: the pull request is open.
reset_terms
FAKE_NO_AUTOMERGE=1 join_run > "$work/join2.out"
grep -q '^auto-merge is off on origin: pull request 7 ' "$work/join2.out" \
  || team_fail "join did not say auto-merge is off"

# A clone an older join left on sync/sam goes back to main, then commits and pushes there.
reset_terms
git -C "$co" checkout -q -b sync/sam
: > "$work/host.log"
join_run > "$work/join4.out"
grep -qx 'terms: proposed' "$work/join4.out" || team_fail "old branch: no terms"
[ "$(git -C "$co" symbolic-ref --short HEAD)" = "main" ] || team_fail "old branch: the folder is off main"
grep -q "^open-pr origin --head sync/sam/$seat " "$work/host.log" || team_fail "old branch: no pull request"
# The checkout back to main is refused: join stops before it commits anything.
reset_terms
git -C "$co" checkout -q -b sync/sam
before=$(git -C "$co" rev-parse HEAD)
rc=0
PATH="$work/shim:$PATH" FAKE_REFUSE_MAIN=1 join_try > "$work/join5.out" || rc=$?
[ "$rc" -eq 3 ] || team_fail "refused checkout: exit $rc, not 3"
grep -q 'could not go back to main' "$work/join.err" || team_fail "refused checkout: no plain line"
[ "$(git -C "$co" rev-parse HEAD)" = "$before" ] || team_fail "refused checkout: join committed off main"

# The terms push fails: the commit stays in the folder. The retry sees the dated page and
# pushes it.
reset_terms
if PATH="$work/shim:$PATH" FAKE_REFUSE_PUSH=1 join_try > "$work/join6.out"; then
  team_fail "join with a refused terms push exited 0"
fi
git --git-dir "$work/origin.git" rev-parse --verify --quiet "refs/heads/sync/sam/$seat" >/dev/null \
  && team_fail "the shim did not refuse the push"
grep -q 'sync push stopped' "$work/join.err" || team_fail "a refused push gave no reason"
grep -Eq '^terms_accepted: [0-9]{4}-' "$co/people/Sam Member.md" || team_fail "the folder page is not dated"
: > "$work/host.log"
join_try > "$work/join7.out" || { cat "$work/join.err" >&2; team_fail "retry after a refused push failed"; }
grep -qx 'terms: already' "$work/join7.out" || team_fail "retry after a refused push proposed again"
git --git-dir "$work/origin.git" show "sync/sam/$seat:people/Sam Member.md" | grep -Eq '^terms_accepted: [0-9]{4}-' \
  || team_fail "retry did not push the terms"
grep -q "^open-pr origin --head sync/sam/$seat " "$work/host.log" || team_fail "retry after a refused push opened no pull request"
# open-pr fails after the push: the terms are on the seat branch only. The retry opens it.
reset_terms
if FAKE_NO_OPENPR=1 join_try > "$work/join8.out"; then
  team_fail "join with a failed open-pr exited 0"
fi
# Round 5 (50): offline, with a dated page in the folder. join must not guess "already":
# it stops with exit 3 and one line, and opens nothing.
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
grep -q "^open-pr origin --head sync/sam/$seat " "$work/host.log" || team_fail "retry after a failed open-pr did not open it"
grep -qx 'auto-merge origin 7' "$work/host.log" || team_fail "retry after a failed open-pr did not turn on auto-merge"

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

# logsfix (66): a v0 clone behind the upgrade's snapshot, with one edit that overlaps a
# change made on branch logs. join keeps that file as the person's copy with the other
# text beside it. Every other log keeps the newer text.
rm -f "$co/memory/logs/2026-10-04-sam.md"
git -C "$co" worktree add -q "$work/lw2" logs
printf '%s\n' "ada first" > "$work/lw2/2026-10-05-ada.md"
git -C "$work/lw2" add 2026-10-05-ada.md
git -C "$work/lw2" commit -q -m "Logs: ada"
git -C "$co" worktree remove "$work/lw2"
git -C "$co" push -q origin logs
git -C "$co" worktree add -q --detach "$work/lw3" logs
printf '%s\n' "day one" "noa line" > "$work/lw3/2026-10-01-sam.md"
printf '%s\n' "ada first" "ada later" > "$work/lw3/2026-10-05-ada.md"
git -C "$work/lw3" commit -q -am "Logs: noa"
git -C "$work/lw3" push -q origin HEAD:logs
git -C "$co" worktree remove "$work/lw3"
git -C "$co" fetch -q origin
git -C "$co" rm -rq memory/logs
mkdir -p "$co/memory/logs-archive"
git -C "$co" show origin/logs:2026-10-01-sam.md > "$co/memory/logs-archive/2026-10-01-sam.md"
git -C "$co" show origin/logs:2026-10-05-ada.md > "$co/memory/logs-archive/2026-10-05-ada.md"
git -C "$co" add memory/logs-archive
git -C "$co" commit -q -m "Upgrade to v1: logs archive"
git -C "$co" push -q origin main
git -C "$co" tag -a logs-archive-2026-10-29 origin/logs -m snapshot
git -C "$co" push -q origin logs-archive-2026-10-29
rm -rf "$co/memory/logs"
git -C "$co" worktree add -q "$co/memory/logs" logs
printf '%s\n' "day one" "sam line" > "$co/memory/logs/2026-10-01-sam.md"
# logsfix (70): after the reset, one kept file cannot be copied back (a log open in an
# editor). join fails, and memory/logs is back as it was, so the next join starts over.
mkdir -p "$work/cpshim"
cat > "$work/cpshim/cp" << EOF
#!/bin/bash
if [ -n "\${FAKE_CP_FAIL:-}" ] && [ "\$1" = -p ]; then
  case "\$2" in *os-logs-keep.*/"\$FAKE_CP_FAIL") exit 1 ;; esac
fi
exec $(command -v cp) "\$@"
EOF
chmod 700 "$work/cpshim/cp"
old_logs=$(git -C "$co/memory/logs" rev-parse HEAD)
if PATH="$work/cpshim:$PATH" FAKE_CP_FAIL=2026-10-01-sam.md join_try > "$work/join-cp.out"; then
  team_fail "join (70) with a failed restore exited 0"
fi
grep -q 'could not put the files changed here back into memory/logs, so memory/logs is back as it was' "$work/join.err" \
  || { cat "$work/join.err" >&2; team_fail "join (70) did not say memory/logs is back"; }
[ -f "$co/memory/logs/.git" ] || team_fail "join (70) removed the logs worktree"
[ "$(git -C "$co/memory/logs" rev-parse HEAD)" = "$old_logs" ] || team_fail "join (70) left the logs folder at the host's tip"
[ "$(cat "$co/memory/logs/2026-10-01-sam.md")" = "$(printf '%s\n' "day one" "sam line")" ] || team_fail "join (70) lost the edit"
[ ! -e "$co/memory/logs/2026-10-01-sam.old-branch.md" ] || team_fail "join (70) left a file beside"
cp_keep=$(sed -n 's/.*A copy of them is also in \([^ ]*\)\. Close.*/\1/p' "$work/join.err" | head -n 1)
[ -f "$cp_keep/files/2026-10-01-sam.md" ] || team_fail "join (70) did not name the kept copy"
rm -rf "$cp_keep"
join_run > "$work/join10.out"
grep -qx 'v0-logs: moved, 1 files kept as local changes' "$work/join10.out" \
  || { cat "$work/join10.out" >&2; team_fail "join (66) did not move the v0 logs worktree"; }
grep -qx 'v0-logs: 1 files were changed here and on the old logs branch, so the old text is beside each one as <name>.old-branch.md. Nothing was written over.' "$work/join10.out" \
  || team_fail "join (66) did not say what went beside"
[ ! -e "$co/memory/logs/.git" ] || team_fail "join (66) left the logs worktree"
[ "$(cat "$co/memory/logs-archive/2026-10-05-ada.md")" = "$(printf '%s\n' "ada first" "ada later")" ] \
  || team_fail "join (66) wrote an older log over the archive"
git -C "$co" diff --quiet -- memory/logs-archive/2026-10-05-ada.md || team_fail "join (66) changed a log the person did not touch"
[ "$(cat "$co/memory/logs-archive/2026-10-01-sam.md")" = "$(printf '%s\n' "day one" "sam line")" ] \
  || team_fail "join (66) lost the person's edit"
[ "$(cat "$co/memory/logs-archive/2026-10-01-sam.old-branch.md")" = "$(printf '%s\n' "day one" "noa line")" ] \
  || team_fail "join (66) did not put the other text beside the edited log"

printf '%s\n' "PASS stage"
