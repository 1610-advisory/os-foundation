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

fj_drop() {
  rm -f "$@"
}

fj_call() {
  local method=$1 path=$2 body=${3-} secret_file=${4-}
  local token url out err http code cfg bodyfile
  token=$(host_forgejo_token)
  url="${OS_HOST_URL%/}/api/v1${path}"
  case "$url" in
    *'token='*)
      host_die 3 "refusing a token in a URL"
      ;;
  esac
  out=$(host_mktemp)
  err=$(host_mktemp)
  cfg=$(host_mktemp)
  bodyfile=""
  chmod 600 "$cfg" "$out"
  {
    printf '%s\n' "header = \"Authorization: token ${token}\""
    printf '%s\n' 'header = "Accept: application/json"'
    printf '%s\n' 'header = "Content-Type: application/json"'
    printf '%s\n' "url = \"${url}\""
    printf '%s\n' "request = \"${method}\""
    printf '%s\n' "output = \"${out}\""
    printf '%s\n' 'silent'
    printf '%s\n' 'show-error'
    printf '%s\n' 'connect-timeout = 10'
    printf '%s\n' 'max-time = 60'
    printf '%s\n' 'write-out = "%{http_code}"'
  } > "$cfg"
  if [ -n "$body" ]; then
    bodyfile=$(host_mktemp)
    chmod 600 "$bodyfile"
    printf '%s' "$body" > "$bodyfile"
    printf '%s\n' "data-binary = \"@${bodyfile}\"" >> "$cfg"
  fi
  code=0
  set +e
  http=$(curl --config "$cfg" 2>"$err")
  code=$?
  set -e
  if [ "$code" -ne 0 ] || [ "$http" = "000" ] || [ -z "$http" ]; then
    host_scrub_file "$err" "$secret_file" >&2
    FJ_HTTP=0
    FJ_BODY=""
    fj_drop "$cfg" "$out" "$err" "$bodyfile"
    return 5
  fi
  if [ -s "$err" ]; then
    host_scrub_file "$err" "$secret_file" >&2
  fi
  FJ_HTTP=$http
  FJ_BODY=$(cat "$out")
  fj_drop "$cfg" "$out" "$err" "$bodyfile"
  return 0
}

fj_message() {
  local secret_file=${1-} msg
  msg=$(printf '%s' "$FJ_BODY" | jq -r '.message // empty' 2>/dev/null || true)
  if [ -n "$secret_file" ] && [ -f "$secret_file" ] && [ -n "$msg" ]; then
    local tmp
    tmp=$(host_mktemp)
    printf '%s\n' "$msg" > "$tmp"
    msg=$(host_scrub_file "$tmp" "$secret_file")
    rm -f "$tmp"
  fi
  printf '%s' "$msg"
}

fj_fail() {
  local secret_file=${1-} msg
  msg=$(fj_message "$secret_file")
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
      apply_to_admins: true,
      block_on_official_review_requests: true
    } + (if $field == "" then {} else {($field): true} end)'
}

fj_team_id() {
  local name=$1 id page=1 n
  FJ_TEAM_ID=""
  while true; do
    if ! fj_call GET "/orgs/${OS_ORG}/teams?limit=50&page=${page}"; then
      fj_offline
    fi
    fj_ok
    id=$(printf '%s' "$FJ_BODY" | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' | head -n 1)
    if [ -n "$id" ]; then
      FJ_TEAM_ID=$id
      return 0
    fi
    n=$(printf '%s' "$FJ_BODY" | jq 'length')
    if [ "$n" -lt 50 ]; then
      return 0
    fi
    page=$((page + 1))
  done
}

fj_team_permission() {
  local name=$1 page=1 perm n
  while true; do
    if ! fj_call GET "/orgs/${OS_ORG}/teams?limit=50&page=${page}"; then
      fj_offline
    fi
    fj_ok
    perm=$(printf '%s' "$FJ_BODY" | jq -r --arg name "$name" '.[] | select(.name==$name) | .permission' | head -n 1)
    if [ -n "$perm" ]; then
      printf '%s' "$perm"
      return 0
    fi
    n=$(printf '%s' "$FJ_BODY" | jq 'length')
    if [ "$n" -lt 50 ]; then
      return 0
    fi
    page=$((page + 1))
  done
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
  jq -nc --arg field "$field" '{
    ok: true,
    branch: "main",
    code_owners: "request-block",
    gap: "Forgejo has no require-code-owner-review field. It blocks while an official review request is open. A person who can merge can remove that request.",
    field: (if $field == "" then null else $field end)
  }'
}

