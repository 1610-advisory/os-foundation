#!/bin/bash
# B30: remove.sh cancels pending invites for a person who never accepted, and says
# revoked: only when the org invite and every repo invite are gone. GitHub adapter, fake gh.
# Round 2: a list error is not checked (62), an area not checked out here still counts (63),
# org membership is read again (64), and a bots/ change gets no auto-merge (65).
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"
root=$(team_root)
team_need git jq
work=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT
[ -z "${KEEP:-}" ] || printf 'work=%s\n' "$work" >&2

co="$work/co"
mkdir -p "$co/people" "$co/areas/marketing" "$work/bin" "$work/state/repo" "$work/state/team"
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
areas: [marketing, sales]
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
# Sales is not checked out here, but Mia's page grants it. Ops is only granted by her team.
printf '%s\n' '[{"id":93,"invitee":{"login":"acme-member-m"},"permissions":"write"}]' \
  > "$work/state/repo/acme-sales.json"
printf '%s\n' '[{"id":94,"invitee":{"login":"acme-member-m"},"permissions":"write"}]' \
  > "$work/state/repo/acme-ops.json"
printf '%s\n' '[{"name":"acme-os"},{"name":"acme-ops"}]' > "$work/state/team/acme-company.json"
# Item 3: a direct invite on an old area that is on no page, no team and not checked out here.
printf '%s\n' '[{"id":95,"invitee":{"login":"acme-member-m"},"permissions":"write"}]' \
  > "$work/state/repo/acme-legacy.json"
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
fail500() {
  printf '%s\n' "gh: Server Error (HTTP 500)" >&2
  exit 1
}
case "$method $bare" in
  "GET /orgs/acme/repos")
    [ -n "${FAKE_REPOS_500:-}" ] && fail500
    [ "$page" = "1" ] || { printf '%s\n' '[]'; exit 0; }
    for f in "$FAKE_GH_STATE"/repo/*.json; do basename "$f" .json; done | jq -Rsc 'split("\n") | map(select(. != "")) | map({name: .})'
    exit 0 ;;
  "GET /orgs/acme/invitations"|"GET /repos/acme/"*"/invitations")
    [ -n "${FAKE_INVITES_500:-}" ] && fail500
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
  "GET /repos/acme/acme-os/pulls")
    # B37: a stale add pull request for this person, and another person's sync one.
    [ -n "${FAKE_ADD_PR:-}" ] && [ "$page" = "1" ] || { printf '%s\n' '[]'; exit 0; }
    printf '%s\n' '[{"number":7,"head":{"ref":"rules/ada/add-mia"}},{"number":8,"head":{"ref":"sync/dana"}}]'
    exit 0 ;;
  "GET /repos/acme/"*"/collaborators/"*"/permission")
    printf '%s\n' '{"permission":"none"}'
    exit 0 ;;
  "GET /orgs/acme/memberships/"*)
    [ -n "${FAKE_MEMBERSHIP_500:-}" ] && fail500
    if [ -n "${FAKE_ORG_REMOVE_500:-}" ]; then
      printf '%s\n' '{"state":"active","role":"member"}'
      exit 0
    fi
    # B35: the host still says active on the first read after the removal.
    if [ -n "${FAKE_ACTIVE_ONCE:-}" ] && [ ! -f "$FAKE_GH_STATE/active-read" ]; then
      : > "$FAKE_GH_STATE/active-read"
      printf '%s\n' '{"state":"active","role":"member"}'
      exit 0
    fi
    printf '%s\n' "gh: Not Found (HTTP 404)" >&2
    exit 1 ;;
  "DELETE /orgs/acme/members/"*)
    [ -n "${FAKE_ORG_REMOVE_500:-}" ] && fail500
    printf '%s\n' "gh: Cannot find acme-member-m (HTTP 404)" >&2
    exit 1 ;;
  "GET /orgs/acme/teams/"*"/repos")
    t=${bare#/orgs/acme/teams/}
    f="$FAKE_GH_STATE/team/${t%%/*}.json"
    if [ "$page" != "1" ] || [ ! -f "$f" ]; then printf '%s\n' '[]'; else cat "$f"; fi
    exit 0 ;;
  "GET /orgs/acme/teams/"*)
    [ -f "$FAKE_GH_STATE/team/${bare##*/}.json" ] && { printf '%s\n' '{}'; exit 0; }
    printf '%s\n' "gh: Not Found (HTTP 404)" >&2
    exit 1 ;;
  "DELETE /orgs/acme/teams/"*)
    printf '%s\n' "gh: Cannot find acme-member-m (HTTP 404)" >&2
    exit 1 ;;
esac
printf '%s\n' '{}'
EOF
chmod 700 "$work/bin/gh"

# The real host layer, except the pull request and the git token.
cat > "$work/bin/host.sh" << EOF
#!/bin/bash
printf '%s\n' "\$*" >> "\$FAKE_HOST_LOG"
case "\$1" in
  open-pr) printf '%s\n' '{"number":4,"url":"http://example.test/4"}'; exit 0 ;;
  auto-merge-off) printf '%s\n' '{"ok":true}'; exit 0 ;;
  get-token) printf '%s\n' local-token; exit 0 ;;
  whoami) printf '%s\n' '{"login":"acme-admin"}'; exit 0 ;;
