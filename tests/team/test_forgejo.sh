#!/bin/bash
# Team scripts against the local Acme Forgejo. Never print a token or a secret.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
team_need git jq curl python3

if ! curl -fsS --max-time 5 http://localhost:3300/api/v1/version >/dev/null 2>&1; then
  printf '%s\n' "BLOCKED forgejo is not up"
  exit 0
fi

token_dir="${HOME}/.cache/os-foundation/forgejo/tokens"
admin_token="$token_dir/acme-admin"
[ -s "$admin_token" ] || team_fail "admin token file is missing"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
log="$work/log"
: > "$log"

scrub() {
  python3 "$root/tests/acme/lib/scrub.py" --secrets-dir "${HOME}/.cache/os-foundation/forgejo" "$1" >&2 || true
}

die() {
  printf 'FAIL: %s\n' "$1" >&2
  if [ -s "$log" ]; then
    scrub "$log"
  fi
  exit 1
}

HOST="$root/template/skills/_host/host.sh"
[ -f "$HOST" ] || die "host.sh is not in this tree"

export OS_HOST_SH="$HOST"
export GIT_TERMINAL_PROMPT=0
export OS_HOST=forgejo
export OS_HOST_URL="http://localhost:3300"
export OS_ORG=acme
export OS_SLUG=team
export OS_TEST_MODE=1

load_token() {
  local file=$1
  tr -d '[:space:]' < "$file"
}

export FORGEJO_TOKEN
FORGEJO_TOKEN=$(load_token "$admin_token")

# Drop repos from an earlier run. Ignore missing repos.
for name in team-os team-marketing team-finance team-leak \
  team-user-ada team-user-dana team-user-mia team-user-max \
  team-user-noa team-user-sam team-user-lee; do
  "$HOST" delete-repo "$name" --yes-test-only >/dev/null 2>>"$log" || true
done

# Synced-folder refusal, before any host call that matters.
sync_home="$work/sync-home"
mkdir -p "$sync_home/Dropbox/acme"
printf '%s\n' "---" > "$sync_home/Dropbox/acme/company-profile.md"
printf '%s\n' "company_slug: team" >> "$sync_home/Dropbox/acme/company-profile.md"
cat > "$work/sync-answers" << EOF
root=$sync_home/Dropbox/acme
host=forgejo
host_url=http://localhost:3300
org=acme
sync_engine=true
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.role=admin
person.ada.areas=marketing
EOF
set +e
HOME="$sync_home" "$root/template/skills/add-teammate/team-on.sh" --answers "$work/sync-answers" >"$work/sync.out" 2>>"$log"
rc=$?
set -e
[ "$rc" -eq 2 ] || die "synced folder was not refused"

company="$work/acme"
mkdir -p "$company"
cp -R "$root/template/." "$company/"
# Fill the slug. Leave other template text. This folder is not the public repo.
python3 - << PY
from pathlib import Path
p = Path("$company/company-profile.md")
text = p.read_text()
text = text.replace("{{COMPANY_SLUG}}", "team")
text = text.replace("{{COMPANY_NAME}}", "Acme Co")
text = text.replace("{{DATE}}", "2026-10-24")
text = text.replace("{{ONE_LINER}}", "A test company")
text = text.replace("{{OS_VERSION}}", "v1.0.0")
p.write_text(text)
PY

mkdir -p "$company/areas/marketing" "$company/areas/finance" "$company/bots/helper"
printf '%s\n' "# Marketing" > "$company/areas/marketing/AGENTS.md"
printf '%s\n' "# Finance" > "$company/areas/finance/AGENTS.md"
cat > "$company/bots/helper/BOT.md" << 'EOF'
---
type: bot
owner: sam
---

# Helper
EOF
cat > "$company/architecture.md" << 'EOF'
# Architecture

## Connections

- Chat vendor seat
- Books vendor seat
EOF

git_id() {
  GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
    GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
    "$@"
}
init_repo() {
  local dir=$1
  git -C "$dir" init -q
  git -C "$dir" checkout -q -b main
  git_id git -C "$dir" add -A
  git_id git -C "$dir" commit -q -m "start"
}
init_repo "$company"
init_repo "$company/areas/marketing"
init_repo "$company/areas/finance"

