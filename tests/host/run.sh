#!/bin/bash
# Run every host verb against a local Forgejo and check the result through the API.
# Uses a throwaway container named osf-host-forgejo on port 3310.
# Set KEEP=1 to leave the container up. Tokens are not printed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOST="${ROOT}/template/skills/_host/host.sh"
BASE="${OS_HOST_URL:-http://localhost:3310}"
CONTAINER=osf-host-forgejo
IMAGE=codeberg.org/forgejo/forgejo:11.0.11
PASS=0
FAIL=0

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  printf '%s\n' "Usage: tests/host/run.sh"
  printf '%s\n' "Run every host verb against local Forgejo and check the API."
  exit 0
fi

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

scrub() {
  local file=$1 extra=${2-}
  if [ ! -f "$file" ]; then
    return 0
  fi
  awk -v extra="$extra" '
    function scrub(line) {
      gsub(/Authorization:[[:space:]]*(Bearer|bearer|token|Basic|basic)[[:space:]]+[^[:space:]]+/, "Authorization: <redacted>", line)
      if (extra != "") {
        out = ""
        rest = line
        elen = length(extra)
        while (index(rest, extra) > 0) {
          i = index(rest, extra)
          out = out substr(rest, 1, i - 1) "<redacted>"
          rest = substr(rest, i + elen)
        }
        line = out rest
      }
      return line
    }
    { print scrub($0) }
  ' "$file"
}

