#!/bin/bash
# GitHub adapter. Uses gh. Other skills must call host.sh, not this file.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap host_cleanup EXIT

host_load_context
if [ "${OS_HOST}" != "github" ]; then
  host_die 1 "host is not github"
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

GH_HOSTNAME=""
if [ -n "${OS_HOST_URL:-}" ]; then
  GH_HOSTNAME=${OS_HOST_URL#https://}
  GH_HOSTNAME=${GH_HOSTNAME#http://}
  GH_HOSTNAME=${GH_HOSTNAME%%/*}
  GH_HOSTNAME=${GH_HOSTNAME%/}
fi

host_dry() {
  [ "${HOST_DRY_RUN:-}" = "1" ]
}

host_emit() {
  local method=$1 path=$2 body=${3-}
  if [ -n "$GH_HOSTNAME" ]; then
    host_emit_call "$method" "$path" "$body" "$GH_HOSTNAME"
  else
    host_emit_call "$method" "$path" "$body"
  fi
}

host_classify_gh() {
  local errfile=$1 code=$2 text
  text=$(cat "$errfile")
  case "$text" in
    *"Could not resolve"*|*"error connecting"*|*"connect: "*|*"connection refused"*|*"network is unreachable"*|*"TLS handshake timeout"*|*"i/o timeout"*)
      printf '%s\n' "5"
      return
      ;;
  esac
  case "$text" in
    *"HTTP 401"*|*"Bad credentials"*|*"authentication required"*|*"Requires authentication"*)
      printf '%s\n' "4"
      return
      ;;
  esac
  case "$text" in
    *"HTTP 404"*|*"HTTP 403"*)
      printf '%s\n' "2"
      return
      ;;
  esac
  if [ "$code" -eq 4 ]; then
    printf '%s\n' "4"
    return
  fi
  printf '%s\n' "3"
}

# Run gh. On success print the body. On failure scrub stderr, set GH_STATUS, return it.
host_gh_call() {
  local method=$1 path=$2 body=${3-}
  local out err code
  host_require_bin gh
  out=$(host_mktemp)
  err=$(host_mktemp)
  set +e
  if [ -n "$GH_HOSTNAME" ]; then
    if [ -n "$body" ]; then
      printf '%s' "$body" | gh api --hostname "$GH_HOSTNAME" --method "$method" "$path" --input - >"$out" 2>"$err"
    else
      gh api --hostname "$GH_HOSTNAME" --method "$method" "$path" >"$out" 2>"$err"
    fi
  else
    if [ -n "$body" ]; then
      printf '%s' "$body" | gh api --method "$method" "$path" --input - >"$out" 2>"$err"
    else
      gh api --method "$method" "$path" >"$out" 2>"$err"
    fi
  fi
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    GH_STATUS=0
    cat "$out"
    return 0
  fi
  GH_STATUS=$(host_classify_gh "$err" "$code")
  host_scrub_file "$err" >&2
  case "$GH_STATUS" in
    2) printf '%s\n' "not found or no access" >&2 ;;
    4) printf '%s\n' "auth failed" >&2 ;;
    5) printf '%s\n' "host is offline" >&2 ;;
    *) printf '%s\n' "host error" >&2 ;;
  esac
  return "$GH_STATUS"
}

host_gh_ok() {
  local body
  set +e
  body=$(host_gh_call "$@")
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi
  printf '%s' "$body"
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

host_ruleset_body() {
  local checks_json
  host_require_bin jq
  checks_json=$(host_check_lines "checks" | jq -R . | jq -s 'map(select(length > 0)) | map({context:.})')
  jq -n \
    --argjson approvals "$APPROVALS" \
    --argjson checks "$checks_json" \
    --argjson code_owners "$( [ "$CODE_OWNERS" = "1" ] && printf 'true' || printf 'false' )" \
    '{
      name: "main",
      target: "branch",
      enforcement: "active",
      conditions: {ref_name: {include: ["refs/heads/main"], exclude: []}},
      rules: [
        {
          type: "pull_request",
          parameters: {
            dismiss_stale_reviews_on_push: false,
            require_code_owner_review: $code_owners,
            require_last_push_approval: false,
            required_approving_review_count: $approvals,
            required_review_thread_resolution: false
          }
        },
        {
          type: "required_status_checks",
          parameters: {
            required_status_checks: $checks,
            strict_required_status_checks_policy: false
          }
        },
        {type: "non_fast_forward"},
        {type: "deletion"}
      ]
    }'
}

host_support_text() {
  local name=$1
  cat << EOF
Please purge unreachable Git objects from this repository after a history rewrite.

Repository: https://github.com/${OS_ORG}/${name}
Request: run garbage collection and drop unreachable objects, including caches and forks that still hold the old objects.

Why: a leak was removed from history. The old objects must not stay readable.
EOF
}

cmd_whoami() {
  [ -z "$POS1" ] || host_die 1 "too many arguments"
  if host_dry; then
    host_emit GET "/user"
    return 0
  fi
  local body login
  body=$(host_gh_ok GET "/user")
  login=$(printf '%s' "$body" | jq -r '.login // empty')
  [ -n "$login" ] || host_die 3 "host did not return a login"
  jq -nc --arg login "$login" '{login:$login}'
}

cmd_create_repo() {
  local name body result url
  host_need_name
  name=$POS1
  if [ "$PUSH" = "1" ] && [ -z "$SOURCE" ]; then
    host_die 1 "--push needs --source"
  fi
  host_require_bin jq
  body=$(jq -nc --arg name "$name" '{name:$name, private:true, visibility:"private"}')
  if host_dry; then
    host_emit POST "/orgs/${OS_ORG}/repos" "$body"
    if [ -n "$SOURCE" ] && [ "$PUSH" = "1" ]; then
      host_push_source "$SOURCE" "$(host_clone_url "$name")"
    fi
    return 0
  fi
  result=$(host_gh_ok POST "/orgs/${OS_ORG}/repos" "$body")
  if [ -n "$SOURCE" ] && [ "$PUSH" = "1" ]; then
    url=$(printf '%s' "$result" | jq -r '.clone_url // empty')
    if [ -z "$url" ]; then
      url=$(host_clone_url "$name")
    fi
    host_push_source "$SOURCE" "$url"
  fi
  printf '%s' "$result" | jq -c '{name:.name, full_name:.full_name, clone_url:.clone_url, private:.private}'
}

cmd_repo_access() {
  local name body rc
  host_need_name
  name=$POS1
  if host_dry; then
    host_emit GET "$(host_repo "$name")"
    return 0
  fi
  set +e
  body=$(host_gh_call GET "$(host_repo "$name")")
  rc=$?
  set -e
  case "$rc" in
    0) jq -nc '{access:"ok"}' ;;
    2) jq -nc '{access:"no-access"}'; exit 2 ;;
    4) jq -nc '{error:"auth"}'; exit 4 ;;
    5) jq -nc '{error:"offline"}'; exit 5 ;;
    *) exit "$rc" ;;
  esac
}

cmd_protect() {
  local name body
  host_need_name
  name=$POS1
  body=$(host_ruleset_body)
  if host_dry; then
    host_emit POST "$(host_repo "$name")/rulesets" "$body"
    return 0
  fi
  local list existing
  list=$(host_gh_ok GET "$(host_repo "$name")/rulesets")
  existing=$(printf '%s' "$list" | jq -r '.[] | select(.name=="main") | .id' | head -n 1)
  if [ -n "$existing" ]; then
    host_gh_ok PUT "$(host_repo "$name")/rulesets/${existing}" "$body" >/dev/null
  else
    host_gh_ok POST "$(host_repo "$name")/rulesets" "$body" >/dev/null
  fi
  jq -nc --arg name "$name" '{ok:true, name:$name, ruleset:"main"}'
}

cmd_team_create() {
  local team body
  [ -n "$POS1" ] || host_die 1 "team is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_team "$POS1"
  host_require_org
  team=$POS1
  body=$(jq -nc --arg name "$team" '{name:$name, privacy:"closed"}')
  if host_dry; then
    host_emit POST "/orgs/${OS_ORG}/teams" "$body"
    return 0
  fi
  host_gh_ok POST "/orgs/${OS_ORG}/teams" "$body" | jq -c '{name:.name, slug:.slug, id:.id}'
}

cmd_team_add() {
  local team user slug body
  [ -n "$POS1" ] || host_die 1 "team is required"
  [ -n "$POS2" ] || host_die 1 "user is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_team "$POS1"
  host_require_name "user" "$POS2"
  host_require_org
  team=$POS1
  user=$POS2
  slug=$(host_slugify "$team")
  body=$(jq -nc '{role:"member"}')
  if host_dry; then
    host_emit PUT "/orgs/${OS_ORG}/teams/${slug}/memberships/${user}" "$body"
    return 0
  fi
  host_gh_ok PUT "/orgs/${OS_ORG}/teams/${slug}/memberships/${user}" "$body" >/dev/null
  jq -nc --arg team "$team" --arg user "$user" '{ok:true, team:$team, user:$user}'
}

cmd_team_remove() {
  local team user slug
  [ -n "$POS1" ] || host_die 1 "team is required"
  [ -n "$POS2" ] || host_die 1 "user is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_team "$POS1"
  host_require_name "user" "$POS2"
  host_require_org
  team=$POS1
  user=$POS2
  slug=$(host_slugify "$team")
  if host_dry; then
    host_emit DELETE "/orgs/${OS_ORG}/teams/${slug}/memberships/${user}"
    return 0
  fi
  host_gh_ok DELETE "/orgs/${OS_ORG}/teams/${slug}/memberships/${user}" >/dev/null
  jq -nc --arg team "$team" --arg user "$user" '{ok:true, team:$team, user:$user}'
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

cmd_grant() {
  local name perm gperm body path
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -n "$POS2" ] || host_die 1 "user or team is required"
  [ -n "$POS3" ] || host_die 1 "permission is required"
  host_require_name "name" "$POS1"
  host_require_org
  name=$POS1
  host_split_grant "$POS2"
  perm=$(host_permission "$POS3")
  gperm=$(host_github_permission "$perm")
  body=$(jq -nc --arg permission "$gperm" '{permission:$permission}')
  if [ "$GRANT_KIND" = "team" ]; then
    path="/orgs/${OS_ORG}/teams/$(host_slugify "$GRANT_WHO")/repos/${OS_ORG}/${name}"
  else
    path="$(host_repo "$name")/collaborators/${GRANT_WHO}"
  fi
  if host_dry; then
    host_emit PUT "$path" "$body"
    return 0
  fi
  host_gh_ok PUT "$path" "$body" >/dev/null
  jq -nc --arg name "$name" --arg who "$POS2" --arg permission "$perm" \
    '{ok:true, name:$name, who:$who, permission:$permission}'
}

cmd_revoke() {
  local name path
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -n "$POS2" ] || host_die 1 "user or team is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_name "name" "$POS1"
  host_require_org
  name=$POS1
  host_split_grant "$POS2"
  if [ "$GRANT_KIND" = "team" ]; then
    path="/orgs/${OS_ORG}/teams/$(host_slugify "$GRANT_WHO")/repos/${OS_ORG}/${name}"
  else
    path="$(host_repo "$name")/collaborators/${GRANT_WHO}"
  fi
  if host_dry; then
    host_emit DELETE "$path"
    return 0
  fi
  host_gh_ok DELETE "$path" >/dev/null
  jq -nc --arg name "$name" --arg who "$POS2" '{ok:true, name:$name, who:$who}'
}

cmd_org_remove() {
  local user
  [ -n "$POS1" ] || host_die 1 "user is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_name "user" "$POS1"
  host_require_org
  user=$POS1
  if host_dry; then
    host_emit DELETE "/orgs/${OS_ORG}/members/${user}"
    return 0
  fi
  host_gh_ok DELETE "/orgs/${OS_ORG}/members/${user}" >/dev/null
  jq -nc --arg user "$user" '{ok:true, user:$user}'
}

cmd_archive() {
  local name body
  host_need_name
  name=$POS1
  body=$(jq -nc '{archived:true}')
  if host_dry; then
    host_emit PATCH "$(host_repo "$name")" "$body"
    return 0
  fi
  host_gh_ok PATCH "$(host_repo "$name")" "$body" >/dev/null
  jq -nc --arg name "$name" '{ok:true, name:$name, archived:true}'
}

cmd_open_pr() {
  local name text body
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
  body=$(jq -nc --arg title "$TITLE" --arg head "$HEAD" --arg base "$BASE" --arg body "$text" \
    '{title:$title, head:$head, base:$base, body:$body}')
  if host_dry; then
    host_emit POST "$(host_repo "$name")/pulls" "$body"
    return 0
  fi
  local list number existing patch
  local head_q
  head_q=$(printf '%s' "${OS_ORG}:${HEAD}" | jq -sRr @uri)
  list=$(host_gh_ok GET "$(host_repo "$name")/pulls?state=open&head=${head_q}")
  number=$(printf '%s' "$list" | jq -r --arg head "$HEAD" \
    '.[] | select(.head.ref==$head) | .number' | head -n 1)
  if [ -n "$number" ]; then
    patch=$(jq -nc --arg title "$TITLE" --arg body "$text" '{title:$title, body:$body}')
    existing=$(host_gh_ok PATCH "$(host_repo "$name")/pulls/${number}" "$patch")
  else
    existing=$(host_gh_ok POST "$(host_repo "$name")/pulls" "$body")
  fi
  printf '%s' "$existing" | jq -c '{number:.number, url:.html_url}'
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

cmd_auto_merge() {
  local name number
  host_need_number
  name=$POS1
  number=$POS2
  if host_dry; then
    host_emit EXEC "gh pr merge ${number} --repo ${OS_ORG}/${name} --auto --merge"
    return 0
  fi
  host_require_bin gh
  local err code
  err=$(host_mktemp)
  set +e
  if [ -n "$GH_HOSTNAME" ]; then
    gh pr merge "$number" --repo "${OS_ORG}/${name}" --auto --merge --hostname "$GH_HOSTNAME" >"$err" 2>&1
  else
    gh pr merge "$number" --repo "${OS_ORG}/${name}" --auto --merge >"$err" 2>&1
  fi
  code=$?
  set -e
  if [ "$code" -ne 0 ]; then
    host_scrub_file "$err" >&2
    GH_STATUS=$(host_classify_gh "$err" "$code")
    exit "$GH_STATUS"
  fi
  jq -nc --arg name "$name" --argjson number "$number" '{ok:true, name:$name, number:$number, merge:"merge"}'
}

cmd_pr_status() {
  local name number
  host_need_number
  name=$POS1
  number=$POS2
  if host_dry; then
    host_emit GET "$(host_repo "$name")/pulls/${number}"
    host_emit GET "$(host_repo "$name")/pulls/${number}/reviews"
    host_emit GET "$(host_repo "$name")/commits/{sha}/check-runs"
    host_emit GET "$(host_repo "$name")/commits/{sha}/status"
    return 0
  fi
  local pr sha reviews checks statuses
  pr=$(host_gh_ok GET "$(host_repo "$name")/pulls/${number}")
  sha=$(printf '%s' "$pr" | jq -r '.head.sha // empty')
  [ -n "$sha" ] || host_die 3 "pull request has no head"
  reviews=$(host_gh_ok GET "$(host_repo "$name")/pulls/${number}/reviews")
  checks=$(host_gh_ok GET "$(host_repo "$name")/commits/${sha}/check-runs")
  statuses=$(host_gh_ok GET "$(host_repo "$name")/commits/${sha}/status")
  jq -nc --argjson pr "$pr" --argjson reviews "$reviews" --argjson checks "$checks" --argjson statuses "$statuses" '
    {
      state: $pr.state,
      merged: $pr.merged,
      approved: ([$reviews[]?.state] | map(ascii_downcase) | index("approved") != null),
      checks: (
        [($checks.check_runs // [])[] | {name:.name, state:(.conclusion // .status)}]
        + [($statuses.statuses // [])[] | {name:.context, state:.state}]
      )
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
  if host_dry; then
    host_emit POST "$(host_repo "$name")/issues/${number}/comments" "$body"
    return 0
  fi
  host_gh_ok POST "$(host_repo "$name")/issues/${number}/comments" "$body" \
    | jq -c '{ok:true, id:.id}'
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
  if host_dry; then
    body=$(jq -nc '{encrypted_value:"<redacted>", key_id:"<public-key>", visibility:"all"}')
    host_emit PUT "/orgs/${OS_ORG}/actions/secrets/${name}" "$body"
    return 0
  fi
  host_require_bin gh
  local err code
  err=$(host_mktemp)
  set +e
  if [ -n "$GH_HOSTNAME" ]; then
    gh secret set "$name" --org "$OS_ORG" --visibility all --hostname "$GH_HOSTNAME" < "$secret_file" >"$err" 2>&1
  else
    gh secret set "$name" --org "$OS_ORG" --visibility all < "$secret_file" >"$err" 2>&1
  fi
  code=$?
  set -e
  if [ "$code" -ne 0 ]; then
    host_scrub_file "$err" "$(cat "$secret_file")" >&2
    GH_STATUS=$(host_classify_gh "$err" "$code")
    exit "$GH_STATUS"
  fi
  jq -nc --arg name "$name" '{ok:true, name:$name}'
}

cmd_get_token() {
  [ -z "$POS1" ] || host_die 1 "too many arguments"
  if [ -n "$BOT" ]; then
    local inst
    inst=$(host_bot_field "$BOT" installation_id)
    host_bot_field "$BOT" app_id >/dev/null
    if host_dry; then
      host_emit POST "/app/installations/${inst}/access_tokens" "" 
      # auth is never printed. The call record has no token.
      return 0
    fi
    local key jwt token err code
    key=$(host_bot_field "$BOT" key_path)
    jwt=$(host_github_app_jwt "$(host_bot_field "$BOT" app_id)" "$key")
    err=$(host_mktemp)
    local out
    out=$(host_mktemp)
    host_require_bin gh
    set +e
    if [ -n "$GH_HOSTNAME" ]; then
      gh api --hostname "$GH_HOSTNAME" --method POST \
        -H "Authorization: Bearer ${jwt}" \
        -H "Accept: application/vnd.github+json" \
        "/app/installations/${inst}/access_tokens" >"$out" 2>"$err"
    else
      gh api --method POST \
        -H "Authorization: Bearer ${jwt}" \
        -H "Accept: application/vnd.github+json" \
        "/app/installations/${inst}/access_tokens" >"$out" 2>"$err"
    fi
    code=$?
    set -e
    if [ "$code" -ne 0 ]; then
      host_scrub_file "$err" "$jwt" >&2
      GH_STATUS=$(host_classify_gh "$err" "$code")
      exit "$GH_STATUS"
    fi
    token=$(jq -r '.token // empty' "$out")
    [ -n "$token" ] || host_die 3 "host did not return a token"
    printf '%s\n' "$token"
    return 0
  fi
  if host_dry; then
    host_emit EXEC "gh auth token"
    return 0
  fi
  host_require_bin gh
  local token err code
  err=$(host_mktemp)
  set +e
  token=$(gh auth token 2>"$err")
  code=$?
  set -e
  if [ "$code" -ne 0 ] || [ -z "$token" ]; then
    host_scrub_file "$err" >&2
    host_die 4 "auth failed"
  fi
  printf '%s\n' "$token"
}

cmd_purge() {
  local name text
  host_need_name
  name=$POS1
  text=$(host_support_text "$name")
  jq -nc --arg text "$text" '{text:$text, url:"https://support.github.com/contact"}'
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
  if host_dry; then
    host_emit DELETE "$(host_repo "$name")"
    return 0
  fi
  host_gh_ok DELETE "$(host_repo "$name")" >/dev/null
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
