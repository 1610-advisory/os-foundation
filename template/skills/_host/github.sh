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

# Make <name> or read it when it exists. A second run must not fail.
# GitHub answers 422 when the name is taken. Print the new or the existing body.
host_gh_create() {
  local create=$1 read=$2 body=$3 errf out rc
  errf=$(host_mktemp)
  set +e
  out=$(host_gh_call POST "$create" "$body" 2>"$errf")
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    rm -f "$errf"
    printf '%s' "$out"
    return 0
  fi
  if grep -q 'HTTP 422' "$errf"; then
    rm -f "$errf"
    host_gh_ok GET "$read"
    return 0
  fi
  cat "$errf" >&2
  rm -f "$errf"
  exit "$rc"
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

host_checks_json() {
  host_check_lines "checks" | jq -R . | jq -s 'map(select(length > 0)) | map({context:.})'
}

host_main_ruleset_body() {
  local checks_json
  host_require_bin jq
  checks_json=$(host_checks_json)
  jq -n \
    --argjson approvals "$APPROVALS" \
    --argjson checks "$checks_json" \
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
            require_code_owner_review: false,
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

host_rules_review_body() {
  host_require_bin jq
  jq -n '{
    name: "rules-review",
    target: "branch",
    enforcement: "active",
    bypass_actors: [
      {actor_type: "OrganizationAdmin", bypass_mode: "pull_request"}
    ],
    conditions: {ref_name: {include: ["refs/heads/main"], exclude: []}},
    rules: [
      {
        type: "pull_request",
        parameters: {
          dismiss_stale_reviews_on_push: false,
          require_code_owner_review: true,
          require_last_push_approval: false,
          required_approving_review_count: 0,
          required_review_thread_resolution: false
        }
      }
    ]
  }'
}

host_gh_all() {
  local path=$1
  local page=1 all='[]' chunk n sep
  while true; do
    sep='?'
    case "$path" in
      *'?'*) sep='&' ;;
    esac
    # set -e does not reach into $( ). Stop here, or a failed page loops forever.
    chunk=$(host_gh_ok GET "${path}${sep}per_page=100&page=${page}") || exit $?
    n=$(printf '%s' "$chunk" | jq 'if type == "array" then length else 0 end')
    all=$(jq -n --argjson a "$all" --argjson b "$chunk" 'if ($b|type) == "array" then $a + $b else $a end')
    if [ "$n" -lt 100 ]; then
      break
    fi
    page=$((page + 1))
  done
  printf '%s' "$all"
}

host_gh_keyed() {
  local path=$1 key=$2
  local page=1 all='[]' chunk n sep
  while true; do
    sep='?'
    case "$path" in
      *'?'*) sep='&' ;;
    esac
    # set -e does not reach into $( ). Stop here, or a failed page loops forever.
    chunk=$(host_gh_ok GET "${path}${sep}per_page=100&page=${page}") || exit $?
    n=$(printf '%s' "$chunk" | jq --arg k "$key" '.[$k] | length')
    all=$(jq -n --argjson a "$all" --argjson b "$chunk" --arg k "$key" '$a + ($b[$k] // [])')
    if [ "$n" -lt 100 ]; then
      break
    fi
    page=$((page + 1))
  done
  printf '%s' "$all"
}

# A Free org answers a ruleset call on a private repo with 403 "Upgrade to GitHub Pro".
host_ruleset_call() {
  local errf rc out
  errf=$(host_mktemp)
  set +e
  out=$("$@" 2>"$errf")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    if grep -qi 'upgrade to github' "$errf"; then
      rm -f "$errf"
      host_free_plan
    fi
    cat "$errf" >&2
    rm -f "$errf"
    exit "$rc"
  fi
  rm -f "$errf"
  printf '%s' "$out"
}

