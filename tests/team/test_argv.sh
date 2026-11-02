#!/bin/bash
# A fake git and a fake host.sh write their argv. A token must not appear there.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sentinel="argv-sentinel-$(team_sha <(printf '%s' "$$-$RANDOM") | cut -c 1-12)"
printf '%s\n' "$sentinel" > "$work/token"
chmod 600 "$work/token"

mkdir -p "$work/bin"
cat > "$work/bin/git" << 'EOF'
#!/bin/bash
printf '%s\n' "$#" >> "$OS_ARGV_LOG"
i=1
for arg in "$@"; do
  printf 'arg %s\n' "$i" >> "$OS_ARGV_LOG"
  printf '%s\n' "$arg" >> "$OS_ARGV_LOG"
  i=$((i + 1))
done
printf '%s\n' "---" >> "$OS_ARGV_LOG"
# Remote checks and fetch must hit the real git. A bare push stays a log-only spy.
for arg in "$@"; do
  case "$arg" in
    -C|fetch|remote|rev-parse)
      exec /usr/bin/git "$@"
      ;;
  esac
done
exit 0
EOF
cat > "$work/bin/host.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$#" >> "$OS_ARGV_LOG"
i=1
for arg in "$@"; do
  printf 'arg %s\n' "$i" >> "$OS_ARGV_LOG"
  printf '%s\n' "$arg" >> "$OS_ARGV_LOG"
  i=$((i + 1))
done
printf '%s\n' "---" >> "$OS_ARGV_LOG"
case "$1" in
  get-token)
    cat "$OS_TOKEN_FILE"
    ;;
  whoami)
    if [ -n "${OS_FAKE_SCOPES:-}" ]; then
      printf '{"login":"%s","scopes":%s}\n' "${OS_FAKE_LOGIN:-ada}" "$OS_FAKE_SCOPES"
    else
      printf '{"login":"%s"}\n' "${OS_FAKE_LOGIN:-ada}"
    fi
    ;;
  plan-check)
    if [ "${OS_FAKE_PLAN:-}" = "free" ]; then
      printf '%s\n' "This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again." >&2
      exit 3
    fi
    printf '{"plan":"%s"}\n' "${OS_FAKE_PLAN:-team}"
    ;;
  secret-exists)
    if [ "${OS_FAKE_SECRET_403:-}" = "1" ]; then
      printf '%s\n' "cannot read org secrets: sign in as an org owner" >&2
      exit 4
    fi
    printf '%s\n' '{"exists":false}'
    ;;
  open-pr)
    printf '%s\n' '{"number":1,"url":"http://example.test/pr/1"}'
    ;;
  org-membership)
    case "$2" in
      outside*) printf '{"user":"%s","state":"none"}\n' "$2" ;;
      *) printf '{"user":"%s","state":"active","role":"member"}\n' "$2" ;;
    esac
    ;;
  my-membership)
    printf '{"state":"%s"}\n' "${OS_FAKE_MY_STATE:-active}"
    ;;
  repo-access)
    if [ "${OS_REPO_EXISTS:-}" = "1" ]; then
      printf '%s\n' '{"access":"ok"}'
      exit 0
    fi
    # gh's own lines for a repo that is not there yet (round 5: team-on must not show them).
    printf '%s\n' "gh: Not Found (HTTP 404)" "not found or no access" >&2
    printf '%s\n' '{"access":"no-access"}'
    exit 2
    ;;
  *)
    printf '%s\n' '{"ok":true}'
    ;;
esac
exit 0
EOF
chmod 700 "$work/bin/git" "$work/bin/host.sh"

export OS_ARGV_LOG="$work/argv.log"
export OS_TOKEN_FILE="$work/token"
export OS_HOST_BIN="$work/bin/host.sh"
: > "$OS_ARGV_LOG"

# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"
# The lib sets its own EXIT trap. Run both.
trap 'rm -rf "$work"; os_cleanup' EXIT
PATH="$work/bin:$PATH" os_with_git_token git push origin main

