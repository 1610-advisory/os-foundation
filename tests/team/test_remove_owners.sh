#!/bin/bash
# Round 4 (R6): remove takes the person out of every CODEOWNERS they are on, in the
# company and in each area, in both files. A line they owned alone names the admin.
# Each rules pull request has a body that says so, and the override line.
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
mkdir -p "$co/people" "$co/.github" "$co/.gitea" "$work/bin"
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
printf '%s\n' "# Rules files only." "**/AGENTS.md @acme-admin" "/docs/legal/ @Acme-Member-D" > "$co/.github/CODEOWNERS"
printf '%s\n' "# Rules files only." '^(.*/)?AGENTS\.md$ @acme-admin' '^docs/legal/.* @acme-member-d' > "$co/.gitea/CODEOWNERS"
printf '%s\n' "/areas/" "/users/" > "$co/.gitignore"
seed "$co" "$work/acme-os.git"

area="$co/areas/lab"
mkdir -p "$area/.github" "$area/.gitea"
printf '%s\n' "# Area" > "$area/AGENTS.md"
printf '%s\n' "# Rules files only." "**/AGENTS.md @acme-member-d @acme-admin" "**/skills/ @acme-member-d" > "$area/.github/CODEOWNERS"
printf '%s\n' "# Rules files only." '^(.*/)?AGENTS\.md$ @acme-member-d @acme-admin' '^(.*/)?skills/.* @acme-member-d' > "$area/.gitea/CODEOWNERS"
seed "$area" "$work/acme-lab.git"

cat > "$work/bin/host.sh" << 'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$1" in
  user-access) printf '%s\n' '{"access":"none"}' ;;
  org-membership) printf '%s\n' '{"state":"none"}' ;;
  invites) printf '%s\n' '{"invites":[]}' ;;
  open-prs) printf '%s\n' '{"prs":[]}' ;;
  org-repos|team-repos) printf '%s\n' '{"repos":[]}' ;;
  open-pr)
    repo=$2
    while [ $# -gt 0 ]; do
      [ "$1" = "--body-file" ] && cp "$2" "${FAKE_LOG}.body.${repo}"
      shift
    done
    printf '%s\n' '{"number":4,"url":"http://example.test/4"}' ;;
  get-token) printf '%s\n' local-token ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF2
chmod 700 "$work/bin/host.sh"
export FAKE_LOG="$work/host.log"
set +e
OS_HOST_SH="$work/bin/host.sh" "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person sam \
  --date 2026-10-28 > "$work/rm.out" 2> "$work/rm.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/rm.out" "$work/rm.err" >&2; team_fail "remove exit $rc"; }

branch=rules/ada/offboard-sam
# Company: the sole owner line now names the admin; the page is marked left.
files=$(git --git-dir "$work/acme-os.git" diff --name-only main "$branch" | sort | tr '\n' ' ')
[ "$files" = ".gitea/CODEOWNERS .github/CODEOWNERS people/Sam Member.md " ] || team_fail "company offboard branch has: $files"
git --git-dir "$work/acme-os.git" show "$branch:.github/CODEOWNERS" | grep -qxF '/docs/legal/ @acme-admin' \
  || team_fail "company: a line Sam owned alone does not name the admin"
git --git-dir "$work/acme-os.git" show "$branch:.gitea/CODEOWNERS" | grep -qxF '^docs/legal/.* @acme-admin' \
  || team_fail "company Forgejo: a line Sam owned alone does not name the admin"
git --git-dir "$work/acme-os.git" show "$branch:.github/CODEOWNERS" "$branch:.gitea/CODEOWNERS" | grep -qi 'acme-member-d' \
  && team_fail "company: Sam is still a code owner"

# Area: Sam is off both files; the shared line keeps the admin; the sole line names the admin.
git --git-dir "$work/acme-lab.git" rev-parse -q --verify "$branch" >/dev/null || team_fail "no area offboard branch"
afiles=$(git --git-dir "$work/acme-lab.git" diff --name-only main "$branch" | sort | tr '\n' ' ')
[ "$afiles" = ".gitea/CODEOWNERS .github/CODEOWNERS " ] || team_fail "area offboard branch has: $afiles"
git --git-dir "$work/acme-lab.git" show "$branch:.github/CODEOWNERS" | grep -qxF '**/AGENTS.md @acme-admin' || team_fail "area: shared line"
git --git-dir "$work/acme-lab.git" show "$branch:.github/CODEOWNERS" | grep -qxF '**/skills/ @acme-admin' || team_fail "area: sole line"
git --git-dir "$work/acme-lab.git" show "$branch:.gitea/CODEOWNERS" | grep -qxF '^(.*/)?skills/.* @acme-admin' || team_fail "area Forgejo: sole line"
git --git-dir "$work/acme-lab.git" show "$branch:.github/CODEOWNERS" "$branch:.gitea/CODEOWNERS" | grep -q 'acme-member-d' \
  && team_fail "area: Sam is still a code owner"
[ "$(git -C "$area" symbolic-ref --short HEAD)" = "main" ] || team_fail "remove left the area off main"
git -C "$area" show main:.github/CODEOWNERS | grep -q 'acme-member-d' || team_fail "remove changed the area main"

# Output and bodies.
grep -qx 'rules-pr: acme-lab 4 (.github/CODEOWNERS .gitea/CODEOWNERS)' "$work/rm.out" || { cat "$work/rm.out" >&2; team_fail "no area rules-pr line"; }
grep -q '^merge-by-hand: acme-lab 4: it changes CODEOWNERS' "$work/rm.out" || team_fail "area: no merge-by-hand line on GitHub"
grep -q '^merge-by-hand: acme-os 4: it changes CODEOWNERS' "$work/rm.out" || team_fail "company: no merge-by-hand line on GitHub"
grep -q 'checks are green' "$work/rm.out" && team_fail "merge-by-hand still says when its checks are green"
for r in acme-os acme-lab; do
  grep -q "^override: $r 4 if the model review fails it: .*/override remove: offboard sam as the body says$" "$work/rm.out" \
    || team_fail "$r: no override line"
  body="${FAKE_LOG}.body.$r"
  [ -f "$body" ] || team_fail "$r: no body"
  grep -q '^Offboard: sam left on 2026-10-28. sam (@acme-member-d) stops being a code owner' "$body" || { cat "$body" >&2; team_fail "$r: body lacks why"; }
  grep -q '^Code owners removed: @acme-member-d' "$body" || { cat "$body" >&2; team_fail "$r: body does not name who stops"; }
  grep -q 'stays a code owner of every line' "$body" || team_fail "$r: body does not say the admin stays"
done
grep -q "^people: sam's page gets left: 2026-10-28.$" "${FAKE_LOG}.body.acme-os" || team_fail "company body lacks the page line"

printf '%s\n' "PASS remove-owners"