host_upsert_ruleset() {
  local repo_name=$1 ruleset_name=$2 body=$3
  local list existing
  if host_dry; then
    host_emit POST "$(host_repo "$repo_name")/rulesets" "$body"
    return 0
  fi
  list=$(host_ruleset_call host_gh_all "$(host_repo "$repo_name")/rulesets") || exit $?
  existing=$(printf '%s' "$list" | jq -r --arg name "$ruleset_name" '.[] | select(.name==$name) | .id' | head -n 1)
  if [ -n "$existing" ]; then
    host_ruleset_call host_gh_ok PUT "$(host_repo "$repo_name")/rulesets/${existing}" "$body" >/dev/null
  else
    host_ruleset_call host_gh_ok POST "$(host_repo "$repo_name")/rulesets" "$body" >/dev/null
  fi
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
  local out err code body login scopes
  host_require_bin gh
  out=$(host_mktemp)
  err=$(host_mktemp)
  set +e
  if [ -n "$GH_HOSTNAME" ]; then
    gh api --hostname "$GH_HOSTNAME" -i "/user" >"$out" 2>"$err"
  else
    gh api -i "/user" >"$out" 2>"$err"
  fi
  code=$?
  set -e
  if [ "$code" -ne 0 ]; then
    GH_STATUS=$(host_classify_gh "$err" "$code")
    host_scrub_file "$err" >&2
    exit "$GH_STATUS"
  fi
  # -i prints the headers, a blank line, then the body.
  body=$(tr -d '\r' < "$out" | awk 'b { print } /^$/ { b = 1 }')
  login=$(printf '%s' "$body" | jq -r '.login // empty')
  [ -n "$login" ] || host_die 3 "host did not return a login"
  # gh sign-in: X-OAuth-Scopes lists the scopes. A fine-grained token sends none: scopes is null.
  scopes=$(tr -d '\r' < "$out" | awk 'b { exit } /^$/ { b = 1 } { print }' \
    | sed -n 's/^[Xx]-[Oo][Aa][Uu][Tt][Hh]-[Ss][Cc][Oo][Pp][Ee][Ss]:[[:space:]]*//p' | head -n 1)
  if tr -d '\r' < "$out" | awk 'b { exit } /^$/ { b = 1 } { print }' | grep -qi '^x-oauth-scopes:'; then
    jq -nc --arg login "$login" --arg s "$scopes" \
      '{login:$login, scopes:($s | split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0)))}'
  else
    jq -nc --arg login "$login" '{login:$login, scopes:null}'
  fi
}

