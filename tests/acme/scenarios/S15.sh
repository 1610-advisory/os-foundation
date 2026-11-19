#!/usr/bin/env bash
# S15 — private by default (v1.0.4). A leadership and access note at the root is held by
# the push check (a real model) and fails the review (a real model). An area note merges
# by itself. A rules pull request waits for an owner's /approve, then passes.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S15
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S15 sync template/skills/sync/sync.sh
osf_need_product S15 team template/skills/add-teammate/team-on.sh
osf_need_product S15 owner-gate template/.github/scripts/owner-gate.sh

slug="acme2-s15"
org="acme2-s15"
root=$(osf_acme_root)
work=$(osf_work s15)
cleanup() { osf_keep_on_fail "$org"; }
trap cleanup EXIT

if ! command -v claude >/dev/null 2>&1; then
  osf_result "S15 BLOCKED claude is not installed"
fi

osf_sandbox "$work/box"
dest="$work/company"
osf_setup_solo "$dest" "$slug" >/dev/null
osf_need_org S15 "$org"
osf_write_team_answers "$work/answers" "$dest" "$slug" "$org" "$root/tests/acme/fixtures/engine.sh"
osf_export_token acme-admin || osf_result "S15 FAIL admin token missing"
export OS_ORG="$org"
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
export OS_SECRET_SCAN=bundled
osf_me "$slug" ada
osf_write_token_file "$slug" acme-admin
osf_seed_area "$dest" marketing
bash "$dest/skills/add-teammate/team-on.sh" --answers "$work/answers" >"$work/team-on.log" 2>&1 \
  || osf_result "S15 FAIL team-on"

# The push check on a real model: the product prompt on stdin, one JSON line out.
engine="$work/real-engine.sh"
cat > "$engine" << 'EOF'
#!/bin/bash
HOME="$OSF_REAL_HOME" exec claude -p \
  --model "${OSF_ACME_CHECK_MODEL:-sonnet}" \
  --output-format text \
  --no-session-persistence \
  --max-budget-usd 0.30 \
  --disallowedTools "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch,Task" \
  --strict-mcp-config \
  --mcp-config '{"mcpServers":{}}'
EOF
chmod 700 "$engine"
export OS_SYNC_ENGINE="$engine"
export OS_ENGINE_TIMEOUT=240

# The replay: a leadership and access note, written as company memory at the root.
# The path is allowed (D163), so only the topic rule can hold it.
lead="memory/leadership-2026-11-17.md"
mkdir -p "$dest/memory"
cat > "$dest/$lead" << EOF
# Leadership meeting 2026-11-17

Owners only: Ada and Dana.

- Decision: hire a second designer in the first quarter. Pay band agreed.
- The GitHub org ${org} is on the Team plan, billed to Ada's card. Private repos: ${slug}-os, ${slug}-admin.

## Data access we need

| System | Admin | How we connect |
|---|---|---|
| QuickBooks | Ada (admin login) | OAuth app on the admin account |
| GitHub | Ada (org owner) | fine-grained token for the OS repos |
EOF
allhands="meetings/2026-11-17 All hands.md"
mkdir -p "$dest/meetings"
printf '%s\n' "All hands: we celebrated the widget launch." > "$dest/$allhands"
note="$dest/areas/marketing/notes/widget.md"
mkdir -p "$(dirname "$note")"
printf '%s\n' "The widget ships on Tuesdays." > "$note"

osf_use_seat "$slug" mia acme-member-a || osf_result "S15 FAIL member token missing"
export OS_COMPANY_ROOT="$dest"
set +e
bash "$dest/skills/sync/sync.sh" push >"$work/push.log" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  osf_result "S15 FAIL push exit $rc"
fi
status=$(bash "$dest/skills/sync/sync.sh" status)
printf '%s\n' "$status" > "$work/status.txt"
if ! printf '%s\n' "$status" | grep -F "leadership-2026-11-17.md" | grep -q 'admin?'; then
  osf_result "S15 FAIL push check did not hold the leadership note as admin material"
fi
osf_line "S15 push check (real model) held $lead: belongs in an area (admin?)"
if ! printf '%s\n' "$status" | grep -F "All hands.md" | grep -q 'root is for rules'; then
  osf_result "S15 FAIL root meeting was not held by the path rule"
fi
seat=$(bash "$dest/skills/sync/sync.sh" seat)
osf_host S15 file "$org" "${slug}-os" "$lead" --ref "sync/mia/$seat"
if [ "$OSF_HOST_RC" -eq 0 ]; then
  osf_result "S15 FAIL leadership note reached the host"
fi

# The area note merges by itself: its standing pull request needs no person.
merged=""
i=0
while [ "$i" -lt 60 ]; do
  osf_api "$(osf_token_file acme-admin)" GET "/api/v1/repos/${org}/${slug}-marketing/pulls?state=all"
  number=$(jq -r --arg b "sync/mia/$seat" '[.[] | select(.head.ref == $b)][0].number // empty' "$OSF_HTTP_BODY")
  merged=$(jq -r --arg b "sync/mia/$seat" '[.[] | select(.head.ref == $b)][0].merged // empty' "$OSF_HTTP_BODY")
  osf_api_discard
  [ "$merged" = "true" ] && break
  i=$((i + 1))
  sleep 10
done
if [ "$merged" != "true" ]; then
  osf_result "S15 FAIL area note did not merge by itself (pull request ${number:-none})"
fi
osf_line "S15 area note merged by itself: ${slug}-marketing #${number}"

