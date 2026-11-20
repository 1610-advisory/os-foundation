#!/bin/bash
# team-on checks two GitHub org settings: base permission and member repo creation.
# An org owner in the company's own org gets them locked. Anyone else gets the settings
# path. The real GitHub adapter runs against a fake gh. team-on stops at the teams step:
# the fake gh does not answer it, and this test needs only the org settings lines.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
team_need git jq
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cp "$root/tests/host/fake-gh-state.sh" "$work/bin/gh"
chmod 700 "$work/bin/gh"

company="$work/company"
mkdir -p "$company"
cat > "$company/company-profile.md" << 'EOF'
---
type: company-profile
company_slug: acme
level: solo
switches: []
host: none
---

# Acme Co
EOF

answers="$work/answers"
cat > "$answers" << EOF
root=$company
host=github
org=acme
sync_engine=true
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.role=admin
person.ada.areas=
EOF

PAGE="https://github.com/organizations/acme/settings/member_privileges"
ASK="org settings: ask an org owner to set Base permissions to \"No permission\" and turn off repository creation for members: ${PAGE}"
LOCKED="org settings: base permission none, members cannot make repos (was: read, on)"

export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
mkdir -p "$HOME"
unset OS_HOST_SH OS_HOST_BIN GH_TOKEN GITHUB_TOKEN

# One fresh fake org per case. Flags: base, member-repos, role, repos, extra files.
fresh() {
  rm -rf "$work/gh"
  mkdir -p "$work/gh"
  printf '%s\n' "repo, admin:org, workflow" > "$work/gh/scopes"
  printf '%s\n' "team" > "$work/gh/plan"
}

run_on() {
  local file=${1:-$answers}
  set +e
  PATH="$work/bin:$PATH" FAKE_GH_DIR="$work/gh" \
    "$root/template/skills/add-teammate/team-on.sh" --answers "$file" >"$work/out" 2>"$work/err"
  set -e
}

patched() {
  grep -q -- '--method PATCH.* orgs/acme$' "$work/gh/gh.log"
}

# Owner, own org, open settings: locked, with the old values in the line.
fresh
printf '%s\n' read > "$work/gh/base"
printf '%s\n' true > "$work/gh/member-repos"
printf '%s\n' admin > "$work/gh/role"
printf '%s\n' acme-os acme-marketing acme-user-ada acme-library > "$work/gh/repos"
run_on
grep -qxF "$LOCKED" "$work/out" || { cat "$work/out" "$work/err" >&2; team_fail "owner: no lock line"; }
grep -qxF "$ASK" "$work/out" && team_fail "owner: path line after a good lock"
patched || team_fail "owner: org-lock did not PATCH the org"
[ "$(jq -cS . "$work/gh/last-input")" = '{"default_repository_permission":"none","members_can_create_repositories":false}' ] \
  || team_fail "org-lock body: $(cat "$work/gh/last-input")"
grep -q 'private' "$work/gh/last-input" && team_fail "org-lock sent a private-only field"
# The org settings come before the teams step, the first place team-on can stop.
grep -q 'could not read the teams on the host' "$work/err" || { cat "$work/err" >&2; team_fail "team-on did not reach the teams step"; }

# A second run: already locked. One ok line, no PATCH.
: > "$work/gh/gh.log"
run_on
grep -qx 'org settings: ok' "$work/out" || { cat "$work/out" >&2; team_fail "locked: no ok line"; }
patched && team_fail "locked: team-on sent a PATCH"

# Not an owner: GitHub hides the settings. The path line, no PATCH.
fresh
printf '%s\n' member > "$work/gh/role"
run_on
grep -qxF "$ASK" "$work/out" || { cat "$work/out" >&2; team_fail "not owner: no path line"; }
patched && team_fail "not owner: team-on sent a PATCH"

# The org's own .github repo (profile and defaults) does not block the lock.
fresh
printf '%s\n' read > "$work/gh/base"
printf '%s\n' true > "$work/gh/member-repos"
printf '%s\n' admin > "$work/gh/role"
printf '%s\n' .github acme-os acme-sales > "$work/gh/repos"
run_on
grep -qxF "$LOCKED" "$work/out" || { cat "$work/out" "$work/err" >&2; team_fail ".github repo: no lock line"; }
patched || team_fail ".github repo: org-lock did not PATCH the org"

# An org with another company's repo: not the company's own. The path line, no PATCH.
fresh
printf '%s\n' read > "$work/gh/base"
printf '%s\n' true > "$work/gh/member-repos"
printf '%s\n' admin > "$work/gh/role"
printf '%s\n' acme-os other-site > "$work/gh/repos"
run_on
grep -qxF "$ASK" "$work/out" || { cat "$work/out" >&2; team_fail "foreign repo: no path line"; }
patched && team_fail "foreign repo: team-on sent a PATCH"

# org_own: no in the answers: the path line, no PATCH, even for an owner.
fresh
printf '%s\n' read > "$work/gh/base"
printf '%s\n' true > "$work/gh/member-repos"
printf '%s\n' admin > "$work/gh/role"
printf '%s\n' acme-os > "$work/gh/repos"
{ cat "$answers"; printf '%s\n' "org_own=no"; } > "$work/answers-no"
run_on "$work/answers-no"
grep -qxF "$ASK" "$work/out" || { cat "$work/out" >&2; team_fail "org_own no: no path line"; }
patched && team_fail "org_own no: team-on sent a PATCH"

# org-lock refused: team-on goes on and prints the path line.
fresh
printf '%s\n' read > "$work/gh/base"
printf '%s\n' true > "$work/gh/member-repos"
printf '%s\n' admin > "$work/gh/role"
touch "$work/gh/org-lock-denied"
run_on
grep -qxF "$LOCKED" "$work/out" || { cat "$work/out" >&2; team_fail "refused: no lock line"; }
grep -qxF "$ASK" "$work/out" || { cat "$work/out" >&2; team_fail "refused: no path line"; }
grep -q 'could not read the teams on the host' "$work/err" || { cat "$work/err" >&2; team_fail "refused: team-on stopped at org-lock"; }

printf '%s\n' "PASS org settings"