# Auto-merge must be on, or the standing pull request never merges by itself.
# A failure is one plain line. The caller goes on.
host_allow_auto_merge() {
  local name=$1 body
  body=$(jq -nc '{allow_auto_merge:true}')
  if host_dry; then
    host_emit PATCH "$(host_repo "$name")" "$body"
    return 0
  fi
  if ! host_gh_call PATCH "$(host_repo "$name")" "$body" >/dev/null 2>&1; then
    printf '%s\n' "could not turn on auto-merge for ${name}: sign in as an org owner, then run skills/_host/host.sh protect ${name}" >&2
    return 1
  fi
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
    host_allow_auto_merge "$name"
    if [ -n "$SOURCE" ] && [ "$PUSH" = "1" ]; then
      host_push_source "$SOURCE" "$(host_clone_url "$name")"
    fi
    return 0
  fi
  result=$(host_gh_create "/orgs/${OS_ORG}/repos" "$(host_repo "$name")" "$body")
  host_allow_auto_merge "$name" || true
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

# Rulesets on a private repo need a paid plan. A Free org gets 403 on every one.
host_free_plan() {
  host_die 3 "This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again."
}

# Only an org owner sees .plan. Team setup needs an org owner anyway, so a hidden plan
# stops here too, before any write.
host_plan_name() {
  local body plan
  body=$(host_gh_ok GET "/orgs/${OS_ORG}") || exit $?
  plan=$(printf '%s' "$body" | jq -r '.plan.name // empty')
  [ "$plan" != "free" ] || host_free_plan
  [ -n "$plan" ] || host_die 3 "Could not read the plan of the GitHub org ${OS_ORG}: sign in as an org owner, then run this again. Team setup needs an org owner."
  printf '%s' "$plan"
}

cmd_plan_check() {
  local plan
  [ -z "$POS1" ] || host_die 1 "too many arguments"
  if host_dry; then
    host_emit GET "/orgs/${OS_ORG}"
    return 0
  fi
  plan=$(host_plan_name) || exit $?
  jq -nc --arg plan "$plan" '{plan: $plan}'
}

cmd_protect() {
  local name main_body review_body
  host_need_name
  name=$POS1
  main_body=$(host_main_ruleset_body)
  review_body=$(host_rules_review_body)
  # Before any write: a Free org stops here with one line.
  if host_dry; then
    host_emit GET "/orgs/${OS_ORG}"
  else
    host_plan_name >/dev/null
  fi
  host_upsert_ruleset "$name" main "$main_body"
  host_upsert_ruleset "$name" rules-review "$review_body"
  # Also covers a repo made before this setting (a v0 repo in upgrade).
  host_allow_auto_merge "$name" || true
  host_drop_classic "$name"
  if host_dry; then
    return 0
  fi
  jq -nc --arg name "$name" '{ok:true, name:$name, rulesets:["main","rules-review"]}'
}

# A v0 repo has a classic rule on main: one code-owner approval. The rulesets above
# replace it. They are already on, so main is never unprotected. 404: no classic rule.
host_drop_classic() {
  local name=$1 errf rc
  if host_dry; then
    host_emit DELETE "$(host_repo "$name")/branches/main/protection"
    return 0
  fi
  errf=$(host_mktemp)
  # host_gh_call turns set -e back on. The || keeps a 404 from ending the script.
  rc=0
  HOST_CLASSIC_DROPPED=0
  host_gh_call DELETE "$(host_repo "$name")/branches/main/protection" >/dev/null 2>"$errf" || rc=$?
  [ "$rc" -ne 0 ] || HOST_CLASSIC_DROPPED=1
  if [ "$rc" -ne 0 ] && ! grep -q 'HTTP 404' "$errf"; then
    cat "$errf" >&2
    rm -f "$errf"
    printf '%s\n' "could not remove the old classic rule on ${name} main: sign in as an org owner" >&2
    exit "$rc"
  fi
  rm -f "$errf"
}

host_ruleset_id() {
  local list=$1 ruleset=$2
  printf '%s' "$list" | jq -r --arg ruleset "$ruleset" '.[] | select(.name==$ruleset) | .id' | head -n 1
}

host_restore_ruleset() {
  local name=$1 file=$2 expect=$3 body resp id got
  [ -s "$file" ] || return 1
  body=$(jq 'del(.id, .node_id, .created_at, .updated_at, .source, .source_type, .current_user_can_bypass, ._links)' "$file")
  if ! resp=$(host_gh_call POST "$(host_repo "$name")/rulesets" "$body"); then
    return 1
  fi
  id=$(printf '%s' "$resp" | jq -r '.id // empty')
  [ -n "$id" ] || return 1
  if ! got=$(host_gh_call GET "$(host_repo "$name")/rulesets/${id}"); then
    return 1
  fi
  printf '%s' "$got" | jq -e --arg expect "$expect" '.name == $expect' >/dev/null
}

host_protection_off() {
  local name=$1
  host_die 3 "PROTECTION IS OFF on ${name}: run skills/_host/host.sh protect ${name} --code-owners --approvals 0"
}

# unprotect stopped part way. Main is open only if the classic rule is already gone.
host_unprotect_stop() {
  local name=$1
  if [ "${HOST_CLASSIC_DROPPED:-0}" -eq 1 ]; then
    host_protection_off "$name"
  fi
  exit 3
}

cmd_unprotect() {
  local name list id saved_main saved_review deleted_main deleted_review
  host_need_name
  name=$POS1
  if host_dry; then
    host_emit DELETE "$(host_repo "$name")/branches/main/protection"
    host_emit DELETE "$(host_repo "$name")/rulesets/main"
    host_emit DELETE "$(host_repo "$name")/rulesets/rules-review"
    return 0
  fi
  # A v0 repo has a classic rule on main too. It would refuse the push that follows.
  # It goes first: if that fails, nothing is lifted. protect puts the v1 rulesets in its place.
  host_drop_classic "$name"
  # From here, a failure with the classic rule gone leaves main open: say so plainly.
  list=$(host_gh_all "$(host_repo "$name")/rulesets") || host_unprotect_stop "$name"
  saved_main=$(host_mktemp)
  saved_review=$(host_mktemp)
  deleted_main=0
  deleted_review=0
  id=$(host_ruleset_id "$list" main)
  if [ -n "$id" ]; then
    host_gh_call GET "$(host_repo "$name")/rulesets/${id}" > "$saved_main" || host_unprotect_stop "$name"
  fi
  id=$(host_ruleset_id "$list" rules-review)
  if [ -n "$id" ]; then
    host_gh_call GET "$(host_repo "$name")/rulesets/${id}" > "$saved_review" || host_unprotect_stop "$name"
  fi
  id=$(host_ruleset_id "$list" main)
  if [ -n "$id" ]; then
    if host_gh_call DELETE "$(host_repo "$name")/rulesets/${id}" >/dev/null; then
      deleted_main=1
    else
      host_unprotect_stop "$name"
    fi
  fi
  id=$(host_ruleset_id "$list" rules-review)
  if [ -n "$id" ]; then
    if host_gh_call DELETE "$(host_repo "$name")/rulesets/${id}" >/dev/null; then
      deleted_review=1
    else
      if [ "$deleted_main" -eq 1 ] && ! host_restore_ruleset "$name" "$saved_main" main; then
        host_protection_off "$name"
      fi
      if [ "$deleted_review" -eq 1 ] && ! host_restore_ruleset "$name" "$saved_review" rules-review; then
        host_protection_off "$name"
      fi
      exit 3
    fi
  fi
  jq -nc --arg name "$name" '{ok:true, name:$name}'
}

cmd_user_access() {
  local name user out err code perm access kind invites
  [ -n "$POS1" ] || host_die 1 "name is required"
  [ -n "$POS2" ] || host_die 1 "user is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_name "name" "$POS1"
  host_require_name "user" "$POS2"
  host_require_org
  host_require_bin gh
  name=$POS1
  user=$POS2
  if host_dry; then
    host_emit GET "$(host_repo "$name")/collaborators/${user}/permission"
    return 0
  fi
  out=$(host_mktemp)
  err=$(host_mktemp)
  set +e
  if [ -n "$GH_HOSTNAME" ]; then
    gh api --hostname "$GH_HOSTNAME" --method GET "$(host_repo "$name")/collaborators/${user}/permission" >"$out" 2>"$err"
  else
    gh api --method GET "$(host_repo "$name")/collaborators/${user}/permission" >"$out" 2>"$err"
  fi
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    perm=$(jq -r '.permission // .role_name // "none"' "$out")
    case "$perm" in
      admin|owner) access="admin" ;;
      write|maintain|push) access="write" ;;
      read|pull|triage) access="read" ;;
      *) access="none" ;;
    esac
  elif grep -q 'HTTP 404' "$err"; then
    access="none"
  elif grep -q 'HTTP 403' "$err"; then
    host_scrub_file "$err" >&2
    host_die 4 "cannot read collaborators: sign in as an org owner"
  else
    kind=$(host_classify_gh "$err" "$code")
    host_scrub_file "$err" >&2
    exit "$kind"
  fi
  # A pending invite is access: the person gets it the moment they accept.
  # A failed invite list is not "no invite": exit with its status.
  if [ "$access" = "none" ]; then
    invites=$(host_user_invites "$user" "$name") || exit $?
    if [ "$(printf '%s' "$invites" | jq 'length')" -gt 0 ]; then
      access="invited"
    fi
  fi
  jq -nc --arg access "$access" '{access:$access}'
}

