#!/bin/bash
# remove.sh clears the admin's private <slug>-library repo when it exists: it revokes a
# direct grant, cancels a pending invite, and says remove: ok only when user-access on it
# is none. GitHub: the real adapter with a fake gh. Forgejo: a stub host.sh.
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"
root=$(team_root)
team_need git jq
work=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT
[ -z "${KEEP:-}" ] || printf 'work=%s\n' "$work" >&2

# One company folder per host. Ada and Ben are admins; Mia is a member.
make_company() {
  local co=$1 host=$2
  mkdir -p "$co/people"
  cat > "$co/company-profile.md" << EOF
---
company_slug: acme
host: ${host}
host_url: "http://127.0.0.1:9"
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
  cat > "$co/people/Ben Admin.md" << 'EOF'
---
slug: ben
github: acme-admin-b
role: admin
left: ""
---
# Ben Admin
EOF
  cat > "$co/people/Mia Member.md" << 'EOF'
---
slug: mia
github: acme-member-m
role: writer
left: ""
manager: ada
---
# Mia Member
EOF
  printf '%s\n' "areas/" "/library/" > "$co/.gitignore"
  git -C "$co" init -q -b main
  git -C "$co" add -A
  git -C "$co" -c user.name=t -c user.email=t@example.test commit -q -m seed
  git init -q --bare "$co.origin.git"
  git -C "$co" remote add origin "$co.origin.git"
  git -C "$co" push -q origin main
}

run_remove() {
  local co=$1 person=$2 name=$3
  set +e
  "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person "$person" \
    --date 2026-10-30 > "$work/$name.out" 2> "$work/$name.err"
  rc=$?
  set -e
}

must_stop() {
  local name=$1 want=$2
  [ "$rc" -eq 3 ] || { cat "$work/$name.out" "$work/$name.err" >&2; team_fail "$name: exit $rc, want 3"; }
  grep -q '^revoked:' "$work/$name.out" && team_fail "$name: revoked: printed"
  grep -q 'remove: ok' "$work/$name.out" && team_fail "$name: remove: ok printed"
  grep -q "$want" "$work/$name.err" || team_fail "$name: missing '$want': $(cat "$work/$name.err")"
}

must_pass() {
  local name=$1
  [ "$rc" -eq 0 ] || { cat "$work/$name.out" "$work/$name.err" >&2; team_fail "$name: exit $rc"; }
  grep -qx 'remove: ok' "$work/$name.out" || team_fail "$name: missing remove: ok"
}

# ---- GitHub: the real adapter, a fake gh --------------------------------------------
co="$work/gh-co"
make_company "$co" github
mkdir -p "$work/gh-bin" "$work/gh-state0/repo" "$work/gh-state0/collab" "$work/gh-state0/team"
# Ben had a direct admin grant on the library. Mia never accepted her library invite.
printf '%s\n' '{"acme-admin":"admin","acme-admin-b":"admin"}' > "$work/gh-state0/collab/acme-library.json"
printf '%s\n' '[{"id":95,"invitee":{"login":"acme-member-m"},"permissions":"read"}]' \
  > "$work/gh-state0/repo/acme-library.json"
printf '%s\n' '[{"name":"acme-os"}]' > "$work/gh-state0/team/acme-company.json"