cmd_unprotect() {
  local name page n saved rule
  host_need_name
  name=$POS1
  if [ "${HOST_DRY_RUN:-}" = "1" ]; then
    host_emit_call DELETE "$(host_repo "$name")/branch_protections/main"
    return 0
  fi
  saved=$(host_mktemp)
  page=1
  while true; do
    if ! fj_call GET "$(host_repo "$name")/branch_protections?limit=50&page=${page}"; then
      fj_offline
    fi
    if [ "$FJ_HTTP" = "404" ]; then
      break
    fi
    case "$FJ_HTTP" in
      200) ;;
      *) fj_fail ;;
    esac
    printf '%s' "$FJ_BODY" | jq -c '.[] | select(.rule_name=="main")' | head -n 1 > "$saved"
    if [ -s "$saved" ]; then
      break
    fi
    n=$(printf '%s' "$FJ_BODY" | jq 'if type == "array" then length else 0 end')
    if [ "$n" -lt 50 ]; then
      break
    fi
    page=$((page + 1))
  done
  if [ ! -s "$saved" ]; then
    jq -nc --arg name "$name" '{ok:true, name:$name, branch:"main", removed:false}'
    return 0
  fi
  rule=main
  if ! fj_call DELETE "$(host_repo "$name")/branch_protections/${rule}"; then
    fj_offline
  fi
  case "$FJ_HTTP" in
    200|201|204) ;;
    *)
      fj_fail
      ;;
  esac
  if ! fj_call GET "$(host_repo "$name")/branch_protections/${rule}" || [ "$FJ_HTTP" != "404" ]; then
    if ! fj_call POST "$(host_repo "$name")/branch_protections" "$(cat "$saved")"; then
      host_die 3 "PROTECTION IS OFF on ${name}: run skills/_host/host.sh protect ${name} --code-owners --approvals 0"
    fi
    case "$FJ_HTTP" in
      200|201|204) ;;
      *)
        host_die 3 "PROTECTION IS OFF on ${name}: run skills/_host/host.sh protect ${name} --code-owners --approvals 0"
        ;;
    esac
    if ! fj_call GET "$(host_repo "$name")/branch_protections/${rule}" || [ "$FJ_HTTP" != "200" ]; then
      host_die 3 "PROTECTION IS OFF on ${name}: run skills/_host/host.sh protect ${name} --code-owners --approvals 0"
    fi
    host_die 3 "unprotect failed. The main rule was restored."
  fi
  jq -nc --arg name "$name" '{ok:true, name:$name, branch:"main"}'
}

cmd_secret_exists() {
  local name
  [ -n "$POS1" ] || host_die 1 "secret name is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_org
  case "$POS1" in
    *[!A-Za-z0-9_]*) host_die 1 "secret name has invalid characters" ;;
  esac
  name=$POS1
  if [ "${HOST_DRY_RUN:-}" = "1" ]; then
    host_emit_call GET "/orgs/${OS_ORG}/actions/secrets/${name}"
    return 0
  fi
  if ! fj_call GET "/orgs/${OS_ORG}/actions/secrets/${name}"; then
    fj_offline
  fi
  case "$FJ_HTTP" in
    200) jq -nc '{exists:true}' ;;
    404) jq -nc '{exists:false}' ;;
    401|403)
      host_die 4 "cannot read org secrets: sign in as an org owner"
      ;;
    *) fj_fail ;;
  esac
}