cmd_secret_exists() {
  local name out err code
  [ -n "$POS1" ] || host_die 1 "secret name is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_org
  host_require_bin gh
  case "$POS1" in
    *[!A-Za-z0-9_]*) host_die 1 "secret name has invalid characters" ;;
  esac
  name=$POS1
  if host_dry; then
    host_emit GET "/orgs/${OS_ORG}/actions/secrets/${name}"
    return 0
  fi
  out=$(host_mktemp)
  err=$(host_mktemp)
  set +e
  if [ -n "$GH_HOSTNAME" ]; then
    gh api --hostname "$GH_HOSTNAME" --method GET "/orgs/${OS_ORG}/actions/secrets/${name}" >"$out" 2>"$err"
  else
    gh api --method GET "/orgs/${OS_ORG}/actions/secrets/${name}" >"$out" 2>"$err"
  fi
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    jq -nc '{exists:true}'
    return 0
  fi
  if grep -q 'HTTP 404' "$err"; then
    jq -nc '{exists:false}'
    return 0
  fi
  if grep -q 'HTTP 403' "$err"; then
    host_scrub_file "$err" >&2
    host_die 4 "cannot read org secrets: sign in as an org owner"
  fi
  host_scrub_file "$err" >&2
  host_die 3 "host error"
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
  # An existing team is ok, like on Forgejo.
  host_gh_create "/orgs/${OS_ORG}/teams" "/orgs/${OS_ORG}/teams/$(host_slugify "$team")" "$body" \
    | jq -c '{name:.name, slug:.slug, id:.id}'
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

