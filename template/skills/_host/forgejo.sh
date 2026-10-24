#!/bin/bash
# Forgejo adapter. Uses curl and jq. Other skills must call host.sh, not this file.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap host_cleanup EXIT

host_load_context
if [ "${OS_HOST}" != "forgejo" ]; then
  host_die 1 "host is not forgejo"
fi
if [ -z "${OS_HOST_URL:-}" ]; then
  host_die 1 "host_url is not set"
fi

if [ $# -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  host_usage_text
  if [ $# -eq 0 ]; then
    exit 1
  fi
  exit 0
fi

VERB=$1
shift
set +e
host_parse_args "$@"
parse_rc=$?
set -e
if [ "$parse_rc" -eq 2 ]; then
  host_usage_text
  exit 0
fi
if [ "$parse_rc" -ne 0 ]; then
  exit "$parse_rc"
fi

host_require_bin curl
host_require_bin jq

FJ_HTTP=""
FJ_BODY=""

fj_call() {
  local method=$1 path=$2 body=${3-} secret=${4-}
  local token url out err http code
  token=$(host_forgejo_token)
  url="${OS_HOST_URL%/}/api/v1${path}"
  case "$url" in
    *'token='*)
      host_die 3 "refusing a token in a URL"
      ;;
  esac
  out=$(host_mktemp)
  err=$(host_mktemp)
  code=0
  set +e
  if [ -n "$body" ]; then
    http=$(curl -sS --connect-timeout 10 --max-time 60 \
      -o "$out" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: token ${token}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      --data-binary "$body" \
      "$url" 2>"$err")
  else
    http=$(curl -sS --connect-timeout 10 --max-time 60 \
      -o "$out" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: token ${token}" \
      -H "Accept: application/json" \
      "$url" 2>"$err")
  fi
  code=$?
  set -e
  if [ "$code" -ne 0 ] || [ "$http" = "000" ] || [ -z "$http" ]; then
    host_scrub_file "$err" "$secret" >&2
    FJ_HTTP=0
    FJ_BODY=""
    return 5
  fi
  if [ -s "$err" ]; then
    host_scrub_file "$err" "$secret" >&2
  fi
  FJ_HTTP=$http
  FJ_BODY=$(cat "$out")
  return 0
}

fj_message() {
  local secret=${1-} msg
  msg=$(printf '%s' "$FJ_BODY" | jq -r '.message // empty' 2>/dev/null || true)
  if [ -n "$secret" ] && [ -n "$msg" ]; then
    local tmp
    tmp=$(host_mktemp)
    printf '%s\n' "$msg" > "$tmp"
    msg=$(host_scrub_file "$tmp" "$secret")
  fi
  printf '%s' "$msg"
}

fj_fail() {
  local secret=${1-} msg
  msg=$(fj_message "$secret")
  case "$FJ_HTTP" in
    401) host_die 4 "auth failed" ;;
    403|404) host_die 2 "not found or no access" ;;
    *)
      if [ -n "$msg" ]; then
        host_die 3 "host error (${FJ_HTTP}): ${msg}"
      fi
      host_die 3 "host error (${FJ_HTTP})"
      ;;
  esac
}

fj_ok() {
  local secret=${1-}
  case "$FJ_HTTP" in
    200|201|204) return 0 ;;
  esac
  fj_fail "$secret"
}

fj_offline() {
  jq -nc '{error:"offline"}'
  host_die 5 "host is offline"
}

host_need_name() {
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_name "name" "$POS1"
  host_require_org
}

host_need_number() {
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -n "$POS2" ] || host_die 1 "number is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_name "name" "$POS1"
  host_require_int "number" "$POS2"
  host_require_org
}

host_repo() {
  printf '/repos/%s/%s' "$OS_ORG" "$1"
}

host_require_branch() {
  local val=$1
  case "$val" in
    ""|*..*|/*|*/|*[[:space:]]*)
      host_die 1 "branch is not valid"
      ;;
  esac
  case "$val" in
    *[!A-Za-z0-9._/-]*)
      host_die 1 "branch has invalid characters"
      ;;
  esac
}

