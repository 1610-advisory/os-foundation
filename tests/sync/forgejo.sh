#!/bin/bash
# Forgejo cases for sync. Token values are never printed.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
cache=${OSF_ACME_CACHE:-}
if [ -z "$cache" ]; then
  echo "FAIL: OSF_ACME_CACHE is not set" >&2
  exit 1
fi
url=${OSF_ACME_URL:-http://localhost:3300}
if ! curl -fsS --max-time 5 "$url/api/v1/version" >/dev/null; then
  echo "BLOCKED: Forgejo is not reachable" >&2
  exit 2
fi

HOST="$root/template/skills/_host/host.sh"
SYNC="$root/template/skills/sync/sync.sh"
ENGINE="$root/tests/fakes/engine.sh"
admin_token="$cache/tokens/acme-admin"
member_token="$cache/tokens/acme-member-a"
repos_file=$(mktemp)
sandbox=$(mktemp -d)
export HOME="$sandbox"
export XDG_CONFIG_HOME="$sandbox/.config"
export OS_TEST_MODE=1
export OS_SECRET_SCAN=bundled
export OS_SYNC_ENGINE="$ENGINE"
export OS_ENGINE_TIMEOUT=15
export OS_HOST_SH="$HOST"
export OS_PROFILE_SH="$root/template/skills/_host/profile.sh"
export GIT_AUTHOR_NAME="Mia Member"
export GIT_AUTHOR_EMAIL="mia.member@acme.test"
export GIT_COMMITTER_NAME="Mia Member"
export GIT_COMMITTER_EMAIL="mia.member@acme.test"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

as_admin() {
  cp "$admin_token" "$XDG_CONFIG_HOME/acme-os/forgejo-token"
  chmod 600 "$XDG_CONFIG_HOME/acme-os/forgejo-token"
}

as_member() {
  cp "$member_token" "$XDG_CONFIG_HOME/acme-os/forgejo-token"
  chmod 600 "$XDG_CONFIG_HOME/acme-os/forgejo-token"
}

cleanup() {
  if [ -f "$admin_token" ]; then
    as_admin || true
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      OS_PROFILE="$sandbox/cleanup-profile.md" "$HOST" delete-repo "$name" --yes-test-only >/dev/null 2>&1 || true
    done < "$repos_file"
  fi
  rm -rf "$sandbox" "$repos_file"
}
trap cleanup EXIT

mkdir -p "$XDG_CONFIG_HOME/acme-os"
chmod 700 "$XDG_CONFIG_HOME/acme-os"
printf '%s\n' mia > "$XDG_CONFIG_HOME/acme-os/me"
cat > "$sandbox/cleanup-profile.md" << EOF
---
company_slug: acme
host: forgejo
host_url: "${url}"
org: acme
---
EOF
as_admin

ask=$(mktemp)
chmod 700 "$ask"
cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF

git_as() {
  local who=$1
  shift
  local token user
  if [ "$who" = "admin" ]; then
    token=$(tr -d '\r\n' < "$admin_token")
    user=acme-admin
  else
    token=$(tr -d '\r\n' < "$member_token")
    user=acme-member-a
  fi
  OS_GIT_USER="$user" OS_GIT_TOKEN="$token" GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= "$@"
  token=""
}

write_profile() {
  local dir=$1
  local level=$2
  cat > "$dir/company-profile.md" << EOF
---
type: company-profile
summary: "Acme Co test"
updated: 2026-10-24
company_slug: acme
level: ${level}
switches: []
os_version: 0.0.0-test
host: forgejo
host_url: "${url}"
org: acme
sync_engine: ""
runner: ubuntu-latest
---

# Acme Co
EOF
}

write_person() {
  local dir=$1
  local github=$2
  mkdir -p "$dir/people"
  cat > "$dir/people/Mia.md" << EOF
---
type: person
slug: mia
github: ${github}
email: mia.member@acme.test
role: writer
---

# Mia Member
EOF
}

new_repo() {
  local name=$1
  as_admin
  export OS_PROFILE="$2"
  "$HOST" create-repo "$name" --private >/dev/null
  "$HOST" grant "$name" acme-member-a write >/dev/null
  printf '%s\n' "$name" >> "$repos_file"
  as_member
}

seed_repo() {
  local dir=$1
  local name=$2
  git init -q -b main "$dir"
  git -C "$dir" config user.name "Mia Member"
  git -C "$dir" config user.email "mia.member@acme.test"
  git -C "$dir" remote add origin "${url}/acme/${name}.git"
  if [ ! -f "$dir/README.md" ]; then
    printf '%s\n' seed > "$dir/README.md"
  fi
  git -C "$dir" add -A
  git -C "$dir" commit -q -m seed
  git_as member -C "$dir" push -q -u origin main
}

sync_env() {
  local dir=$1
  export OS_COMPANY_ROOT="$dir"
  export OS_PROFILE="$dir/company-profile.md"
}

say() {
  printf '%s\n' "CASE $*"
}

# --- clean push, holds, pull ---
say push-pull
company="$sandbox/acme"
mkdir -p "$company"
write_profile "$company" team
write_person "$company" acme-member-a
printf '%s\n' 'areas/' > "$company/.gitignore"
printf '%s\n' 'users/' >> "$company/.gitignore"
name="sync-t-$$-root"
new_repo "$name" "$company/company-profile.md"
seed_repo "$company" "$name"
mkdir -p "$company/notes"
printf '%s\n' "a shop note" > "$company/notes/ok.md"
printf '%s\n' "HOLD-ME please" > "$company/notes/held.md"
printf '%s\n' "PERSONAL-FACT about a family trip" > "$company/notes/life.md"
printf '%s\n' "PRIVATE-QUOTE from a DM" > "$company/notes/quote.md"
printf '%s\n' "token = $(printf '%s%s_' gh p)$(printf 'ab12%.0s' {1..9})" > "$company/notes/secret.md"
before=$(cksum "$company/notes/held.md")
sync_env "$company"
bash "$SYNC" push
log="$XDG_CONFIG_HOME/acme-os/state/sync.log"
grep -q "push ok root" "$log" || fail "push did not record ok"
grep -q "push hold root notes/held.md" "$log" || fail "held file was not held"
status=$(bash "$SYNC" status)
printf '%s\n' "$status" | grep -q "notes/held.md" || fail "status missing held file"
printf '%s\n' "$status" | grep -q "notes/secret.md" || fail "status missing secret"
printf '%s\n' "$status" | grep -q "personal-life fact" || fail "status missing personal fact"
printf '%s\n' "$status" | grep -q "private-source quote" || fail "status missing private quote"
case "$status" in
  *"$(printf '%s%s_' gh p)"*) fail "status printed a secret value" ;;
