#!/usr/bin/env bash
# Bring-up smoke. Prints one line: S0 PASS, S0 FAIL, or S0 BLOCKED.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/common.sh"
# shellcheck disable=SC1091
source "$here/../lib/api.sh"

say() {
  echo "S0 $*"
}

if ! docker info >/dev/null 2>&1; then
  say "BLOCKED Docker is not running"
  exit 0
fi

root=$(osf_acme_root)
lib=$(osf_acme_lib_dir)
out="$root/tests/acme/.out/s0"
mkdir -p "$out"
log="$out/s0.log"
: > "$log"

if ! "$root/tests/acme/forgejo/up.sh" >>"$log" 2>&1; then
  say "BLOCKED Forgejo did not start"
  exit 0
fi
if ! "$root/tests/acme/forgejo/bootstrap.sh" >>"$log" 2>&1; then
  say "FAIL bootstrap"
  exit 0
fi

fail() {
  say "FAIL $*"
  exit 0
}

while IFS='|' read -r _seat _engine username _full_name _email; do
  [ -n "$username" ] || continue
  if ! python3 "$lib/results.py" user-exists "$username" >>"$log" 2>&1; then
    fail "missing user $username"
  fi
done < "$lib/seats.txt"

if ! python3 "$lib/results.py" org-exists acme >>"$log" 2>&1; then
  fail "missing org"
fi
if ! python3 "$lib/results.py" runner-online >>"$log" 2>&1; then
  fail "runner offline"
fi

stamp="$(date +%s)-$$"
smoke="s0-smoke-${stamp}"
private="s0-private-${stamp}"
admin_token="$(osf_acme_token_dir)/acme-admin"

cleanup() {
  osf_api "$admin_token" DELETE "/api/v1/repos/acme/${smoke}" || true
  osf_api_discard
  osf_api "$admin_token" DELETE "/api/v1/repos/acme-admin/${private}" || true
  osf_api_discard
}
trap cleanup EXIT

body=$(mktemp)
jq -n --arg name "$smoke" '{name:$name, private:true, auto_init:true, default_branch:"main"}' > "$body"
osf_api "$admin_token" POST "/api/v1/orgs/acme/repos" "$body"
code="$OSF_HTTP_CODE"
osf_api_discard
rm -f "$body"
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
  fail "could not create smoke repo"
fi

workflow='name: checks
on:
  pull_request:
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - run: echo smoke-ok
'
b64=$(printf '%s\n' "$workflow" | base64 | tr -d '\n')
body=$(mktemp)
jq -n --arg content "$b64" '{message:"add checks", content:$content, branch:"main"}' > "$body"
osf_api "$admin_token" POST "/api/v1/repos/acme/${smoke}/contents/.github/workflows/checks.yml" "$body"
code="$OSF_HTTP_CODE"
osf_api_discard
rm -f "$body"
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
  fail "could not add workflow"
fi

body=$(mktemp)
jq -n '{new_branch_name:"s0-pr", old_branch_name:"main"}' > "$body"
osf_api "$admin_token" POST "/api/v1/repos/acme/${smoke}/branches" "$body"
code="$OSF_HTTP_CODE"
osf_api_discard
rm -f "$body"
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
  fail "could not create branch"
fi

note_b64=$(printf '%s\n' "s0 note" | base64 | tr -d '\n')
body=$(mktemp)
jq -n --arg content "$note_b64" '{message:"s0 note", content:$content, branch:"s0-pr"}' > "$body"
osf_api "$admin_token" POST "/api/v1/repos/acme/${smoke}/contents/note.txt" "$body"
code="$OSF_HTTP_CODE"
osf_api_discard
rm -f "$body"
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
  fail "could not add note"
fi

body=$(mktemp)
jq -n '{title:"s0 smoke", head:"s0-pr", base:"main"}' > "$body"
osf_api "$admin_token" POST "/api/v1/repos/acme/${smoke}/pulls" "$body"
code="$OSF_HTTP_CODE"
pr_body="$OSF_HTTP_BODY"
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
  osf_api_discard
  rm -f "$body"
  fail "could not open pull request"
fi
sha=$(jq -r '.head.sha // empty' "$pr_body")
osf_api_discard
rm -f "$body"
if [ -z "$sha" ]; then
  fail "pull request has no head"
fi

if ! python3 "$lib/results.py" wait-check acme "$smoke" "$sha" --timeout 180 >>"$log" 2>&1; then
  docker logs --tail 120 osf-acme-runner > "$out/runner.raw" 2>&1 || true
  python3 "$lib/scrub.py" --secrets-dir "$(osf_acme_cache)" --out "$out/runner.log" "$out/runner.raw" || true
  rm -f "$out/runner.raw"
  fail "checks did not succeed"
fi

body=$(mktemp)
jq -n --arg name "$private" '{name:$name, private:true, auto_init:true}' > "$body"
osf_api "$admin_token" POST "/api/v1/user/repos" "$body"
code="$OSF_HTTP_CODE"
osf_api_discard
rm -f "$body"
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
  fail "could not create private repo"
fi

if ! python3 "$lib/results.py" clone-denied acme-member-d acme-admin "$private" >>"$log" 2>&1; then
  fail "member-d could clone a private repo"
fi

say "PASS"
