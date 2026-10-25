#!/bin/bash
# Local checks for nightly review and reports. No host API.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  PASS=$((PASS + 1))
  printf 'PASS: %s\n' "$*"
}

# shellcheck disable=SC1091
. "$ROOT/template/skills/nightly-review/lib.sh"

[ "$(nr_iso_week 2026-10-24)" = "2026-W43" ] || fail "iso week of 2026-10-24"
[ "$(nr_iso_week 2021-01-01)" = "2020-W53" ] || fail "iso week of 2021-01-01"
[ "$(nr_week_span 2026-W43)" = "2026-10-19 2026-10-26" ] || fail "week span $(nr_week_span 2026-W43)"
pass "iso week"

bash "$ROOT/template/skills/nightly-review/run.sh" --help >/dev/null
bash "$ROOT/template/skills/reports/run.sh" --help >/dev/null
pass "help"

if grep -n -E 'Authorization|curl ' \
  "$ROOT/template/skills/nightly-review/"*.sh \
  "$ROOT/template/skills/reports/"*.sh; then
  fail "script calls curl or puts an Authorization header in a command"
fi
pass "no curl in shipped scripts"

copy_host() {
  local dest=$1
  mkdir -p "$dest/skills"
  rm -rf "$dest/skills/_host"
  cp -R "$ROOT/template/skills/_host" "$dest/skills/_host"
}

write_people() {
  local dest=$1
  mkdir -p "$dest/people"
  cat > "$dest/people/Ada Admin.md" << 'EOF'
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
  cat > "$dest/people/Dana Director.md" << 'EOF'
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
  cat > "$dest/people/Mia Member.md" << 'EOF'
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
}

make_company() {
  local dest=$1 level=$2 switches=$3
  mkdir -p "$dest/skills" "$dest/areas/finance/notes" "$dest/areas/finance/memory/logs" \
    "$dest/users/mia/profile" "$dest/users/mia/drafts"
  cp -R "$ROOT/template/skills/nightly-review" "$dest/skills/nightly-review"
  cp -R "$ROOT/template/skills/reports" "$dest/skills/reports"
  printf '%s\n' "Return one JSON line." > "$dest/skills/nightly-review/review-prompt.md"
  printf '%s\n' "Return one JSON line." > "$dest/skills/reports/report-prompt.md"
  copy_host "$dest"
  cat > "$dest/company-profile.md" << EOF
---
type: company-profile
summary: "Acme Co"
updated: 2026-10-24
company_slug: acme
level: ${level}
switches: ${switches}
os_version: 0
host: forgejo
host_url: "http://127.0.0.1:9"
org: acme
sync_engine: ""
runner: ubuntu-latest
---

# Acme Co
EOF
  write_people "$dest"
  printf '%s\n' "PROFILE-BAIT-PHRASE leaderboard" > "$dest/users/mia/profile/PROFILE.md"
  printf '%s\n' "WORKSPACE-BAIT-PHRASE" > "$dest/users/mia/drafts/note.md"
}

git_identity() {
  export GIT_AUTHOR_NAME="Mia Member"
  export GIT_AUTHOR_EMAIL="mia@example.com"
  export GIT_COMMITTER_NAME="Mia Member"
  export GIT_COMMITTER_EMAIL="mia@example.com"
  export GIT_AUTHOR_DATE="2026-10-24T12:00:00"
  export GIT_COMMITTER_DATE="2026-10-24T12:00:00"
}

init_git() {
  local dir=$1
  git -C "$dir" init -q -b main
  git -C "$dir" add -A
  git -C "$dir" -c user.name="Mia Member" -c user.email="mia@example.com" commit -q -m "Seed the area"
}

