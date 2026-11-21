#!/bin/bash
# Held mode (v1.1): two made-up companies in one fake holder org. Names do not collide,
# no org-wide call is made (the fake gh fails on any org PATCH or org secret call in
# the holder org), lint checks held mode, and handover works: dry run, --go, --undo,
# --archive, the CODEOWNERS rewrite. The real GitHub adapter runs against the fake gh.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../team/common.sh"
root=$(team_root)
team_need git jq python3 tar
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

HOLDER="holder-co"
export FAKE_GH_DIR="$work/gh" FAKE_GIT_ROOT="$work/git"
mkdir -p "$work/bin" "$FAKE_GH_DIR" "$FAKE_GIT_ROOT"
cat > "$work/bin/gh" << EOF
#!/bin/bash
exec python3 -I "$here/fake_gh_holder.py" "\$@"
EOF
chmod 700 "$work/bin/gh"
export PATH="$work/bin:$PATH"
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_JOBS_DIR="$work/jobs"
export OS_GIT_NAME="Test" OS_GIT_EMAIL="test@example.test"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.test GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.test
mkdir -p "$HOME"
unset OS_HOST_SH OS_HOST_BIN GH_TOKEN GITHUB_TOKEN OS_HOST OS_ORG OS_HOST_URL OS_HOST_MODE OS_PROFILE OS_SLUG || true

# The holder org (Team plan, hal is an owner) and two company orgs for handover.
python3 - "$FAKE_GH_DIR/state.json" "$HOLDER" << 'PY'
import json, sys
path, holder = sys.argv[1], sys.argv[2]
org = lambda members: {"plan": "team", "members": members, "repos": {}, "teams": {}, "secrets": []}
json.dump({
    "login": "holder-admin",
    "scopes": "repo, admin:org, workflow",
    "held_orgs": [holder],
    "orgs": {
        holder: org({"holder-admin": "admin"}),
        "acme-own": org({"holder-admin": "admin", "acme-admin": "admin"}),
        "acme-own2": org({"holder-admin": "admin", "acme-admin": "admin"}),
        "acme-nope": org({"holder-admin": "admin", "acme-admin": "member"}),
    },
}, open(path, "w"))
PY

state() {
  python3 - "$FAKE_GH_DIR/state.json" "$@" << 'PY'
import json, sys
s = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {"s": s}))
PY
}

no_org_calls() {
  if [ -s "$FAKE_GH_DIR/forbidden.log" ]; then
    team_fail "$1: an org-wide call reached the holder org: $(cat "$FAKE_GH_DIR/forbidden.log")"
  fi
  if grep -E -- "--method PATCH .*orgs/${HOLDER}\$" "$FAKE_GH_DIR/gh.log" >/dev/null; then
    team_fail "$1: an org PATCH was sent"
  fi
}

# A solo company folder from the template, with one area.
make_company() {
  local slug=$1 dest="$work/$1"
  mkdir -p "$dest"
  cp -R "$root/template/." "$dest/"
  python3 - "$dest/company-profile.md" "$slug" << 'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text().replace("{{COMPANY_SLUG}}", sys.argv[2]).replace("{{COMPANY_NAME}}", "Acme Co")
p.write_text(t)
PY
  git -C "$dest" init -q -b main
  git -C "$dest" add -A
  git -C "$dest" commit -q -m "Company OS: start"
  mkdir -p "$dest/areas/marketing"
  printf '%s\n' "# marketing" > "$dest/areas/marketing/AGENTS.md"
  printf '%s\n' "Plan for spring." > "$dest/areas/marketing/plan.md"
  git -C "$dest/areas/marketing" init -q -b main
  git -C "$dest/areas/marketing" add -A
  git -C "$dest/areas/marketing" commit -q -m "Area: start"
}

answers() {
  local slug=$1 file="$work/$1.answers"
  cat > "$file" << EOF
root=$work/$slug
host=github
host_url=file://$FAKE_GIT_ROOT
host_mode=held
holder_org=$HOLDER
sync_engine=true
person.hal.name=Hal Holder
person.hal.github=holder-admin
person.hal.role=admin
person.hal.holder=true
person.hal.areas=marketing
EOF
  printf '%s\n' "$file"
}

team_on() {
  local slug=$1
  set +e
  bash "$work/$slug/skills/add-teammate/team-on.sh" --answers "$(answers "$slug")" >"$work/$slug.out" 2>"$work/$slug.err"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || team_fail "team-on $slug exit $rc: $(cat "$work/$slug.err") $(tail -5 "$work/$slug.out")"
}

# 1. team-on in held mode: no org-wide call, slug names, owner on record.
make_company acme
team_on acme
no_org_calls "team-on acme"
grep -qx "org settings: held mode, not changed (they belong to the holder org ${HOLDER})" "$work/acme.out" \
  || team_fail "no held org settings line: $(grep 'org settings' "$work/acme.out")"