# Org membership of <user>: active, pending (an invite), or none. Any error exits non-zero.
cmd_org_membership() {
  local user errf rc out
  [ -n "$POS1" ] || host_die 1 "user is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_name "user" "$POS1"
  host_require_org
  user=$POS1
  if host_dry; then
    host_emit GET "/orgs/${OS_ORG}/memberships/${user}"
    return 0
  fi
  errf=$(host_mktemp)
  set +e
  out=$(host_gh_call GET "/orgs/${OS_ORG}/memberships/${user}" 2>"$errf")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    if grep -q 'HTTP 404' "$errf"; then
      jq -nc --arg user "$user" '{user:$user, state:"none"}'
      return 0
    fi
    cat "$errf" >&2
    exit "$rc"
  fi
  printf '%s' "$out" | jq -c --arg user "$user" '{user:$user, state:(.state // "unknown"), role:(.role // "")}'
}

# The repos a team grants. A missing team: exists false, no repos.
cmd_team_repos() {
  local team slug errf rc all
  [ -n "$POS1" ] || host_die 1 "team is required"
  [ -z "$POS2" ] || host_die 1 "too many arguments"
  host_require_team "$POS1"
  host_require_org
  team=$POS1
  slug=$(host_slugify "$team")
  if host_dry; then
    host_emit GET "/orgs/${OS_ORG}/teams/${slug}/repos"
    return 0
  fi
  errf=$(host_mktemp)
  # host_gh_call turns set -e back on. The || keeps its failure from exiting here.
  rc=0
  host_gh_call GET "/orgs/${OS_ORG}/teams/${slug}" >/dev/null 2>"$errf" || rc=$?
  if [ "$rc" -ne 0 ]; then
    if grep -q 'HTTP 404' "$errf"; then
      jq -nc --arg team "$team" '{team:$team, exists:false, repos:[]}'
      return 0
    fi
    cat "$errf" >&2
    exit "$rc"
  fi
  all=$(host_gh_all "/orgs/${OS_ORG}/teams/${slug}/repos") || exit $?
  printf '%s' "$all" | jq -c --arg team "$team" '{team:$team, exists:true, repos:[.[].name]}'
}

# The invite list of the org, or of one repo. Unscoped: org.
host_invites_path() {
  if [ -n "$1" ]; then
    printf '%s/invitations' "$(host_repo "$1")"
  else
    printf '/orgs/%s/invitations' "$OS_ORG"
  fi
}