seed_area() {
  local area=$1
  cat > "$area/notes/widget.md" << 'EOF'
# Widget

See [[Ada]].

CLEAR-ERROR broken link
JUDGMENT-CALL confirm the price
EOF
  cat > "$area/AGENTS.md" << 'EOF'
# Finance

RULES-BROKEN do not change this line
EOF
  printf '%s\n' "Filed the widget note." > "$area/memory/logs/2026-10-24-mia.md"
  printf '%s\n' "Result: The note is on main." >> "$area/memory/logs/2026-10-24-mia.md"
  printf '%s\n' "Old action from September." > "$area/memory/logs/2026-09-23-mia.md"
  git_identity
  init_git "$area"
}

run_env() {
  local home=$1
  export HOME="$home/home"
  export XDG_CONFIG_HOME="$home/config"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME"
  export OS_SYNC_ENGINE="$ROOT/tests/nightly/fake-engine.sh"
  export OS_SKIP_FETCH=1
  export OS_SKIP_PUSH=1
  export OS_NOW=2026-10-24
  unset OS_REVIEW_CAP || true
  unset OS_BOT || true
  unset OS_RUN_ID || true
}

show() {
  git -C "$1" show "$2:$3"
}

main_case() {
  local box company area
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" team "[]"
  area="$company/areas/finance"
  seed_area "$area"
  git -C "$company" init -q -b main
  git -C "$company" add company-profile.md people
  git -C "$company" -c user.name="Ada Admin" -c user.email="ada@example.com" \
    -c committer.date="2026-10-23T12:00:00" commit -q -m "Add the company pages"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  show "$area" "review/2026-10-24" "notes/widget.md" | grep -F '[[Ada Admin]]' >/dev/null
  if show "$area" "review/2026-10-24" "notes/widget.md" | grep -F '[[Ada]].' >/dev/null; then
    fail "broken link still in the note"
  fi
  show "$area" "review/2026-10-24" "AGENTS.md" | grep -F 'RULES-BROKEN' >/dev/null
  if show "$area" "review/2026-10-24" "AGENTS.md" | grep -F 'FIXED' >/dev/null; then
    fail "rules file was edited"
  fi
  if git -C "$area" cat-file -e "review/2026-10-24:memory/logs/2026-09-23-mia.md" 2>/dev/null; then
    fail "old log still on the review branch"
  fi
  git -C "$area" cat-file -e "review/2026-10-24:memory/logs/2026-09-summary.md"
  [ -n "$(git -C "$area" log --all --oneline -- memory/logs/2026-09-23-mia.md)" ]
  grep -F 'Confirm the price.' "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24.json" >/dev/null
  git -C "$area" log -1 --format=%B "review/2026-10-24" | grep -F 'Run-Id: review-' >/dev/null
  if git -C "$area" log -1 --format=%B "review/2026-10-24" | grep -F 'Bot-Owner:' >/dev/null; then
    fail "Bot-Owner set when bots is off"
  fi
  bash "$company/skills/reports/run.sh" --root "$company" --date 2026-10-24 --week 2026-W43
  show "$area" "review/2026-10-24" "reports/2026-10-24-to-decide.md" | grep -F 'Confirm the price.' >/dev/null
  local weekly
  weekly=$(show "$area" "review/2026-10-24" "reports/2026-W43.md")
  printf '%s\n' "$weekly" | grep -F 'Filed the widget note.' >/dev/null
  printf '%s\n' "$weekly" | grep -F 'Commits merged' >/dev/null
  printf '%s\n' "$weekly" | grep -F 'format: markdown' >/dev/null
  if printf '%s\n' "$weekly" | grep -F 'WORKSPACE-BAIT-PHRASE' >/dev/null; then
    fail "workspace text in the weekly report"
  fi
  if printf '%s\n' "$weekly" | grep -F 'PROFILE-BAIT-PHRASE' >/dev/null; then
    fail "profile text in the weekly report"
  fi
  if printf '%s\n' "$weekly" | grep -E -i '(^|[^A-Za-z])(rank|ranking|ranked|score|scores|leaderboard|rating)([^A-Za-z]|$)' >/dev/null; then
    fail "ranking word in the weekly report"
  fi
  show "$company" "review/2026-10-24" "reports/2026-W43-company.md" | grep -F 'finance' >/dev/null
  pass "clear error, judgment, fold, weekly report"
  rm -rf "$box"
}

