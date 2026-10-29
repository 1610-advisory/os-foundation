#!/usr/bin/env bash
# Run the checks workflow on the local Forgejo. Results come from the API.
# Does not print tokens. Does not wipe the Forgejo volume.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
# shellcheck disable=SC1091
source "$root/tests/acme/lib/common.sh"
# shellcheck disable=SC1091
source "$root/tests/acme/lib/api.sh"

usage() {
  cat << 'EOF'
usage: tests/ci/run.sh

Run the checks workflow on the shared Acme Forgejo.
Prints one PASS or FAIL line per scenario.
Tokens are not printed. The Forgejo volume is not wiped.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi
if [ $# -ne 0 ]; then
  usage >&2
  exit 1
fi

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

if ! docker info >/dev/null 2>&1; then
  echo "BLOCKED: Docker is not running"
  exit 0
fi
if ! curl -fsS --max-time 5 "$(osf_acme_url)/api/v1/version" >/dev/null 2>&1; then
  echo "BLOCKED: Forgejo is not ready on localhost:3300"
  exit 0
fi

host_src="$root/template/skills/_host"
if [ ! -f "$host_src/host.sh" ]; then
  echo "BLOCKED: host layer is not in this worktree"
  exit 0
fi

admin="$(osf_acme_token_dir)/acme-admin"
member="$(osf_acme_token_dir)/acme-member-a"
lib=$(osf_acme_lib_dir)
stamp="$(date +%s)-$$"
repo="ci-checks-${stamp}"
area_repo=""
EXTRA_REPOS=""
work=$(mktemp -d)
# Every later temp file lands in the work folder, which cleanup removes.
mkdir "$work/tmp"
export TMPDIR="$work/tmp"
log="$work/run.log"
: > "$log"
runner_saved="$work/runner-config.yml"
runner_changed=0

scrub_log() {
  if [ -f "$1" ]; then
    python3 "$lib/scrub.py" --secrets-dir "$(osf_acme_cache)" "$1" >&2 || true
  fi
}

restore_runner() {
  if [ "$runner_changed" = "1" ] && [ -s "$runner_saved" ]; then
    docker cp "$runner_saved" osf-acme-runner:/data/config.yml >/dev/null 2>&1 || true
    docker exec -u 0 osf-acme-runner chmod 600 /data/config.yml >/dev/null 2>&1 || true
    docker restart osf-acme-runner >/dev/null 2>&1 || true
    runner_changed=0
  fi
}

cleanup() {
  restore_runner
  if [ -x "$work/host/host.sh" ] && [ -f "$admin" ]; then
    export OS_TEST_MODE=1
    FORGEJO_TOKEN=$(tr -d '[:space:]' < "$admin")
    export FORGEJO_TOKEN
    for name in "$repo" ${area_repo:-} ${EXTRA_REPOS:-}; do
      [ -n "$name" ] || continue
      "$work/host/host.sh" delete-repo "$name" --yes-test-only >>"$log" 2>&1 || true
    done
  fi
  scrub_log "$log"
  rm -rf "$work"
}
trap cleanup EXIT

export OS_HOST=forgejo
export OS_HOST_URL
OS_HOST_URL=$(osf_acme_url)
export OS_ORG=acme
export OS_SLUG=acme
export OS_TEST_MODE=1
export FORGEJO_TOKEN
FORGEJO_TOKEN=$(tr -d '[:space:]' < "$admin")
export XDG_CONFIG_HOME="$work/config"
mkdir -p "$XDG_CONFIG_HOME" "$work/host"
cp "$host_src"/*.sh "$work/host/"
chmod +x "$work/host/"*.sh

src="$work/src"
mkdir -p "$src/.github/workflows" "$src/.github/scripts" "$src/skills" "$src/.agents" "$src/.claude" "$src/people"
printf '%s\n' 'Company skills live here.' > "$src/skills/README.md"
ln -s ../skills "$src/.agents/skills"
ln -s ../skills "$src/.claude/skills"
cp "$root/template/.github/workflows/checks.yml" "$src/.github/workflows/checks.yml"
cp -R "$root/template/.github/scripts/." "$src/.github/scripts/"
cp "$root/template/review-rules.md" "$src/review-rules.md"
chmod +x "$src/.github/scripts/"*.sh "$src/.github/scripts/tools/"*.sh "$src/.github/scripts/tools/host/"*.sh
cat > "$src/company-profile.md" << 'EOF'
---
type: company-profile
summary: "Acme Co checks"
updated: 2026-10-24
company_slug: acme
level: team
switches: []
os_version: 0
host: forgejo
host_url: "http://forgejo:3000"
org: "acme"
sync_engine: ""
runner: ubuntu-latest
---
EOF
printf '%s\n' '# Acme' > "$src/AGENTS.md"
printf '%s\n' 'A note.' > "$src/note.txt"
# Product owners. A hand-written root CODEOWNERS hid the Forgejo gap.
# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"
os_codeowners "$src" "$(os_at_users acme-admin acme-admin)"
cat > "$src/people/Ada.md" << 'EOF'
---
github: acme-admin
role: admin
---
Ada Admin
EOF
git -C "$src" init -q -b main
git -C "$src" config user.email ada.admin@acme.test
git -C "$src" config user.name "Ada Admin"
git -C "$src" add .
git -C "$src" commit -q -m "init"

if ! "$work/host/host.sh" create-repo "$repo" --source "$src" --push >>"$log" 2>&1; then
  fail "create repo"
  echo "CI: PASS $PASS FAIL $FAIL"
  exit 1
fi
"$work/host/host.sh" grant "$repo" acme-member-a write >>"$log" 2>&1
"$work/host/host.sh" protect "$repo" --code-owners --approvals 0 >>"$log" 2>&1

docker cp osf-acme-runner:/data/config.yml "$runner_saved"
python3 - "$runner_saved" "$work/runner-new.yml" << 'PY'
import sys
from pathlib import Path
src, dest = sys.argv[1:]
text = Path(src).read_text(encoding="utf-8")
if "OS_REVIEW_FAKE:" not in text:
    text = text.replace(
        "    DOCKER_CERT_PATH: /certs/client\n",
        "    DOCKER_CERT_PATH: /certs/client\n    OS_REVIEW_FAKE: /opt/os-review-fake/verdicts.txt\n",
        1,
    )
old = 'options: "-v /certs/client:/certs/client:ro"'
new = 'options: "-v /certs/client:/certs/client:ro -v /opt/os-review-fake:/opt/os-review-fake:ro"'
if old in text:
    text = text.replace(old, new, 1)
if "  - /opt/os-review-fake\n" not in text:
    text = text.replace("    - /certs/client\n", "    - /certs/client\n    - /opt/os-review-fake\n", 1)
Path(dest).write_text(text, encoding="utf-8")
PY
if ! grep -q 'OS_REVIEW_FAKE:' "$work/runner-new.yml"; then
  echo "BLOCKED: could not set the runner fake-review path"
  echo "CI: PASS $PASS FAIL $FAIL"
  exit 0
fi
docker exec osf-acme-dind mkdir -p /opt/os-review-fake
docker exec -i osf-acme-dind sh -c 'cat > /opt/os-review-fake/verdicts.txt && chmod 644 /opt/os-review-fake/verdicts.txt' \
  < "$here/fixtures/verdicts.txt"
docker cp "$work/runner-new.yml" osf-acme-runner:/data/config.yml
docker exec -u 0 osf-acme-runner chmod 600 /data/config.yml
runner_changed=1
docker restart osf-acme-runner >/dev/null
if ! python3 "$lib/results.py" runner-online >/dev/null 2>&1; then
  i=0
  while [ "$i" -lt 20 ]; do
    if python3 "$lib/results.py" runner-online >/dev/null 2>&1; then
      break
    fi
    i=$((i + 1))
    sleep 2
  done
fi
if ! python3 "$lib/results.py" runner-online >/dev/null 2>&1; then
  echo "BLOCKED: runner did not come back"
  echo "CI: PASS $PASS FAIL $FAIL"
  exit 0
fi

as_user() {
  local file=$1
  FORGEJO_TOKEN=$(tr -d '[:space:]' < "$file")
  export FORGEJO_TOKEN
}

push_branch() {
  local token_file=$1 branch=$2
  local ask
  ask=$(mktemp)
  chmod 700 "$ask"
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "git" ;;
  *) cat "$OS_TOKEN_FILE" ;;
esac
EOF
  OS_TOKEN_FILE=$token_file GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -C "$src" -c credential.helper= push origin "HEAD:refs/heads/${branch}" >>"$log" 2>&1
  rm -f "$ask"
}

open_pr() {
  local token_file=$1 branch=$2 title=$3
  local body rc n
  body=$(mktemp)
  printf '%s\n' "$title" > "$body"
  as_user "$token_file"
  n=0
  while true; do
    set +e
    "$work/host/host.sh" open-pr "$repo" --head "$branch" --base main --title "$title" --body-file "$body" >"$work/pr.json"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      break
    fi
    if [ "$rc" -ne 2 ] || [ "$n" -ge 10 ]; then
      rm -f "$body"
      return "$rc"
    fi
    n=$((n + 1))
    printf '%s\n' "NOTE open-pr retry ${n}" >> "$log"
    sleep 1
  done
  rm -f "$body"
  jq -r '.number' "$work/pr.json"
}

pr_sha() {
  local number=$1
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${number}"
  jq -r '.head.sha // empty' "$OSF_HTTP_BODY"
  osf_api_discard
}

approve_and_merge() {
  local number=$1 approver=$2
  local body i merged
  as_user "$admin"
  "$work/host/host.sh" auto-merge "$repo" "$number" >>"$log" 2>&1 || true
  body=$(mktemp)
  printf '%s\n' '{"event":"APPROVED","body":"ok"}' > "$body"
  osf_api "$approver" POST "/api/v1/repos/acme/${repo}/pulls/${number}/reviews" "$body"
  osf_api_discard
  rm -f "$body"
  as_user "$admin"
  "$work/host/host.sh" auto-merge "$repo" "$number" >>"$log" 2>&1 || true
  i=0
  merged=false
  while [ "$i" -lt 20 ]; do
    osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${number}"
    merged=$(jq -r '.merged' "$OSF_HTTP_BODY")
    osf_api_discard
    if [ "$merged" = "true" ]; then
      return 0
    fi
    i=$((i + 1))
    sleep 3
  done
  return 1
}

wait_sha() {
  local want=$2
  local i=0 state fails=0
  while [ "$i" -lt 40 ]; do
    osf_api "$admin" GET "/api/v1/repos/acme/${repo}/commits/${want}/status"
    state=$(jq -r '.state // empty' "$OSF_HTTP_BODY")
    osf_api_discard
    if [ "$state" = "success" ]; then
      return 0
    fi
    if [ "$state" = "failure" ] || [ "$state" = "error" ]; then
      fails=$((fails + 1))
      if [ "$fails" -ge 2 ]; then
        return 2
      fi
    else
      fails=0
    fi
    i=$((i + 1))
    sleep 5
  done
  return 2
}

comment() {
  local token_file=$1 number=$2 text=$3
  local body
  body=$(mktemp)
  printf '%s\n' "$text" > "$body"
  as_user "$token_file"
  "$work/host/host.sh" pr-comment "$repo" "$number" --body-file "$body" >>"$log" 2>&1
  rm -f "$body"
}

comments_text() {
  local number=$1
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/issues/${number}/comments?limit=50"
  jq -r '.[].body' "$OSF_HTTP_BODY"
  osf_api_discard
}

new_branch() {
  local name=$1
  git -C "$src" checkout -q main
  git -C "$src" checkout -q -B "$name"
}

# Notes pull request: checks pass, then auto-merge.
new_branch notes
printf '%s\n' 'A longer note.' >> "$src/note.txt"
git -C "$src" add note.txt
git -C "$src" commit -q -m "extend the note"
push_branch "$admin" notes
notes_pr=$(open_pr "$admin" notes "Extend a note")
as_user "$admin"
"$work/host/host.sh" auto-merge "$repo" "$notes_pr" >>"$log" 2>&1 || true
notes_sha=$(pr_sha "$notes_pr")
if wait_sha "$notes_pr" "$notes_sha"; then
  pass "notes checks"
else
  fail "notes checks"
fi
merged=0
i=0
while [ "$i" -lt 20 ]; do
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${notes_pr}"
  if [ "$(jq -r '.merged' "$OSF_HTTP_BODY")" = "true" ]; then
    merged=1
  fi
  osf_api_discard
  if [ "$merged" = "1" ]; then
    break
  fi
  i=$((i + 1))
  sleep 3
done
if [ "$merged" != "1" ]; then
  as_user "$admin"
  "$work/host/host.sh" auto-merge "$repo" "$notes_pr" >>"$log" 2>&1 || true
  i=0
  while [ "$i" -lt 15 ]; do
    osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${notes_pr}"
    if [ "$(jq -r '.merged' "$OSF_HTTP_BODY")" = "true" ]; then
      merged=1
    fi
    osf_api_discard
    if [ "$merged" = "1" ]; then
      break
    fi
    i=$((i + 1))
    sleep 3
  done
fi
if [ "$merged" = "1" ]; then
  pass "notes auto-merge"
else
  fail "notes auto-merge"
fi

# Planted secret.
new_branch secret
printf '%s%s %s%s\n' '-----BE' 'GIN' 'PRIVATE' ' KEY' > "$src/secret.txt"
git -C "$src" add secret.txt
git -C "$src" commit -q -m "add a file"
push_branch "$member" secret
secret_pr=$(open_pr "$member" secret "Add a file")
secret_sha=$(pr_sha "$secret_pr")
set +e
wait_sha "$secret_pr" "$secret_sha"
secret_rc=$?
set -e
if [ "$secret_rc" -eq 2 ]; then
  pass "secret scan fails"
else
  fail "secret scan fails"
fi

# Lint failure. The shipped lint fails when AGENTS.md is over 10000 characters.
new_branch lint
python3 -c 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_text("x"*10001)' "$src/AGENTS.md"
git -C "$src" add AGENTS.md
git -C "$src" commit -q -m "mark lint"
push_branch "$member" lint
lint_pr=$(open_pr "$member" lint "Mark lint")
lint_sha=$(pr_sha "$lint_pr")
set +e
wait_sha "$lint_pr" "$lint_sha"
lint_rc=$?
set -e
if [ "$lint_rc" -eq 2 ]; then
  pass "lint fails"
else
  fail "lint fails"
fi

# Review failure, member override, admin override.
new_branch review
printf '%s\n' 'OSF_REVIEW_FAIL' > "$src/review.txt"
git -C "$src" add review.txt
git -C "$src" commit -q -m "mark review"
push_branch "$member" review
review_pr=$(open_pr "$member" review "Mark review")
review_sha=$(pr_sha "$review_pr")
set +e
wait_sha "$review_pr" "$review_sha"
review_rc=$?
set -e
if [ "$review_rc" -eq 2 ]; then
  pass "review fails"
else
  fail "review fails"
fi
comment "$member" "$review_pr" "/override please"
sleep 5
ignored=$(comments_text "$review_pr" || true)
if printf '%s\n' "$ignored" | grep -q 'override ignored:'; then
  pass "member override ignored"
else
  # The comment job may still be queued.
  i=0
  while [ "$i" -lt 36 ]; do
    ignored=$(comments_text "$review_pr" || true)
    if printf '%s\n' "$ignored" | grep -q 'override ignored:'; then
      break
    fi
    i=$((i + 1))
    sleep 5
  done
  if printf '%s\n' "$ignored" | grep -q 'override ignored:'; then
    pass "member override ignored"
  else
    fail "member override ignored"
  fi
fi
comment "$admin" "$review_pr" "/override the marker is a test"
i=0
overrode=0
while [ "$i" -lt 36 ]; do
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/commits/${review_sha}/status"
  state=$(jq -r '.state // empty' "$OSF_HTTP_BODY")
  osf_api_discard
  recorded=$(comments_text "$review_pr" || true)
  if [ "$state" = "success" ] && printf '%s\n' "$recorded" | grep -q "override by acme-admin for ${review_sha}: the marker is a test"; then
    overrode=1
    break
  fi
  i=$((i + 1))
  sleep 5
done
if [ "$overrode" = "1" ]; then
  pass "admin override"
else
  fail "admin override"
fi

# P1: a later push runs the review again. The old override does not stick.
git -C "$src" checkout -q review
printf '%s\n' 'still failing' >> "$src/review.txt"
git -C "$src" add review.txt
git -C "$src" commit -q -m "another review change"
push_branch "$member" review
later_sha=$(pr_sha "$review_pr")
set +e
wait_sha "$review_pr" "$later_sha"
later_rc=$?
set -e
if [ "$later_sha" != "$review_sha" ] && [ "$later_rc" -eq 2 ]; then
  pass "override does not stick"
else
  fail "override does not stick"
fi

# P1: head scripts are not executed. A planted secret still fails.
new_branch hijack
printf '%s\n' '#!/bin/bash' 'exit 0' > "$src/.github/scripts/run-checks.sh"
chmod +x "$src/.github/scripts/run-checks.sh"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$src/.github/scripts/tools/secret-scan.sh"
chmod +x "$src/.github/scripts/tools/secret-scan.sh"
printf '%s%s %s%s\n' '-----BE' 'GIN' 'PRIVATE' ' KEY' > "$src/secret.txt"
git -C "$src" add .github/scripts/run-checks.sh .github/scripts/tools/secret-scan.sh secret.txt
git -C "$src" commit -q -m "replace the check"
push_branch "$member" hijack
hijack_pr=$(open_pr "$member" hijack "Replace the check")
hijack_sha=$(pr_sha "$hijack_pr")
set +e
wait_sha "$hijack_pr" "$hijack_sha"
hijack_rc=$?
set -e
if [ "$hijack_rc" -eq 2 ]; then
  pass "head script ignored"
else
  fail "head script ignored"
fi

# P1: a head lint script that writes a marker is never run.
new_branch lint-hijack
printf '%s\n' '#!/bin/bash' 'echo OSF_LINT_RAN' 'exit 0' > "$src/.github/scripts/tools/lint.sh"
chmod +x "$src/.github/scripts/tools/lint.sh"
python3 -c 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_text("x"*10001)' "$src/AGENTS.md"
git -C "$src" add .github/scripts/tools/lint.sh AGENTS.md
git -C "$src" commit -q -m "replace lint"
push_branch "$member" lint-hijack
lint_hijack_pr=$(open_pr "$member" lint-hijack "Replace lint")
lint_hijack_sha=$(pr_sha "$lint_hijack_pr")
set +e
wait_sha "$lint_hijack_pr" "$lint_hijack_sha"
lint_hijack_rc=$?
set -e
osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/runs?limit=10"
run_id=$(python3 -c 'import json,sys; raw=json.load(open(sys.argv[1])); rows=raw if isinstance(raw,list) else raw.get("workflow_runs") or raw.get("runs") or []; print(next((str(r.get("id")) for r in rows if r.get("head_sha")==sys.argv[2]), ""))' "$OSF_HTTP_BODY" "$lint_hijack_sha")
osf_api_discard
log_hit=0
if [ -n "$run_id" ]; then
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/runs/${run_id}/jobs"
  job_id=$(jq -r 'if type=="array" then .[0].id else (.jobs[0].id // empty) end' "$OSF_HTTP_BODY")
  osf_api_discard
  if [ -n "$job_id" ] && [ "$job_id" != "null" ]; then
    osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/jobs/${job_id}/logs"
    if grep -q 'OSF_LINT_RAN' "$OSF_HTTP_BODY"; then
      log_hit=1
    fi
    osf_api_discard
  fi
fi
if [ "$lint_hijack_rc" -eq 2 ] && [ "$log_hit" -eq 0 ]; then
  pass "head lint ignored"
else
  fail "head lint ignored"
fi

# Rules file waits for the owner.
new_branch rules
printf '%s\n' 'Changed rule.' >> "$src/AGENTS.md"
git -C "$src" add AGENTS.md
git -C "$src" commit -q -m "change a rule"
push_branch "$member" rules
rules_pr=$(open_pr "$member" rules "Change a rule")
rules_sha=$(pr_sha "$rules_pr")
if wait_sha "$rules_pr" "$rules_sha"; then
  pass "rules checks"
else
  fail "rules checks"
fi
osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${rules_pr}"
reviewers=$(jq -r '[.requested_reviewers[]?.login] | join(" ")' "$OSF_HTTP_BODY")
osf_api_discard
if printf '%s' "$reviewers" | grep -q acme-admin; then
  pass "rules requests owner"
else
  fail "rules requests owner"
fi
as_user "$admin"
set +e
"$work/host/host.sh" auto-merge "$repo" "$rules_pr" >>"$log" 2>&1
set -e
sleep 3
osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${rules_pr}"
rules_merged=$(jq -r '.merged' "$OSF_HTTP_BODY")
osf_api_discard
if [ "$rules_merged" != "true" ]; then
  pass "rules blocked"
else
  fail "rules blocked"
fi
body=$(mktemp)
printf '%s\n' '{"event":"APPROVED","body":"ok"}' > "$body"
osf_api "$admin" POST "/api/v1/repos/acme/${repo}/pulls/${rules_pr}/reviews" "$body"
approve_code=$OSF_HTTP_CODE
osf_api_discard
rm -f "$body"
if [ "$approve_code" != "200" ] && [ "$approve_code" != "201" ]; then
  fail "owner approves"
else
  as_user "$admin"
  "$work/host/host.sh" auto-merge "$repo" "$rules_pr" >>"$log" 2>&1 || true
  i=0
  rules_merged=false
  while [ "$i" -lt 20 ]; do
    osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${rules_pr}"
    rules_merged=$(jq -r '.merged' "$OSF_HTTP_BODY")
    osf_api_discard
    if [ "$rules_merged" = "true" ]; then
      break
    fi
    i=$((i + 1))
    sleep 3
  done
  if [ "$rules_merged" = "true" ]; then
    pass "rules merges after approval"
  else
    fail "rules merges after approval"
  fi
fi

# A root CODEOWNERS is read before .gitea/CODEOWNERS. Owning that path blocks the add.
new_branch root-owners
printf '%s\n' '* @acme-member-a' > "$src/CODEOWNERS"
git -C "$src" add CODEOWNERS
git -C "$src" commit -q -m "add a root owners file"
push_branch "$member" root-owners
root_pr=$(open_pr "$member" root-owners "Add root owners")
root_sha=$(pr_sha "$root_pr")
if wait_sha "$root_pr" "$root_sha"; then
  pass "root owners checks"
else
  fail "root owners checks"
fi
osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${root_pr}"
root_reviewers=$(jq -r '[.requested_reviewers[]?.login] | join(" ")' "$OSF_HTTP_BODY" 2>/dev/null || true)
osf_api_discard
if printf '%s' "$root_reviewers" | grep -q acme-admin; then
  pass "root owners requests owner"
else
  fail "root owners requests owner"
fi
as_user "$admin"
set +e
"$work/host/host.sh" auto-merge "$repo" "$root_pr" >>"$log" 2>&1
set -e
sleep 3
osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${root_pr}"
root_merged=$(jq -r '.merged' "$OSF_HTTP_BODY")
osf_api_discard
if [ "$root_merged" != "true" ]; then
  pass "root owners blocked"
else
  fail "root owners blocked"
fi
root_body=$(mktemp)
printf '%s\n' '{"event":"APPROVED","body":"ok"}' > "$root_body"
osf_api "$admin" POST "/api/v1/repos/acme/${repo}/pulls/${root_pr}/reviews" "$root_body"
osf_api_discard
rm -f "$root_body"
as_user "$admin"
"$work/host/host.sh" auto-merge "$repo" "$root_pr" >>"$log" 2>&1 || true
root_i=0
root_merged=false
while [ "$root_i" -lt 20 ]; do
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${root_pr}"
  root_merged=$(jq -r '.merged' "$OSF_HTTP_BODY")
  osf_api_discard
  if [ "$root_merged" = "true" ]; then
    break
  fi
  root_i=$((root_i + 1))
  sleep 3
done
if [ "$root_merged" = "true" ]; then
  pass "root owners merges after approval"
else
  fail "root owners merges after approval"
fi

# Deleting the company profile on the head must not switch to the size-only lint.
new_branch drop-profile
rm -f "$src/company-profile.md"
mkdir -p "$src/company-profile.md"
git -C "$src" add -A
git -C "$src" commit -q -m "replace the profile with a directory"
push_branch "$member" drop-profile
drop_pr=$(open_pr "$member" drop-profile "Drop the profile")
drop_sha=$(pr_sha "$drop_pr")
set +e
wait_sha "$drop_pr" "$drop_sha"
drop_rc=$?
set -e
if [ "$drop_rc" -eq 2 ]; then
  pass "deleted profile still fails full lint"
else
  fail "deleted profile still fails full lint"
fi

# Area-shaped repo: no skills/ directory. The check tools live under .github/scripts/tools/.
area_repo="ci-area-${stamp}"
src="$work/area"
repo="$area_repo"
mkdir -p "$src/.github/workflows" "$src/.github/scripts"
cp "$root/template/.github/workflows/checks.yml" "$src/.github/workflows/checks.yml"
cp -R "$root/template/.github/scripts/." "$src/.github/scripts/"
cp "$root/template/review-rules.md" "$src/review-rules.md"
chmod +x "$src/.github/scripts/"*.sh "$src/.github/scripts/tools/"*.sh "$src/.github/scripts/tools/host/"*.sh
printf '%s\n' '# Area' > "$src/AGENTS.md"
printf '%s\n' 'A note.' > "$src/note.txt"
printf '%s\n' '.*AGENTS\.md @acme-admin' > "$src/CODEOWNERS"
git -C "$src" init -q -b main
git -C "$src" config user.email ada.admin@acme.test
git -C "$src" config user.name "Ada Admin"
git -C "$src" add .
git -C "$src" commit -q -m "init"
if ! "$work/host/host.sh" create-repo "$area_repo" --source "$src" --push >>"$log" 2>&1; then
  fail "area create repo"
else
  "$work/host/host.sh" grant "$area_repo" acme-member-a write >>"$log" 2>&1
  "$work/host/host.sh" protect "$area_repo" --code-owners --approvals 0 >>"$log" 2>&1
  new_branch area-note
  printf '%s\n' 'A longer note.' >> "$src/note.txt"
  git -C "$src" add note.txt
  git -C "$src" commit -q -m "extend the note"
  push_branch "$admin" area-note
  area_pr=$(open_pr "$admin" area-note "Area note")
  area_sha=$(pr_sha "$area_pr")
  if wait_sha "$area_pr" "$area_sha"; then
    pass "area clean"
  else
    fail "area clean"
  fi
  new_branch area-secret
  printf '%s%s %s%s\n' '-----BE' 'GIN' 'PRIVATE' ' KEY' > "$src/secret.txt"
  git -C "$src" add secret.txt
  git -C "$src" commit -q -m "add a file"
  push_branch "$member" area-secret
  area_sec=$(open_pr "$member" area-secret "Area secret")
  area_sec_sha=$(pr_sha "$area_sec")
  set +e
  wait_sha "$area_sec" "$area_sec_sha"
  area_sec_rc=$?
  set -e
  if [ "$area_sec_rc" -eq 2 ]; then
    pass "area secret fails"
  else
    fail "area secret fails"
  fi
  new_branch area-hijack
  printf '%s\n' '#!/bin/bash' 'exit 0' > "$src/.github/scripts/tools/secret-scan.sh"
  chmod +x "$src/.github/scripts/tools/secret-scan.sh"
  printf '%s%s %s%s\n' '-----BE' 'GIN' 'PRIVATE' ' KEY' > "$src/secret.txt"
  git -C "$src" add .github/scripts/tools/secret-scan.sh secret.txt
  git -C "$src" commit -q -m "replace the scanner"
  push_branch "$member" area-hijack
  area_hijack_pr=$(open_pr "$member" area-hijack "Replace the scanner")
  area_hijack_sha=$(pr_sha "$area_hijack_pr")
  set +e
  wait_sha "$area_hijack_pr" "$area_hijack_sha"
  area_hijack_rc=$?
  set -e
  if [ "$area_hijack_rc" -eq 2 ]; then
    pass "area head tools ignored"
  else
    fail "area head tools ignored"
  fi
fi
repo="ci-checks-${stamp}"

# Upgrade opens a pull request in the area repo. It does not commit area files in the company repo.
up_slug="ciup${stamp}"
up_slug=${up_slug//-/}
up_company="${up_slug}-os"
up_area="${up_slug}-marketing"
EXTRA_REPOS="${EXTRA_REPOS} ${up_company} ${up_area}"
up_root="$work/upgrade"
mkdir -p "$up_root/skills"
printf '%s\n' '/areas/' > "$up_root/.gitignore"
printf '%s\n' '# Acme' > "$up_root/AGENTS.md"
cat > "$up_root/company-profile.md" << EOF
---
type: company-profile
summary: "Acme upgrade"
company_slug: ${up_slug}
host: forgejo
host_url: "http://localhost:3300"
org: "acme"
---
EOF
git -C "$up_root" init -q -b main
git -C "$up_root" config user.email ada.admin@acme.test
git -C "$up_root" config user.name "Ada Admin"
git -C "$up_root" add .gitignore company-profile.md AGENTS.md
git -C "$up_root" commit -q -m "v0 start"
up_seed="$work/up-seed"
mkdir -p "$up_seed"
printf '%s\n' '# Marketing' > "$up_seed/AGENTS.md"
printf '%s\n' '* @acme-admin' > "$up_seed/CODEOWNERS"
git -C "$up_seed" init -q -b main
git -C "$up_seed" config user.email ada.admin@acme.test
git -C "$up_seed" config user.name "Ada Admin"
git -C "$up_seed" add .
git -C "$up_seed" commit -q -m "area start"
if "$work/host/host.sh" create-repo "$up_company" --private --source "$up_root" --push >>"$log" 2>&1 \
  && "$work/host/host.sh" create-repo "$up_area" --private --source "$up_seed" --push >>"$log" 2>&1; then
  "$work/host/host.sh" protect "$up_area" --code-owners --approvals 0 >>"$log" 2>&1 || true
  if git -C "$up_root" remote get-url origin >/dev/null 2>&1; then
    git -C "$up_root" remote set-url origin "http://localhost:3300/acme/${up_company}.git"
  else
    git -C "$up_root" remote add origin "http://localhost:3300/acme/${up_company}.git"
  fi
  ask=$(mktemp)
  chmod 700 "$ask"
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "git" ;;
  *) cat "$OS_TOKEN_FILE" ;;
esac
EOF
  mkdir -p "$up_root/areas"
  OS_TOKEN_FILE=$admin GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= clone -q "http://localhost:3300/acme/${up_area}.git" "$up_root/areas/marketing" >>"$log" 2>&1 || true
  rm -f "$ask"
  if [ -d "$up_root/areas/marketing/.git" ]; then
    set +e
    OS_HOST_SH="$work/host/host.sh" "$root/template/skills/upgrade/upgrade.sh" \
      --root "$up_root" --template "$root/template" --level team >"$work/upgrade.out" 2>>"$log"
    up_rc=$?
    set -e
    if [ "$up_rc" -eq 0 ] \
      && grep -q "pr: ${up_area} " "$work/upgrade.out" \
      && git -C "$up_root/areas/marketing" cat-file -e "upgrade/scripts:.github/scripts/tools/secret-scan.sh" \
      && git -C "$up_root/areas/marketing" cat-file -e "upgrade/scripts:.github/scripts/checkout.sh" \
      && ! git -C "$up_root" ls-files | grep -q '^areas/'; then
      osf_api "$admin" GET "/api/v1/repos/acme/${up_area}/contents/.github/scripts/tools/secret-scan.sh?ref=main"
      main_code=$OSF_HTTP_CODE
      osf_api_discard
      # The upgrade puts the check tools on main first, so the pull request can pass its checks.
      if [ "$main_code" = "200" ]; then
        pass "upgrade area pr"
      else
        fail "upgrade area pr"
      fi
    else
      cat "$work/upgrade.out" >>"$log" 2>/dev/null || true
      fail "upgrade area pr"
    fi
  else
    fail "upgrade area pr"
  fi
else
  fail "upgrade area pr"
fi

# A second team-on opens a pull request when the area main has no check tools.
tools_slug="cit${stamp}"
tools_slug=${tools_slug//-/}
tools_company="${tools_slug}-os"
tools_area="${tools_slug}-marketing"
tools_user="${tools_slug}-user-ada"
EXTRA_REPOS="${EXTRA_REPOS} ${tools_company} ${tools_area} ${tools_user}"
tools_root="$work/team"
mkdir -p "$tools_root"
cp -R "$root/template/." "$tools_root/"
python3 - "$tools_root/company-profile.md" "$tools_slug" << 'PY'
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
git -C "$tools_root" init -q -b main
git -C "$tools_root" config user.email ada.admin@acme.test
git -C "$tools_root" config user.name "Ada Admin"
git -C "$tools_root" add -A
git -C "$tools_root" commit -q -m "company start"
seed="$work/tools-seed"
mkdir -p "$seed/.github" "$seed/.gitea"
printf '%s\n' '# Marketing' > "$seed/AGENTS.md"
printf '%s\n' '* @acme-admin' > "$seed/.github/CODEOWNERS"
printf '%s\n' '.* @acme-admin' > "$seed/.gitea/CODEOWNERS"
printf '%s\n' 'vendor=xai' 'model=' 'kind=second-vendor' > "$seed/.github/review.conf"
git -C "$seed" init -q -b main
git -C "$seed" config user.email ada.admin@acme.test
git -C "$seed" config user.name "Ada Admin"
git -C "$seed" add .
git -C "$seed" commit -q -m "area rules"
if "$work/host/host.sh" create-repo "$tools_area" --private --source "$seed" --push >>"$log" 2>&1; then
  "$work/host/host.sh" protect "$tools_area" --code-owners --approvals 0 >>"$log" 2>&1 || true
  ask=$(mktemp)
  chmod 700 "$ask"
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "git" ;;
  *) cat "$OS_TOKEN_FILE" ;;
esac
EOF
  mkdir -p "$tools_root/areas"
  OS_TOKEN_FILE=$admin GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= clone -q "http://localhost:3300/acme/${tools_area}.git" "$tools_root/areas/marketing" >>"$log" 2>&1 || true
  rm -f "$ask"
  tools_main=$(git -C "$tools_root/areas/marketing" rev-parse origin/main)
  at='@'
  cat > "$work/tools-answers" << EOF
root=$tools_root
host=forgejo
host_url=http://localhost:3300
org=acme
sync_engine=true
runner=ubuntu-latest
company_name=Acme Co
company_slug=${tools_slug}
review_vendor=xai
review_kind=second-vendor
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.email=ada${at}acme.test
person.ada.role=admin
person.ada.areas=marketing
area.marketing.director=ada
EOF
  set +e
  OS_HOST_SH="$work/host/host.sh" OS_JOBS_DIR="$work/jobs" \
    "$root/template/skills/add-teammate/team-on.sh" --answers "$work/tools-answers" >"$work/team-on.out" 2>>"$log"
  tools_rc=$?
  set -e
  if [ "$tools_rc" -eq 0 ] \
    && grep -q "pr: ${tools_area} " "$work/team-on.out" \
    && git -C "$tools_root/areas/marketing" cat-file -e "team/scripts-tools:.github/scripts/tools/secret-scan.sh" \
    && [ "$(git -C "$tools_root/areas/marketing" rev-parse origin/main)" = "$tools_main" ]; then
    pass "area tools pull request"
  else
    cat "$work/team-on.out" >>"$log" 2>/dev/null || true
    fail "area tools pull request"
  fi
  if [ "$tools_rc" -eq 0 ] \
    && git -C "$tools_root/areas/marketing" cat-file -e "team/scripts-tools:review-rules.md" \
    && ! git -C "$tools_root/areas/marketing" cat-file -e "origin/main:review-rules.md" 2>/dev/null \
    && [ "$(git -C "$tools_root/areas/marketing" rev-parse "team/scripts-tools:review-rules.md")" = "$(git -C "$tools_root" rev-parse "HEAD:review-rules.md")" ] \
    && [ "$(git -C "$tools_root/areas/marketing" rev-parse origin/main)" = "$tools_main" ]; then
    pass "area review-rules pull request"
  else
    fail "area review-rules pull request"
  fi
else
  fail "area tools pull request"
  fail "area review-rules pull request"
fi

# The pull request that adds review-rules.md must pass checks and merge.
# Main already has the check scripts, including the default, and not the root file.
intro_slug="cin${stamp}"
intro_slug=${intro_slug//-/}
intro_company="${intro_slug}-os"
intro_area="${intro_slug}-marketing"
intro_user="${intro_slug}-user-ada"
EXTRA_REPOS="${EXTRA_REPOS} ${intro_company} ${intro_area} ${intro_user}"
intro_root="$work/intro"
mkdir -p "$intro_root"
cp -R "$root/template/." "$intro_root/"
python3 - "$intro_root/company-profile.md" "$intro_slug" << 'PY'
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
intro_seed="$work/intro-seed"
mkdir -p "$intro_seed/.github/workflows" "$intro_seed/.github/scripts"
cp "$root/template/.github/workflows/checks.yml" "$intro_seed/.github/workflows/checks.yml"
cp -R "$root/template/.github/scripts/." "$intro_seed/.github/scripts/"
printf '%s\n' '# Marketing' > "$intro_seed/AGENTS.md"
printf '%s\n' 'vendor=xai' 'model=' 'kind=second-vendor' > "$intro_seed/.github/review.conf"
printf '%s\n' '/review-rules.md @acme-member-a' > "$intro_seed/.github/CODEOWNERS"
mkdir -p "$intro_seed/.gitea"
printf '%s\n' '^review-rules\.md$ @acme-member-a' > "$intro_seed/.gitea/CODEOWNERS"
git -C "$intro_root" init -q -b main
git -C "$intro_root" config user.email ada.admin@acme.test
git -C "$intro_root" config user.name "Ada Admin"
git -C "$intro_root" add -A
git -C "$intro_root" commit -q -m "company start"
git -C "$intro_seed" init -q -b main
git -C "$intro_seed" config user.email ada.admin@acme.test
git -C "$intro_seed" config user.name "Ada Admin"
git -C "$intro_seed" add -A
git -C "$intro_seed" commit -q -m "area scripts, no review rules"
if "$work/host/host.sh" create-repo "$intro_area" --private --source "$intro_seed" --push >>"$log" 2>&1; then
  "$work/host/host.sh" grant "$intro_area" acme-member-a write >>"$log" 2>&1 || true
  "$work/host/host.sh" protect "$intro_area" --code-owners --approvals 0 >>"$log" 2>&1 || true
  ask=$(mktemp)
  chmod 700 "$ask"
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "git" ;;
  *) cat "$OS_TOKEN_FILE" ;;
esac
EOF
  mkdir -p "$intro_root/areas"
  OS_TOKEN_FILE=$admin GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= clone -q "http://localhost:3300/acme/${intro_area}.git" "$intro_root/areas/marketing" >>"$log" 2>&1 || true
  rm -f "$ask"
  at='@'
  cat > "$work/intro-answers" << EOF
root=$intro_root
host=forgejo
host_url=http://localhost:3300
org=acme
sync_engine=true
runner=ubuntu-latest
company_name=Acme Co
company_slug=${intro_slug}
review_vendor=xai
review_kind=second-vendor
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.email=ada${at}acme.test
person.ada.role=admin
person.ada.areas=marketing
area.marketing.director=ada
EOF
  set +e
  OS_HOST_SH="$work/host/host.sh" OS_JOBS_DIR="$work/jobs" \
    "$root/template/skills/add-teammate/team-on.sh" --answers "$work/intro-answers" >"$work/intro.out" 2>>"$log"
  intro_rc=$?
  set -e
  intro_number=$(awk -v area="$intro_area" '$1 == "pr:" && $2 == area { print $3; exit }' "$work/intro.out")
  if [ "$intro_rc" -eq 0 ] && [ -n "$intro_number" ] \
    && git -C "$intro_root/areas/marketing" cat-file -e "team/review-rules:review-rules.md" \
    && ! git -C "$intro_root/areas/marketing" cat-file -e "origin/main:review-rules.md" 2>/dev/null; then
    src="$intro_root/areas/marketing"
    repo="$intro_area"
    intro_sha=$(pr_sha "$intro_number")
    if wait_sha "$intro_number" "$intro_sha" && approve_and_merge "$intro_number" "$member"; then
      osf_api "$admin" GET "/api/v1/repos/acme/${intro_area}/contents/review-rules.md?ref=main"
      if [ "$OSF_HTTP_CODE" = "200" ] \
        && [ "$(jq -r '.sha // empty' "$OSF_HTTP_BODY")" = "$(git hash-object "$intro_root/review-rules.md")" ]; then
        pass "area review-rules merge"
      else
        fail "area review-rules merge"
      fi
      osf_api_discard
    else
      fail "area review-rules merge"
    fi
  else
    cat "$work/intro.out" >>"$log" 2>/dev/null || true
    fail "area review-rules merge"
  fi
else
  fail "area review-rules merge"
fi
repo="ci-checks-${stamp}"

# An area made by team-on has review-rules.md on main. Its checks job passes.
rules_slug="crr${stamp}"
rules_slug=${rules_slug//-/}
rules_company="${rules_slug}-os"
rules_area="${rules_slug}-marketing"
rules_user="${rules_slug}-user-ada"
EXTRA_REPOS="${EXTRA_REPOS} ${rules_company} ${rules_area} ${rules_user}"
rules_root="$work/rules"
mkdir -p "$rules_root/areas/marketing"
cp -R "$root/template/." "$rules_root/"
python3 - "$rules_root/company-profile.md" "$rules_slug" << 'PY'
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
rm -rf "$rules_root/areas/marketing"
mkdir -p "$rules_root/areas/marketing"
printf '%s\n' '# Marketing' > "$rules_root/areas/marketing/AGENTS.md"
printf '%s\n' 'A note.' > "$rules_root/areas/marketing/note.txt"
git -C "$rules_root" init -q -b main
git -C "$rules_root" config user.email ada.admin@acme.test
git -C "$rules_root" config user.name "Ada Admin"
git -C "$rules_root" add -A
git -C "$rules_root" commit -q -m "company start"
git -C "$rules_root/areas/marketing" init -q -b main
git -C "$rules_root/areas/marketing" config user.email ada.admin@acme.test
git -C "$rules_root/areas/marketing" config user.name "Ada Admin"
git -C "$rules_root/areas/marketing" add -A
git -C "$rules_root/areas/marketing" commit -q -m "area start"
at='@'
cat > "$work/rules-answers" << EOF
root=$rules_root
host=forgejo
host_url=http://localhost:3300
org=acme
sync_engine=true
runner=ubuntu-latest
company_name=Acme Co
company_slug=${rules_slug}
review_vendor=xai
review_kind=second-vendor
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.email=ada${at}acme.test
person.ada.role=admin
person.ada.areas=marketing
area.marketing.director=ada
EOF
set +e
OS_HOST_SH="$work/host/host.sh" OS_JOBS_DIR="$work/jobs" \
  "$root/template/skills/add-teammate/team-on.sh" --answers "$work/rules-answers" >"$work/rules-team.out" 2>>"$log"
rules_rc=$?
set -e
rules_on_main=0
if [ "$rules_rc" -eq 0 ]; then
  osf_api "$admin" GET "/api/v1/repos/acme/${rules_area}/contents/review-rules.md?ref=main"
  if [ "$OSF_HTTP_CODE" = "200" ] \
    && [ "$(jq -r '.sha // empty' "$OSF_HTTP_BODY")" = "$(git hash-object "$rules_root/review-rules.md")" ]; then
    rules_on_main=1
  fi
  osf_api_discard
fi
if [ "$rules_on_main" -eq 1 ]; then
  src="$rules_root/areas/marketing"
  repo="$rules_area"
  git -C "$src" checkout -q -B area-note
  printf '%s\n' 'A longer note.' >> "$src/note.txt"
  git -C "$src" add note.txt
  git -C "$src" commit -q -m "extend the note"
  push_branch "$admin" area-note
  rules_pr=$(open_pr "$admin" area-note "Area note")
  rules_sha=$(pr_sha "$rules_pr")
  if wait_sha "$rules_pr" "$rules_sha"; then
    pass "area team-on checks"
  else
    fail "area team-on checks"
  fi
else
  cat "$work/rules-team.out" >>"$log" 2>/dev/null || true
  fail "area team-on checks"
fi
repo="ci-checks-${stamp}"

# Area rules PR. Owners are os_codeowners output, not a hand-written file.
# Forgejo names only the director. A member's skill change is blocked until
# that director approves, then it merges. GitHub still names both.
own_repo="ci-own-${stamp}"
EXTRA_REPOS="${EXTRA_REPOS} ${own_repo}"
src="$work/own"
repo="$own_repo"
director="$(osf_acme_token_dir)/acme-director"
mkdir -p "$src/.github/workflows" "$src/.github/scripts" "$src/skills/sample"
cp "$root/template/.github/workflows/checks.yml" "$src/.github/workflows/checks.yml"
cp -R "$root/template/.github/scripts/." "$src/.github/scripts/"
cp "$root/template/review-rules.md" "$src/review-rules.md"
chmod +x "$src/.github/scripts/"*.sh "$src/.github/scripts/tools/"*.sh "$src/.github/scripts/tools/host/"*.sh
printf '%s\n' '# Area' > "$src/AGENTS.md"
printf '%s\n' 'A note.' > "$src/note.txt"
printf '%s\n' '# Sample' > "$src/skills/sample/SKILL.md"
# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"
os_codeowners "$src" "$(os_at_users acme-admin acme-director)" "$(os_forgejo_owner acme-admin acme-director)"
if [ -f "$src/CODEOWNERS" ] || [ ! -f "$src/.gitea/CODEOWNERS" ] \
  || ! grep -F -x -q '^skills/.* @acme-director' "$src/.gitea/CODEOWNERS" \
  || grep -q acme-admin "$src/.gitea/CODEOWNERS" \
  || ! grep -F -q '/.gitea/ @acme-director @acme-admin' "$src/.github/CODEOWNERS"; then
  fail "area rules uses product owners"
else
  git -C "$src" init -q -b main
  git -C "$src" config user.email ada.admin@acme.test
  git -C "$src" config user.name "Ada Admin"
  git -C "$src" add .
  git -C "$src" commit -q -m "init"
  as_user "$admin"
  if ! "$work/host/host.sh" create-repo "$own_repo" --source "$src" --push >>"$log" 2>&1; then
    fail "area rules create repo"
  else
    {
      "$work/host/host.sh" grant "$own_repo" acme-member-a write
      "$work/host/host.sh" grant "$own_repo" acme-director write
      "$work/host/host.sh" protect "$own_repo" --code-owners --approvals 0
    } >>"$log" 2>&1
    new_branch area-rules
    printf '%s\n' 'Changed skill.' >> "$src/skills/sample/SKILL.md"
    git -C "$src" add skills/sample/SKILL.md
    git -C "$src" commit -q -m "change a skill"
    push_branch "$member" area-rules
    own_pr=$(open_pr "$member" area-rules "Change a skill")
    own_sha=$(pr_sha "$own_pr")
    if wait_sha "$own_pr" "$own_sha"; then
      pass "area rules checks"
      own_checks=1
    else
      fail "area rules checks"
      own_checks=0
      osf_api "$admin" GET "/api/v1/repos/acme/${repo}/commits/${own_sha}/status"
      echo "area rules status $(jq -c '{state,statuses}' "$OSF_HTTP_BODY" 2>/dev/null || echo bad-status)" >>"$log"
      osf_api_discard
      osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/runs?limit=5"
      own_run=$(python3 -c 'import json,sys; raw=json.load(open(sys.argv[1])); rows=raw if isinstance(raw,list) else raw.get("workflow_runs") or raw.get("runs") or []; print(next((str(r.get("id")) for r in rows if r.get("head_sha")==sys.argv[2]), ""))' "$OSF_HTTP_BODY" "$own_sha" 2>/dev/null || true)
      osf_api_discard
      if [ -n "$own_run" ]; then
        osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/runs/${own_run}/jobs"
        own_job=$(jq -r 'if type=="array" then .[0].id else (.jobs[0].id // empty) end' "$OSF_HTTP_BODY" 2>/dev/null || true)
        osf_api_discard
        if [ -n "$own_job" ] && [ "$own_job" != "null" ]; then
          osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/jobs/${own_job}/logs"
          python3 "$lib/scrub.py" --secrets-dir "$(osf_acme_cache)" "$OSF_HTTP_BODY" | tail -n 40 >>"$log" || true
          osf_api_discard
        fi
      fi
    fi
    own_i=0
    own_reviewers=""
    while [ "$own_i" -lt 8 ]; do
      osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${own_pr}"
      own_reviewers=$(jq -r '[.requested_reviewers[]?.login] | join(" ")' "$OSF_HTTP_BODY" 2>/dev/null || true)
      osf_api_discard
      if printf '%s' "$own_reviewers" | grep -q acme-director; then
        break
      fi
      own_i=$((own_i + 1))
      sleep 1
    done
    if printf '%s' "$own_reviewers" | grep -q acme-director \
      && ! printf '%s' "$own_reviewers" | grep -q acme-admin; then
      pass "area rules requests director"
    else
      fail "area rules requests director"
    fi
    if [ "$own_checks" -eq 1 ]; then
      as_user "$admin"
      set +e
      "$work/host/host.sh" auto-merge "$repo" "$own_pr" >>"$log" 2>&1
      set -e
      sleep 3
      osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${own_pr}"
      own_merged=$(jq -r '.merged' "$OSF_HTTP_BODY")
      osf_api_discard
      if [ "$own_merged" != "true" ]; then
        pass "area rules blocked"
      else
        fail "area rules blocked"
      fi
      own_body=$(mktemp)
      printf '%s\n' '{"event":"APPROVED","body":"ok"}' > "$own_body"
      osf_api "$director" POST "/api/v1/repos/acme/${repo}/pulls/${own_pr}/reviews" "$own_body"
      own_approve=$OSF_HTTP_CODE
      osf_api_discard
      rm -f "$own_body"
      if [ "$own_approve" != "200" ] && [ "$own_approve" != "201" ]; then
        fail "area rules merges after director"
      else
        as_user "$admin"
        "$work/host/host.sh" auto-merge "$repo" "$own_pr" >>"$log" 2>&1 || true
        own_i=0
        own_merged=false
        while [ "$own_i" -lt 20 ]; do
          osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${own_pr}"
          own_merged=$(jq -r '.merged' "$OSF_HTTP_BODY")
          osf_api_discard
          if [ "$own_merged" = "true" ]; then
            break
          fi
          own_i=$((own_i + 1))
          sleep 3
        done
        if [ "$own_merged" = "true" ]; then
          pass "area rules merges after director"
        else
          fail "area rules merges after director"
        fi
      fi
    else
      fail "area rules blocked"
      fail "area rules merges after director"
    fi
  fi
fi
repo="ci-checks-${stamp}"

# One job duration, for the billed-minute estimate.
osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/runs?limit=20"
python3 - "$OSF_HTTP_BODY" << 'PY'
import json, sys
from datetime import datetime
raw = json.load(open(sys.argv[1]))
rows = raw if isinstance(raw, list) else raw.get("workflow_runs") or raw.get("runs") or []
best = None
for row in rows:
    start = row.get("started_at") or row.get("created_at") or ""
    stop = row.get("stopped_at") or row.get("updated_at") or ""
    if not start or not stop:
        continue
    try:
        a = datetime.fromisoformat(start.replace("Z", "+00:00"))
        b = datetime.fromisoformat(stop.replace("Z", "+00:00"))
    except ValueError:
        continue
    secs = int((b - a).total_seconds())
    if secs < 0:
        continue
    if best is None or secs < best:
        best = secs
if best is None:
    print("JOB_SECONDS unknown")
else:
    print(f"JOB_SECONDS {best}")
    print(f"BILLED_MINUTES 1")
PY
osf_api_discard

if [ "$FAIL" -ne 0 ]; then
  set +e
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/runs?limit=1"
  run_id=$(jq -r 'if type=="array" then .[0].id else (.workflow_runs[0].id // .runs[0].id // empty) end' "$OSF_HTTP_BODY")
  osf_api_discard
  if [ -n "$run_id" ] && [ "$run_id" != "null" ]; then
    osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/runs/${run_id}/jobs"
    job_id=$(jq -r 'if type=="array" then .[0].id else (.jobs[0].id // empty) end' "$OSF_HTTP_BODY")
    osf_api_discard
    if [ -n "$job_id" ] && [ "$job_id" != "null" ]; then
      osf_api "$admin" GET "/api/v1/repos/acme/${repo}/actions/jobs/${job_id}/logs"
      python3 "$lib/scrub.py" --secrets-dir "$(osf_acme_cache)" "$OSF_HTTP_BODY" | tail -n 40
      osf_api_discard
    fi
  fi
fi

echo "CI: PASS $PASS FAIL $FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