cat > "$work/gh-bin/gh" << 'EOF'
#!/bin/bash
method=GET
path=""
prev=""
for arg in "$@"; do
  case "$prev" in
    --method) method=$arg ;;
    --hostname) ;;
    *) case "$arg" in /*) path=$arg ;; esac ;;
  esac
  prev=$arg
done
printf '%s %s\n' "$method" "$path" >> "$FAKE_GH_LOG"
page=1
case "$path" in *page=*) page=${path##*page=} ;; esac
bare=${path%%\?*}
s=$FAKE_GH_STATE
not_found() {
  printf '%s\n' "gh: Not Found (HTTP 404)" >&2
  exit 1
}
case "$method $bare" in
  "GET /repos/acme/acme-library")
    [ -n "${FAKE_LIB_500:-}" ] && { printf '%s\n' "gh: Server Error (HTTP 500)" >&2; exit 1; }
    [ -n "${FAKE_NO_LIBRARY:-}" ] && not_found
    printf '%s\n' '{"name":"acme-library","private":true}'
    exit 0 ;;
  "GET /orgs/acme/invitations") printf '%s\n' '[]'; exit 0 ;;
  "GET /repos/acme/"*"/invitations")
    r=${bare#/repos/acme/}
    f="$s/repo/${r%%/*}.json"
    if [ "$page" != "1" ] || [ ! -f "$f" ]; then printf '%s\n' '[]'; else cat "$f"; fi
    exit 0 ;;
  "DELETE /repos/acme/"*"/invitations/"*)
    [ -n "${FAKE_KEEP:-}" ] && exit 0
    r=${bare#/repos/acme/}
    f="$s/repo/${r%%/*}.json"
    id=${bare##*/}
    [ -f "$f" ] && jq -e --argjson id "$id" 'any(.[]; .id == $id)' "$f" >/dev/null || not_found
    jq -c --argjson id "$id" 'map(select(.id != $id))' "$f" > "$f.new" && mv "$f.new" "$f"
    exit 0 ;;
  "GET /repos/acme/"*"/collaborators/"*"/permission")
    r=${bare#/repos/acme/}
    u=${bare#*/collaborators/}
    u=${u%/permission}
    f="$s/collab/${r%%/*}.json"
    [ -f "$f" ] || not_found
    p=$(jq -r --arg u "$u" '.[$u] // empty' "$f")
    [ -n "$p" ] || not_found
    printf '{"permission":"%s"}\n' "$p"
    exit 0 ;;
  "DELETE /repos/acme/"*"/collaborators/"*)
    [ -n "${FAKE_KEEP:-}" ] && exit 0
    r=${bare#/repos/acme/}
    u=${bare##*/}
    f="$s/collab/${r%%/*}.json"
    [ -f "$f" ] || not_found
    jq -c --arg u "$u" 'del(.[$u])' "$f" > "$f.new" && mv "$f.new" "$f"
    exit 0 ;;
  "GET /orgs/acme/memberships/"*|"DELETE /orgs/acme/members/"*|"DELETE /orgs/acme/teams/"*) not_found ;;
  "GET /orgs/acme/teams/"*"/repos")
    t=${bare#/orgs/acme/teams/}
    f="$s/team/${t%%/*}.json"
    if [ "$page" != "1" ] || [ ! -f "$f" ]; then printf '%s\n' '[]'; else cat "$f"; fi
    exit 0 ;;
  "GET /orgs/acme/teams/"*)
    [ -f "$s/team/${bare##*/}.json" ] && { printf '%s\n' '{}'; exit 0; }
    not_found ;;
esac
printf '%s\n' '{}'
EOF
chmod 700 "$work/gh-bin/gh"

# The real host layer, except the pull request and the git token.
cat > "$work/gh-bin/host.sh" << EOF
#!/bin/bash
case "\$1" in
  open-pr) printf '%s\n' '{"number":4,"url":"http://example.test/4"}'; exit 0 ;;
  get-token) printf '%s\n' local-token; exit 0 ;;
  whoami) printf '%s\n' '{"login":"acme-admin"}'; exit 0 ;;
esac
exec "$root/template/skills/_host/host.sh" "\$@"
EOF
chmod 700 "$work/gh-bin/host.sh"

gh_reset() {
  rm -rf "$work/gh-state"
  cp -R "$work/gh-state0" "$work/gh-state"
  : > "$FAKE_GH_LOG"
}
export FAKE_GH_STATE="$work/gh-state" FAKE_GH_LOG="$work/gh.log"
PATH0=$PATH
export PATH="$work/gh-bin:$PATH" OS_HOST_SH="$work/gh-bin/host.sh"

# 1. A removed admin with a direct grant: the grant goes, and only then remove: ok.
gh_reset
FAKE_KEEP=1 run_remove "$co" ben gh-keep-grant
must_stop gh-keep-grant 'acme-library (admin)'
gh_reset
run_remove "$co" ben gh-grant
must_pass gh-grant
grep -qx 'DELETE /repos/acme/acme-library/collaborators/acme-admin-b' "$FAKE_GH_LOG" \
  || team_fail "the library grant was not revoked"
[ "$(jq -c 'keys' "$FAKE_GH_STATE/collab/acme-library.json")" = '["acme-admin"]' ] \
  || team_fail "library collaborators left: $(cat "$FAKE_GH_STATE/collab/acme-library.json")"