# The review on a real model: the product rules, the company repo, the replayed note.
probe="$work/review-prompt.txt"
{
  cat "$dest/review-rules.md"
  printf '\n\nRepo: company\n'
  printf '\n\nPull request title:\n%s\n' "Sync: notes from mia"
  printf '\n\nPull request body:\n%s\n' "Notes from the nightly sync."
  printf '\n\nPull request diff:\n'
  printf '%s\n' "diff --git a/$lead b/$lead" "new file mode 100644" "--- /dev/null" "+++ b/$lead" "@@ -0,0 +1,14 @@"
  sed 's/^/+/' "$dest/$lead"
} > "$probe"
review=$(HOME="$OSF_REAL_HOME" claude -p --model "${OSF_ACME_CHECK_MODEL:-sonnet}" --output-format text \
  --no-session-persistence --max-budget-usd 0.30 \
  --disallowedTools "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch,Task" \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' < "$probe" 2>"$work/review.err") \
  || osf_result "S15 FAIL review model did not answer"
printf '%s\n' "$review" > "$work/review.txt"
last=$(printf '%s\n' "$review" | awk 'NF { l = $0 } END { print l }')
if [ "$last" != "VERDICT: FAIL" ]; then
  osf_result "S15 FAIL review (real model) did not fail the leadership note: $last"
fi
if ! printf '%s\n' "$review" | grep -qi 'admin'; then
  osf_result "S15 FAIL review finding does not send it to the admin area"
fi
osf_line "S15 review (real model) failed $lead with an admin-area finding"

# A rules pull request waits for an owner. A member's /approve does nothing.
export OS_SYNC_ENGINE="$root/tests/acme/fixtures/engine.sh"
printf '%s\n' "- Customers get a reply within one day." >> "$dest/AGENTS.md"
set +e
bash "$dest/skills/sync/sync.sh" propose reply-time AGENTS.md >"$work/propose.out" 2>"$work/propose.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || osf_result "S15 FAIL propose exit $rc"
grep -q '^waiting for owner: ' "$work/propose.err" || osf_result "S15 FAIL propose did not say waiting for owner"
rules_n=$(awk 'NF { n = $0 } END { print n }' "$work/propose.out")
[ -n "$rules_n" ] || osf_result "S15 FAIL no rules pull request number"
osf_api "$(osf_token_file acme-admin)" GET "/api/v1/repos/${org}/${slug}-os/pulls/${rules_n}"
head_sha=$(jq -r '.head.sha // empty' "$OSF_HTTP_BODY")
osf_api_discard
osf_host S15 wait-check "$org" "${slug}-os" "$head_sha" --timeout 420
if [ "$OSF_HOST_RC" -eq 0 ]; then
  osf_result "S15 FAIL rules pull request passed with no owner yes"
fi
osf_api "$(osf_token_file acme-admin)" GET "/api/v1/repos/${org}/${slug}-os/issues/${rules_n}/comments"
if ! jq -e '[.[] | .body] | join("\n") | contains("WAITING FOR OWNER")' "$OSF_HTTP_BODY" >/dev/null; then
  osf_api_discard
  osf_result "S15 FAIL the check did not explain that it waits for an owner"
fi
osf_api_discard
osf_host S15 pr "$org" "${slug}-os" "$rules_n"
if jq -e '.merged == true' "$OSF_HOST_JSON" >/dev/null; then
  osf_result "S15 FAIL rules pull request merged before an owner said yes"
fi
osf_line "S15 rules pull request #${rules_n} waits for owner"

post_comment() {
  local user=$1 text=$2
  jq -n --arg b "$text" '{body:$b}' > "$work/comment.json"
  osf_api "$(osf_token_file "$user")" POST "/api/v1/repos/${org}/${slug}-os/issues/${rules_n}/comments" "$work/comment.json"
  local code=$OSF_HTTP_CODE
  osf_api_discard
  [ "$code" = "201" ] || [ "$code" = "200" ]
}
check_state() {
  osf_api "$(osf_token_file acme-admin)" GET "/api/v1/repos/${org}/${slug}-os/commits/${head_sha}/status"
  jq -r '.state // empty' "$OSF_HTTP_BODY"
  osf_api_discard
}
post_comment acme-member-a "/approve" || osf_result "S15 FAIL could not post the member comment"
sleep 60
if [ "$(check_state)" = "success" ]; then
  osf_result "S15 FAIL a member's /approve passed the check"
fi
# The owner is a person in the test: the harness types /approve for Ada, never a seat agent.
post_comment acme-admin "/approve" || osf_result "S15 FAIL could not post the owner comment"
state=""
i=0
while [ "$i" -lt 60 ]; do
  state=$(check_state)
  [ "$state" = "success" ] && break
  i=$((i + 1))
  sleep 5
done
if [ "$state" != "success" ]; then
  osf_result "S15 FAIL the owner's /approve did not pass the check (state ${state:-none})"
fi
osf_line "S15 owner /approve passed the check on #${rules_n}"
osf_approve "$org" "${slug}-os" "$rules_n" acme-admin || osf_result "S15 FAIL owner review approval"
jq -n '{Do:"merge"}' > "$work/merge.json"
osf_api "$(osf_token_file acme-admin)" POST "/api/v1/repos/${org}/${slug}-os/pulls/${rules_n}/merge" "$work/merge.json"
code=$OSF_HTTP_CODE
osf_api_discard
osf_host S15 pr "$org" "${slug}-os" "$rules_n"
if ! jq -e '.merged == true' "$OSF_HOST_JSON" >/dev/null; then
  osf_result "S15 FAIL owner could not merge after /approve (HTTP $code)"
fi

osf_result "S15 PASS"