if grep -F -q -f "$work/token" "$OS_ARGV_LOG"; then
  team_fail "token appeared in argv"
fi
grep -q 'push' "$OS_ARGV_LOG" || team_fail "spy git did not run"

# team-on must not read a key file and must not pass a key to host.sh.
company="$work/company"
mkdir -p "$company/skills" "$company/areas/marketing" "$company/people"
cat > "$company/company-profile.md" << 'EOF'
---
type: company-profile
company_slug: team
level: solo
switches: []
os_version: v1.0.0
host: forgejo
host_url: "http://127.0.0.1:9"
org: acme
---

# Acme Co
EOF
git -C "$company" init -q
git -C "$company" checkout -q -b main
printf '%s\n' "/areas/" > "$company/.gitignore"
printf '%s\n' "/users/" >> "$company/.gitignore"
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" commit -q -m "start"
git -C "$company/areas/marketing" init -q
git -C "$company/areas/marketing" checkout -q -b main
printf '%s\n' "# Marketing" > "$company/areas/marketing/AGENTS.md"
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company/areas/marketing" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company/areas/marketing" commit -q -m "start"

answers="$work/answers"
cat > "$answers" << EOF
root=$company
host=forgejo
host_url=http://127.0.0.1:9
org=acme
sync_engine=true
runner=ubuntu-latest
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.email=ada$(printf '%s' '@')example.test
person.ada.role=admin
person.ada.areas=marketing
EOF
: > "$OS_ARGV_LOG"
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
mkdir -p "$HOME"
export OS_HOST_SH="$work/bin/host.sh"
set +e
out=$(PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$answers" 2>"$work/err")
rc=$?
set -e
printf '%s\n' "$out" | grep -q 'review-command: OS_HOST=[a-z]* OS_ORG=[^ ]* .*skills/_host/host.sh set-secret OS_REVIEW_KEY' || team_fail "missing review command"
# B24: a new company's teams carry its slug.
printf '%s\n' "$out" | grep -qx 'teams: team-company, team-area-marketing' || team_fail "team-on did not make slug teams"
grep -qx 'team-company' "$OS_ARGV_LOG" || team_fail "team-on did not create team-company"
awk 'prev == "team-create" && $0 == "arg 2" { getline; if ($0 == "company") bad = 1 } { prev = $0 } END { exit bad }' "$OS_ARGV_LOG" \
  || team_fail "team-on created the plain team company"
printf '%s\n' "$out" | grep -q 'no review key: every pull request fails the model review until you add one' || team_fail "missing no-key sentence"
if grep -F -q -f "$work/token" "$OS_ARGV_LOG"; then
  team_fail "token appeared in team-on argv"
fi
if grep -F -q 'set-secret' "$OS_ARGV_LOG"; then
  team_fail "team-on must not run set-secret"
fi
# The answers file must not be asked to hold a key. The script must not read one.
grep -q 'review_key' "$answers" && team_fail "answers file must not hold a review key"
[ "$rc" -eq 0 ] || {
  printf '%s\n' "$out" >&2
  cat "$work/err" >&2
  team_fail "team-on spy run failed ($rc)"
}
# Round 5: a repo not there yet is expected before each create: no raw 404 lines.
grep -q 'Not Found (HTTP 404)\|not found or no access' "$work/err" && { cat "$work/err" >&2; team_fail "r5: team-on showed the expected 404 lines"; }
[ "$(git -C "$company" remote get-url origin)" = "http://127.0.0.1:9/acme/team-os.git" ] || team_fail "create path left the wrong company origin"
# v1.0.2: me is the person this computer signs in as. The stub signs in as "ada",
# which is no person's github here (ada's is acme-admin): no me file, one line.
[ ! -e "$HOME/.config/team-os/me" ] || team_fail "me was written for a login that matches no one"
printf '%s\n' "$out" | grep -qx "me: this computer signs in as ada, which is no person in the answers; add yourself as a person, or write $HOME/.config/team-os/me by hand" \
  || team_fail "no me line for an unknown login"
# Two admins: the second one runs it (an outside advisor who is an org owner).
two="$work/answers-two"
{ cat "$answers"; printf '%s\n' "person.bo.name=Bo Advisor" "person.bo.github=acme-advisor" "person.bo.role=admin" "person.bo.areas=marketing"; } > "$two"
[ "$(os_me_for_login "$two" acme-advisor)" = "bo" ] || team_fail "me for the second admin"
[ "$(os_me_for_login "$two" acme-admin)" = "ada" ] || team_fail "me for the first admin"
[ -z "$(os_me_for_login "$two" someone-else)" ] || team_fail "me for no one"
[ "$(git -C "$company/areas/marketing" remote get-url origin)" = "http://127.0.0.1:9/acme/team-marketing.git" ] || team_fail "create path left the wrong area origin"
[ "$(git -C "$company/users/ada" remote get-url origin)" = "http://127.0.0.1:9/acme/team-user-ada.git" ] || team_fail "create path left the wrong workspace origin"

# Existing repo, origin absent: add the clone URL and fetch. A later run with
# origin set but no origin/main fetches again.
seed_bare() {
  local name=$1 bare seed
  bare="$work/git/acme/${name}.git"
  seed="$work/seed-$name"
  git init -q --bare "$bare"
  git init -q "$seed"
  git -C "$seed" checkout -q -b main
  printf '%s\n' "seed" > "$seed/README.md"
  GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
    GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
    git -C "$seed" add README.md
  GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
    GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
    git -C "$seed" commit -q -m "seed"
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -q origin main
}
mkdir -p "$work/git/acme"
seed_bare team-os
seed_bare team-marketing
seed_bare team-user-ada
answers2="$work/answers-exists"
sed "s|host_url=http://127.0.0.1:9|host_url=file://${work}/git|" "$answers" > "$answers2"
git -C "$company" remote remove origin
git -C "$company/areas/marketing" remote remove origin
git -C "$company/users/ada" remote remove origin
: > "$OS_ARGV_LOG"
set +e
out=$(OS_FAKE_LOGIN=acme-admin OS_REPO_EXISTS=1 PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$answers2" 2>"$work/err2")
rc=$?
set -e
[ "$rc" -eq 0 ] || {
  printf '%s\n' "$out" >&2
  cat "$work/err2" >&2
  team_fail "existing-repo team-on failed ($rc)"
}
if grep -F -q -f "$work/token" "$OS_ARGV_LOG"; then
  team_fail "token appeared in existing-repo argv"
fi
[ "$(git -C "$company" remote get-url origin)" = "file://${work}/git/acme/team-os.git" ] || team_fail "existing path left the wrong company origin"
[ "$(git -C "$company/areas/marketing" remote get-url origin)" = "file://${work}/git/acme/team-marketing.git" ] || team_fail "existing path left the wrong area origin"
[ "$(git -C "$company/users/ada" remote get-url origin)" = "file://${work}/git/acme/team-user-ada.git" ] || team_fail "existing path left the wrong workspace origin"
git -C "$company" rev-parse --verify --quiet origin/main >/dev/null || team_fail "existing path did not fetch origin/main"
[ "$(tr -d '[:space:]' < "$HOME/.config/team-os/me")" = "ada" ] || team_fail "me is not the signed-in person"
git -C "$company" update-ref -d refs/remotes/origin/main
git -C "$company/areas/marketing" update-ref -d refs/remotes/origin/main
git -C "$company/users/ada" update-ref -d refs/remotes/origin/main
set +e
out=$(OS_REPO_EXISTS=1 PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$answers2" 2>"$work/err3")
rc=$?
set -e
[ "$rc" -eq 0 ] || {
  printf '%s\n' "$out" >&2
  cat "$work/err3" >&2
  team_fail "retry after a missing origin/main failed ($rc)"
}
git -C "$company" rev-parse --verify --quiet origin/main >/dev/null || team_fail "retry did not fill origin/main"

# B4: a repo an earlier run made is empty (its first push failed). The next run
# pushes main first, lifts any protection before that push, and protects after.
mkdir -p "$work/git2/acme"
for name in team-os team-marketing team-user-ada; do
  git init -q --bare "$work/git2/acme/${name}.git"
done
answers3="$work/answers-empty"
sed "s|host_url=http://127.0.0.1:9|host_url=file://${work}/git2|" "$answers" > "$answers3"
# The spy git above skips add and commit without -C, so the workspace has no commit yet.
if ! git -C "$company/users/ada" rev-parse --verify --quiet HEAD >/dev/null; then
  git -C "$company/users/ada" add -A
  GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
    GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
    git -C "$company/users/ada" commit -q -m "Workspace: start"
fi
for d in "$company" "$company/areas/marketing" "$company/users/ada"; do
  git -C "$d" update-ref -d refs/remotes/origin/main 2>/dev/null || true
done
git -C "$company" remote set-url origin "file://${work}/git2/acme/team-os.git"
git -C "$company/areas/marketing" remote set-url origin "file://${work}/git2/acme/team-marketing.git"
git -C "$company/users/ada" remote set-url origin "file://${work}/git2/acme/team-user-ada.git"
: > "$OS_ARGV_LOG"
set +e
out=$(OS_REPO_EXISTS=1 PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$answers3" 2>"$work/err4")
rc=$?
set -e
[ "$rc" -eq 0 ] || {
  printf '%s\n' "$out" >&2
  cat "$work/err4" >&2
  team_fail "empty-repo team-on failed ($rc)"
}
for name in team-os team-marketing team-user-ada; do
  git --git-dir "$work/git2/acme/${name}.git" rev-parse --verify --quiet refs/heads/main >/dev/null \
    || team_fail "empty repo ${name} got no first push"
  printf '%s\n' "$out" | grep -qx "first push: ${name}" || team_fail "no first push line for ${name}"
done
verbs=$(awk 'prev == "arg 1" { v = $0 } prev == "arg 2" && (v == "unprotect" || v == "protect") { print v " " $0 } { prev = $0 }' "$OS_ARGV_LOG")
first_verb=$(printf '%s\n' "$verbs" | grep ' team-os$' | head -n 1)
[ "$first_verb" = "unprotect team-os" ] || team_fail "team-os was protected before its first push: ${first_verb:-none}"
printf '%s\n' "$verbs" | grep -qx 'protect team-os' || team_fail "team-os was not protected after its first push"

# B3: a gh sign-in without admin:org or workflow stops before any change.
sed 's|^host=forgejo$|host=github|; s|^host_url=.*$|host_url=|' "$answers" > "$work/answers-gh"
set +e
out=$(OS_FAKE_SCOPES='["repo","read:org"]' PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$work/answers-gh" 2>"$work/err5")
rc=$?
set -e
[ "$rc" -eq 4 ] || team_fail "missing gh scopes exit was $rc"
grep -q 'gh auth refresh -s admin:org,workflow' "$work/err5" || team_fail "missing gh scopes line"

# A Free GitHub org stops with one line before any write.
: > "$OS_ARGV_LOG"
set +e
out=$(OS_FAKE_PLAN=free PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$work/answers-gh" 2>"$work/err7")
rc=$?
set -e
[ "$rc" -eq 3 ] || team_fail "free plan exit was $rc"
[ "$(cat "$work/err7")" = "This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again." ] \
  || team_fail "free plan line: $(cat "$work/err7")"
grep -qx -E 'create-repo|team-create|protect|unprotect|grant|set-secret' "$OS_ARGV_LOG" && team_fail "free plan run changed the host"

# B2: an unreadable review key is not "no review key".
set +e
out=$(OS_FAKE_SECRET_403=1 OS_REPO_EXISTS=1 PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$answers3" 2>"$work/err6")
set -e
printf '%s\n' "$out" | grep -q 'could not check the review key: sign in as an org owner' || team_fail "unreadable key line missing"
printf '%s\n' "$out" | grep -q 'no review key' && team_fail "unreadable key said no review key"

# B6: the GitHub hand-off names github.com/<org>, not an empty host.
line=$(os_hand_off dana "Dana Director" acme team-os marketing team-user-dana github "" | tail -n 1)
case "$line" in
  *"Host: github.com/acme."*) ;;
  *) team_fail "github hand-off host line: $line" ;;
esac

# v1.0.2: a v0 people page used role: for the job title. It moves to job_title:, and
# role: takes the OS role. A second run changes nothing.
v0="$work/v0"
mkdir -p "$v0/people"
printf '%s\n' '---' 'type: person' 'summary: ""' 'role: "President"' 'email: ""' '---' '' '# Ada Admin' '' 'Runs the shop.' > "$v0/people/Ada Admin.md"
os_write_person_page "$v0" ada "Ada Admin" acme-admin "ada@example.test" admin marketing "" >/dev/null
page="$v0/people/Ada Admin.md"
grep -qx 'role: admin' "$page" || team_fail "v0 page role: $(grep '^role:' "$page")"
grep -qx 'job_title: "President"' "$page" || team_fail "v0 job title not kept: $(cat "$page")"
grep -qx 'Runs the shop.' "$page" || team_fail "v0 page body changed"
cp "$page" "$work/v0-first"
os_write_person_page "$v0" ada "Ada Admin" acme-admin "ada@example.test" admin marketing "" >/dev/null
cmp -s "$work/v0-first" "$page" || team_fail "second run changed the v0 page"
# A job title already there is never written over.
printf '%s\n' '---' 'type: person' 'job_title: "Owner"' 'role: "CEO"' '---' > "$v0/people/Bo Advisor.md"
os_write_person_page "$v0" bo "Bo Advisor" acme-advisor "bo@example.test" admin marketing "" >/dev/null
grep -qx 'job_title: "Owner"' "$v0/people/Bo Advisor.md" || team_fail "an existing job title was written over"
grep -qx 'role: admin' "$v0/people/Bo Advisor.md" || team_fail "bo role"

# v1.0.2: a team add for someone who is not an org member sends a GitHub org invite.
# Say so once per person; a member gets no line; Forgejo has no invites.
invite_out=$(OS_HOST=github; os_team_add team-company outside-carl; os_team_add team-area-marketing outside-carl; os_team_add team-company acme-admin)
[ "$invite_out" = "invite: outside-carl is not an org member; adding them to team-company sends an org invite (no new seat if they already use one as a collaborator). They accept it before join." ] \
  || team_fail "invite line: $invite_out"
[ "$(grep -c '^team-add$' "$OS_ARGV_LOG")" -ge 3 ] || team_fail "os_team_add did not add"
[ -z "$(OS_HOST=forgejo; os_team_add team-company outside-dee)" ] || team_fail "forgejo printed an invite line"
# join stops while the person's own invite is still open, and names the page.
jc="$work/join-company"
mkdir -p "$jc"
printf '%s\n' '---' 'company_slug: team' 'level: team' 'host: github' 'host_url: ""' 'org: acme' '---' > "$jc/company-profile.md"
printf '%s\n' "root=$jc" "me=carl" > "$work/join-answers"
set +e
jout=$(OS_FAKE_MY_STATE=pending "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" 2>&1)
jrc=$?
set -e
[ "$jrc" -eq 2 ] || team_fail "join with a pending invite exit was $jrc: $jout"
printf '%s\n' "$jout" | grep -qx 'invite: accept the org invite first: https://github.com/orgs/acme/invitation, then run join again' \
  || team_fail "join pending line: $jout"

printf '%s\n' "PASS argv"