# 2. A person with only a pending library invite: it is cancelled before remove: ok.
gh_reset
FAKE_KEEP=1 run_remove "$co" mia gh-keep-invite
must_stop gh-keep-invite 'acme-library (invited)'
gh_reset
run_remove "$co" mia gh-invite
must_pass gh-invite
grep -qx 'DELETE /repos/acme/acme-library/invitations/95' "$FAKE_GH_LOG" \
  || team_fail "the library invite was not cancelled"
[ "$(jq length "$FAKE_GH_STATE/repo/acme-library.json")" = "0" ] || team_fail "library invite still pending"

# 3. No library repo: nothing to clear, remove: ok.
gh_reset
FAKE_NO_LIBRARY=1 run_remove "$co" mia gh-none
must_pass gh-none
grep -q 'acme-library/' "$FAKE_GH_LOG" && team_fail "a missing library repo was cleared"

# 4. The host cannot say whether the library exists: not checked, never gone.
gh_reset
FAKE_LIB_500=1 run_remove "$co" mia gh-500
must_stop gh-500 'acme-library (not checked)'
export PATH=$PATH0

# ---- Forgejo: a stub host.sh ---------------------------------------------------------
# Forgejo adds collaborators directly (no invite), and an org remove keeps the row.
co="$work/fj-co"
make_company "$co" forgejo
mkdir -p "$work/fj-bin"
cat > "$work/fj-bin/host.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_HOST_LOG"
lib="$FAKE_FJ_STATE/library-collab"
case "$1" in
  repo-access)
    [ "$2" = "acme-library" ] && [ -n "${FAKE_NO_LIBRARY:-}" ] && { printf '%s\n' '{"access":"no-access"}'; exit 2; }
    printf '%s\n' '{"access":"ok"}' ;;
  revoke)
    if [ "$2" = "acme-library" ] && [ -z "${FAKE_KEEP:-}" ]; then
      grep -vx "$3" "$lib" > "$lib.new" || true
      mv "$lib.new" "$lib"
    fi
    printf '%s\n' '{"ok":true}' ;;
  user-access)
    if [ "$2" = "acme-library" ] && grep -qx "$3" "$lib"; then
      printf '%s\n' '{"access":"admin"}'
    else
      printf '%s\n' '{"access":"none"}'
    fi ;;
  team-repos) printf '%s\n' '{"repos":[]}' ;;
  org-membership) printf '%s\n' '{"state":"none"}' ;;
  invites) printf '%s\n' '{"invites":[]}' ;;
  open-pr) printf '%s\n' '{"number":4,"url":"http://example.test/4"}' ;;
  get-token) printf '%s\n' local-token ;;
  whoami) printf '%s\n' '{"login":"acme-admin"}' ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF
chmod 700 "$work/fj-bin/host.sh"
export FAKE_FJ_STATE="$work/fj-state" FAKE_HOST_LOG="$work/fj-host.log"
fj_reset() {
  mkdir -p "$FAKE_FJ_STATE"
  printf '%s\n' acme-admin acme-admin-b > "$FAKE_FJ_STATE/library-collab"
  : > "$FAKE_HOST_LOG"
}
export OS_HOST_SH="$work/fj-bin/host.sh"

fj_reset
FAKE_KEEP=1 run_remove "$co" ben fj-keep
must_stop fj-keep 'acme-library (admin)'
fj_reset
run_remove "$co" ben fj-grant
must_pass fj-grant
grep -qx 'revoke acme-library acme-admin-b' "$FAKE_HOST_LOG" || team_fail "forgejo: library grant not revoked"
grep -qx 'user-access acme-library acme-admin-b' "$FAKE_HOST_LOG" || team_fail "forgejo: library not checked"
[ "$(cat "$FAKE_FJ_STATE/library-collab")" = "acme-admin" ] || team_fail "forgejo: the other admin lost the library"

fj_reset
FAKE_NO_LIBRARY=1 run_remove "$co" ben fj-none
must_pass fj-none
grep -q '^revoke acme-library' "$FAKE_HOST_LOG" && team_fail "forgejo: a missing library repo was cleared"

printf '%s\n' "PASS remove library"