grep -q "review-command: OS_HOST=github OS_ORG=${HOLDER} OS_HOST_MODE=held skills/_host/host.sh set-secret OS_REVIEW_KEY --repo acme-os --repo acme-marketing " "$work/acme.out" \
  || team_fail "review command is not per repo: $(grep review-command "$work/acme.out")"
[ "$(state "sorted(s['orgs']['$HOLDER']['repos'])")" = "['acme-marketing', 'acme-os', 'acme-user-hal']" ] \
  || team_fail "acme repos: $(state "sorted(s['orgs']['$HOLDER']['repos'])")"
[ "$(state "sorted(s['orgs']['$HOLDER']['teams'])")" = "['acme-area-marketing', 'acme-company']" ] \
  || team_fail "acme teams: $(state "sorted(s['orgs']['$HOLDER']['teams'])")"
p="$work/acme/company-profile.md"
grep -qx 'host_mode: held' "$p" || team_fail "profile host_mode"
grep -qx "holder_org: ${HOLDER}" "$p" || grep -qx "holder_org: \"${HOLDER}\"" "$p" || team_fail "profile holder_org: $(grep holder_org "$p")"
grep -qx "org: ${HOLDER}" "$p" || team_fail "profile org"
grep -qx 'holder: true' "$work/acme/people/Hal Holder.md" || team_fail "hal page has no holder: true"
grep -q '^\*\*/AGENTS.md @holder-admin$' "$work/acme/.github/CODEOWNERS" || team_fail "CODEOWNERS does not name the holder's owner"

# 2. A second company in the same holder org: its own names, nothing shared.
make_company acmeb
team_on acmeb
no_org_calls "team-on acmeb"
[ "$(state "sorted(s['orgs']['$HOLDER']['teams'])")" = "['acme-area-marketing', 'acme-company', 'acmeb-area-marketing', 'acmeb-company']" ] \
  || team_fail "teams collide: $(state "sorted(s['orgs']['$HOLDER']['teams'])")"
[ "$(state "s['orgs']['$HOLDER']['teams']['acme-company']['repos']")" = "['acme-os']" ] || team_fail "acme-company grants more than acme-os"
[ "$(state "s['orgs']['$HOLDER']['teams']['acmeb-company']['repos']")" = "['acmeb-os']" ] || team_fail "acmeb-company grants more than acmeb-os"
[ "$(state "s['orgs']['$HOLDER']['teams']['acmeb-area-marketing']['repos']")" = "['acmeb-marketing']" ] || team_fail "acmeb area team"

# A held team never takes the plain name, even where a plain team grants this repo.
(
  # shellcheck disable=SC1091
  . "$root/template/skills/add-teammate/lib.sh"
  OS_HOST_MODE=held
  os_team_names acme
  [ "$(os_team_company) $(os_team_area finance)" = "acme-company acme-area-finance" ] || team_fail "held names: $(os_team_company)"
)

# 3. The review key: per repo in held mode. Never on the holder org.
host() {
  (cd "$work/acme" && bash skills/_host/host.sh "$@")
}
set +e
printf 'k-123\n' | host set-secret OS_REVIEW_KEY >"$work/s.out" 2>"$work/s.err"
rc=$?
set -e
[ "$rc" -eq 1 ] || team_fail "org secret in held mode: exit $rc"
grep -q 'held mode: an org secret is readable from every repo in the holder org' "$work/s.err" || team_fail "org secret line: $(cat "$work/s.err")"
set +e
host secret-exists OS_REVIEW_KEY >/dev/null 2>&1
rc1=$?
host org-lock >/dev/null 2>"$work/l.err"
rc2=$?
printf 'k-123\n' | host set-secret OS_REVIEW_KEY --repo acmeb-os >/dev/null 2>"$work/o.err"
rc3=$?
set -e
[ "$rc1" -eq 1 ] || team_fail "org secret-exists in held mode: exit $rc1"
if ! { [ "$rc2" -eq 1 ] && grep -q 'held mode: the org settings belong to the holder org' "$work/l.err"; }; then team_fail "org-lock in held mode: exit $rc2"; fi
if ! { [ "$rc3" -eq 1 ] && grep -q 'repo acmeb-os does not start with acme-' "$work/o.err"; }; then team_fail "another company's repo took the key: exit $rc3"; fi
no_org_calls "secret guard"
printf 'k-123\n' | host set-secret OS_REVIEW_KEY --repo acme-os --repo acme-marketing > "$work/set.json"
[ "$(jq -c .repos "$work/set.json")" = '["acme-os","acme-marketing"]' ] || team_fail "set-secret repos: $(cat "$work/set.json")"
host secret-exists OS_REVIEW_KEY --repo acme-os --repo acme-marketing > "$work/ex.json"
[ "$(jq -c . "$work/ex.json")" = '{"exists":true,"repos":{"acme-os":true,"acme-marketing":true}}' ] || team_fail "secret-exists: $(cat "$work/ex.json")"
[ "$(state "s['orgs']['$HOLDER']['secrets']")" = "[]" ] || team_fail "a secret reached the holder org"
grep -q 'k-123' "$FAKE_GH_DIR/gh.log" && team_fail "the key is in the gh argv log"
no_org_calls "set-secret"

