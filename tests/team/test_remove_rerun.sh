#!/bin/bash
# Round 6 (B66, B67): every step of remove is safe to run again. The first run cannot
# reach one area. The company offboard pull request merges. The second run finishes the
# area and ends "remove: ok": the archived workspace is done, the company has nothing to
# change (no branch, no push, no pull request, and the old branch goes), and the area gets
# its own pull request. A third run changes nothing.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME="Ada Admin" GIT_AUTHOR_EMAIL="ada.admin@acme.test"
export GIT_COMMITTER_NAME="Ada Admin" GIT_COMMITTER_EMAIL="ada.admin@acme.test"

seed() {
  local dir=$1 bare=$2
  git -C "$dir" init -q -b main
  git -C "$dir" add -A
  git -C "$dir" commit -q -m seed
  git init -q --bare "$bare"
  git -C "$dir" remote add origin "$bare"
  git -C "$dir" push -q origin main
}

co="$work/co"
mkdir -p "$co/people" "$co/.github" "$co/.gitea" "$work/bin" "$work/state"
cat > "$co/company-profile.md" << 'EOF2'
---
company_slug: acme
host: github
org: acme
level: team
---
# Acme Co
EOF2
cat > "$co/people/Ada Admin.md" << 'EOF2'
---
slug: ada
github: acme-admin
role: admin
left: ""
---
# Ada Admin
EOF2
cat > "$co/people/Sam Member.md" << 'EOF2'
---
slug: sam
github: acme-member-d
role: writer
left: ""
manager: ada
areas: [lab]
---
# Sam Member
EOF2
printf '%s\n' "# Rules files only." "**/AGENTS.md @acme-admin" "/docs/legal/ @acme-member-d" > "$co/.github/CODEOWNERS"
printf '%s\n' "# Rules files only." '^(.*/)?AGENTS\.md$ @acme-admin' '^docs/legal/.* @acme-member-d' > "$co/.gitea/CODEOWNERS"
printf '%s\n' "/areas/" "/users/" > "$co/.gitignore"
seed "$co" "$work/acme-os.git"

area="$co/areas/lab"
mkdir -p "$area/.github" "$area/.gitea"
printf '%s\n' "# Area" > "$area/AGENTS.md"
printf '%s\n' "# Rules files only." "**/AGENTS.md @acme-member-d @acme-admin" "**/skills/ @acme-member-d" > "$area/.github/CODEOWNERS"
printf '%s\n' "# Rules files only." '^(.*/)?AGENTS\.md$ @acme-member-d @acme-admin' '^(.*/)?skills/.* @acme-member-d' > "$area/.gitea/CODEOWNERS"
seed "$area" "$work/acme-lab.git"

# The fake host answers like GitHub where a re-run meets it: an archived repo is done
# (host.sh reads it first, B66), and a pull request with no commits beyond main is
# refused (422, B67).
cat > "$work/bin/host.sh" << 'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$1" in
  user-access) printf '%s\n' '{"access":"none"}' ;;
  org-membership) printf '%s\n' '{"state":"none"}' ;;
  invites) printf '%s\n' '{"invites":[]}' ;;
  open-prs) printf '%s\n' '{"prs":[]}' ;;
  org-repos|team-repos) printf '%s\n' '{"repos":[]}' ;;
  archive-repo)
    if [ -f "$FAKE_STATE/archived-$2" ]; then
      printf '{"ok":true,"name":"%s","archived":true,"already":true}\n' "$2"
    else
      touch "$FAKE_STATE/archived-$2"
      printf '{"ok":true,"name":"%s","archived":true}\n' "$2"
    fi ;;
  open-pr)
    repo=$2 head=""
    while [ $# -gt 0 ]; do
      [ "$1" = "--head" ] && head=$2
      shift
    done
    n=$(git --git-dir "$FAKE_STATE/../${repo}.git" rev-list --count "main..refs/heads/${head}" 2>/dev/null || printf 0)
    if [ "$n" = "0" ]; then
      printf '%s\n' "gh: Validation Failed: No commits between main and ${head} (HTTP 422)" "host error" >&2
      exit 3
    fi
    printf '%s\n' '{"number":4,"url":"http://example.test/4"}' ;;
  get-token) printf '%s\n' local-token ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF2
chmod 700 "$work/bin/host.sh"
export FAKE_LOG="$work/host.log" FAKE_STATE="$work/state"
branch=rules/ada/offboard-sam

