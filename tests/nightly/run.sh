#!/bin/bash
# Nightly review on the local Forgejo. Exit 3 when Forgejo is not up.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
URL="${OSF_ACME_URL:-http://localhost:3300}"
ORG=acme
COMPANY_REPO=nightly-os
AREA_REPO=nightly-finance

if ! curl -fsS --max-time 5 "$URL/api/v1/version" >/dev/null 2>&1; then
  printf '%s\n' "BLOCKED: Forgejo is not up"
  exit 3
fi

token_file="${OSF_ACME_TOKEN:-${HOME}/.cache/os-foundation/forgejo/tokens/acme-admin}"
if [ ! -f "$token_file" ]; then
  printf '%s\n' "BLOCKED: Acme admin token file is missing"
  exit 3
fi

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

box=$(mktemp -d)
# shellcheck disable=SC2064
trap 'rm -rf "$box"' EXIT

export HOME="$box/home"
export XDG_CONFIG_HOME="$box/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
# Token stays in the environment. It is not passed as an argument.
FORGEJO_TOKEN=$(tr -d '\r\n' < "$token_file")
export FORGEJO_TOKEN
export OS_TEST_MODE=1
export OS_SYNC_ENGINE="$ROOT/tests/nightly/fake-engine.sh"
export OS_NOW=2026-10-24
export GIT_AUTHOR_NAME="Mia Member"
export GIT_AUTHOR_EMAIL="mia@example.com"
export GIT_COMMITTER_NAME="Mia Member"
export GIT_COMMITTER_EMAIL="mia@example.com"

company="$box/acme"
area="$company/areas/finance"
mkdir -p "$company/skills" "$company/people" "$area/notes" "$area/memory/logs" \
  "$company/users/mia/profile" "$company/users/mia/drafts"
cp -R "$ROOT/template/skills/nightly-review" "$company/skills/nightly-review"
cp -R "$ROOT/template/skills/reports" "$company/skills/reports"
cp -R "$ROOT/template/skills/_host" "$company/skills/_host"
printf '%s\n' "Return one JSON line." > "$company/skills/nightly-review/review-prompt.md"
printf '%s\n' "Return one JSON line." > "$company/skills/reports/report-prompt.md"
cat > "$company/company-profile.md" << EOF
---
type: company-profile
summary: "Acme Co"
updated: 2026-10-24
company_slug: acme
level: team
switches: []
os_version: 0
host: forgejo
host_url: "${URL}"
org: ${ORG}
sync_engine: ""
runner: ubuntu-latest
---

# Acme Co
EOF
cat > "$company/people/Ada Admin.md" << 'EOF'
---
type: person
summary: "Admin"
slug: ada
github: acme-admin
email: ada@example.com
role: admin
areas: []
---

# Ada Admin
EOF
cat > "$company/people/Dana Director.md" << 'EOF'
---
type: person
summary: "Director"
slug: dana
github: acme-director
email: dana@example.com
role: director
areas: [finance]
---

# Dana Director
EOF
cat > "$company/people/Mia Member.md" << 'EOF'
---
type: person
summary: "Writer"
slug: mia
github: acme-member-a
email: mia@example.com
role: writer
areas: [finance]
---

# Mia Member
EOF
printf '%s\n' "PROFILE-BAIT-PHRASE leaderboard" > "$company/users/mia/profile/PROFILE.md"
printf '%s\n' "WORKSPACE-BAIT-PHRASE" > "$company/users/mia/drafts/note.md"
cat > "$area/notes/widget.md" << 'EOF'
# Widget

See [[Ada]].

CLEAR-ERROR broken link
JUDGMENT-CALL confirm the price
EOF
printf '%s\n' "RULES-BROKEN do not change this line" > "$area/AGENTS.md"
printf '%s\n' "Filed the widget note." > "$area/memory/logs/2026-10-24-mia.md"
printf '%s\n' "Result: The note is on main." >> "$area/memory/logs/2026-10-24-mia.md"
printf '%s\n' "Old action from September." > "$area/memory/logs/2026-09-23-mia.md"
printf '%s\n' "SECRET-LINE" > "$area/notes/leak.md"
printf '%s\n' "POSSIBLE-LEAK marker" >> "$area/notes/leak.md"
mkdir -p "$area/.github/workflows"
cat > "$area/.github/workflows/checks.yml" << 'EOF'
name: checks
on:
  pull_request:
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
EOF

git -C "$area" init -q -b main
git -C "$area" add -A
GIT_AUTHOR_DATE="2026-10-24T12:00:00" GIT_COMMITTER_DATE="2026-10-24T12:00:00" \
  git -C "$area" -c user.name="Mia Member" -c user.email="mia@example.com" \
  commit -q -m "Seed the area"
git -C "$company" init -q -b main
git -C "$company" add company-profile.md people
GIT_AUTHOR_DATE="2026-10-23T12:00:00" GIT_COMMITTER_DATE="2026-10-23T12:00:00" \
  git -C "$company" -c user.name="Ada Admin" -c user.email="ada@example.com" \
  commit -q -m "Add the company pages"

host="$company/skills/_host/host.sh"
cd "$company"
export OS_PROFILE="$company/company-profile.md"

drop_repo() {
  bash "$host" delete-repo "$1" --yes-test-only >/dev/null 2>&1 || true
}
drop_repo "$AREA_REPO"
drop_repo "$COMPANY_REPO"
# shellcheck disable=SC2064
trap 'drop_repo "$AREA_REPO"; drop_repo "$COMPANY_REPO"; rm -rf "$box"' EXIT

