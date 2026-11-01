#!/bin/bash
# Round 8: join and an old (v0) folder renamed beside the new one.
#  1. CRLF: the old folder checks text out with core.autocrlf=true (the Git for Windows
#     default) and has no eol=lf. The base set aside and the person's copy differ only by
#     the one edit, never on every line.
#  2. A name with a new line and ../ is refused and named. Nothing is written outside the
#     new folder or state/reapply. Nothing is copied through a link in the new folder.
#  3. An unpushed commit adds a file, then the file is deleted from the worktree (company
#     and logs): join brings the commit's text. A link in the old folder is flagged.
# On Windows (Git Bash) this runs with the real core.autocrlf=true and skips the name and
# link parts (Windows names cannot hold a new line; Git Bash links are copies).
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
team_need git jq
work=$(mktemp -d)
out=$(mktemp -d)
trap 'rm -rf "$work" "$out"' EXIT
export GIT_AUTHOR_NAME="Ada Admin" GIT_AUTHOR_EMAIL="ada.admin@acme.test"
export GIT_COMMITTER_NAME="Ada Admin" GIT_COMMITTER_EMAIL="ada.admin@acme.test"
windows=0
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=1 ;;
esac

# The host: a bare repo. Main has the profile, the people pages (terms already accepted,
# so join does not push) and a plan file, with no .gitattributes (v0).
co="$work/co"
old="$work/co-old"
mkdir -p "$co/people" "$co/notes" "$work/bin" "$work/home/.config"
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
cat > "$co/people/Sam Member.md" << 'EOF'
---
slug: sam
github: acme-member-d
role: writer
left: ""
terms_accepted: 2026-10-01
---
# Sam Member
EOF
printf '%s\n' "/areas/" "/users/" > "$co/.gitignore"
printf '%s\n' "# Plan" "- base line" "- second line" > "$co/notes/plan.md"
git -C "$co" init -q -b main
git -C "$co" add -A
git -C "$co" commit -q -m seed
git init -q --bare "$work/origin.git"
git -C "$co" remote add origin "$work/origin.git"
git -C "$co" push -q origin main
# The v0 logs branch, pushed once.
git -C "$co" checkout -q --orphan logs
git -C "$co" rm -rq --cached .
git -C "$co" clean -fdqx
printf '%s\n' "day one" > "$co/2026-10-01-sam.md"
git -C "$co" add 2026-10-01-sam.md
git -C "$co" commit -q -m "Log: day one"
git -C "$co" push -q origin logs
git -C "$co" checkout -q main
rm -rf "$co"

# The old copy, cloned the way Git for Windows does: core.autocrlf=true, so text is CRLF.
if [ "$windows" -eq 1 ]; then
  [ "$(git config --get core.autocrlf || true)" = "true" ] \
    || team_fail "the Windows runner's git does not have core.autocrlf=true"
  git clone -q -b main "$work/origin.git" "$co"
else
  git clone -q -c core.autocrlf=true -b main "$work/origin.git" "$co"
fi
git -C "$co" fetch -q origin logs:refs/remotes/origin/logs
git -C "$co" branch -q logs origin/logs
git -C "$co" worktree add -q "$co/memory/logs" logs
printf '%s\n' "/memory/logs/" >> "$co/.git/info/exclude"
LC_ALL=C grep -q $'\r' "$co/notes/plan.md" || team_fail "setup: the old folder's plan.md is not CRLF"
# 1. The person's edit, saved by a Windows editor (CRLF kept).
printf '%s\r\n' "- sam: from the old folder" >> "$co/notes/plan.md"
# 3. An unpushed commit adds a file, then it is deleted from the worktree.
printf '%s\n' "added in a commit" > "$co/notes/added.md"
git -C "$co" add notes/added.md
git -C "$co" commit -q -m "Sam: added note"
rm "$co/notes/added.md"
# 3. The same on the logs side: an unpushed log commit, then the log is deleted.
printf '%s\n' "day two" > "$co/memory/logs/2026-10-31-sam.md"
git -C "$co/memory/logs" add 2026-10-31-sam.md
git -C "$co/memory/logs" commit -q -m "Log: sam"
rm "$co/memory/logs/2026-10-31-sam.md"
if [ "$windows" -eq 0 ]; then
  # 2. An untracked name with a new line and ../ : git status -z keeps it one record.
  mkdir -p "$co/x"$'\n'"abc.."
  printf '%s\n' "evil" > "$co/x"$'\n'"abc../evil.md"
  # 2. An untracked file whose folder is a link in the new folder.
  mkdir -p "$co/linkdir" "$work/outside"
  printf '%s\n' "through a link" > "$co/linkdir/new.md"
  # 3. A link in the old folder: never brought, and flagged.
  ln -s /etc/hosts "$co/oldlink.md"
fi
git -C "$co" remote set-url origin https://github.com/acme/acme-os.git
mv "$co" "$old"

# Main moves on: v1 adds .gitattributes (eol=lf) and a colleague adds a line.
git clone -q -b main "$work/origin.git" "$work/up"
printf '%s\n' "* text=auto eol=lf" > "$work/up/.gitattributes"
printf '%s\n' "- ada: newer on main" >> "$work/up/notes/plan.md"
git -C "$work/up" add -A
git -C "$work/up" commit -q -m "v1 and a newer plan line"
git -C "$work/up" push -q origin main
rm -rf "$work/up"
# The new folder, cloned fresh, with the workspace already there.
git clone -q -b main "$work/origin.git" "$co"
mkdir -p "$co/users/sam"
git -C "$co/users/sam" init -q -b main
[ "$windows" -eq 1 ] || ln -s "$work/outside" "$co/linkdir"
cat > "$work/bin/host.sh" << 'EOF'
#!/bin/bash
case "$1" in
  get-token) printf '%s\n' local-token ;;
  open-prs) printf '%s\n' '[]' ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF
chmod 700 "$work/bin/host.sh"
printf '%s\n' "root=$co" "me=sam" "areas=" > "$out/answers"

snap_old() {
  (cd "$old" && git status --porcelain && git rev-parse HEAD && git for-each-ref \
    && find . -type f -print0 | sort -z | xargs -0 cksum)
}
snap_out() {
  find "$work" \( -path "$co" -o -path "$old" -o -path "$work/home/.config/acme-os" \) -prune -o -print | LC_ALL=C sort
}
old_state=$(snap_old)
out_state=$(snap_out)
HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_SYNC_ENGINE="$root/tests/fakes/engine.sh" OS_HOST_SH="$work/bin/host.sh" \
  bash "$root/template/skills/add-teammate/join.sh" --answers "$out/answers" > "$out/join.out" 2> "$out/join.err" \
  || { cat "$out/join.out" "$out/join.err" >&2; team_fail "join exit"; }
say() { cat "$out/join.out" >&2; team_fail "$1"; }
grep -qx 'join: ok' "$out/join.out" || say "join did not finish"

# 1. The set-aside base and the person's copy differ only by the one edit.
hold="$work/home/.config/acme-os/state/reapply/root/notes/plan.md"
[ -f "$hold" ] && [ -f "$hold.base" ] || say "1: plan.md was not set aside"
LC_ALL=C grep -q $'\r' "$hold" && say "1: the set-aside copy still has CRLF line ends"
d=$(diff "$hold.base" "$hold" || true)
if [ "$(grep -c '^[<>]' <<< "$d")" != "1" ] || ! grep -qx -- '> - sam: from the old folder' <<< "$d"; then
  printf '%s\n' "$d" >&2
  team_fail "1: base and mine differ on more than the one edit"
fi
grep -qx -- '- ada: newer on main' "$co/notes/plan.md" || say "1: main's newer line is gone"
grep -q 'sam: from the old folder' "$co/notes/plan.md" && say "1: join wrote the old file over main"

# 3. The commit's text comes back, company and logs.
grep -qx "old-folder: $old/notes/added.md copied to notes/added.md: sync sends it." "$out/join.out" \
  || say "3: the committed file deleted from the worktree was not brought"
[ "$(cat "$co/notes/added.md")" = "added in a commit" ] || say "3: notes/added.md does not have the commit's text"
grep -qx "old-folder: $old/memory/logs/2026-10-31-sam.md copied to memory/logs/2026-10-31-sam.md: sync sends it." "$out/join.out" \
  || say "3: the committed log deleted from the worktree was not brought"
[ "$(cat "$co/memory/logs/2026-10-31-sam.md")" = "day two" ] || say "3: the log does not have the commit's text"
grep -q 'You may delete it' "$out/join.out" && say "3: said the old folder may be deleted"

if [ "$windows" -eq 0 ]; then
  # 2. The bad name is refused and named; nothing written outside.
  grep -qx "old-folder: $old/x?abc../evil.md was not brought: its name has .., a leading /, a tab or a new line. Check it by hand before deleting the old folder." "$out/join.out" \
    || say "2: the name with a new line was not refused"
  [ ! -e "$work/evil.md" ] || say "2: join wrote outside the new folder"
  [ ! -e "$co/evil.md" ] || say "2: join wrote a second path from the name"
  grep -qx "old-folder: $old/linkdir/new.md was not copied: linkdir/new.md goes through a link in this folder. Copy it by hand before deleting the old folder." "$out/join.out" \
    || say "2: no line for the copy through a link"
  [ ! -e "$work/outside/new.md" ] || say "2: join copied through a link in the new folder"
  # 3. A link in the old folder is flagged.
  grep -qx "old-folder: $old/oldlink.md is not a plain file (a link or a special file), so join did not bring it. Check it by hand before deleting the old folder." "$out/join.out" \
    || say "3: the link was not flagged"
  grep -q "^old-folder: $old held [0-9]* items the host lacks (listed above), and some of it could not be checked. .*Do not delete it yet.\$" "$out/join.out" \
    || say "2/3: the summary does not hold the old folder back"
  # set-aside refuses a path that leaves state/reapply.
  if OS_COMPANY_ROOT="$co" HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_HOST_SH="$work/bin/host.sh" \
    OS_PROFILE_SH="$root/template/skills/_host/profile.sh" \
    bash "$root/template/skills/sync/sync.sh" set-aside root "../../escape.md" "$co/notes/added.md" - > "$out/sa.out" 2>&1; then
    team_fail "2: set-aside took a path with .."
  fi
  grep -q 'bad path' "$out/sa.out" || { cat "$out/sa.out" >&2; team_fail "2: set-aside did not name the bad path"; }
fi
[ "$out_state" = "$(snap_out)" ] || { diff <(printf '%s\n' "$out_state") <(snap_out) >&2 || true; team_fail "2: join wrote outside the new folder and its state"; }
[ "$(find "$work/home/.config/acme-os/state" -path "$work/home/.config/acme-os/state/reapply" -prune -o -type f -newer "$out/answers" -print \
  | grep -v -e '/sync\.log$' -e '/held\.json$' -e '/join-brought$' -e '/lock' || true)" = "" ] \
  || team_fail "2: join wrote an unexpected file in state"
[ "$old_state" = "$(snap_old)" ] || team_fail "join changed the old folder"
printf '%s\n' "PASS"