run_remove() {
  local out=$1 rc
  set +e
  OS_HOST_SH="$work/bin/host.sh" "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person sam \
    --date "$2" > "$out" 2> "$out.err"
  rc=$?
  set -e
  printf '%s' "$rc"
}

# Run 1: the area cannot be reached.
git -C "$area" remote set-url origin "$work/missing-lab.git"
rc=$(run_remove "$work/r1.out" 2026-10-28)
[ "$rc" -eq 3 ] || { cat "$work/r1.out" "$work/r1.out.err" >&2; team_fail "run 1: exit $rc, want 3"; }
grep -qx 'archived: acme-user-sam' "$work/r1.out" || team_fail "run 1: no archived line"
grep -qx 'pr: 4' "$work/r1.out" || team_fail "run 1: no company pull request"
# Low (round 6): the branch list it could not read counts too, once.
grep -q '^could not list branches in areas/lab: delete sync/sam/\* by hand' "$work/r1.out" || team_fail "run 1: no branch-list line"
grep -qx 'remove: not finished: lab. The steps above are done. Run remove again for the rest.' "$work/r1.out" \
  || { cat "$work/r1.out" >&2; team_fail "run 1: no not-finished line naming lab once"; }

# The company offboard pull request merges (fast-forward). Its branch stays on the host.
git --git-dir "$work/acme-os.git" update-ref refs/heads/main "refs/heads/${branch}"
git -C "$area" remote set-url origin "$work/acme-lab.git"

# Run 2, on a later day: everything left is done.
: > "$FAKE_LOG"
rc=$(run_remove "$work/r2.out" 2026-10-30)
[ "$rc" -eq 0 ] || { cat "$work/r2.out" "$work/r2.out.err" >&2; team_fail "run 2: exit $rc, want 0"; }
grep -qx 'archived: acme-user-sam' "$work/r2.out" || team_fail "B66: run 2 stopped at the archived workspace"
grep -qx 'already done: acme-os (main has the offboard change)' "$work/r2.out" || { cat "$work/r2.out" >&2; team_fail "B67: no already-done line"; }
grep -q '^open-pr acme-os ' "$FAKE_LOG" && team_fail "B67: run 2 opened a company pull request with nothing in it"
grep -qx "deleted: acme-os ${branch} (main has its change)" "$work/r2.out" || team_fail "B67: the stray company branch was not deleted"
git --git-dir "$work/acme-os.git" rev-parse -q --verify "refs/heads/${branch}" >/dev/null && team_fail "B67: the stray branch is still on the host"
grep -qx 'left: 2026-10-28' "$work/r2.out" || team_fail "B67: run 2 changed the left date"
grep -qx 'rules-pr: acme-lab 4 (.github/CODEOWNERS .gitea/CODEOWNERS)' "$work/r2.out" || { cat "$work/r2.out" >&2; team_fail "run 2: no area pull request"; }
git --git-dir "$work/acme-lab.git" show "${branch}:.github/CODEOWNERS" | grep -q 'acme-member-d' && team_fail "run 2: the area CODEOWNERS still name sam"
git --git-dir "$work/acme-lab.git" show "${branch}:.github/CODEOWNERS" | grep -qxF '**/skills/ @acme-admin' || team_fail "run 2: the area sole line does not name the admin"
grep -qx 'remove: ok' "$work/r2.out" || team_fail "run 2: no remove: ok"
grep -q 'not finished' "$work/r2.out" && team_fail "run 2: still not finished"

# Run 3, after the area pull request merged too: nothing to do, still ok.
git --git-dir "$work/acme-lab.git" update-ref refs/heads/main "refs/heads/${branch}"
: > "$FAKE_LOG"
rc=$(run_remove "$work/r3.out" 2026-10-31)
[ "$rc" -eq 0 ] || { cat "$work/r3.out" "$work/r3.out.err" >&2; team_fail "run 3: exit $rc, want 0"; }
grep -q '^open-pr ' "$FAKE_LOG" && team_fail "run 3: opened a pull request"
grep -qx "deleted: acme-lab ${branch} (main has its change)" "$work/r3.out" || team_fail "run 3: the stray area branch was not deleted"
grep -qx 'remove: ok' "$work/r3.out" || team_fail "run 3: no remove: ok"

printf '%s\n' "PASS remove-rerun"