engine_down_case() {
  local box company area
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  export OS_SYNC_ENGINE="$ROOT/tests/nightly/engine-down.sh"
  make_company "$company" team "[]"
  area="$company/areas/finance"
  seed_area "$area"
  set +e
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  local rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "engine down should exit 2"
  if git -C "$area" show-ref --verify --quiet refs/heads/review/2026-10-24; then
    fail "engine down created a review branch"
  fi
  grep -F '[[Ada]].' "$area/notes/widget.md" >/dev/null
  grep -F 'The review did not run.' "$XDG_CONFIG_HOME/acme-os/state/review.log" >/dev/null
  grep -F 'The review did not run.' "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24-ada.md" >/dev/null
  pass "engine down"
  rm -rf "$box"
}

cap_case() {
  local box company area
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  export OS_REVIEW_CAP=2
  make_company "$company" team "[]"
  area="$company/areas/finance"
  mkdir -p "$area/notes" "$area/memory/logs"
  printf '%s\n' "MANY-FLAGS in this note" > "$area/notes/many.md"
  git_identity
  init_git "$area"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  grep -F 'and 2 more' "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24-mia.md" >/dev/null
  pass "digest cap"
  rm -rf "$box"
}

solo_case() {
  local box company
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" solo "[]"
  local out
  out=$(bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24)
  printf '%s\n' "$out" | grep -F 'skipped: solo' >/dev/null
  pass "solo skip"
  rm -rf "$box"
}

bots_case() {
  local box company area
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" team "[bots]"
  mkdir -p "$company/bots/acme-bot"
  cat > "$company/bots/acme-bot/BOT.md" << 'EOF'
---
owner: ada
name: Acme Bot
area: ""
---

# Acme Bot
EOF
  area="$company/areas/finance"
  seed_area "$area"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  git -C "$area" log -1 --format=%B "review/2026-10-24" | grep -F 'Bot-Owner: ada' >/dev/null
  git -C "$area" log -1 --format=%B "review/2026-10-24" | grep -F 'Run-Id: review-' >/dev/null
  pass "bot trailers"
  rm -rf "$box"
}

mdx_case() {
  local box company area weekly
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" team "[mdx-reports]"
  area="$company/areas/finance"
  seed_area "$area"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  bash "$company/skills/reports/run.sh" --root "$company" --date 2026-10-24 --week 2026-W43
  weekly=$(show "$area" "review/2026-10-24" "reports/2026-W43.md")
  printf '%s\n' "$weekly" | grep -F 'format: mdx' >/dev/null
  printf '%s\n' "$weekly" | grep -F '<Callout>' >/dev/null
  printf '%s\n' "$weekly" | grep -F '<Table>' >/dev/null
  printf '%s\n' "$weekly" | grep -F '<Chart ' >/dev/null
  if printf '%s\n' "$weekly" | grep -F '<script' >/dev/null; then
    fail "mdx report has a script tag"
  fi
  pass "mdx flag"
  rm -rf "$box"
}