cleanup() {
  rm -f "${TOKEN_FILE:-}" "${MIA_TOKEN_FILE:-}" "${BOT_TOKEN_FILE:-}" "${ERR:-}" "${OUT:-}"
  if [ "${KEEP:-}" != "1" ]; then
    docker rm -f -v "$CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! docker info >/dev/null 2>&1; then
  printf '%s\n' "BLOCKED docker is not running"
  exit 2
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" \
    -p 3310:3000 \
    -e USER_UID=1000 \
    -e USER_GID=1000 \
    -e FORGEJO__server__ROOT_URL="${BASE}/" \
    -e FORGEJO__server__HTTP_PORT=3000 \
    -e FORGEJO__server__DOMAIN=localhost \
    -e FORGEJO__database__DB_TYPE=sqlite3 \
    -e FORGEJO__security__INSTALL_LOCK=true \
    "$IMAGE" >/dev/null
fi

ready=0
i=0
while [ "$i" -lt 60 ]; do
  if curl -sf "${BASE}/api/v1/version" >/dev/null 2>&1; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 2
done
if [ "$ready" != "1" ]; then
  printf '%s\n' "BLOCKED Forgejo did not start"
  exit 2
fi

VERSION=$(curl -sf "${BASE}/api/v1/version" | jq -r '.version')
printf 'FORGEJO_VERSION %s\n' "$VERSION"

fj_admin() {
  docker exec -u git "$CONTAINER" forgejo "$@" --config /data/gitea/conf/app.ini
}

ensure_user() {
  local name=$1 email=$2 admin_flag=${3-}
  if [ -n "$admin_flag" ]; then
    fj_admin admin user create \
      --username "$name" \
      --password test-only-password \
      --email "$email" \
      --admin \
      --must-change-password=false >/dev/null 2>&1 || true
  else
    fj_admin admin user create \
      --username "$name" \
      --password test-only-password \
      --email "$email" \
      --must-change-password=false >/dev/null 2>&1 || true
  fi
}

ensure_user ada ada@example.test --admin
ensure_user mia mia@example.test
ensure_user dana dana@example.test

TOKEN_FILE=$(mktemp)
chmod 600 "$TOKEN_FILE"
fj_admin admin user generate-access-token \
  --username ada --token-name "osf-host-$$" --raw --scopes all > "$TOKEN_FILE"
MIA_TOKEN_FILE=$(mktemp)
chmod 600 "$MIA_TOKEN_FILE"
fj_admin admin user generate-access-token \
  --username mia --token-name "osf-host-mia-$$" --raw --scopes all > "$MIA_TOKEN_FILE"

WORK=$(mktemp -d)
ERR=$(mktemp)
OUT=$(mktemp)
PROFILE="${WORK}/company-profile.md"
cat > "$PROFILE" << EOF
---
type: company-profile
summary: "Acme Co company OS"
updated: 2026-10-24
company_slug: acme
level: team
switches: []
os_version: 1
host: forgejo
host_url: ${BASE}
org: acme
sync_engine: ""
runner: ubuntu-latest
---

Acme Co.
EOF
mkdir -p "${WORK}/bots/helper"
BOT_TOKEN_FILE=$(mktemp)
chmod 600 "$BOT_TOKEN_FILE"
printf '%s' 'bot-token-for-test' > "$BOT_TOKEN_FILE"
cat > "${WORK}/bots/helper/BOT.md" << EOF
---
token_path: ${BOT_TOKEN_FILE}
---

Helper bot.
EOF

export OS_HOST=forgejo
export OS_HOST_URL="$BASE"
export OS_ORG=acme
export OS_SLUG=acme
export OS_PROFILE="$PROFILE"
export FORGEJO_TOKEN
FORGEJO_TOKEN=$(tr -d '\r\n' < "$TOKEN_FILE")
if [ "${#FORGEJO_TOKEN}" -lt 20 ]; then
  fail "setup token length ${#FORGEJO_TOKEN}"
fi

api() {
  local method=$1 path=$2 body=${3-}
  local token code
  token=$(tr -d '\r\n' < "$TOKEN_FILE")
  code=0
  if [ -n "$body" ]; then
    code=$(curl -sS -o "$OUT" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: token ${token}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      --data-binary "$body" \
      "${BASE}/api/v1${path}" 2>"$ERR" || true)
  else
    code=$(curl -sS -o "$OUT" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: token ${token}" \
      -H "Accept: application/json" \
      "${BASE}/api/v1${path}" 2>"$ERR" || true)
  fi
  printf '%s' "$code"
}

run_host() {
  set +e
  "$HOST" "$@" >"$OUT" 2>"$ERR"
  local rc=$?
  set -e
  printf '%s' "$rc"
}

expect_rc() {
  local want=$1
  shift
  local name=$1 rc
  rc=$(run_host "$@")
  if [ "$rc" = "$want" ]; then
    pass "$name"
  else
    fail "$name exit ${rc} want ${want}: err=$(scrub "$ERR" "${FORGEJO_TOKEN:-}" | tr '\n' ' ') out=$(scrub "$OUT" "${FORGEJO_TOKEN:-}" | tr '\n' ' ')"
  fi
}

# Org and membership are test setup, not host verbs.
org_code=$(api POST /orgs '{"username":"acme","visibility":"private"}')
if [ "$org_code" != "201" ] && [ "$org_code" != "409" ] && [ "$org_code" != "422" ]; then
  fail "setup org HTTP ${org_code}"
else
  pass "setup org"
fi
api POST /orgs/acme/teams '{"name":"members","permission":"read","includes_all_repositories":false,"units":["repo.code"]}' >/dev/null
members_id=$(jq -r '.id // empty' "$OUT" 2>/dev/null || true)
if [ -z "$members_id" ] || [ "$members_id" = "null" ]; then
  api GET /orgs/acme/teams >/dev/null
  members_id=$(jq -r '.[] | select(.name=="members") | .id' "$OUT")
fi
if [ -z "$members_id" ] || [ "$members_id" = "null" ]; then
  fail "setup members team"
else
  api PUT "/teams/${members_id}/members/dana" >/dev/null
  pass "setup dana in org"
fi

SRC="${WORK}/src"
mkdir -p "$SRC"
git -C "$SRC" init -b main >/dev/null
git -C "$SRC" config user.email ada@example.test
git -C "$SRC" config user.name "Ada Admin"
printf '%s\n' "Acme note" > "$SRC/note.txt"
git -C "$SRC" add note.txt
git -C "$SRC" commit -m "Add a note" >/dev/null
git -C "$SRC" tag v1
git -C "$SRC" checkout -b feature >/dev/null
printf '%s\n' "A second note" >> "$SRC/note.txt"
git -C "$SRC" add note.txt
git -C "$SRC" commit -m "Extend the note" >/dev/null
git -C "$SRC" checkout main >/dev/null

expect_rc 0 whoami
login=$(jq -r '.login // empty' "$OUT" 2>/dev/null || true)
if [ "$login" = "ada" ]; then pass "whoami login"; else fail "whoami login"; fi

expect_rc 0 create-repo acme-os --private --source "$SRC" --push
if jq -e '.private == true and .name == "acme-os"' "$OUT" >/dev/null; then
  pass "create-repo json"
else
  fail "create-repo json"
fi
api GET /repos/acme/acme-os >/dev/null
if jq -e '.private == true' "$OUT" >/dev/null; then pass "create-repo api private"; else fail "create-repo api private"; fi
branch_ok=0
n=0
while [ "$n" -lt 10 ]; do
  api GET /repos/acme/acme-os/branches >/dev/null
  if jq -e 'type == "array" and (map(.name) | index("main") != null) and (map(.name) | index("feature") != null)' "$OUT" >/dev/null 2>&1; then
    branch_ok=1
    break
  fi
  n=$((n + 1))
  sleep 1
done
if [ "$branch_ok" = "1" ]; then
  pass "create-repo pushed branches"
else
  fail "create-repo pushed branches"
fi
api GET /repos/acme/acme-os/tags >/dev/null
if jq -e '[.[].name] | index("v1")' "$OUT" >/dev/null; then pass "create-repo pushed tag"; else fail "create-repo pushed tag"; fi

expect_rc 0 repo-access acme-os
if jq -e '.access == "ok"' "$OUT" >/dev/null; then pass "repo-access ok json"; else fail "repo-access ok json"; fi

saved=$FORGEJO_TOKEN
FORGEJO_TOKEN=$(tr -d '\r\n' < "$MIA_TOKEN_FILE")
expect_rc 2 repo-access acme-os
if jq -e '.access == "no-access"' "$OUT" >/dev/null; then pass "repo-access no-access json"; else fail "repo-access no-access json"; fi
FORGEJO_TOKEN=not-a-valid-token
expect_rc 4 repo-access acme-os
if [ -z "$(grep -F 'not-a-valid-token' "$ERR" || true)" ] && [ -z "$(grep -F 'not-a-valid-token' "$OUT" || true)" ]; then
  pass "repo-access auth hides token"
else
  fail "repo-access auth printed the token"
fi
FORGEJO_TOKEN=$saved

set +e
OS_HOST_URL=http://127.0.0.1:9 "$HOST" repo-access acme-os >"$OUT" 2>"$ERR"
off_rc=$?
set -e
if [ "$off_rc" = "5" ]; then pass "repo-access offline"; else fail "repo-access offline exit ${off_rc}"; fi
if grep -F "$FORGEJO_TOKEN" "$ERR" >/dev/null 2>&1 || grep -F "$FORGEJO_TOKEN" "$OUT" >/dev/null 2>&1; then
  fail "offline output contained a token"
else
  pass "offline hides token"
fi

expect_rc 0 protect acme-os --approvals 0 --code-owners
if jq -e '.code_owners == "unsupported" or .code_owners == "set"' "$OUT" >/dev/null; then
  pass "protect json"
  printf 'CODE_OWNERS %s\n' "$(jq -r '.code_owners' "$OUT")"
else
  fail "protect json"
fi
api GET /repos/acme/acme-os/branch_protections >/dev/null
if jq -e '
  [.[] | select(.rule_name=="main" or .branch_name=="main")]
  | .[0].enable_push == false
  and .[0].enable_status_check == true
  and (.[0].required_approvals == 0)
  and (.[0].status_check_contexts | index("checks / checks (pull_request)"))
  and .[0].apply_to_admins == true
' "$OUT" >/dev/null; then
  pass "protect api"
else
  fail "protect api $(jq -c . "$OUT")"
fi
expect_rc 0 protect acme-os

expect_rc 0 team-create writers
expect_rc 0 team-add writers dana
api GET /orgs/acme/teams >/dev/null
writers_id=$(jq -r '.[] | select(.name=="writers") | .id' "$OUT")
api GET "/teams/${writers_id}/members" >/dev/null
if jq -e '[.[].login] | index("dana")' "$OUT" >/dev/null; then pass "team-add api"; else fail "team-add api"; fi
expect_rc 0 team-remove writers dana
api GET "/teams/${writers_id}/members" >/dev/null
if jq -e '[.[].login] | index("dana") | not' "$OUT" >/dev/null; then pass "team-remove api"; else fail "team-remove api"; fi
expect_rc 0 team-add writers dana

expect_rc 0 grant acme-os dana write
api GET /repos/acme/acme-os/collaborators/dana/permission >/dev/null
if jq -e '.permission == "write"' "$OUT" >/dev/null; then pass "grant user api"; else fail "grant user api $(jq -c . "$OUT")"; fi
expect_rc 0 grant acme-os team:writers write
api GET /repos/acme/acme-os/teams >/dev/null
if jq -e '[.[].name] | index("writers")' "$OUT" >/dev/null; then pass "grant team api"; else fail "grant team api"; fi
expect_rc 0 revoke acme-os dana
api GET /repos/acme/acme-os/collaborators/dana/permission >/dev/null
api GET /repos/acme/acme-os/collaborators >/dev/null
if jq -e 'type == "array" and (map(.login) | index("dana") == null)' "$OUT" >/dev/null 2>&1; then
  pass "revoke user api"
else
  fail "revoke user api"
fi
expect_rc 0 revoke acme-os team:writers
api GET /repos/acme/acme-os/teams >/dev/null
if jq -e '[.[].name] | index("writers") | not' "$OUT" >/dev/null; then pass "revoke team api"; else fail "revoke team api"; fi

BODY="${WORK}/body.txt"
printf '%s\n' "Please review this note." > "$BODY"
expect_rc 0 open-pr acme-os --head feature --base main --title "Add a note" --body-file "$BODY"
PR=$(jq -r '.number' "$OUT")
if [ -n "$PR" ] && [ "$PR" != "null" ]; then pass "open-pr number"; else fail "open-pr number"; fi
api GET "/repos/acme/acme-os/pulls/${PR}" >/dev/null
if jq -e '.title == "Add a note" and .head.ref == "feature"' "$OUT" >/dev/null; then
  pass "open-pr api"
else
  fail "open-pr api"
fi
SHA=$(jq -r '.head.sha' "$OUT")
printf '%s\n' "Updated review note." > "$BODY"
expect_rc 0 open-pr acme-os --head feature --base main --title "Add a note again" --body-file "$BODY"
if [ "$(jq -r '.number' "$OUT")" = "$PR" ]; then pass "open-pr updates"; else fail "open-pr updates"; fi

api POST "/repos/acme/acme-os/statuses/${SHA}" \
  '{"context":"checks / checks (pull_request)","state":"success","description":"ok"}' >/dev/null

expect_rc 0 pr-status acme-os "$PR"
if jq -e --arg sha_state "success" '
  .state == "open" and .merged == false and
  ([.checks[] | select(.name == "checks / checks (pull_request)") | .state] | index("success"))
' "$OUT" >/dev/null; then
  pass "pr-status api shape"
else
  fail "pr-status $(jq -c . "$OUT")"
fi

expect_rc 0 pr-comment acme-os "$PR" --body-file "$BODY"
api GET "/repos/acme/acme-os/issues/${PR}/comments" >/dev/null
if jq -e '[.[].body] | index("Updated review note.")' "$OUT" >/dev/null; then
  pass "pr-comment api"
else
  fail "pr-comment api"
fi

expect_rc 0 auto-merge acme-os "$PR"
merged=0
n=0
while [ "$n" -lt 15 ]; do
  api GET "/repos/acme/acme-os/pulls/${PR}" >/dev/null
  if jq -e '.merged == true' "$OUT" >/dev/null; then
    merged=1
    break
  fi
  n=$((n + 1))
  sleep 1
done
if [ "$merged" = "1" ]; then pass "auto-merge api"; else fail "auto-merge did not merge"; fi

expect_rc 0 create-repo acme-old --private
expect_rc 0 archive-repo acme-old
api GET /repos/acme/acme-old >/dev/null
if jq -e '.archived == true' "$OUT" >/dev/null; then pass "archive api"; else fail "archive api"; fi

expect_rc 0 org-remove dana
member_code=$(api GET /orgs/acme/members/dana)
if [ "$member_code" = "404" ]; then pass "org-remove api"; else fail "org-remove api HTTP ${member_code}"; fi

printf '%s' 'secret-value-for-test' > "${WORK}/secret.txt"
set +e
"$HOST" set-secret OS_REVIEW_KEY < "${WORK}/secret.txt" >"$OUT" 2>"$ERR"
secret_rc=$?
set -e
if [ "$secret_rc" = "0" ]; then pass "set-secret"; else fail "set-secret exit ${secret_rc}: $(scrub "$ERR" 'secret-value-for-test' | tr '\n' ' ')"; fi
if grep -F 'secret-value-for-test' "$ERR" >/dev/null 2>&1 || grep -F 'secret-value-for-test' "$OUT" >/dev/null 2>&1; then
  fail "set-secret printed the value"
else
  pass "set-secret hides value"
fi
api GET /orgs/acme/actions/secrets >/dev/null
if jq -e '[.[].name] | index("OS_REVIEW_KEY")' "$OUT" >/dev/null; then
  pass "set-secret api"
else
  fail "set-secret api $(jq -c . "$OUT" 2>/dev/null || echo missing)"
fi

expect_rc 0 get-token
if [ "$(tr -d '\r\n' < "$OUT")" = "$FORGEJO_TOKEN" ]; then
  pass "get-token person"
else
  fail "get-token person mismatch"
fi
if grep -F "$FORGEJO_TOKEN" "$ERR" >/dev/null 2>&1; then
  fail "get-token printed the token on stderr"
else
  pass "get-token stderr clean"
fi
expect_rc 0 get-token --bot helper
if [ "$(tr -d '\r\n' < "$OUT")" = "bot-token-for-test" ]; then
  pass "get-token bot"
else
  fail "get-token bot mismatch"
fi

expect_rc 0 purge-request acme-os
if jq -e '.purged == true or .purged == false' "$OUT" >/dev/null; then
  pass "purge-request json"
  printf 'PURGE %s\n' "$(jq -c '{purged,gap,path,note}' "$OUT")"
else
  fail "purge-request json"
fi

expect_rc 1 delete-repo acme-old
OS_TEST_MODE=1 expect_rc 1 delete-repo acme-old
OS_TEST_MODE=1 expect_rc 0 delete-repo acme-old --yes-test-only
gone=$(api GET /repos/acme/acme-old)
if [ "$gone" = "404" ]; then pass "delete-repo api"; else fail "delete-repo api HTTP ${gone}"; fi

printf 'RESULT pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