at='@'
answers="$work/answers"
cat > "$answers" << EOF
root=$company
host=forgejo
host_url=http://localhost:3300
org=acme
sync_engine=true
runner=ubuntu-latest
company_name=Acme Co
review_vendor=xai
review_kind=second-vendor
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.email=ada${at}acme.test
person.ada.role=admin
person.ada.areas=marketing,finance
person.dana.name=Dana Director
person.dana.github=acme-director
person.dana.email=dana${at}acme.test
person.dana.role=director
person.dana.areas=marketing
person.mia.name=Mia Member
person.mia.github=acme-member-a
person.mia.email=mia${at}acme.test
person.mia.role=writer
person.mia.areas=marketing
person.max.name=Max Member
person.max.github=acme-member-b
person.max.email=max${at}acme.test
person.max.role=writer
person.max.areas=marketing
person.noa.name=Noa Member
person.noa.github=acme-member-c
person.noa.email=noa${at}acme.test
person.noa.role=writer
person.noa.areas=finance
person.sam.name=Sam Member
person.sam.github=acme-member-d
person.sam.email=sam${at}acme.test
person.sam.role=writer
person.sam.areas=finance
person.sam.manager=ada
area.marketing.director=dana
area.finance.director=ada
EOF

export HOME="$work/admin-home" XDG_CONFIG_HOME="$work/admin-home/.config"
mkdir -p "$HOME"
export OS_PROFILE="$company/company-profile.md"
printf '%s\n' "step: team-on" >&2
if ! "$root/template/skills/add-teammate/team-on.sh" --answers "$answers" >"$work/team-on.out" 2>>"$log"; then
  cat "$work/team-on.out" >> "$log"
  die "team-on failed"
fi
grep -q 'team-on: ok' "$work/team-on.out" || die "team-on did not report ok"
grep -q 'level: team' "$work/team-on.out" || die "level not reported"
grep -q 'no review key: every pull request fails the model review until you add one' "$work/team-on.out" || die "no-key sentence missing"
grep -q '^kind=second-vendor$' "$company/.github/review.conf" || die "review.conf missing"
grep -q '^vendor=xai$' "$company/.github/review.conf" || die "review vendor missing"
grep -q '^kind=second-vendor$' "$company/areas/marketing/.github/review.conf" || die "area review.conf missing"
grep -q '^review:' "$company/company-profile.md" && die "profile must not hold a review line"
grep -q 'review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY' "$work/team-on.out" || die "review command missing"
grep -q '^level: team$' "$company/company-profile.md" || die "profile level not team"
grep -q 'hand-off: mia' "$work/team-on.out" || die "missing hand-off"
grep -q 'http://localhost:3300/acme/team-os' "$work/team-on.out" || die "hand-off missing repo URL"

# Fresh repo path: origin is the host clone URL on the company, each area, and each workspace.
assert_origin() {
  local dir=$1 name=$2 got
  got=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
  [ "$got" = "http://localhost:3300/acme/${name}.git" ] || die "origin for $name is '${got}'"
}
assert_origin "$company" team-os
assert_origin "$company/areas/marketing" team-marketing
assert_origin "$company/areas/finance" team-finance
for slug in ada dana mia max noa sam; do
  [ -d "$company/users/$slug/.git" ] || die "workspace $slug missing"
  assert_origin "$company/users/$slug" "team-user-$slug"
done
grep -q 'CODEOWNERS' "$company/.github/CODEOWNERS" || true
grep -q '@acme-admin' "$company/.github/CODEOWNERS" || die "company CODEOWNERS missing admin"
grep -F -q '/.gitea/ @acme-admin' "$company/.github/CODEOWNERS" || die "company CODEOWNERS does not own .gitea"
grep -F -q '^AGENTS\.md$ @acme-admin' "$company/.gitea/CODEOWNERS" || die "company Forgejo CODEOWNERS missing"
grep -F -q '^\.gitea/.* @acme-admin' "$company/.gitea/CODEOWNERS" || die "company Forgejo CODEOWNERS does not own itself"
grep -q '@acme-director' "$company/areas/marketing/.github/CODEOWNERS" || die "area CODEOWNERS missing director"
grep -q '@acme-admin' "$company/areas/marketing/.github/CODEOWNERS" || die "area CODEOWNERS missing admin"
grep -F -q '/.gitea/ @acme-director @acme-admin' "$company/areas/marketing/.github/CODEOWNERS" || die "area CODEOWNERS does not own .gitea"
grep -F -q '^skills/.* @acme-director @acme-admin' "$company/areas/marketing/.gitea/CODEOWNERS" || die "area Forgejo CODEOWNERS missing"
[ -f "$company/people/Mia Member.md" ] || die "people page missing"
grep -q '^slug: mia$' "$company/people/Mia Member.md" || die "people slug missing"