# Pending invites for <user>: [{id, permission}]. An org invite has the login
# at the top. A repo invite has it under invitee.
host_user_invites() {
  local user=$1 repo=$2 all
  all=$(host_gh_all "$(host_invites_path "$repo")") || exit $?
  printf '%s' "$all" | jq -c --arg u "$user" '
    [ .[]
      | select(((.login // .invitee.login // "") | ascii_downcase) == ($u | ascii_downcase))
      | {id: .id, permission: (.permissions // .role // "")} ]'
}

host_need_invite_args() {
  [ -n "$POS1" ] || host_die 1 "user is required"
  [ -z "$POS3" ] || host_die 1 "too many arguments"
  host_require_name "user" "$POS1"
  if [ -n "$POS2" ]; then
    host_require_name "name" "$POS2"
  fi
  host_require_org
}

cmd_invites() {
  local list
  host_need_invite_args
  if host_dry; then
    host_emit GET "$(host_invites_path "$POS2")"
    return 0
  fi
  list=$(host_user_invites "$POS1" "$POS2") || exit $?
  jq -nc --argjson invites "$list" '{invites:$invites}'
}

# Every repo in the org, by name.
cmd_org_repos() {
  local all
  [ -z "$POS1" ] || host_die 1 "too many arguments"
  host_require_org
  if host_dry; then
    host_emit GET "/orgs/${OS_ORG}/repos"
    return 0
  fi
  all=$(host_gh_all "/orgs/${OS_ORG}/repos") || exit $?
  printf '%s' "$all" | jq -c '{repos: [.[].name]}'
}

# Cancel every pending invite for <user>: the org's, or one repo's. 404 is gone already.
cmd_cancel_invites() {
  local list id n errf rc path
  host_need_invite_args
  path=$(host_invites_path "$POS2")
  if host_dry; then
    host_emit GET "$path"
    return 0
  fi
  list=$(host_user_invites "$POS1" "$POS2") || exit $?
  n=0
  for id in $(printf '%s' "$list" | jq -r '.[].id'); do
    host_require_int "invite id" "$id"
    errf=$(host_mktemp)
    # host_gh_call turns set -e back on. The || keeps its failure from exiting here.
    rc=0
    host_gh_call DELETE "${path}/${id}" >/dev/null 2>"$errf" || rc=$?
    if [ "$rc" -ne 0 ] && ! grep -q 'HTTP 404' "$errf"; then
      cat "$errf" >&2
      exit "$rc"
    fi
    n=$((n + 1))
  done
  jq -nc --arg user "$POS1" --argjson n "$n" '{ok:true, user:$user, cancelled:$n}'
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
    # No --body-file: keep the body it has (B40). A person may have written one.
    if [ -n "$BODY_FILE" ]; then
      patch=$(jq -nc --arg title "$TITLE" --arg body "$text" '{title:$title, body:$body}')
    else
      patch=$(jq -nc --arg title "$TITLE" '{title:$title}')
    fi
    existing=$(host_gh_ok PATCH "$(host_repo "$name")/pulls/${number}" "$patch")
  else
    existing=$(host_gh_ok POST "$(host_repo "$name")/pulls" "$body")
  fi
  printf '%s' "$existing" | jq -c '{number:.number, url:.html_url}'
}

# Open pull requests: number and head branch.
cmd_open_prs() {
  local all
  host_need_name
  if host_dry; then
    host_emit GET "$(host_repo "$POS1")/pulls?state=open"
    return 0
  fi
  all=$(host_gh_all "$(host_repo "$POS1")/pulls?state=open") || exit $?
  printf '%s' "$all" | jq -c '{prs: [.[] | {number:.number, head:.head.ref}]}'
}

cmd_close_pr() {
  local body
  host_need_number
  body=$(jq -nc '{state:"closed"}')
  if host_dry; then
    host_emit PATCH "$(host_repo "$POS1")/pulls/${POS2}" "$body"
    return 0
  fi
  host_gh_ok PATCH "$(host_repo "$POS1")/pulls/${POS2}" "$body" >/dev/null
  jq -nc --arg name "$POS1" --argjson number "$POS2" '{ok:true, name:$name, number:$number, closed:true}'
}

# Turn auto-merge off. A pull request with none is already off.
cmd_auto_merge_off() {
  local pr id q
  host_need_number
  if host_dry; then
    host_emit GET "$(host_repo "$POS1")/pulls/${POS2}"
    return 0
  fi
  pr=$(host_gh_ok GET "$(host_repo "$POS1")/pulls/${POS2}")
  if [ "$(printf '%s' "$pr" | jq -r '.auto_merge == null')" = "false" ]; then
    id=$(printf '%s' "$pr" | jq -r '.node_id // empty')
    [ -n "$id" ] || host_die 3 "pull request has no id"
    q=$(jq -nc --arg id "$id" \
      '{query:"mutation($id:ID!){disablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}", variables:{id:$id}}')
    host_gh_ok POST "graphql" "$q" >/dev/null
    # Check the outcome, not only the call: read it again.
    pr=$(host_gh_ok GET "$(host_repo "$POS1")/pulls/${POS2}")
    if [ "$(printf '%s' "$pr" | jq -r '.auto_merge == null')" = "false" ]; then
      host_die 3 "auto-merge is still on for pull request ${POS2}"
    fi
  fi
  jq -nc --arg name "$POS1" --argjson number "$POS2" '{ok:true, name:$name, number:$number, auto_merge:"off"}'
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
  local err code low
  err=$(host_mktemp)
  set +e
  if [ -n "$GH_HOSTNAME" ]; then
    gh pr merge "$number" --repo "${OS_ORG}/${name}" --auto --merge --hostname "$GH_HOSTNAME" >"$err" 2>&1
  else
    gh pr merge "$number" --repo "${OS_ORG}/${name}" --auto --merge >"$err" 2>&1
  fi
  code=$?
  set -e
  if [ "$code" -ne 0 ] && grep -qi 'auto merge is not allowed' "$err"; then
    # A repo made before v1 has auto-merge off. Turn it on, then try once more.
    if host_allow_auto_merge "$name"; then
      set +e
      if [ -n "$GH_HOSTNAME" ]; then
        gh pr merge "$number" --repo "${OS_ORG}/${name}" --auto --merge --hostname "$GH_HOSTNAME" >"$err" 2>&1
      else
        gh pr merge "$number" --repo "${OS_ORG}/${name}" --auto --merge >"$err" 2>&1
      fi
      code=$?
      set -e
    fi
  fi
  if [ "$code" -ne 0 ]; then
    low=$(tr '[:upper:]' '[:lower:]' < "$err")
    case "$low" in
      *"already enabled"*)
        rm -f "$err"
        jq -nc --arg name "$name" --argjson number "$number" \
          '{ok:true, name:$name, number:$number, auto_merge:"already"}'
        return 0
        ;;
      *"clean status"*)
        # The checks are already green, so GitHub will not wait for them (B45). Merge now.
        set +e
        if [ -n "$GH_HOSTNAME" ]; then
          gh pr merge "$number" --repo "${OS_ORG}/${name}" --merge --hostname "$GH_HOSTNAME" >"$err" 2>&1
        else
          gh pr merge "$number" --repo "${OS_ORG}/${name}" --merge >"$err" 2>&1
        fi
        code=$?
        set -e
        rm -f "$err"
        if [ "$code" -ne 0 ]; then
          host_die 3 "pull request ${number} is green: merge it"
        fi
        jq -nc --arg name "$name" --argjson number "$number" '{ok:true, name:$name, number:$number, merge:"merged"}'
        return 0
        ;;
    esac
    host_scrub_file "$err" >&2
    GH_STATUS=$(host_classify_gh "$err" "$code")
    exit "$GH_STATUS"
  fi
  rm -f "$err"
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
    host_emit POST "graphql" "$(host_rollup_body "$name" "$number")"
    return 0
  fi
  local pr sha reviews checks statuses rollup errf
  pr=$(host_gh_ok GET "$(host_repo "$name")/pulls/${number}")
  sha=$(printf '%s' "$pr" | jq -r '.head.sha // empty')
  [ -n "$sha" ] || host_die 3 "pull request has no head"
  reviews=$(host_gh_all "$(host_repo "$name")/pulls/${number}/reviews")
  # A fine-grained token can never read REST check-runs. The GraphQL rollup works
  # with one (Commit statuses and Actions read) and with a gh sign-in. REST is the fallback.
  errf=$(host_mktemp)
  if rollup=$(host_gh_call POST "graphql" "$(host_rollup_body "$name" "$number")" 2>"$errf"); then
    checks=$(printf '%s' "$rollup" | jq -c '
      [.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?
        | if .__typename == "CheckRun"
          then {name:.name, state:((.conclusion // .status) | ascii_downcase)}
          else {name:.context, state:(.state | ascii_downcase)} end]')
    statuses='[]'
  else
    checks=$(host_gh_keyed "$(host_repo "$name")/commits/${sha}/check-runs" check_runs \
      | jq -c '[.[] | {name:.name, state:(.conclusion // .status)}]')
    statuses=$(host_gh_keyed "$(host_repo "$name")/commits/${sha}/status" statuses \
      | jq -c '[.[] | {name:.context, state:.state}]')
  fi
  rm -f "$errf"
  jq -nc --argjson pr "$pr" --argjson reviews "$reviews" --argjson checks "$checks" --argjson statuses "$statuses" '
    {
      state: $pr.state,
      merged: $pr.merged,
      approved: ([$reviews[]?.state] | map(ascii_downcase) | index("approved") != null),
      checks: ($checks + $statuses)
    }'
}

host_rollup_body() {
  local name=$1 number=$2
  jq -nc --arg owner "$OS_ORG" --arg name "$name" --argjson number "$number" '{
    query: "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100){nodes{__typename ... on CheckRun{name conclusion status} ... on StatusContext{context state}}}}}}}}}}",
    variables: {owner:$owner, name:$name, number:$number}
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
    host_scrub_file "$err" "$secret_file" >&2
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
      GH_TOKEN="$jwt" gh api --hostname "$GH_HOSTNAME" --method POST \
        -H "Accept: application/vnd.github+json" \
        "/app/installations/${inst}/access_tokens" >"$out" 2>"$err"
    else
      GH_TOKEN="$jwt" gh api --method POST \
        -H "Accept: application/vnd.github+json" \
        "/app/installations/${inst}/access_tokens" >"$out" 2>"$err"
    fi
    code=$?
    set -e
    if [ "$code" -ne 0 ]; then
      jwt_file=$(host_mktemp)
      printf '%s' "$jwt" > "$jwt_file"
      host_scrub_file "$err" "$jwt_file" >&2
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
  plan-check) cmd_plan_check ;;
  create-repo) cmd_create_repo ;;
  repo-access) cmd_repo_access ;;
  protect) cmd_protect ;;
  unprotect) cmd_unprotect ;;
  secret-exists) cmd_secret_exists ;;
  user-access) cmd_user_access ;;
  team-create) cmd_team_create ;;
  team-add) cmd_team_add ;;
  team-remove) cmd_team_remove ;;
  team-repos) cmd_team_repos ;;
  org-repos) cmd_org_repos ;;
  grant) cmd_grant ;;
  revoke) cmd_revoke ;;
  org-remove) cmd_org_remove ;;
  org-membership) cmd_org_membership ;;
  invites) cmd_invites ;;
  cancel-invites) cmd_cancel_invites ;;
  archive-repo) cmd_archive ;;
  open-pr) cmd_open_pr ;;
  auto-merge) cmd_auto_merge ;;
  auto-merge-off) cmd_auto_merge_off ;;
  open-prs) cmd_open_prs ;;
  close-pr) cmd_close_pr ;;
  pr-status) cmd_pr_status ;;
  pr-comment) cmd_pr_comment ;;
  set-secret) cmd_set_secret ;;
  get-token) cmd_get_token ;;
  purge-request) cmd_purge ;;
  delete-repo) cmd_delete ;;
  *) host_die 1 "unknown verb: ${VERB}" ;;
esac