fj_code_owner_field() {
  local raw field
  raw=$(curl -sS --connect-timeout 5 --max-time 20 \
    "${OS_HOST_URL%/}/swagger.v1.json" 2>/dev/null || true)
  field=$(printf '%s' "$raw" | jq -r '
    (.definitions.CreateBranchProtectionOption.properties // {})
    | keys[]
    | select(test("code_owner|codeowner"; "i"))
  ' 2>/dev/null | head -n 1 || true)
  printf '%s' "$field"
}

fj_protect_body() {
  local checks_json field=$1
  checks_json=$(host_check_lines "checks / checks (pull_request)" | jq -R . | jq -s 'map(select(length > 0))')
  if [ -n "$field" ]; then
    jq -n \
      --argjson approvals "$APPROVALS" \
      --argjson checks "$checks_json" \
      --arg field "$field" \
      '{
        branch_name: "main",
        rule_name: "main",
        enable_push: false,
        enable_status_check: true,
        status_check_contexts: $checks,
        required_approvals: $approvals,
        apply_to_admins: true
      } + {($field): true}'
  else
    jq -n \
      --argjson approvals "$APPROVALS" \
      --argjson checks "$checks_json" \
      '{
        branch_name: "main",
        rule_name: "main",
        enable_push: false,
        enable_status_check: true,
        status_check_contexts: $checks,
        required_approvals: $approvals,
        apply_to_admins: true
      }'
  fi
}

fj_team_id() {
  local name=$1 id
  if ! fj_call GET "/orgs/${OS_ORG}/teams?limit=50"; then
    fj_offline
  fi
  fj_ok
  id=$(printf '%s' "$FJ_BODY" | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' | head -n 1)
  printf '%s' "$id"
}

host_split_grant() {
  case "$1" in
    team:*)
      GRANT_KIND=team
      GRANT_WHO=${1#team:}
      [ -n "$GRANT_WHO" ] || host_die 1 "team name is empty"
      host_require_team "$GRANT_WHO"
      ;;
    *)
      GRANT_KIND=user
      GRANT_WHO=$1
      host_require_name "user" "$GRANT_WHO"
      ;;
  esac
}

cmd_whoami() {
  [ -z "$POS1" ] || host_die 1 "too many arguments"
  if ! fj_call GET "/user"; then
    fj_offline
  fi
  fj_ok
  jq -nc --arg login "$(printf '%s' "$FJ_BODY" | jq -r '.login // empty')" '
    if $login == "" then error("no login") else {login:$login} end'
}

cmd_create_repo() {
  local name body url repo_json
  host_need_name
  name=$POS1
  if [ "$PUSH" = "1" ] && [ -z "$SOURCE" ]; then
    host_die 1 "--push needs --source"
  fi
  body=$(jq -nc --arg name "$name" \
    '{name:$name, private:true, auto_init:false, default_branch:"main"}')
  if ! fj_call POST "/orgs/${OS_ORG}/repos" "$body"; then
    fj_offline
  fi
  if [ "$FJ_HTTP" = "409" ] || [ "$FJ_HTTP" = "422" ]; then
    if ! fj_call GET "$(host_repo "$name")"; then
      fj_offline
    fi
  fi
  fj_ok
  repo_json=$FJ_BODY
  if [ -n "$SOURCE" ] && [ "$PUSH" = "1" ]; then
    url=$(printf '%s' "$repo_json" | jq -r '.clone_url // empty')
    if [ -z "$url" ]; then
      url=$(host_clone_url "$name")
    fi
    case "$url" in
      *'@'*) host_die 3 "refusing a credential in a clone URL" ;;
    esac
    if ! fj_call GET "/user"; then
      fj_offline
    fi
    fj_ok
    OS_GIT_USER=$(printf '%s' "$FJ_BODY" | jq -r '.login // empty')
    if [ -z "$OS_GIT_USER" ]; then
      OS_GIT_USER=$OS_ORG
    fi
    host_push_source "$SOURCE" "$url"
    FJ_BODY=$repo_json
  fi
  printf '%s' "$repo_json" | jq -c '{name:.name, full_name:.full_name, clone_url:.clone_url, private:.private}'
}

cmd_repo_access() {
  local name
  host_need_name
  name=$POS1
  if ! fj_call GET "$(host_repo "$name")"; then
    jq -nc '{error:"offline"}'
    exit 5
  fi
  case "$FJ_HTTP" in
    200) jq -nc '{access:"ok"}' ;;
    403|404) jq -nc '{access:"no-access"}'; exit 2 ;;
    401) jq -nc '{error:"auth"}'; exit 4 ;;
    *) fj_fail ;;
  esac
}