esac
exec "$root/template/skills/_host/host.sh" "\$@"
EOF
chmod 700 "$work/bin/host.sh"

export FAKE_GH_STATE="$work/state" FAKE_GH_LOG="$work/gh.log" FAKE_HOST_LOG="$work/host.log"
export PATH="$work/bin:$PATH" OS_HOST_SH="$work/bin/host.sh" OS_RECHECK_WAIT=0
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
grep -q 'org (invited)' "$work/keep.err" || team_fail "pending org invite was not named: $(cat "$work/keep.err")"
grep -q 'acme-marketing (invited)' "$work/keep.err" || team_fail "pending area invite was not named"
grep -q 'acme-user-mia (invited)' "$work/keep.err" || team_fail "pending workspace invite was not named"
grep -q 'acme-sales (invited)' "$work/keep.err" || team_fail "area not checked out here was not checked"
grep -q 'acme-ops (invited)' "$work/keep.err" || team_fail "repo granted by the company team was not checked"
grep -q 'acme-legacy (invited)' "$work/keep.err" || team_fail "item 3: invite on another org repo was not checked"
grep -q 'PATCH /repos/acme/acme-user-mia$' "$FAKE_GH_LOG" && team_fail "workspace archived before access was gone"

# Each failure below must stop before revoked: and remove: ok, with exit 3.
must_stop() {
  local name=$1 want=$2
  [ "$rc" -eq 3 ] || { cat "$work/f.out" "$work/f.err" >&2; team_fail "$name: exit $rc, want 3"; }
  grep -q '^revoked:' "$work/f.out" && team_fail "$name: revoked: printed"
  grep -q 'remove: ok' "$work/f.out" && team_fail "$name: remove: ok printed"
  grep -q "$want" "$work/f.err" || team_fail "$name: missing '$want': $(cat "$work/f.err")"
}
reset_state() {
  rm -rf "$work/state"
  cp -R "$work/state0" "$work/state"
}
export OS_PROFILE="$co/company-profile.md"

# 62. The invite list answers 500: never none, never ok.
host="$root/template/skills/_host/host.sh"
if FAKE_INVITES_500=1 "$host" user-access acme-marketing acme-member-m > /dev/null 2>&1; then
  team_fail "user-access said none when the invite list failed"
fi
if FAKE_INVITES_500=1 "$host" invites acme-member-m > /dev/null 2>&1; then
  team_fail "invites said empty when the list failed"
fi
if FAKE_INVITES_500=1 "$host" cancel-invites acme-member-m acme-marketing > /dev/null 2>&1; then
  team_fail "cancel-invites succeeded when the list failed"
fi
set +e
FAKE_INVITES_500=1 "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/f.out" 2> "$work/f.err"
rc=$?
set -e
must_stop "invite list 500" 'acme-marketing (not checked)'
grep -q 'org (not checked)' "$work/f.err" || team_fail "org invite list 500 was not named"

# Item 3: the org repo list answers 500: not checked, never ok.
reset_state
set +e
FAKE_REPOS_500=1 "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/f.out" 2> "$work/f.err"
rc=$?
set -e
must_stop "org repos 500" 'org repos (not checked)'

# 64. org-remove answers 500 and the person is still a member.
reset_state
set +e
FAKE_ORG_REMOVE_500=1 "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/f.out" 2> "$work/f.err"
rc=$?
set -e
must_stop "org-remove 500" 'org (active)'
grep -q 'HTTP 500' "$work/f.err" || team_fail "B39: a real org-remove error was hidden"
# The membership cannot be read: not checked.
reset_state
set +e
FAKE_MEMBERSHIP_500=1 "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/f.out" 2> "$work/f.err"
rc=$?
set -e
must_stop "membership 500" 'org (not checked)'
out=$("$root/template/skills/_host/host.sh" org-membership acme-member-m)
[ "$(printf '%s' "$out" | jq -r '.state')" = "none" ] || team_fail "org-membership 404: $out"
reset_state

# B35: membership reads active once after org-remove, then gone. The re-check passes.
: > "$FAKE_GH_LOG"
set +e
FAKE_ACTIVE_ONCE=1 "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/b35.out" 2> "$work/b35.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/b35.out" "$work/b35.err" >&2; team_fail "B35: exit $rc after a late membership read"; }
grep -qx 'remove: ok' "$work/b35.out" || team_fail "B35: no remove: ok"
[ "$(grep -c '^GET /orgs/acme/memberships/' "$FAKE_GH_LOG")" -ge 2 ] || team_fail "B35: membership was not read again"
reset_state