esac
after=$(cksum "$company/notes/held.md")
[ "$before" = "$after" ] || fail "held file changed"
git_as member -C "$company" fetch -q origin "refs/heads/sync/mia:refs/remotes/origin/sync/mia"
git -C "$company" cat-file -e origin/sync/mia:notes/ok.md || fail "ok note was not pushed"
if git -C "$company" cat-file -e origin/sync/mia:notes/held.md 2>/dev/null; then
  fail "held file was pushed"
fi
if git -C "$company" cat-file -e origin/sync/mia:notes/secret.md 2>/dev/null; then
  fail "secret was pushed"
fi
if git -C "$company" cat-file -e origin/sync/mia:notes/life.md 2>/dev/null; then
  fail "personal fact was pushed"
fi
# Pull request may still be open. Fast-forward main so the pull property can be checked.
git_as member -C "$company" push -q origin refs/remotes/origin/sync/mia:refs/heads/main
bash "$SYNC" pull
git -C "$company" diff --quiet HEAD -- notes/ok.md || fail "ok note is not clean after pull"
[ -f "$company/notes/held.md" ] || fail "held file missing after pull"
grep -q HOLD-ME "$company/notes/held.md" || fail "held file content changed"
git -C "$company" status --porcelain -- notes/held.md | grep -q . || fail "held file is not a local change"
printf '%s\n' "PASS push-pull"

