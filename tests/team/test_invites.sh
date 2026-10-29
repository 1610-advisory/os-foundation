#!/bin/bash
# B30: remove.sh cancels pending invites for a person who never accepted, and says
# revoked: only when the org invite and every repo invite are gone. GitHub adapter, fake gh.
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"
root=$(team_root)
team_need git jq
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

co="$work/co"
mkdir -p "$co/people" "$co/areas/marketing" "$work/bin" "$work/state/repo"
cat > "$co/company-profile.md" << 'EOF'
---
company_slug: acme
host: github
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
printf '%s\n' "areas/" > "$co/.gitignore"
git -C "$co/areas/marketing" init -q -b main
git -C "$co" init -q -b main
git -C "$co" add -A
git -C "$co" -c user.name=t -c user.email=t@example.test commit -q -m seed
git init -q --bare "$work/origin.git"
git -C "$co" remote add origin "$work/origin.git"
git -C "$co" push -q origin main

# The person never accepted: one org invite, and write invites on the area and the workspace.
# Another person's invite must stay.
printf '%s\n' '[{"id":81,"login":"Acme-Member-M","role":"direct_member"},{"id":82,"login":"acme-other","role":"direct_member"}]' \
  > "$work/state/org.json"
printf '%s\n' '[{"id":91,"invitee":{"login":"acme-member-m"},"permissions":"write"}]' \
  > "$work/state/repo/acme-marketing.json"
printf '%s\n' '[{"id":92,"invitee":{"login":"acme-member-m"},"permissions":"write"}]' \
  > "$work/state/repo/acme-user-mia.json"
cp -R "$work/state" "$work/state0"

cat > "$work/bin/gh" << 'EOF'
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
list_file() {
  case "$1" in
    /orgs/acme/invitations*) printf '%s\n' "$FAKE_GH_STATE/org.json" ;;
    /repos/acme/*/invitations*)
      r=${1#/repos/acme/}
      printf '%s\n' "$FAKE_GH_STATE/repo/${r%%/*}.json" ;;
  esac
}
case "$method $bare" in
  "GET /orgs/acme/invitations"|"GET /repos/acme/"*"/invitations")
    f=$(list_file "$bare")
    if [ "$page" != "1" ] || [ ! -f "$f" ]; then printf '%s\n' '[]'; else cat "$f"; fi
    exit 0 ;;
  "DELETE /orgs/acme/invitations/"*|"DELETE /repos/acme/"*"/invitations/"*)
    [ -n "${FAKE_KEEP_INVITES:-}" ] && exit 0
    f=$(list_file "$bare")
    id=${bare##*/}
    if [ ! -f "$f" ] || ! jq -e --argjson id "$id" 'any(.[]; .id == $id)' "$f" >/dev/null; then
      printf '%s\n' "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    jq -c --argjson id "$id" 'map(select(.id != $id))' "$f" > "$f.new" && mv "$f.new" "$f"
    exit 0 ;;
  "GET /repos/acme/"*"/collaborators/"*"/permission")
    printf '%s\n' '{"permission":"none"}'
    exit 0 ;;
  "DELETE /orgs/acme/members/"*|"DELETE /orgs/acme/teams/"*)
    printf '%s\n' "gh: Cannot find acme-member-m (HTTP 404)" >&2
    exit 1 ;;
esac
printf '%s\n' '{}'
EOF
chmod 700 "$work/bin/gh"

# The real host layer, except the pull request and the git token.
cat > "$work/bin/host.sh" << EOF
#!/bin/bash
case "\$1" in
  open-pr) printf '%s\n' '{"number":4,"url":"http://example.test/4"}'; exit 0 ;;
  get-token) printf '%s\n' local-token; exit 0 ;;
  whoami) printf '%s\n' '{"login":"acme-admin"}'; exit 0 ;;
esac
exec "$root/template/skills/_host/host.sh" "\$@"
EOF
chmod 700 "$work/bin/host.sh"

export FAKE_GH_STATE="$work/state" FAKE_GH_LOG="$work/gh.log"
export PATH="$work/bin:$PATH" OS_HOST_SH="$work/bin/host.sh"
: > "$FAKE_GH_LOG"

# 1. Invites that will not cancel: no revoked:, no ok, and each one is named.
set +e
FAKE_KEEP_INVITES=1 "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/keep.out" 2> "$work/keep.err"
rc=$?
set -e
[ "$rc" -eq 3 ] || { cat "$work/keep.out" "$work/keep.err" >&2; team_fail "kept invites: exit $rc, want 3"; }
grep -q '^revoked:' "$work/keep.out" && team_fail "revoked: printed while invites are pending"
grep -q 'remove: ok' "$work/keep.out" && team_fail "remove: ok printed while invites are pending"
grep -q 'org (invited)' "$work/keep.err" || team_fail "pending org invite was not named"
grep -q 'acme-marketing (invited)' "$work/keep.err" || team_fail "pending area invite was not named"
grep -q 'acme-user-mia (invited)' "$work/keep.err" || team_fail "pending workspace invite was not named"
grep -q 'PATCH /repos/acme/acme-user-mia$' "$FAKE_GH_LOG" && team_fail "workspace archived before access was gone"

# 2. The real run cancels every invite for the person, and only theirs.
: > "$FAKE_GH_LOG"
set +e
"$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/rm.out" 2> "$work/rm.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/rm.out" "$work/rm.err" >&2; team_fail "remove exit $rc"; }
grep -qx 'revoked: mia' "$work/rm.out" || team_fail "missing revoked:"
grep -qx 'remove: ok' "$work/rm.out" || team_fail "missing remove: ok"
# B31: the offboard pull request merges by itself, like propose.
grep -qx 'auto-merge: on' "$work/rm.out" || team_fail "offboard PR has no auto-merge: $(cat "$work/rm.out")"
for want in "DELETE /orgs/acme/invitations/81" "DELETE /repos/acme/acme-marketing/invitations/91" \
  "DELETE /repos/acme/acme-user-mia/invitations/92"; do
  grep -qx "$want" "$FAKE_GH_LOG" || team_fail "not called: $want"
done
grep -q 'invitations/82' "$FAKE_GH_LOG" && team_fail "another person's invite was cancelled"
[ "$(jq -c '[.[].id]' "$work/state/org.json")" = "[82]" ] || team_fail "org invites left: $(cat "$work/state/org.json")"
[ "$(jq length "$work/state/repo/acme-marketing.json")" = "0" ] || team_fail "area invite still pending"
[ "$(jq length "$work/state/repo/acme-user-mia.json")" = "0" ] || team_fail "workspace invite still pending"

# 3. A second cancel is fine: nothing pending is success.
export OS_PROFILE="$co/company-profile.md"
out=$("$root/template/skills/_host/host.sh" cancel-invites acme-member-m acme-marketing)
[ "$(printf '%s' "$out" | jq -r '.cancelled')" = "0" ] || team_fail "second cancel: $out"
out=$("$root/template/skills/_host/host.sh" user-access acme-marketing acme-member-m)
[ "$(printf '%s' "$out" | jq -r '.access')" = "none" ] || team_fail "user-access after cancel: $out"
cp "$work/state0/repo/acme-marketing.json" "$work/state/repo/acme-marketing.json"
out=$("$root/template/skills/_host/host.sh" user-access acme-marketing acme-member-m)
[ "$(printf '%s' "$out" | jq -r '.access')" = "invited" ] || team_fail "a pending invite is not access: $out"

printf '%s\n' "PASS invites"