cmd_protect() {
  local name field body rule
  host_need_name
  name=$POS1
  field=$(fj_code_owner_field)
  body=$(fj_protect_body "$field")
  if ! fj_call GET "$(host_repo "$name")/branch_protections"; then
    fj_offline
  fi
  if [ "$FJ_HTTP" = "404" ]; then
    fj_fail
  fi
  fj_ok
  rule=$(printf '%s' "$FJ_BODY" | jq -r \
    '.[] | select(.rule_name=="main" or .branch_name=="main") | (.rule_name // .branch_name)' \
    | head -n 1)
  if [ -n "$rule" ]; then
    local patch_body
    patch_body=$(printf '%s' "$body" | jq 'del(.branch_name, .rule_name)')
    if ! fj_call PATCH "$(host_repo "$name")/branch_protections/${rule}" "$patch_body"; then
      fj_offline
    fi
  else
    if ! fj_call POST "$(host_repo "$name")/branch_protections" "$body"; then
      fj_offline
    fi
  fi
  fj_ok
  if [ -n "$field" ]; then
    jq -nc --arg field "$field" '{ok:true, branch:"main", code_owners:"set", field:$field}'
  else
    jq -nc '{ok:true, branch:"main", code_owners:"unsupported", gap:"Forgejo branch protection has no code-owner review field. A person who may merge can drop a code-owner request."}'
  fi
}

cmd_team_create() {
  local team body
  [ -n "$POS1" ] || host_die 1 "team is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_team "$POS1"
  host_require_org
  team=$POS1
  body=$(jq -nc --arg name "$team" '{
    name:$name,
    permission:"write",
    can_create_org_repo:false,
    includes_all_repositories:false,
    units:["repo.code","repo.pulls","repo.issues","repo.actions"]
  }')
  if ! fj_call POST "/orgs/${OS_ORG}/teams" "$body"; then
    fj_offline
  fi
  if [ "$FJ_HTTP" = "409" ] || [ "$FJ_HTTP" = "422" ]; then
    local id
    id=$(fj_team_id "$team")
    [ -n "$id" ] || host_die 3 "team exists but was not listed"
    jq -nc --arg name "$team" --arg id "$id" '{name:$name, id:($id|tonumber)}'
    return 0
  fi
  fj_ok
  printf '%s' "$FJ_BODY" | jq -c '{name:.name, id:.id}'
}

cmd_team_add() {
  local team user id
  [ -n "$POS1" ] || host_die 1 "team is required"
  [ -n "$POS2" ] || host_die 1 "user is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_team "$POS1"
  host_require_name "user" "$POS2"
  host_require_org
  team=$POS1
  user=$POS2
  id=$(fj_team_id "$team")
  [ -n "$id" ] || host_die 2 "not found or no access"
  if ! fj_call PUT "/teams/${id}/members/${user}"; then
    fj_offline
  fi
  fj_ok
  jq -nc --arg team "$team" --arg user "$user" '{ok:true, team:$team, user:$user}'
}

cmd_team_remove() {
  local team user id
  [ -n "$POS1" ] || host_die 1 "team is required"
  [ -n "$POS2" ] || host_die 1 "user is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_team "$POS1"
  host_require_name "user" "$POS2"
  host_require_org
  team=$POS1
  user=$POS2
  id=$(fj_team_id "$team")
  [ -n "$id" ] || host_die 2 "not found or no access"
  if ! fj_call DELETE "/teams/${id}/members/${user}"; then
    fj_offline
  fi
  fj_ok
  jq -nc --arg team "$team" --arg user "$user" '{ok:true, team:$team, user:$user}'
}

cmd_grant() {
  local name perm
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -n "$POS2" ] || host_die 1 "user or team is required"
  [ -n "$POS3" ] || host_die 1 "permission is required"
  host_require_name "name" "$POS1"
  host_require_org
  name=$POS1
  host_split_grant "$POS2"
  perm=$(host_permission "$POS3")
  if [ "$GRANT_KIND" = "user" ]; then
    local body
    body=$(jq -nc --arg permission "$perm" '{permission:$permission}')
    if ! fj_call PUT "$(host_repo "$name")/collaborators/${GRANT_WHO}" "$body"; then
      fj_offline
    fi
  else
    local enc
    enc=$(printf '%s' "$GRANT_WHO" | jq -sRr @uri)
    if ! fj_call PUT "$(host_repo "$name")/teams/${enc}"; then
      fj_offline
    fi
  fi
  fj_ok
  jq -nc --arg name "$name" --arg who "$POS2" --arg permission "$perm" \
    '{ok:true, name:$name, who:$who, permission:$permission}'
}