# --- engine down ---
say engine-down
engdir="$sandbox/eng"
mkdir -p "$engdir"
write_profile "$engdir" team
write_person "$engdir" acme-member-a
ename="sync-t-$$-eng"
new_repo "$ename" "$engdir/company-profile.md"
seed_repo "$engdir" "$ename"
printf '%s\n' "ENGINE-FAIL" > "$engdir/bad.md"
sync_env "$engdir"
set +e
bash "$SYNC" push
erc=$?
set -e
[ "$erc" -ne 0 ] || fail "engine failure should not succeed"
git_as member -C "$engdir" ls-remote --heads origin > "$sandbox/eng-heads"
if grep -q "sync/mia" "$sandbox/eng-heads"; then
  fail "engine failure pushed a branch"
fi
grep -q "engine check failed" "$XDG_CONFIG_HOME/acme-os/state/sync.log" || fail "engine failure was not logged"
printf '%s\n' "PASS engine-down"

# --- network down ---
say network
netdir="$sandbox/net"
mkdir -p "$netdir"
write_profile "$netdir" team
write_person "$netdir" acme-member-a
nname="sync-t-$$-net"
new_repo "$nname" "$netdir/company-profile.md"
seed_repo "$netdir" "$nname"
printf '%s\n' "offline note" > "$netdir/offline.md"
git -C "$netdir" remote set-url origin "http://127.0.0.1:9/acme/${nname}.git"
sync_env "$netdir"
lines_before=$(wc -l < "$XDG_CONFIG_HOME/acme-os/state/sync.log" | tr -d ' ')
set +e
bash "$SYNC" push
nrc=$?
set -e
[ "$nrc" -ne 0 ] || fail "network failure should not succeed"
lines_after=$(wc -l < "$XDG_CONFIG_HOME/acme-os/state/sync.log" | tr -d ' ')
added=$((lines_after - lines_before))
[ "$added" -eq 1 ] || fail "network failure wrote $added log lines"
printf '%s\n' "PASS network"

# --- identity mismatch ---
say identity
iddir="$sandbox/id"
mkdir -p "$iddir"
write_profile "$iddir" team
write_person "$iddir" somebody-else
iname="sync-t-$$-id"
new_repo "$iname" "$iddir/company-profile.md"
seed_repo "$iddir" "$iname"
printf '%s\n' "should stay" > "$iddir/stay.md"
sync_env "$iddir"
set +e
bash "$SYNC" push
irc=$?
set -e
[ "$irc" -ne 0 ] || fail "identity mismatch should not succeed"
idstatus=$(bash "$SYNC" status)
printf '%s\n' "$idstatus" | grep -q "identity mismatch" || fail "status missing identity reason"
git_as member -C "$iddir" ls-remote --heads origin > "$sandbox/id-heads"
if grep -q "sync/mia" "$sandbox/id-heads"; then
  fail "identity mismatch pushed a branch"
fi
printf '%s\n' "PASS identity"

# --- rules and propose ---
say propose
rdir="$sandbox/rules"
mkdir -p "$rdir"
write_profile "$rdir" team
write_person "$rdir" acme-member-a
printf '%s\n' "# rules" > "$rdir/AGENTS.md"
rname="sync-t-$$-rules"
new_repo "$rname" "$rdir/company-profile.md"
seed_repo "$rdir" "$rname"
printf '%s\n' "# changed rules" > "$rdir/AGENTS.md"
sync_env "$rdir"
bash "$SYNC" push
rstatus=$(bash "$SYNC" status)
printf '%s\n' "$rstatus" | grep -q "rules file: propose it with sync.sh propose" || fail "rules reason mismatch"
git_as member -C "$rdir" fetch -q origin || true
if git -C "$rdir" cat-file -e origin/sync/mia:AGENTS.md 2>/dev/null; then
  # The seed AGENTS.md is on main. The sync branch must not contain the new text.
  if git -C "$rdir" show origin/sync/mia:AGENTS.md 2>/dev/null | grep -q "changed rules"; then
    fail "rules change was pushed on the standing branch"
  fi
fi
number=$(bash "$SYNC" propose rules-topic AGENTS.md)
case "$number" in
  ''|*[!0-9]*) fail "propose did not return a pull request number" ;;
esac
printf '%s\n' "PASS propose"