# 4. Lint in held mode.
lint_held() {
  (cd "$work/acme" && bash skills/lint/lint.sh --root "$work/acme" 2>&1 || true) | grep 'held' || true
}
out=$(lint_held)
[ -z "$out" ] || team_fail "lint held findings on a good folder: $out"
git -C "$work/acmeb/areas/marketing" remote set-url origin "file://$FAKE_GIT_ROOT/$HOLDER/marketing.git"
out=$( (bash "$work/acmeb/skills/lint/lint.sh" --root "$work/acmeb" 2>&1 || true) | grep 'held:' || true)
printf '%s\n' "$out" | grep -q 'held: repo marketing (areas/marketing) does not start with acmeb-' || team_fail "lint: no slug finding: $out"
printf '%s\n' "$out" | grep -q 'held: no review key on acmeb-os, acmeb-marketing' || team_fail "lint: no repo key finding: $out"
git -C "$work/acmeb/areas/marketing" remote set-url origin "file://$FAKE_GIT_ROOT/$HOLDER/acmeb-marketing.git"
sed -i.bak '/^holder: true$/d' "$work/acmeb/people/Hal Holder.md" && rm -f "$work/acmeb/people/Hal Holder.md.bak"
out=$( (OS_LINT_NO_HOST=1 bash "$work/acmeb/skills/lint/lint.sh" --root "$work/acmeb" 2>&1 || true) | grep 'held:' || true)
printf '%s\n' "$out" | grep -q 'held: no owner on record' || team_fail "lint: no owner finding: $out"
no_org_calls "lint"

# 5. Handover. The company admin's page is a note on main (no access in the holder org).
cat > "$work/acme/people/Ada Admin.md" << 'EOF'
---
type: person
slug: ada
github: acme-admin
role: writer
areas: [marketing]
---

# Ada Admin
EOF
git -C "$work/acme" add "people/Ada Admin.md"
git -C "$work/acme" commit -q -m "People: Ada"
git -C "$work/acme" push -q origin HEAD:main
git -C "$work/acme" fetch -q origin
handover() {
  set +e
  (cd "$work/acme" && bash skills/handover/handover.sh "$@") >"$work/h.out" 2>"$work/h.err"
  hrc=$?
  set -e
}

# Stops before any change.
printf 'x\n' >> "$work/acme/areas/marketing/plan.md"
handover --to-org acme-own --admin ada
if ! { [ "$hrc" -eq 2 ] && grep -q 'areas/marketing: uncommitted changes' "$work/h.err"; }; then team_fail "dirty area: exit $hrc $(cat "$work/h.err")"; fi
git -C "$work/acme/areas/marketing" checkout -q -- plan.md
handover --to-org acme-nope --admin ada
if ! { [ "$hrc" -eq 2 ] && grep -q 'acme-admin is not an owner' "$work/h.err"; }; then team_fail "admin not owner: exit $hrc $(cat "$work/h.err")"; fi
handover --to-org acme-own --admin hal
if ! { [ "$hrc" -eq 2 ] && grep -q 'hal is a holder person' "$work/h.err"; }; then team_fail "holder as admin: exit $hrc"; fi
handover --to-org acme-own --admin ada --archive
[ "$hrc" -eq 2 ] || team_fail "archive with no handover: exit $hrc"

# Dry run: every step printed, nothing made.
handover --to-org acme-own --admin ada
[ "$hrc" -eq 0 ] || team_fail "dry run exit $hrc: $(cat "$work/h.err")"
for n in 1 2 3 4 5 6 7 8; do
  grep -q "^step $n: " "$work/h.out" || team_fail "dry run has no step $n"
done
grep -q '^skip: users/hal' "$work/h.out" || team_fail "dry run does not skip the holder workspace"
grep -q 'dry run: nothing was changed' "$work/h.out" || team_fail "dry run line"
[ "$(state "sorted(s['orgs']['acme-own']['repos'])")" = "[]" ] || team_fail "dry run made repos"