cmd_revoke() {
  local name
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -n "$POS2" ] || host_die 1 "user or team is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_name "name" "$POS1"
  host_require_org
  name=$POS1
  host_split_grant "$POS2"
  if [ "$GRANT_KIND" = "user" ]; then
    if ! fj_call DELETE "$(host_repo "$name")/collaborators/${GRANT_WHO}"; then
      fj_offline
    fi
  else
    local enc
    enc=$(printf '%s' "$GRANT_WHO" | jq -sRr @uri)
    if ! fj_call DELETE "$(host_repo "$name")/teams/${enc}"; then
      fj_offline
    fi
  fi
  fj_ok
  jq -nc --arg name "$name" --arg who "$POS2" '{ok:true, name:$name, who:$who}'
}

cmd_org_remove() {
  local user
  [ -n "$POS1" ] || host_die 1 "user is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_name "user" "$POS1"
  host_require_org
  user=$POS1
  if ! fj_call DELETE "/orgs/${OS_ORG}/members/${user}"; then
    fj_offline
  fi
  fj_ok
  jq -nc --arg user "$user" '{ok:true, user:$user}'
}

cmd_archive() {
  local name body
  host_need_name
  name=$POS1
  body=$(jq -nc '{archived:true}')
  if ! fj_call PATCH "$(host_repo "$name")" "$body"; then
    fj_offline
  fi
  fj_ok
  jq -nc --arg name "$name" '{ok:true, name:$name, archived:true}'
}

cmd_open_pr() {
  local name text body number
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_name "name" "$POS1"
  host_require_org
  [ -n "$HEAD" ] || host_die 1 "--head is required"
  [ -n "$TITLE" ] || host_die 1 "--title is required"
  host_require_branch "$HEAD"
  host_require_branch "$BASE"
  name=$POS1
  text=$(host_read_body_file)
  if ! fj_call GET "$(host_repo "$name")/pulls?state=open&limit=50"; then
    fj_offline
  fi
  fj_ok
  number=$(printf '%s' "$FJ_BODY" | jq -r --arg head "$HEAD" \
    '.[] | select(.head.ref==$head) | .number' | head -n 1)
  if [ -n "$number" ]; then
    body=$(jq -nc --arg title "$TITLE" --arg body "$text" '{title:$title, body:$body}')
    if ! fj_call PATCH "$(host_repo "$name")/pulls/${number}" "$body"; then
      fj_offline
    fi
  else
    body=$(jq -nc --arg title "$TITLE" --arg head "$HEAD" --arg base "$BASE" --arg body "$text" \
      '{title:$title, head:$head, base:$base, body:$body}')
    if ! fj_call POST "$(host_repo "$name")/pulls" "$body"; then
      fj_offline
    fi
  fi
  fj_ok
  printf '%s' "$FJ_BODY" | jq -c '{number:.number, url:.html_url}'
}

cmd_auto_merge() {
  local name number body
  host_need_number
  name=$POS1
  number=$POS2
  body=$(jq -nc '{Do:"merge", merge_when_checks_succeed:true}')
  if ! fj_call POST "$(host_repo "$name")/pulls/${number}/merge" "$body"; then
    fj_offline
  fi
  fj_ok
  jq -nc --arg name "$name" --argjson number "$number" \
    '{ok:true, name:$name, number:$number, merge:"merge"}'
}