# --- workspace ---
say workspace
wroot="$sandbox/ws"
mkdir -p "$wroot/users/mia/profile" "$wroot/users/mia/drafts"
write_profile "$wroot" team
write_person "$wroot" acme-member-a
printf '%s\n' 'users/' > "$wroot/.gitignore"
cname="sync-t-$$-co"
new_repo "$cname" "$wroot/company-profile.md"
seed_repo "$wroot" "$cname"
wname="sync-t-$$-user"
as_admin
export OS_PROFILE="$wroot/company-profile.md"
"$HOST" create-repo "$wname" --private >/dev/null
"$HOST" grant "$wname" acme-member-a write >/dev/null
printf '%s\n' "$wname" >> "$repos_file"
as_member
printf '%s\n' "# profile" > "$wroot/users/mia/profile/PROFILE.md"
printf '%s\n' "seed" > "$wroot/users/mia/README.md"
seed_repo "$wroot/users/mia" "$wname"
printf '%s\n' "COMPANY-FACT the shop made 12 units" > "$wroot/users/mia/profile/PROFILE.md"
printf '%s\n' "a draft" > "$wroot/users/mia/drafts/note.md"
sync_env "$wroot"
bash "$SYNC" push
git_as member -C "$wroot/users/mia" fetch -q origin
git -C "$wroot/users/mia" cat-file -e origin/main:drafts/note.md || fail "workspace note was not pushed"
if git -C "$wroot/users/mia" show origin/main:profile/PROFILE.md | grep -q "COMPANY-FACT"; then
  fail "company fact in a profile was pushed"
fi
wstatus=$(bash "$SYNC" status)
printf '%s\n' "$wstatus" | grep -q "company fact in a profile" || fail "profile hold missing"
printf '%s\n' "PASS workspace"

# --- reclone ---
say reclone
rcdir="$sandbox/re"
mkdir -p "$rcdir/areas/shop"
write_profile "$rcdir" team
write_person "$rcdir" acme-member-a
printf '%s\n' 'areas/' > "$rcdir/.gitignore"
rcname="sync-t-$$-re"
new_repo "$rcname" "$rcdir/company-profile.md"
seed_repo "$rcdir" "$rcname"
git init -q -b main "$rcdir/areas/shop"
git -C "$rcdir/areas/shop" config user.email "mia.member@acme.test"
git -C "$rcdir/areas/shop" config user.name "Mia Member"
printf '%s\n' "area seed" > "$rcdir/areas/shop/keep.md"
git -C "$rcdir/areas/shop" add keep.md
git -C "$rcdir/areas/shop" commit -q -m seed
printf '%s\n' "keep this note" > "$rcdir/keep.md"
printf '%s\n' "token = $(printf '%s%s_' gh p)$(printf 'ab12%.0s' {1..9})" > "$rcdir/leak.md"
# Rewrite history on the host.
orphan="$sandbox/orphan"
git init -q -b main "$orphan"
git -C "$orphan" config user.email "ada.admin@acme.test"
git -C "$orphan" config user.name "Ada Admin"
printf '%s\n' "rewritten" > "$orphan/README.md"
git -C "$orphan" add README.md
git -C "$orphan" commit -q -m rewritten
git -C "$orphan" remote add origin "${url}/acme/${rcname}.git"
git_as admin -C "$orphan" push -q --force origin main
tagmsg="$sandbox/tagmsg"
printf '%s\n' "rule: github-pat" > "$tagmsg"
git -C "$orphan" tag -a "os-rewrite-20261024235959" -F "$tagmsg"
git_as admin -C "$orphan" push -q origin "refs/tags/os-rewrite-20261024235959"
sync_env "$rcdir"
bash "$SYNC" pull
[ -f "$rcdir/keep.md" ] || fail "reclone dropped a clean file"
[ ! -f "$rcdir/leak.md" ] || fail "reclone kept a leaked file"
[ -f "$rcdir/areas/shop/keep.md" ] || fail "reclone dropped a nested repo"
grep -q "pull reclone root" "$XDG_CONFIG_HOME/acme-os/state/sync.log" || fail "reclone was not logged"
grep -q "os-rewrite-20261024235959" "$XDG_CONFIG_HOME/acme-os/state/rewrite" || fail "rewrite tag was not recorded"
printf '%s\n' "PASS reclone"

printf '%s\n' "PASS forgejo"