argv_case() {
  local box company area spy log sentinel
  box=$(mktemp -d)
  company="$box/acme"
  log="$box/argv.log"
  sentinel="ARGV-SENTINEL-VALUE"
  run_env "$box"
  unset OS_SKIP_PUSH
  export OS_ARGV_SKIP_WHOAMI=1
  export ARGV_LOG="$log"
  export ARGV_SENTINEL="$sentinel"
  export FORGEJO_TOKEN="$sentinel"
  make_company "$company" team "[]"
  cat > "$company/skills/_host/host.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$ARGV_LOG"
if [ "${1:-}" = "get-token" ]; then
  printf '%s\n' "$ARGV_SENTINEL"
  exit 0
fi
if [ "${1:-}" = "whoami" ]; then
  printf '%s\n' '{"login":"ada"}'
  exit 0
fi
if [ "${1:-}" = "open-pr" ]; then
  printf '%s\n' '{"number":1,"url":"http://example.com/1"}'
  exit 0
fi
if [ "${1:-}" = "auto-merge" ]; then
  printf '%s\n' '{"ok":true}'
  exit 0
fi
printf '%s\n' '{"ok":true}'
exit 0
EOF
  chmod 700 "$company/skills/_host/host.sh"
  spy="$box/bin"
  mkdir -p "$spy"
  cat > "$spy/git" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$ARGV_LOG"
exec /usr/bin/git "$@"
EOF
  cat > "$spy/curl" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$ARGV_LOG"
exit 1
EOF
  chmod 700 "$spy/git" "$spy/curl"
  export PATH="$spy:$PATH"
  area="$company/areas/finance"
  seed_area "$area"
  git -C "$area" remote add origin "https://127.0.0.1:9/acme/argv-finance.git"
  set +e
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  set -e
  if [ ! -f "$log" ]; then
    fail "argv log was not written"
  fi
  if grep -F "$sentinel" "$log" >/dev/null; then
    fail "token in a child argv"
  fi
  pass "argv"
  rm -rf "$box"
}

leak_case() {
  local box company area
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" team "[]"
  area="$company/areas/finance"
  mkdir -p "$area/notes" "$area/memory/logs"
  printf '%s\n' "SECRET-LINE" > "$area/notes/leak.md"
  printf '%s\n' "POSSIBLE-LEAK marker" >> "$area/notes/leak.md"
  git_identity
  init_git "$area"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  if git -C "$area" show "review/2026-10-24:notes/leak.md" 2>/dev/null | grep -F 'gone' >/dev/null; then
    fail "a possible leak was edited"
  fi
  grep -F 'SECRET-LINE' "$area/notes/leak.md" >/dev/null
  grep -F 'Possible leak:' "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24.json" >/dev/null
  grep -F '"audience": "ada"' "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24.json" >/dev/null
  pass "possible leak"
  rm -rf "$box"
}

order_case() {
  local box company area ops
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" team "[]"
  area="$company/areas/finance"
  seed_area "$area"
  ops="$company/areas/ops"
  mkdir -p "$ops/notes"
  printf '%s\n' "ENGINE-DOWN" > "$ops/notes/down.md"
  git_identity
  init_git "$ops"
  set +e
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  local rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "later engine failure should exit 2"
  if git -C "$area" show-ref --verify --quiet refs/heads/review/2026-10-24; then
    fail "a pull request was opened before every engine call finished"
  fi
  if git -C "$ops" show-ref --verify --quiet refs/heads/review/2026-10-24; then
    fail "engine down still opened a review branch"
  fi
  [ "$(grep -c 'The review did not run.' "$XDG_CONFIG_HOME/acme-os/state/review.log")" = "1" ]
  pass "engine calls finish before any commit"
  rm -rf "$box"
}

twice_case() {
  local box company area before sha
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" team "[]"
  area="$company/areas/finance"
  seed_area "$area"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  bash "$company/skills/reports/run.sh" --root "$company" --date 2026-10-24 --week 2026-W43
  before=$(cat "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24.json")
  decide=$(git -C "$area" show "review/2026-10-24:reports/2026-10-24-to-decide.md")
  sha=$(git -C "$area" rev-parse "review/2026-10-24")
  git -C "$area" checkout -q main
  git -C "$area" merge -q --ff-only "review/2026-10-24"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  [ "$(git -C "$area" rev-parse "review/2026-10-24")" = "$sha" ] || fail "second run opened another review commit"
  [ "$(cat "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24.json")" = "$before" ] || fail "second run replaced the digest"
  bash "$company/skills/reports/run.sh" --root "$company" --date 2026-10-24 --week 2026-W43
  [ "$(git -C "$area" show "review/2026-10-24:reports/2026-10-24-to-decide.md")" = "$decide" ] || fail "second run changed the to-decide file"
  pass "second run keeps flags"
  rm -rf "$box"
}