# Member cannot read finance or another workspace. Admin can read a workspace.
access() {
  local token_file=$1 repo=$2
  local rc
  set +e
  FORGEJO_TOKEN=$(load_token "$token_file") "$HOST" repo-access "$repo" >/dev/null 2>>"$log"
  rc=$?
  set -e
  return "$rc"
}
if access "$token_dir/acme-member-a" team-finance; then
  die "member-a can read finance"
fi
if access "$token_dir/acme-member-a" team-user-sam; then
  die "member-a can read sam workspace"
fi
access "$token_dir/acme-admin" team-user-mia || die "admin cannot read a workspace"
access "$token_dir/acme-member-a" team-marketing || die "member-a cannot read marketing"
access "$token_dir/acme-member-a" team-os || die "member-a cannot read the company repo"

# Protected main rejects a direct push. Use the helper so git does not wait on the keychain.
# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"
export OS_HOST_BIN="$HOST"
printf '%s\n' "x" >> "$company/README.md"
git_id git -C "$company" add README.md
git_id git -C "$company" commit -q -m "should not land"
set +e
FORGEJO_TOKEN=$(load_token "$admin_token") os_with_git_token git -C "$company" push origin main >"$work/push.out" 2>>"$log"
push_rc=$?
set -e
[ "$push_rc" -ne 0 ] || die "push to protected main succeeded"
git -C "$company" reset -q --hard HEAD~1

# Existing repo and a folder with no origin: add the remote and fetch. Do not push main.
host_main=$(git -C "$company" rev-parse origin/main)
area_main=$(git -C "$company/areas/marketing" rev-parse origin/main)
git -C "$company" remote remove origin
git -C "$company/areas/marketing" remote remove origin
git -C "$company/areas/finance" remote remove origin
for slug in ada dana mia max noa sam; do
  git -C "$company/users/$slug" remote remove origin
done
before=$(git -C "$company" rev-parse HEAD)
FORGEJO_TOKEN=$(load_token "$admin_token") \
  "$root/template/skills/add-teammate/team-on.sh" --answers "$answers" >"$work/team-on2.out" 2>>"$log" || die "second team-on failed"
after=$(git -C "$company" rev-parse HEAD)
[ "$before" = "$after" ] || die "second team-on moved main"
assert_origin "$company" team-os
assert_origin "$company/areas/marketing" team-marketing
assert_origin "$company/areas/finance" team-finance
for slug in ada dana mia max noa sam; do
  assert_origin "$company/users/$slug" "team-user-$slug"
done
[ "$(git -C "$company" rev-parse origin/main)" = "$host_main" ] || die "second team-on pushed company main"
[ "$(git -C "$company/areas/marketing" rev-parse origin/main)" = "$area_main" ] || die "second team-on pushed area main"

printf '%s\n' "step: join" >&2
# Join for member-a in a sandbox home.
join_home="$work/join-home"
mkdir -p "$join_home/.claude" "$join_home/.codex" "$join_home/.pi/agent" "$join_home/.cursor"
printf '%s\n' "keep this line" > "$join_home/.claude/CLAUDE.md"
printf '%s\n' "keep codex" > "$join_home/.codex/AGENTS.md"
printf '%s\n' "keep pi" > "$join_home/.pi/agent/AGENTS.md"
printf '%s\n' "keep cursor" > "$join_home/.cursor/rules.md"
clone="$work/mia"
mkdir -p "$clone"
FORGEJO_TOKEN=$(load_token "$token_dir/acme-member-a")
os_with_git_token git clone "http://localhost:3300/acme/team-os.git" "$clone" >>"$log" 2>&1 || die "member-a clone failed"
cat > "$work/join-answers" << EOF
root=$clone
me=mia
areas=marketing,finance
EOF
export HOME="$join_home" XDG_CONFIG_HOME="$join_home/.config" OS_JOBS_DIR="$join_home/jobs"
if ! FORGEJO_TOKEN=$(load_token "$token_dir/acme-member-a") \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" >"$work/join.out" 2>"$work/join.err"; then
  cat "$work/join.out" "$work/join.err" >> "$log"
  die "join failed"
