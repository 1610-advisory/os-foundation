#!/usr/bin/env bash
# S13 — short admin run on each first-class engine. One line per engine, then a summary.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S13
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

root=$(osf_acme_root)
org="acme2-s13"
cleanup() { osf_keep_on_fail "$org"; }
trap cleanup EXIT
osf_need_org S13 "$org"
fail=0
blocked=0
for engine in claude codex cursor pi; do
  seat=$(osf_engine_name "$engine")
  if ! line=$(osf_seat_line "$seat"); then
    prefix="BLOCKED: ${seat} "
    reason=${line#"$prefix"}
    osf_line "S13 $engine BLOCKED $reason"
    blocked=$((blocked + 1))
    continue
  fi
  if [ ! -f "$root/template/skills/add-teammate/add-person.sh" ] \
    || [ ! -f "$root/template/skills/remove-teammate/remove.sh" ]; then
    osf_line "S13 $engine BLOCKED not merged: team"
    blocked=$((blocked + 1))
    continue
  fi
  work=$(osf_work "s13-$engine")
  osf_sandbox "$work/box"
  dest="$work/company"
  osf_setup_solo "$dest" "acme2-s13" >/dev/null || {
    osf_line "S13 $engine FAIL setup"
    fail=$((fail + 1))
    continue
  }
  repo="acme2-s13-${engine}"
  body=$(mktemp)
  chmod 600 "$body"
  jq -n --arg name "$repo" '{name:$name, private:true, auto_init:false}' > "$body"
  osf_api "$(osf_token_file acme-admin)" POST "/api/v1/orgs/${org}/repos" "$body"
  code="$OSF_HTTP_CODE"
  rm -f "$body"
  osf_api_discard
  if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    osf_line "S13 $engine FAIL clean start failed"
    fail=$((fail + 1))
    continue
  fi
  user=$(awk -F'|' -v s="$seat" '$1 == s { print $3 }' "$root/tests/acme/lib/seats.txt")
  body=$(mktemp)
  chmod 600 "$body"
  jq -n '{permission:"write"}' > "$body"
  osf_api "$(osf_token_file acme-admin)" PUT "/api/v1/repos/${org}/${repo}/collaborators/${user}" "$body" || true
  rm -f "$body"
  osf_api_discard
  git -C "$dest" remote add origin "$(osf_acme_url)/${org}/${repo}.git"
  prompt="$work/prompt.txt"
  printf '%s\n' "Read company-profile.md. Add one sentence to notes/admin.md: the admin run wrote this. Commit that file and push it to origin. Do not change git identity." > "$prompt"
  if ! bash "$root/tests/acme/seat.sh" "$seat" "$prompt" --cwd "$dest" >"$work/seat.log" 2>&1; then
    if grep -q '^BLOCKED:' "$work/seat.log"; then
      reason=$(sed -n 's/^BLOCKED: //p' "$work/seat.log" | head -n 1)
      osf_line "S13 $engine BLOCKED $reason"
      blocked=$((blocked + 1))
    else
      osf_line "S13 $engine FAIL seat"
      fail=$((fail + 1))
    fi
    continue
  fi
  osf_host S13 file "$org" "$repo" notes/admin.md --ref main
  page=$(cat "$OSF_HOST_JSON")
  found=0
  if [ "$OSF_HOST_RC" -eq 0 ]; then
    set +e
    printf '%s\n' "$page" | grep -q 'the admin run wrote this'
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      found=1
    fi
  fi
  if [ "$found" -ne 1 ]; then
    osf_line "S13 $engine FAIL note is not on the host"
    fail=$((fail + 1))
    continue
  fi
  osf_line "S13 $engine PASS"
done

if [ "$fail" -gt 0 ]; then
  osf_result "S13 FAIL"
fi
if [ "$blocked" -gt 0 ]; then
  osf_result "S13 BLOCKED engines not ready"
fi
osf_result "S13 PASS"