missing_prompt_case() {
  local box company area
  box=$(mktemp -d)
  company="$box/acme"
  run_env "$box"
  make_company "$company" team "[]"
  area="$company/areas/finance"
  seed_area "$area"
  rm -f "$company/skills/nightly-review/review-prompt.md"
  set +e
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  local rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "missing prompt should exit 2"
  if git -C "$area" show-ref --verify --quiet refs/heads/review/2026-10-24; then
    fail "missing prompt still folded or committed"
  fi
  git -C "$area" cat-file -e "main:memory/logs/2026-09-23-mia.md"
  grep -F 'The review did not run.' "$XDG_CONFIG_HOME/acme-os/state/review.log" >/dev/null
  pass "missing prompt"
  rm -rf "$box"
}

leak_publish_case() {
  local box company area bare bodylog
  box=$(mktemp -d)
  company="$box/acme"
  bodylog="$box/bodies"
  : > "$bodylog"
  run_env "$box"
  unset OS_SKIP_PUSH
  export OS_SKIP_FETCH=1
  export OS_ARGV_SKIP_WHOAMI=1
  make_company "$company" team "[]"
  cat > "$company/skills/_host/host.sh" << EOF
#!/bin/bash
prev=
for a in "\$@"; do
  if [ "\$prev" = "--body-file" ]; then
    cat "\$a" >> "$bodylog"
    printf '\n' >> "$bodylog"
  fi
  prev=\$a
done
case "\$1" in
  open-pr)
    printf '%s\n' '{"number":1,"url":"http://example.com/1"}'
    ;;
  auto-merge)
    printf '%s\n' '{"ok":true}'
    ;;
  get-token)
    printf '%s\n' x
    ;;
  *)
    printf '%s\n' '{"ok":true}'
    ;;
esac
exit 0
EOF
  chmod 700 "$company/skills/_host/host.sh"
  area="$company/areas/finance"
  seed_area "$area"
  printf '%s\n' "SECRET-LINE" > "$area/notes/leak.md"
  printf '%s\n' "POSSIBLE-LEAK marker" >> "$area/notes/leak.md"
  git -C "$area" add notes/leak.md
  git -C "$area" -c user.name="Mia Member" -c user.email="mia@example.com" commit -q -m "Add a leak note"
  bare="$box/bare"
  git init -q --bare "$bare"
  git -C "$area" remote add origin "$bare"
  bash "$company/skills/nightly-review/run.sh" --root "$company" --date 2026-10-24
  bash "$company/skills/reports/run.sh" --root "$company" --date 2026-10-24 --week 2026-W43
  if grep -F 'Possible leak' "$bodylog" >/dev/null; then
    fail "possible leak is in the pull request body"
  fi
  if grep -F 'SECRET-LINE' "$bodylog" >/dev/null; then
    fail "leak text is in the pull request body"
  fi
  if git -C "$area" diff main..."review/2026-10-24" | grep -F 'Possible leak' >/dev/null; then
    fail "possible leak was committed"
  fi
  if git -C "$area" log "review/2026-10-24" --not main --format=%B | grep -F 'Possible leak' >/dev/null; then
    fail "possible leak is in a commit message"
  fi
  if git -C "$area" grep -F 'Possible leak' "review/2026-10-24" -- reports >/dev/null 2>&1; then
    fail "possible leak is in a report file"
  fi
  grep -F 'Possible leak:' "$XDG_CONFIG_HOME/acme-os/state/digests/2026-10-24-ada.md" >/dev/null
  pass "possible leak stays out of the repo"
  rm -rf "$box"
}

main_case
engine_down_case
leak_case
order_case
twice_case
missing_prompt_case
leak_publish_case
cap_case
solo_case
bots_case
mdx_case
( argv_case )
printf 'PASS: %s local checks\n' "$PASS"
