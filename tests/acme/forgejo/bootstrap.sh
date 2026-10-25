#!/usr/bin/env bash
# Create the Acme org, users, tokens, and runner. Safe to run again.
# Prints user names and OK lines only. Token values are never printed.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/common.sh"
# shellcheck disable=SC1091
source "$here/../lib/api.sh"

usage() {
  cat << 'EOF'
usage: bootstrap.sh

Create org acme, the seat users, their tokens, and the Actions runner.
Safe to run again. Run up.sh first.
Tokens are written under ~/.cache/os-foundation/forgejo/ and are not printed.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
if [ $# -ne 0 ]; then
  usage >&2
  exit 1
fi

osf_need_cmd docker curl jq python3 openssl
if ! docker info >/dev/null 2>&1; then
  echo "FAIL: Docker is not running" >&2
  exit 1
fi
if ! curl -fsS --max-time 5 "$(osf_acme_url)/api/healthz" >/dev/null 2>&1 \
  && ! curl -fsS --max-time 5 "$(osf_acme_url)/api/v1/version" >/dev/null 2>&1; then
  echo "FAIL: Forgejo is not ready. Run up.sh first." >&2
  exit 1
fi

cache=$(osf_acme_cache)
token_dir=$(osf_acme_token_dir)
admin_token=$(osf_acme_admin_token)
lib=$(osf_acme_lib_dir)
root=$(osf_acme_root)
mkdir -p "$token_dir"
chmod 700 "$cache" "$token_dir"

scrub_file() {
  python3 "$lib/scrub.py" --secrets-dir "$cache" "$1" >&2 || true
}

forgejo_exec() {
  docker exec -u git \
    -e PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    osf-acme-forgejo "$@"
}

user_create_help() {
  forgejo_exec forgejo admin user create --help 2>&1 || true
}

token_create_help() {
  forgejo_exec forgejo admin user generate-access-token --help 2>&1 || true
}

create_user() {
  local username="$1"
  local email="$2"
  local full_name="$3"
  local admin_flag="${4:-}"
  local pass err rc help
  err=$(mktemp)
  chmod 600 "$err"
  pass=$(openssl rand -base64 24 | tr -d '\n/+=' | cut -c 1-24)
  help=$(user_create_help)
  set +e
  # Build the argument list from the flags this Forgejo build accepts.
  set -- forgejo admin user create \
    --username "$username" \
    --password "$pass" \
    --email "$email"
  if printf '%s\n' "$help" | grep -q -- '--fullname'; then
    set -- "$@" --fullname "$full_name"
  fi
  if printf '%s\n' "$help" | grep -q -- '--must-change-password'; then
    set -- "$@" --must-change-password=false
  fi
  if [ -n "$admin_flag" ]; then
    set -- "$@" --admin
  fi
  forgejo_exec "$@" >"$err" 2>&1
  rc=$?
  set -e
  pass=""
  if [ "$rc" -ne 0 ]; then
    if grep -Eiq 'already exists|name is reserved|user already' "$err"; then
      rm -f "$err"
      return 0
    fi
    scrub_file "$err"
    rm -f "$err"
    echo "FAIL: could not create user $username" >&2
    return 1
  fi
  rm -f "$err"
}

user_exists_api() {
  local username="$1"
  osf_api "$admin_token" GET "/api/v1/users/${username}"
  local code="$OSF_HTTP_CODE"
  osf_api_discard
  [ "$code" = "200" ]
}

ensure_token_cli() {
  local username="$1"
  local dest="$2"
  local err name
  err=$(mktemp)
  : > "$dest"
  chmod 600 "$err" "$dest"
  name="osf-acme-$(date +%s)-$$"
  set +e
  forgejo_exec forgejo admin user generate-access-token \
    --username "$username" \
    --token-name "$name" \
    --scopes all \
    --raw >"$dest" 2>"$err"
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    scrub_file "$err"
    rm -f "$err" "$dest"
    return 1
  fi
  rm -f "$err"
  # Keep a single token line.
  tr -d '[:space:]' < "$dest" > "${dest}.trim"
  mv "${dest}.trim" "$dest"
  chmod 600 "$dest"
  local token
  token=$(cat "$dest")
  if [ "${#token}" -lt 20 ]; then
    token=""
    rm -f "$dest"
    return 1
  fi
  token=""
}

ensure_token_api() {
  local username="$1"
  local dest="$2"
  local body name
  body=$(mktemp)
  chmod 600 "$body"
  name="osf-acme-$(date +%s)-$$"
  jq -n --arg name "$name" '{name:$name, scopes:["all"]}' > "$body"
  osf_api "$admin_token" POST "/api/v1/users/${username}/tokens" "$body"
  rm -f "$body"
  if [ "$OSF_HTTP_CODE" != "201" ] && [ "$OSF_HTTP_CODE" != "200" ]; then
    osf_api_discard
    return 1
  fi
  jq -r '.sha1 // .token // empty' "$OSF_HTTP_BODY" > "$dest"
  osf_api_discard
  chmod 600 "$dest"
  local token
  token=$(tr -d '[:space:]' < "$dest")
  printf '%s\n' "$token" > "$dest"
  chmod 600 "$dest"
  if [ "${#token}" -lt 20 ]; then
    token=""
    rm -f "$dest"
    return 1
  fi
  token=""
}

token_works() {
  local file="$1"
  local expect="$2"
  local login
  if [ ! -s "$file" ]; then
    return 1
  fi
  osf_api "$file" GET "/api/v1/user"
  if [ "$OSF_HTTP_CODE" != "200" ]; then
    osf_api_discard
    return 1
  fi
  login=$(jq -r '.login // empty' "$OSF_HTTP_BODY")
  osf_api_discard
  [ "$login" = "$expect" ]
}

ensure_token() {
  local username="$1"
  local dest="$2"
  if token_works "$dest" "$username"; then
    chmod 600 "$dest"
    return 0
  fi
  if ensure_token_cli "$username" "$dest" && token_works "$dest" "$username"; then
    return 0
  fi
  if [ -f "$admin_token" ] && ensure_token_api "$username" "$dest" && token_works "$dest" "$username"; then
    return 0
  fi
  echo "FAIL: could not make a token for $username" >&2
  return 1
}

ensure_org() {
  osf_api "$admin_token" GET "/api/v1/orgs/acme"
  local code="$OSF_HTTP_CODE"
  osf_api_discard
  if [ "$code" = "200" ]; then
    return 0
  fi
  local body
  body=$(mktemp)
  jq -n '{username:"acme", visibility:"private", description:"Acme Co test org", full_name:"Acme Co"}' > "$body"
  osf_api "$token_dir/acme-admin" POST "/api/v1/orgs" "$body"
  code="$OSF_HTTP_CODE"
  osf_api_discard
  rm -f "$body"
  if [ "$code" = "201" ] || [ "$code" = "200" ] || [ "$code" = "422" ]; then
    return 0
  fi
  echo "FAIL: could not create org acme (HTTP $code)" >&2
  return 1
}

ensure_members_team() {
  local body id code
  osf_api "$token_dir/acme-admin" GET "/api/v1/orgs/acme/teams"
  if [ "$OSF_HTTP_CODE" != "200" ]; then
    osf_api_discard
    echo "FAIL: could not list teams" >&2
    return 1
  fi
  id=$(jq -r '.[] | select(.name=="members") | .id' "$OSF_HTTP_BODY")
  osf_api_discard
  if [ -n "$id" ] && [ "$id" != "null" ]; then
    OSF_MEMBERS_TEAM=$id
    return 0
  fi
  body=$(mktemp)
  jq -n '{name:"members", description:"Acme members", permission:"read", includes_all_repositories:false, can_create_org_repo:false, units_map:{"repo.code":"read","repo.issues":"read","repo.pulls":"read","repo.actions":"read"}}' > "$body"
  osf_api "$token_dir/acme-admin" POST "/api/v1/orgs/acme/teams" "$body"
  id=$(jq -r '.id // empty' "$OSF_HTTP_BODY")
  code=$OSF_HTTP_CODE
  osf_api_discard
  rm -f "$body"
  if [ -z "$id" ]; then
    echo "FAIL: could not create the members team (HTTP $code)" >&2
    return 1
  fi
  OSF_MEMBERS_TEAM=$id
}

ensure_member() {
  local username="$1"
  local code
  osf_api "$token_dir/acme-admin" GET "/api/v1/orgs/acme/members/${username}"
  code=$OSF_HTTP_CODE
  osf_api_discard
  if [ "$code" = "204" ] || [ "$code" = "200" ]; then
    return 0
  fi
  osf_api "$token_dir/acme-admin" PUT "/api/v1/teams/${OSF_MEMBERS_TEAM}/members/${username}"
  code=$OSF_HTTP_CODE
  osf_api_discard
  if [ "$code" = "204" ] || [ "$code" = "200" ]; then
    return 0
  fi
  echo "FAIL: could not add $username to acme (HTTP $code)" >&2
  return 1
}

ensure_runner() {
  local secret_file uuid_file cfg rc out
  secret_file="$cache/runner-secret"
  uuid_file="$cache/runner-uuid"
  if [ ! -s "$secret_file" ]; then
    openssl rand -hex 20 | tr -d '[:space:]' > "$secret_file"
    chmod 600 "$secret_file"
  fi
  chmod 600 "$secret_file"
  out=$(mktemp)
  chmod 600 "$out"
  # Empty scope is an instance runner. An org-scoped runner never starts jobs for acme2-* orgs.
  set +e
  docker exec -u git \
    -e PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    -e OSF_SECRET="$(tr -d '[:space:]' < "$secret_file")" \
    osf-acme-forgejo \
    sh -c 'forgejo forgejo-cli actions register --name osf-acme-runner --secret "$OSF_SECRET"' \
    >"$out" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && ! grep -Eiq 'already|exist|duplicate' "$out"; then
    scrub_file "$out"
    rm -f "$out"
    echo "FAIL: could not register the runner" >&2
    return 1
  fi
  local printed
  printed=$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$out" | head -n 1 || true)
  rm -f "$out"
  if [ -n "$printed" ]; then
    printf '%s\n' "$printed" > "$uuid_file"
    chmod 600 "$uuid_file"
  elif [ ! -s "$uuid_file" ]; then
    python3 -c 'import sys,uuid; s=sys.stdin.read().strip(); print(uuid.UUID(bytes=s[:16].encode("utf-8")))' \
      < "$secret_file" > "$uuid_file"
    chmod 600 "$uuid_file"
  fi

  cfg="$cache/runner-config.yml"
  OSF_TEMPLATE="$root/tests/acme/forgejo/runner-config.template.yml" \
  OSF_DEST="$cfg" \
  OSF_UUID="$(tr -d '[:space:]' < "$uuid_file")" \
  OSF_TOKEN="$(tr -d '[:space:]' < "$secret_file")" \
  python3 -c '
import os
from pathlib import Path
text = Path(os.environ["OSF_TEMPLATE"]).read_text()
text = text.replace("OSF_RUNNER_UUID", os.environ["OSF_UUID"])
text = text.replace("OSF_RUNNER_TOKEN", os.environ["OSF_TOKEN"])
dest = Path(os.environ["OSF_DEST"])
dest.write_text(text)
os.chmod(dest, 0o600)
'
  osf_place_review_fake
  docker cp "$cfg" osf-acme-runner:/data/config.yml
  docker exec -u 0 osf-acme-runner chmod 600 /data/config.yml
  # This restarts the shared runner. Do not run bootstrap while other teams use it.
  docker restart osf-acme-runner >/dev/null
}

wait_runner() {
  local i=0
  while [ "$i" -lt 40 ]; do
    if python3 "$lib/results.py" runner-online >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

actions_enabled() {
  osf_api "$token_dir/acme-admin" GET "/api/v1/orgs/acme/actions/runners/registration-token"
  local code="$OSF_HTTP_CODE"
  # The body is a short-lived token. Discard it. Do not print it.
  osf_api_discard
  [ "$code" = "200" ]
}

# Site admin, then tokens, then the company users.
if ! create_user "osf-admin" "osf-admin@acme.test" "Site Admin" admin; then
  exit 1
fi
if ! ensure_token "osf-admin" "$admin_token"; then
  exit 1
fi

while IFS='|' read -r _seat _engine username full_name email; do
  [ -n "$username" ] || continue
  if ! user_exists_api "$username"; then
    if ! create_user "$username" "$email" "$full_name"; then
      exit 1
    fi
  fi
  if ! ensure_token "$username" "$token_dir/$username"; then
    exit 1
  fi
done < "$lib/seats.txt"

if ! ensure_org; then
  exit 1
fi
if ! ensure_members_team; then
  exit 1
fi

while IFS='|' read -r _seat _engine username _full_name _email; do
  [ -n "$username" ] || continue
  if [ "$username" = "acme-admin" ]; then
    continue
  fi
  if ! ensure_member "$username"; then
    exit 1
  fi
done < "$lib/seats.txt"

if ! ensure_runner; then
  exit 1
fi
if ! wait_runner; then
  echo "FAIL: runner did not come online" >&2
  exit 1
fi
if ! actions_enabled; then
  echo "FAIL: Actions is not enabled for org acme" >&2
  exit 1
fi

while IFS='|' read -r _seat _engine username _full_name _email; do
  [ -n "$username" ] || continue
  echo "$username OK"
done < "$lib/seats.txt"
echo "runner OK"
echo "actions OK"