fi
cat "$work/join.err" >> "$log"
grep -q 'company-clone: done' "$work/join.out" || die "join recloned or missed the company"
grep -q 'cloned: team-marketing' "$work/join.out" || die "marketing was not cloned"
grep -q 'skipped: team-finance' "$work/join.out" || die "finance was not skipped"
grep -q 'cloned: team-user-mia' "$work/join.out" || die "workspace was not cloned"
grep -q 'terms: proposed' "$work/join.out" || die "terms were not proposed"
if grep -q 'propose refused' "$work/join.out" "$work/join.err"; then
  die "join printed propose refused"
fi
git -C "$clone" rev-parse --verify --quiet origin/sync/mia >/dev/null || die "sync branch missing"
git -C "$clone" log -1 --format=%s origin/sync/mia | grep -q 'Join: accept terms' || die "terms commit is not on the sync branch"
page=$(os_person_file "$clone" mia)
[ -n "$page" ] || die "people page missing"
rel=${page#"$clone/"}
git -C "$clone" show "origin/sync/mia:$rel" | grep -q '^terms_accepted: ' || die "terms date is not on the sync branch"
number=$(awk '/^pr: / { print $2; exit }' "$work/join.out")
[ -n "$number" ] || die "terms PR was not opened"
head_ref=$(python3 - "$token_dir/acme-member-a" "$number" << 'PY'
import json, sys, urllib.request
token = open(sys.argv[1], encoding="utf-8").read().strip()
url = "http://localhost:3300/api/v1/repos/acme/team-os/pulls/" + sys.argv[2]
req = urllib.request.Request(url, headers={"Authorization": "token " + token})
with urllib.request.urlopen(req, timeout=10) as resp:
    data = json.load(resp)
print(data.get("head", {}).get("ref", ""))
PY
)
[ "$head_ref" = "sync/mia" ] || die "terms PR head is not the sync branch"
grep -qxF 'keep this line' "$join_home/.claude/CLAUDE.md" || die "claude config was overwritten"
grep -q "@$clone/users/mia/profile/PROFILE.md" "$join_home/.claude/CLAUDE.md" || die "claude pointer missing"
grep -q "Read $clone/users/mia/profile/PROFILE.md" "$join_home/.codex/AGENTS.md" || die "codex pointer missing"
grep -q "Read $clone/users/mia/profile/PROFILE.md" "$join_home/.pi/agent/AGENTS.md" || die "pi pointer missing"
grep -q "Read $clone/users/mia/profile/PROFILE.md" "$join_home/.cursor/rules.md" || die "cursor pointer missing"
[ "$(tr -d '[:space:]' < "$join_home/.config/team-os/me")" = "mia" ] || die "me file wrong"
# Second join does not add a second pointer line.
FORGEJO_TOKEN=$(load_token "$token_dir/acme-member-a") \
  "$root/template/skills/add-teammate/join.sh" --answers "$work/join-answers" >"$work/join2.out" 2>>"$log" || die "second join failed"
lines=$(grep -c "@$clone/users/mia/profile/PROFILE.md" "$join_home/.claude/CLAUDE.md" || true)
[ "$lines" -eq 1 ] || die "profile pointer was duplicated"

printf '%s\n' "step: add-person" >&2
# Add one person. Use the bot seat as the new account.
export HOME="$work/admin-home" XDG_CONFIG_HOME="$work/admin-home/.config"
FORGEJO_TOKEN=$(load_token "$admin_token")
cat > "$work/add-answers" << EOF
root=$company
person.lee.name=Lee Member
person.lee.github=acme-bot
person.lee.email=lee${at}acme.test
person.lee.role=writer
person.lee.areas=marketing
EOF
if ! "$root/template/skills/add-teammate/add-person.sh" --answers "$work/add-answers" >"$work/add.out" 2>>"$log"; then
  cat "$work/add.out" >> "$log"
  die "add-person failed"
fi
grep -q 'add-person: ok' "$work/add.out" || die "add-person did not report ok"
grep -q 'workspace: team-user-lee' "$work/add.out" || die "add-person workspace missing"
access "$token_dir/acme-bot" team-user-lee || die "new person cannot read their workspace"
access "$token_dir/acme-member-a" team-user-lee && die "member-a can read the new workspace"

printf '%s\n' "step: remove" >&2
# Remove member-d.
if ! FORGEJO_TOKEN=$(load_token "$admin_token") \
  "$root/template/skills/remove-teammate/remove.sh" --root "$company" --person sam --date 2026-10-24 \
  >"$work/remove.out" 2>>"$log"; then
  cat "$work/remove.out" >> "$log"
  die "remove failed"
fi
grep -q 'remove: ok' "$work/remove.out" || die "remove did not report ok"
grep -q 'left: 2026-10-24' "$work/remove.out" || die "left date missing"
grep -q 'archived: team-user-sam' "$work/remove.out" || die "workspace not archived"
grep -q 'bot-owner: ada' "$work/remove.out" || die "bot owner not moved"
grep -q 'phi: app-level-not-in-v1' "$work/remove.out" || die "phi note missing"
grep -q 'seat: Chat vendor seat' "$work/remove.out" || die "vendor checklist missing"
if access "$token_dir/acme-member-d" team-os; then
  die "removed member can still read the company repo"
fi
if access "$token_dir/acme-member-d" team-finance; then
  die "removed member can still read finance"
fi
FORGEJO_TOKEN=$(load_token "$admin_token") \
  os_with_git_token git -C "$company" fetch origin "rules/ada/offboard-sam" >>"$log" 2>&1 || die "offboard branch missing"
git -C "$company" show "origin/rules/ada/offboard-sam:people/Sam Member.md" | grep -q '^left: 2026-10-24$' || die "left not on the branch"
git -C "$company" show "origin/rules/ada/offboard-sam:bots/helper/BOT.md" | grep -q '^owner: ada$' || die "bot owner not on the branch"

# Last admin cannot be removed.
set +e
FORGEJO_TOKEN=$(load_token "$admin_token") \
  "$root/template/skills/remove-teammate/remove.sh" --root "$company" --person ada >"$work/last.out" 2>>"$log"
rc=$?
set -e
[ "$rc" -eq 2 ] || die "last admin removal was not refused"

printf '%s\n' "step: leak" >&2
# Leak rewrite on an unprotected repo. The secret is generated here and never printed.
leak="$work/leak"
mkdir -p "$leak"
git -C "$leak" init -q
git -C "$leak" checkout -q -b main
secret=$(python3 -c 'import secrets; print("token=" + secrets.token_hex(8))')
printf '%s\n' "$secret" > "$leak/note.md"
chmod 600 "$leak/note.md"
git_id git -C "$leak" add note.md
git_id git -C "$leak" commit -q -m "plant"
FORGEJO_TOKEN=$(load_token "$admin_token")
"$HOST" create-repo team-leak --private --source "$leak" --push >>"$log" 2>&1 || die "could not create leak repo"
"$HOST" protect team-leak --code-owners --approvals 0 >>"$log" 2>&1 || die "could not protect leak repo"
needle="$work/needle"
printf '%s' "$secret" > "$needle"
chmod 600 "$needle"
secret=""
if ! FORGEJO_TOKEN=$(load_token "$admin_token") \
  "$root/template/skills/remove-leak/remove-leak.sh" --root "$company" --repo team-leak --path note.md \
  >"$work/leak.out" 2>>"$log"; then
  cat "$work/leak.out" >> "$log"
  die "remove-leak failed"
fi
grep -q 'remove-leak: ok' "$work/leak.out" || die "remove-leak did not report ok"
grep -q 'tag: os-rewrite-' "$work/leak.out" || die "rewrite tag missing"
if grep -F -q -f "$needle" "$work/leak.out" "$log"; then
  die "secret was printed"
fi
fresh="$work/fresh"
FORGEJO_TOKEN=$(load_token "$admin_token")
os_with_git_token git clone "http://localhost:3300/acme/team-leak.git" "$fresh" >>"$log" 2>&1 || die "fresh clone failed"
if git -C "$fresh" grep -F -q -f "$needle" "$(git -C "$fresh" rev-list --all)" 2>/dev/null; then
  die "secret still in history"
fi
FORGEJO_TOKEN=$(load_token "$admin_token") \
  os_with_git_token git -C "$fresh" ls-remote --tags origin | grep -q 'os-rewrite-' || die "tag not on the host"

# Cleanup. Never wipe the volume.
FORGEJO_TOKEN=$(load_token "$admin_token")
for name in team-os team-marketing team-finance team-leak \
  team-user-ada team-user-dana team-user-mia team-user-max \
  team-user-noa team-user-sam team-user-lee; do
  "$HOST" delete-repo "$name" --yes-test-only >/dev/null 2>>"$log" || true
done

printf '%s\n' "PASS forgejo"