bash "$host" create-repo "$COMPANY_REPO" --source "$company" --push >/dev/null
bash "$host" create-repo "$AREA_REPO" --source "$area" --push >/dev/null

review_out="$box/review.out"
set +e
bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24 \
  >"$review_out" 2>"$box/review.err"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  fail "review exited $rc"
fi
number=$(awk -v repo="$AREA_REPO" '$1=="pr" && $2==repo { print $3 }' "$review_out" | head -n 1)
[ -n "$number" ] || fail "review did not open a pull request"

i=0
merged=0
st=""
while [ "$i" -lt 40 ]; do
  st=$(bash "$host" pr-status "$AREA_REPO" "$number")
  if printf '%s' "$st" | jq -e '.merged == true' >/dev/null; then
    merged=1
    break
  fi
  i=$((i + 1))
  sleep 3
done
[ "$merged" = "1" ] || fail "pull request did not merge: $st"

auth_git() {
  local repo=$1 ask rc
  shift
  ask=$(mktemp)
  chmod 700 "$ask"
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "acme-admin" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
  OS_GIT_TOKEN="$FORGEJO_TOKEN" GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
    git -C "$repo" -c credential.helper= -c http.connectTimeout=5 "$@"
  rc=$?
  rm -f "$ask"
  return "$rc"
}

auth_git "$area" fetch origin main >/dev/null
git -C "$area" show origin/main:notes/widget.md | grep -F '[[Ada Admin]]' >/dev/null
if git -C "$area" show origin/main:notes/widget.md | grep -F '[[Ada]].' >/dev/null; then
  fail "broken link still on main"
fi
if git -C "$area" cat-file -e "origin/main:memory/logs/2026-09-23-mia.md" 2>/dev/null; then
  fail "old log still on main"
fi
git -C "$area" cat-file -e "origin/main:memory/logs/2026-09-summary.md"
[ -n "$(git -C "$area" log --all --oneline -- memory/logs/2026-09-23-mia.md)" ]

bash "$company/skills/reports/run.sh" --root "$company" --date 2026-10-24 --week 2026-W43 \
  >"$box/reports.out" 2>"$box/reports.err"
auth_git "$area" fetch origin "review/2026-10-24" >/dev/null
decide=$(git -C "$area" show "origin/review/2026-10-24:reports/2026-10-24-to-decide.md")
printf '%s\n' "$decide" | grep -F 'Confirm the price.' >/dev/null
if printf '%s\n' "$decide" | grep -F 'Possible leak' >/dev/null; then
  fail "possible leak is in the to-decide file"
fi
if git -C "$area" log "origin/review/2026-10-24" --format=%B | grep -F 'Possible leak' >/dev/null; then
  fail "possible leak is in a commit message"
fi
weekly=$(git -C "$area" show "origin/review/2026-10-24:reports/2026-W43.md")
printf '%s\n' "$weekly" | grep -F 'Filed the widget note.' >/dev/null
printf '%s\n' "$weekly" | grep -F 'Commits merged' >/dev/null
if printf '%s\n' "$weekly" | grep -F 'WORKSPACE-BAIT-PHRASE' >/dev/null; then
  fail "workspace text in the weekly report"
fi
if printf '%s\n' "$weekly" | grep -F 'PROFILE-BAIT-PHRASE' >/dev/null; then
  fail "profile text in the weekly report"
fi
if printf '%s\n' "$weekly" | grep -E -i '(^|[^A-Za-z])(rank|ranking|ranked|score|scores|leaderboard|rating)([^A-Za-z]|$)' >/dev/null; then
  fail "ranking word in the weekly report"
fi

# Wait until the report pull request has merged, then add one more commit.
rnumber=$(awk -v repo="$AREA_REPO" '$1=="pr" && $2==repo { print $3 }' "$box/reports.out" | tail -n 1)
if [ -n "$rnumber" ]; then
  i=0
  while [ "$i" -lt 40 ]; do
    st=$(bash "$host" pr-status "$AREA_REPO" "$rnumber")
    if printf '%s' "$st" | jq -e '.merged == true' >/dev/null; then
      break
    fi
    i=$((i + 1))
    sleep 3
  done
fi
# Engine down: a new commit on main, no edits, one plain line.
auth_git "$area" fetch origin main >/dev/null
git -C "$area" reset --hard origin/main >/dev/null
printf '%s\n' "CLEAR-ERROR-TWO should stay" > "$area/notes/next.md"
git -C "$area" add notes/next.md
GIT_AUTHOR_DATE="2026-10-24T15:00:00" GIT_COMMITTER_DATE="2026-10-24T15:00:00" \
  git -C "$area" -c user.name="Mia Member" -c user.email="mia@example.com" \
  commit -q -m "Add a second note"
ask=$(mktemp)
chmod 700 "$ask"
cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "acme-admin" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
OS_GIT_TOKEN="$FORGEJO_TOKEN" GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
  git -C "$area" -c credential.helper= -c http.connectTimeout=5 push origin main
rm -f "$ask"
export OS_SYNC_ENGINE="$ROOT/tests/nightly/engine-down.sh"
set +e
bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24 \
  >"$box/down.out" 2>"$box/down.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "engine down should exit 2"
grep -F 'The review did not run.' "$XDG_CONFIG_HOME/acme-os/state/review.log" >/dev/null
auth_git "$area" fetch origin main >/dev/null
git -C "$area" show origin/main:notes/next.md | grep -F 'CLEAR-ERROR-TWO' >/dev/null

printf '%s\n' "PASS: forgejo nightly review and reports"