cmd_pr_status() {
  local name number pr sha reviews statuses
  host_need_number
  name=$POS1
  number=$POS2
  if ! fj_call GET "$(host_repo "$name")/pulls/${number}"; then
    fj_offline
  fi
  fj_ok
  pr=$FJ_BODY
  sha=$(printf '%s' "$pr" | jq -r '.head.sha // empty')
  [ -n "$sha" ] || host_die 3 "pull request has no head"
  if ! fj_call GET "$(host_repo "$name")/pulls/${number}/reviews"; then
    fj_offline
  fi
  fj_ok
  reviews=$FJ_BODY
  if ! fj_call GET "$(host_repo "$name")/commits/${sha}/status"; then
    fj_offline
  fi
  fj_ok
  statuses=$FJ_BODY
  jq -nc --argjson pr "$pr" --argjson reviews "$reviews" --argjson statuses "$statuses" '
    {
      state: $pr.state,
      merged: $pr.merged,
      approved: ([$reviews[]?.state // empty] | map(ascii_downcase) | index("approved") != null),
      checks: [($statuses.statuses // [])[] | {name:.context, state:.status}]
    }'
}

cmd_pr_comment() {
  local name number text body
  host_need_number
  name=$POS1
  number=$POS2
  [ -n "$BODY_FILE" ] || host_die 1 "--body-file is required"
  text=$(host_read_body_file)
  body=$(jq -nc --arg body "$text" '{body:$body}')
  if ! fj_call POST "$(host_repo "$name")/issues/${number}/comments" "$body"; then
    fj_offline
  fi
  fj_ok
  printf '%s' "$FJ_BODY" | jq -c '{ok:true, id:.id}'
}

cmd_set_secret() {
  local name secret_file body secret
  [ -n "$POS1" ] || host_die 1 "secret name is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_org
  case "$POS1" in
    *[!A-Za-z0-9_]*) host_die 1 "secret name has invalid characters" ;;
  esac
  name=$POS1
  secret_file=$(host_mktemp)
  cat > "$secret_file"
  secret=$(cat "$secret_file")
  body=$(jq -nc --rawfile data "$secret_file" '{data:$data}')
  if ! fj_call PUT "/orgs/${OS_ORG}/actions/secrets/${name}" "$body" "$secret"; then
    host_die 5 "host is offline"
  fi
  case "$FJ_HTTP" in
    201|204) jq -nc --arg name "$name" '{ok:true, name:$name}' ;;
    *) fj_fail "$secret" ;;
  esac
}

cmd_get_token() {
  local path token
  [ -z "$POS1" ] || host_die 1 "too many arguments"
  if [ -n "$BOT" ]; then
    path=$(host_bot_field "$BOT" token_path 2>/dev/null || true)
    if [ -z "$path" ]; then
      path="$(host_config_dir)/bots/${BOT}/token"
    fi
    [ -f "$path" ] || host_die 4 "bot token file is missing"
    token=$(tr -d '\r\n' < "$path")
    [ -n "$token" ] || host_die 4 "bot token is empty"
    printf '%s\n' "$token"
    return 0
  fi
  token=$(host_forgejo_token)
  printf '%s\n' "$token"
}

cmd_purge() {
  local name tried
  host_need_name
  name=$POS1
  tried=""
  if ! fj_call POST "$(host_repo "$name")/git/gc"; then
    jq -nc '{purged:false, gap:"host is offline"}'
    exit 5
  fi
  tried="/repos/${OS_ORG}/${name}/git/gc"
  if [ "$FJ_HTTP" = "200" ] || [ "$FJ_HTTP" = "201" ] || [ "$FJ_HTTP" = "204" ]; then
    jq -nc --arg path "$tried" '{purged:true, path:$path}'
    return 0
  fi
  if ! fj_call POST "/admin/cron/gc_repos"; then
    jq -nc '{purged:false, gap:"host is offline"}'
    exit 5
  fi
  if [ "$FJ_HTTP" = "200" ] || [ "$FJ_HTTP" = "201" ] || [ "$FJ_HTTP" = "204" ]; then
    jq -nc '{purged:true, path:"/admin/cron/gc_repos", note:"instance cron, not a per-repo purge"}'
    return 0
  fi
  jq -nc --arg tried "$tried" '{
    purged:false,
    gap:"Forgejo has no API to drop unreachable objects in one repository. An admin must run git gc --prune=now on the server repo.",
    tried:[$tried, "/admin/cron/gc_repos"]
  }'
}

cmd_delete() {
  local name
  host_need_name
  name=$POS1
  if [ "$YES" != "1" ]; then
    host_die 1 "delete-repo refuses without --yes-test-only"
  fi
  if [ "${OS_TEST_MODE:-}" != "1" ]; then
    host_die 1 "delete-repo refuses unless OS_TEST_MODE=1"
  fi
  if ! fj_call DELETE "$(host_repo "$name")"; then
    fj_offline
  fi
  fj_ok
  jq -nc --arg name "$name" '{ok:true, name:$name, deleted:true}'
}

case "$VERB" in
  whoami) cmd_whoami ;;
  create-repo) cmd_create_repo ;;
  repo-access) cmd_repo_access ;;
  protect) cmd_protect ;;
  team-create) cmd_team_create ;;
  team-add) cmd_team_add ;;
  team-remove) cmd_team_remove ;;
  grant) cmd_grant ;;
  revoke) cmd_revoke ;;
  org-remove) cmd_org_remove ;;
  archive-repo) cmd_archive ;;
  open-pr) cmd_open_pr ;;
  auto-merge) cmd_auto_merge ;;
  pr-status) cmd_pr_status ;;
  pr-comment) cmd_pr_comment ;;
  set-secret) cmd_set_secret ;;
  get-token) cmd_get_token ;;
  purge-request) cmd_purge ;;
  delete-repo) cmd_delete ;;
  *) host_die 1 "unknown verb: ${VERB}" ;;
esac
