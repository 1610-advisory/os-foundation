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
work=$(mktemp -d)
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
    "$work/host/host.sh" delete-repo "$repo" --yes-test-only >>"$log" 2>&1 || true
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
mkdir -p "$src/.github/workflows" "$src/.github/scripts" "$src/skills/sync" "$src/skills/lint" \
  "$src/skills/_host" "$src/people"
cp "$root/template/.github/workflows/checks.yml" "$src/.github/workflows/checks.yml"
cp "$root/template/.github/scripts/"*.sh "$src/.github/scripts/"
cp "$root/template/review-rules.md" "$src/review-rules.md"
cp "$here/fixtures/secret-scan.sh" "$src/skills/sync/secret-scan.sh"
cp "$here/fixtures/lint.sh" "$src/skills/lint/lint.sh"
cp "$work/host/"*.sh "$src/skills/_host/"
chmod +x "$src/.github/scripts/"*.sh "$src/skills/sync/secret-scan.sh" "$src/skills/lint/lint.sh" \
  "$src/skills/_host/"*.sh
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
cat > "$src/CODEOWNERS" << 'EOF'
.*AGENTS\.md @acme-admin
.*CLAUDE\.md @acme-admin
.*review-rules\.md @acme-admin
skills/.* @acme-admin
\.github/.* @acme-admin
EOF
cat > "$src/.github/CODEOWNERS" << 'EOF'
AGENTS.md @acme-admin
CLAUDE.md @acme-admin
review-rules.md @acme-admin
skills/ @acme-admin
.github/ @acme-admin
EOF
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
  local body
  body=$(mktemp)
  printf '%s\n' "$title" > "$body"
  as_user "$token_file"
  "$work/host/host.sh" open-pr "$repo" --head "$branch" --base main --title "$title" --body-file "$body" >"$work/pr.json"
  rm -f "$body"
  jq -r '.number' "$work/pr.json"
}

pr_sha() {
  local number=$1
  osf_api "$admin" GET "/api/v1/repos/acme/${repo}/pulls/${number}"
  jq -r '.head.sha // empty' "$OSF_HTTP_BODY"
  osf_api_discard
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
printf '%s\n' 'OSF_PLANTED_SECRET' > "$src/secret.txt"
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

# Lint failure.
new_branch lint
printf '%s\n' 'OSF_LINT_FAIL' > "$src/lint.txt"
git -C "$src" add lint.txt
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
  if [ "$state" = "success" ] && printf '%s\n' "$recorded" | grep -q 'override by acme-admin: the marker is a test'; then
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