# 2. The real run cancels every invite for the person, and only theirs.
: > "$FAKE_GH_LOG"
set +e
FAKE_ADD_PR=1 "$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/rm.out" 2> "$work/rm.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/rm.out" "$work/rm.err" >&2; team_fail "remove exit $rc"; }
grep -qx 'revoked: mia' "$work/rm.out" || team_fail "missing revoked:"
grep -qx 'remove: ok' "$work/rm.out" || team_fail "missing remove: ok"
# B31: the offboard pull request merges by itself, like propose.
grep -qx 'auto-merge: on' "$work/rm.out" || team_fail "offboard PR has no auto-merge: $(cat "$work/rm.out")"
for want in "DELETE /orgs/acme/invitations/81" "DELETE /repos/acme/acme-marketing/invitations/91" \
  "DELETE /repos/acme/acme-user-mia/invitations/92" "DELETE /repos/acme/acme-sales/invitations/93" \
  "DELETE /repos/acme/acme-ops/invitations/94" "DELETE /repos/acme/acme-legacy/invitations/95"; do
  grep -qx "$want" "$FAKE_GH_LOG" || team_fail "not called: $want"
done
grep -q 'invitations/82' "$FAKE_GH_LOG" && team_fail "another person's invite was cancelled"
# B37: the stale add pull request is closed, and only that one.
grep -qx 'PATCH /repos/acme/acme-os/pulls/7' "$FAKE_GH_LOG" || team_fail "B37: add pull request not closed"
grep -q 'pulls/8' "$FAKE_GH_LOG" && team_fail "B37: another pull request was closed"
grep -qx 'closed: acme-os 7 (it added mia)' "$work/rm.out" || team_fail "B37: no closed: line"
# B44: the long org read is announced first.
n_repos=$(find "$work/state/repo" -name '*.json' | wc -l | tr -d ' ')
grep -qx "checking ${n_repos} repos in the org..." "$work/rm.out" || team_fail "B44: no checking line: $(head -3 "$work/rm.out")"
# B39: a person who is not an org member is normal. No raw 404 lines.
grep -q 'HTTP 404\|not found or no access' "$work/rm.err" && team_fail "B39: raw 404 lines: $(cat "$work/rm.err")"
[ "$(jq -c '[.[].id]' "$work/state/org.json")" = "[82]" ] || team_fail "org invites left: $(cat "$work/state/org.json")"
[ "$(jq length "$work/state/repo/acme-marketing.json")" = "0" ] || team_fail "area invite still pending"
[ "$(jq length "$work/state/repo/acme-user-mia.json")" = "0" ] || team_fail "workspace invite still pending"

[ "$(jq length "$work/state/repo/acme-sales.json")" = "0" ] || team_fail "invite on an area not checked out here still pending"
[ "$(jq length "$work/state/repo/acme-legacy.json")" = "0" ] || team_fail "item 3: invite on another org repo still pending"

# 3. A second cancel is fine: nothing pending is success.
out=$("$root/template/skills/_host/host.sh" cancel-invites acme-member-m acme-marketing)
[ "$(printf '%s' "$out" | jq -r '.cancelled')" = "0" ] || team_fail "second cancel: $out"
out=$("$root/template/skills/_host/host.sh" user-access acme-marketing acme-member-m)
[ "$(printf '%s' "$out" | jq -r '.access')" = "none" ] || team_fail "user-access after cancel: $out"
cp "$work/state0/repo/acme-marketing.json" "$work/state/repo/acme-marketing.json"
out=$("$root/template/skills/_host/host.sh" user-access acme-marketing acme-member-m)
[ "$(printf '%s' "$out" | jq -r '.access')" = "invited" ] || team_fail "a pending invite is not access: $out"

# 65. A bots/ change on GitHub: no auto-merge (it hides the bypass box), one merge-by-hand line.
mkdir -p "$co/bots/digest"
printf '%s\n' "---" "owner: mia" "---" "# Digest" > "$co/bots/digest/BOT.md"
git -C "$co" add -A
git -C "$co" -c user.name=t -c user.email=t@example.test commit -q -m bot
git -C "$co" push -q origin main
: > "$FAKE_HOST_LOG"
set +e
"$root/template/skills/remove-teammate/remove.sh" --root "$co" --person mia \
  --date 2026-10-29 > "$work/bot.out" 2> "$work/bot.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/bot.out" "$work/bot.err" >&2; team_fail "bot remove exit $rc"; }
grep -qx 'bot-owner: ada' "$work/bot.out" || team_fail "bot owner not moved: $(cat "$work/bot.out")"
grep -q '^merge-by-hand: acme-os 4: it changes bots/' "$work/bot.out" || team_fail "no merge-by-hand line"
# Item 4 and B38: the first run (no bot) turned auto-merge on for this branch's pull
# request. The second run turns it off, and says a plain merge works for the only owner.
grep -q '^auto-merge-off acme-os 4' "$FAKE_HOST_LOG" || team_fail "item 4: auto-merge was not turned off"
grep -q 'When the admin is the only code owner, a plain merge works. If GitHub asks for a review, tick' "$work/bot.out" || team_fail "B38: merge-by-hand text"
grep -q '^auto-merge' "$work/bot.out" && team_fail "auto-merge line on a bots/ change"
grep -q '^auto-merge ' "$FAKE_HOST_LOG" && team_fail "auto-merge was turned on for a bots/ change"

printf '%s\n' "PASS invites"
