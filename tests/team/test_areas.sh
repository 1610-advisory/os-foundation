#!/bin/bash
# One, two, and three areas must all be granted. Never print a token.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"

expect_split() {
  local input=$1 expected=$2 got
  got=$(os_split_areas "$input")
  [ "$got" = "$expected" ] || team_fail "split '${input}' got '${got}' want '${expected}'"
}

expect_split "marketing" "marketing"
expect_split "marketing,finance" "$(printf '%s\n' marketing finance)"
expect_split "red, blue, green" "$(printf '%s\n' red blue green)"
expect_split "red," "red"
expect_split "" ""

count_here() {
  local n=0 a
  while IFS= read -r a || [ -n "$a" ]; do
    [ -n "$a" ] || continue
    n=$((n + 1))
  done << EOF
$(os_split_areas "$1")
EOF
  printf '%s\n' "$n"
}
[ "$(count_here marketing)" = "1" ] || team_fail "one area was dropped"
[ "$(count_here marketing,finance)" = "2" ] || team_fail "two areas dropped the last"
[ "$(count_here red,blue,green)" = "3" ] || team_fail "three areas dropped the last"

if ! curl -fsS --max-time 5 http://localhost:3300/api/v1/version >/dev/null 2>&1; then
  printf '%s\n' "PASS areas"
  exit 0
fi

token_dir="${HOME}/.cache/os-foundation/forgejo/tokens"
admin_token="$token_dir/acme-admin"
[ -s "$admin_token" ] || team_fail "admin token file is missing"

slug="c5$$"
work=$(mktemp -d)
log="$work/log"
: > "$log"
HOST="$root/template/skills/_host/host.sh"
export OS_HOST_SH="$HOST" OS_TEST_MODE=1 OS_HOST=forgejo OS_HOST_URL="http://localhost:3300"
export OS_ORG=acme OS_SLUG="$slug" GIT_TERMINAL_PROMPT=0
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" OS_JOBS_DIR="$work/jobs"
mkdir -p "$HOME"

load_token() {
  tr -d '[:space:]' < "$1"
}

cleanup() {
  local name
  export FORGEJO_TOKEN
  FORGEJO_TOKEN=$(load_token "$admin_token")
  for name in "${slug}-os" "${slug}-red" "${slug}-blue" "${slug}-green" \
    "${slug}-user-ada" "${slug}-user-one" "${slug}-user-two" "${slug}-user-three"; do
    "$HOST" delete-repo "$name" --yes-test-only >/dev/null 2>>"$log" || true
  done
  rm -rf "$work"
}
trap cleanup EXIT

company="$work/company"
mkdir -p "$company"
cp -R "$root/template/." "$company/"
python3 - "$company/company-profile.md" "$slug" << 'PY'
import pathlib, sys
path, slug = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text()
text = text.replace("{{COMPANY_SLUG}}", slug)
text = text.replace("{{COMPANY_NAME}}", "Acme Co")
text = text.replace("{{DATE}}", "2026-10-24")
text = text.replace("{{ONE_LINER}}", "A test company")
text = text.replace("{{OS_VERSION}}", "v1.0.0")
pathlib.Path(path).write_text(text)
PY

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
for area in red blue green; do
  mkdir -p "$company/areas/$area"
  printf '%s\n' "# $area" > "$company/areas/$area/AGENTS.md"
  init_repo "$company/areas/$area"
done
init_repo "$company"

at='@'
cat > "$work/answers" << EOF
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
person.ada.areas=red,blue,green
person.one.name=One Member
person.one.github=acme-member-a
person.one.email=one${at}acme.test
person.one.role=writer
person.one.areas=red
person.two.name=Two Member
person.two.github=acme-member-b
person.two.email=two${at}acme.test
person.two.role=writer
person.two.areas=red,blue
person.three.name=Three Member
person.three.github=acme-member-c
person.three.email=three${at}acme.test
person.three.role=writer
person.three.areas=red,blue,green
area.red.director=ada
area.blue.director=ada
area.green.director=ada
EOF

export FORGEJO_TOKEN
FORGEJO_TOKEN=$(load_token "$admin_token")
export OS_PROFILE="$company/company-profile.md"
if ! "$root/template/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.out" 2>>"$log"; then
  cat "$work/team-on.out" >> "$log"
  team_fail "team-on failed"
fi

check_access() {
  local repo=$1 user=$2 want=$3 got
  got=$("$HOST" user-access "$repo" "$user")
  printf '%s' "$got" | jq -e --arg want "$want" '.access == $want' >/dev/null \
    || team_fail "$user on $repo is ${got} want ${want}"
}

check_access "${slug}-red" acme-member-a write
check_access "${slug}-blue" acme-member-a none
check_access "${slug}-green" acme-member-a none
check_access "${slug}-red" acme-member-b write
check_access "${slug}-blue" acme-member-b write
check_access "${slug}-green" acme-member-b none
check_access "${slug}-red" acme-member-c write
check_access "${slug}-blue" acme-member-c write
check_access "${slug}-green" acme-member-c write

printf '%s\n' "PASS areas"