cmd_user_access() {
  local name user perm access
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -n "$POS2" ] || host_die 1 "user is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_name "name" "$POS1"
  host_require_name "user" "$POS2"
  name=$POS1
  user=$POS2
  if [ "${HOST_DRY_RUN:-}" = "1" ]; then
    host_emit_call GET "$(host_repo "$name")/collaborators/${user}/permission"
    return 0
  fi
  if ! fj_call GET "$(host_repo "$name")/collaborators/${user}/permission"; then
    fj_offline
  fi
  case "$FJ_HTTP" in
    404)
      jq -nc '{access:"none"}'
      return 0
      ;;
    200) ;;
    401|403) host_die 4 "auth failed" ;;
    *) fj_fail ;;
  esac
  perm=$(printf '%s' "$FJ_BODY" | jq -r '.permission // .role_name // "none"')
  case "$perm" in
    admin|owner) access="admin" ;;
    write|maintain|push) access="write" ;;
    read|pull|triage) access="read" ;;
    *) access="none" ;;
  esac
  jq -nc --arg access "$access" '{access:$access}'
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
    fj_team_id "$team"
    id=$FJ_TEAM_ID
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
  fj_team_id "$team"
  id=$FJ_TEAM_ID
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
  fj_team_id "$team"
  id=$FJ_TEAM_ID
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
    local id applied
    fj_team_id "$GRANT_WHO"
    id=$FJ_TEAM_ID
    [ -n "$id" ] || host_die 2 "not found or no access"
    applied=$(fj_team_permission "$GRANT_WHO")
    if [ "$applied" != "$perm" ]; then
      host_die 3 "Forgejo applies the team permission (${applied}), not a per-repo ${perm}"
    fi
    if ! fj_call PUT "/teams/${id}/repos/${OS_ORG}/${name}"; then
      fj_offline
    fi
    perm=$applied
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
  local name text body number page n
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
  number=""
  page=1
  while true; do
    if ! fj_call GET "$(host_repo "$name")/pulls?state=open&limit=50&page=${page}"; then
      fj_offline
    fi
    fj_ok
    number=$(printf '%s' "$FJ_BODY" | jq -r --arg head "$HEAD" \
      '.[] | select(.head.ref==$head) | .number' | head -n 1)
    if [ -n "$number" ]; then
      break
    fi
    n=$(printf '%s' "$FJ_BODY" | jq 'length')
    if [ "$n" -lt 50 ]; then
      break
    fi
    page=$((page + 1))
  done
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
  local name number body n msg
  host_need_number
  name=$POS1
  number=$POS2
  body=$(jq -nc '{Do:"merge", merge_when_checks_succeed:true}')
  n=0
  while true; do
    if ! fj_call POST "$(host_repo "$name")/pulls/${number}/merge" "$body"; then
      fj_offline
    fi
    if [ "$FJ_HTTP" = "200" ] || [ "$FJ_HTTP" = "201" ] || [ "$FJ_HTTP" = "204" ]; then
      break
    fi
    msg=$(fj_message)
    if [ "$FJ_HTTP" = "405" ] && [ "$n" -lt 15 ]; then
      case "$msg" in
        *"Please try again later"*)
          n=$((n + 1))
          sleep 1
          continue
          ;;
      esac
    fi
    fj_fail
  done
  jq -nc --arg name "$name" --argjson number "$number" \
    '{ok:true, name:$name, number:$number, merge:"merge"}'
}

cmd_pr_status() {
  local name number pr sha reviews statuses page n
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
  reviews='[]'
  page=1
  while true; do
    if ! fj_call GET "$(host_repo "$name")/pulls/${number}/reviews?limit=50&page=${page}"; then
      fj_offline
    fi
    fj_ok
    reviews=$(jq -n --argjson a "$reviews" --argjson b "$FJ_BODY" '$a + $b')
    n=$(printf '%s' "$FJ_BODY" | jq 'length')
    if [ "$n" -lt 50 ]; then
      break
    fi
    page=$((page + 1))
  done
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
  local name secret_file body
  [ -n "$POS1" ] || host_die 1 "secret name is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_org
  case "$POS1" in
    *[!A-Za-z0-9_]*) host_die 1 "secret name has invalid characters" ;;
  esac
  name=$POS1
  secret_file=$(host_mktemp)
  cat > "$secret_file"
  body=$(jq -nc --rawfile data "$secret_file" '{data:$data}')
  if ! fj_call PUT "/orgs/${OS_ORG}/actions/secrets/${name}" "$body" "$secret_file"; then
    host_die 5 "host is offline"
  fi
  case "$FJ_HTTP" in
    201|204) jq -nc --arg name "$name" '{ok:true, name:$name}' ;;
    *) fj_fail "$secret_file" ;;
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

fj_purge_one() {
  local path=$1
  if ! fj_call POST "$path"; then
    jq -nc '{purged:false, gap:"host is offline"}'
    exit 5
  fi
  case "$FJ_HTTP" in
    200|201|204) return 0 ;;
    401|403) fj_fail ;;
    404) return 1 ;;
    *) fj_fail ;;
  esac
}

cmd_purge() {
  local name tried
  host_need_name
  name=$POS1
  tried="/repos/${OS_ORG}/${name}/git/gc"
  if fj_purge_one "$tried"; then
    jq -nc --arg path "$tried" '{purged:true, path:$path}'
    return 0
  fi
  if fj_purge_one "/admin/cron/gc_repos"; then
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
  unprotect) cmd_unprotect ;;
  secret-exists) cmd_secret_exists ;;
  user-access) cmd_user_access ;;
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
