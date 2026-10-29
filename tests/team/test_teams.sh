#!/bin/bash
# B24: team names carry the company slug, a v1 company keeps its plain names, and team-on
# refuses a team that already grants another company's repo, before any write.
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"
root=$(team_root)
team_need git jq
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A fake host. FAKE_TEAMS is a file of "<team> <repo>" lines: what each team grants.
mkdir -p "$work/bin"
cat > "$work/bin/host.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_HOST_LOG"
case "$1" in
  team-repos)
    if ! grep -q "^$2 " "$FAKE_TEAMS" 2>/dev/null; then
      jq -nc --arg t "$2" '{team:$t, exists:false, repos:[]}'
      exit 0
    fi
    grep "^$2 " "$FAKE_TEAMS" | cut -d' ' -f2 | jq -Rsc --arg t "$2" '{team:$t, exists:true, repos:(split("\n") | map(select(. != "")))}'
    ;;
  whoami) printf '%s\n' '{"login":"acme-admin"}' ;;
  get-token) printf '%s\n' local-token ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF
chmod 700 "$work/bin/host.sh"
export OS_HOST_BIN="$work/bin/host.sh" OS_HOST_SH="$work/bin/host.sh"
export FAKE_TEAMS="$work/teams" FAKE_HOST_LOG="$work/host.log"

names() {
  (
    # shellcheck disable=SC1091
    . "$root/template/skills/add-teammate/lib.sh"
    os_team_names "$1"
    printf '%s %s\n' "$(os_team_company)" "$(os_team_area marketing)"
  )
}

# A new company in an org where another company has the plain teams: scoped names.
printf '%s\n' "company acme-os" "area-marketing acme-marketing" > "$FAKE_TEAMS"
[ "$(names acmeb)" = "acmeb-company acmeb-area-marketing" ] || team_fail "new company names: $(names acmeb)"
# A fresh org: scoped names too.
: > "$FAKE_TEAMS"
[ "$(names acme)" = "acme-company acme-area-marketing" ] || team_fail "fresh org names: $(names acme)"
# A v1 company whose plain team grants its own repo keeps the plain names (no rename).
printf '%s\n' "company acme-os" > "$FAKE_TEAMS"
[ "$(names acme)" = "company area-marketing" ] || team_fail "v1 company was renamed: $(names acme)"

guard() {
  (
    # shellcheck disable=SC1091
    . "$root/template/skills/add-teammate/lib.sh"
    os_team_guard "$1" "$2"
  )
}
printf '%s\n' "company acme-os" "acmeb-company acmeb-os" > "$FAKE_TEAMS"
guard company acme-os 2> "$work/g.err" || team_fail "guard refused a team that grants only its repo"
guard acmeb-company acmeb-os 2> "$work/g.err" || team_fail "guard refused a scoped team"
guard acmeb-area-sales acmeb-sales 2> "$work/g.err" || team_fail "guard refused a team that does not exist yet"
printf '%s\n' "company acme-os" "company acmeb-os" > "$FAKE_TEAMS"
set +e
guard company acme-os 2> "$work/g.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || team_fail "shared team: guard exit $rc, want 2"
grep -q '^team company already grants acmeb-os. It may grant only acme-os. Two companies must not share a team' "$work/g.err" \
  || team_fail "shared team line: $(cat "$work/g.err")"

# team-on in a v1 company whose plain teams are shared with another company: one plain
# line, exit 2, and no host write.
company="$work/company"
mkdir -p "$company/skills" "$company/areas/marketing" "$company/people"
cat > "$company/company-profile.md" << 'EOF'
---
type: company-profile
company_slug: acme
level: solo
switches: []
os_version: v1.0.0
host: forgejo
host_url: "http://127.0.0.1:9"
org: acme
---

# Acme Co
EOF
printf '%s\n' "/areas/" "/users/" > "$company/.gitignore"
git -C "$company" init -q -b main
git -C "$company" add -A
git -C "$company" -c user.name=t -c user.email=t@example.test commit -q -m start
git -C "$company/areas/marketing" init -q -b main
printf '%s\n' "# Marketing" > "$company/areas/marketing/AGENTS.md"
git -C "$company/areas/marketing" add -A
git -C "$company/areas/marketing" -c user.name=t -c user.email=t@example.test commit -q -m start
cat > "$work/answers" << EOF
root=$company
host=forgejo
host_url=http://127.0.0.1:9
org=acme
sync_engine=true
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.role=admin
person.ada.areas=marketing
EOF
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
mkdir -p "$HOME"
printf '%s\n' "company acme-os" "area-marketing acme-marketing" "area-marketing acmeb-marketing" > "$FAKE_TEAMS"
: > "$FAKE_HOST_LOG"
set +e
"$root/template/skills/add-teammate/team-on.sh" --answers "$work/answers" > "$work/on.out" 2> "$work/on.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || { cat "$work/on.out" "$work/on.err" >&2; team_fail "team-on with a shared team: exit $rc, want 2"; }
grep -q '^team area-marketing already grants acmeb-marketing. It may grant only acme-marketing.' "$work/on.err" \
  || team_fail "team-on shared team line: $(cat "$work/on.err")"
grep -qE '^(create-repo|protect|unprotect|team-create|team-add|grant) ' "$FAKE_HOST_LOG" \
  && team_fail "team-on wrote to the host before the refusal: $(cat "$FAKE_HOST_LOG")"

printf '%s\n' "PASS teams"