# --go: a fresh copy, one commit, the company admin as owner on record.
handover --to-org acme-own --admin ada --go
[ "$hrc" -eq 0 ] || team_fail "--go exit $hrc: $(cat "$work/h.err") $(cat "$work/h.out")"
no_org_calls "handover --go"
[ "$(state "sorted(s['orgs']['acme-own']['repos'])")" = "['acme-marketing', 'acme-os']" ] \
  || team_fail "moved repos: $(state "sorted(s['orgs']['acme-own']['repos'])")"
grep -q '^team-on: acme-admin clones acme-own/acme-os' "$work/h.out" || team_fail "no team-on line"
grep -q "^manual: point the kernel's GitHub team link at acme-own" "$work/h.out" || team_fail "no kernel line"
c="$work/clone"
git clone -q "$FAKE_GIT_ROOT/acme-own/acme-os.git" "$c"
[ "$(git -C "$c" rev-list --count HEAD)" = "1" ] || team_fail "history moved"
[ "$(git -C "$c" log -1 --format=%s)" = "Handover from ${HOLDER}" ] || team_fail "commit: $(git -C "$c" log -1 --format=%s)"
grep -q '@holder-admin' "$c/.github/CODEOWNERS" "$c/.gitea/CODEOWNERS" && team_fail "CODEOWNERS still names the holder"
grep -q '^\*\*/AGENTS.md @acme-admin$' "$c/.github/CODEOWNERS" || team_fail "CODEOWNERS does not name the company admin"
[ ! -e "$c/people/Hal Holder.md" ] || team_fail "the holder page moved"
grep -qx 'role: admin' "$c/people/Ada Admin.md" || team_fail "ada is not admin on record"
grep -qx 'host_mode: own' "$c/company-profile.md" || team_fail "host_mode not own"
grep -qx 'org: acme-own' "$c/company-profile.md" || team_fail "org not switched"
grep -q 'holder-co' "$c/company-profile.md" && team_fail "the holder org is still in the profile"
m="$work/clone-m"
git clone -q "$FAKE_GIT_ROOT/acme-own/acme-marketing.git" "$m"
[ "$(git -C "$m" rev-list --count HEAD)" = "1" ] || team_fail "area history moved"
grep -q '@holder-admin' "$m/.github/CODEOWNERS" && team_fail "area CODEOWNERS still names the holder"
[ "$(state "s['orgs']['$HOLDER']['repos']['acme-os']['archived']")" = "False" ] || team_fail "--go archived the holder copy"
handover --to-org acme-own2 --admin ada --go
if ! { [ "$hrc" -eq 2 ] && grep -q 'is open: run --archive or --undo first' "$work/h.err"; }; then team_fail "second --go: exit $hrc"; fi

# --undo: the new copies are archived (never deleted), the holder copies stay.
handover --undo
[ "$hrc" -eq 0 ] || team_fail "--undo exit $hrc: $(cat "$work/h.err")"
[ "$(state "s['orgs']['acme-own']['repos']['acme-os']['archived']")" = "True" ] || team_fail "undo did not archive the new copy"
[ "$(state "'acme-os' in s['orgs']['acme-own']['repos']")" = "True" ] || team_fail "undo deleted a repo"
[ "$(state "s['orgs']['$HOLDER']['repos']['acme-os']['archived']")" = "False" ] || team_fail "undo touched the holder copy"
handover --to-org acme-own --admin ada
if ! { [ "$hrc" -eq 2 ] && grep -q 'acme-own/acme-os is already there' "$work/h.err"; }; then team_fail "go into used org: exit $hrc"; fi

# --go again into a clean org, then --archive: the holder copies are archived.
handover --to-org acme-own2 --admin ada --go
[ "$hrc" -eq 0 ] || team_fail "second --go exit $hrc: $(cat "$work/h.err")"
handover --undo --to-org acme-own
[ "$hrc" -eq 2 ] || team_fail "undo with the wrong org: exit $hrc"
handover --archive
[ "$hrc" -eq 0 ] || team_fail "--archive exit $hrc: $(cat "$work/h.err")"
for r in acme-os acme-marketing; do
  [ "$(state "s['orgs']['$HOLDER']['repos']['$r']['archived']")" = "True" ] || team_fail "$r not archived in the holder org"
done
[ "$(state "s['orgs']['$HOLDER']['repos']['acme-user-hal']['archived']")" = "False" ] || team_fail "the holder workspace was archived"
[ "$(state "s['orgs']['$HOLDER']['repos']['acmeb-os']['archived']")" = "False" ] || team_fail "the other company was archived"
handover --undo
[ "$hrc" -eq 2 ] || team_fail "undo after archive: exit $hrc"
no_org_calls "handover"
[ ! -s "$FAKE_GH_DIR/unexpected.log" ] || team_fail "unexpected gh calls: $(cat "$FAKE_GH_DIR/unexpected.log")"

printf '%s\n' "PASS: held mode"
