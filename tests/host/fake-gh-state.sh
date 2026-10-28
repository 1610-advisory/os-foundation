#!/bin/bash
# Test double for gh with state. Answers like GitHub for the create, auto-merge and whoami paths.
# FAKE_GH_DIR holds the log and state files. Never prints a real token.
set -euo pipefail

dir=${FAKE_GH_DIR:?}
printf '%s\n' "$*" >> "$dir/gh.log"
method=GET
path=""
include=0
merge=0
while [ $# -gt 0 ]; do
  case "$1" in
    --method) method=$2; shift 2 ;;
    --input) cat > /dev/null; shift 2 ;;
    --hostname|--repo|-H) shift 2 ;;
    -i) include=1; shift ;;
    pr) shift ;;
    merge) merge=1; shift ;;
    api) shift ;;
    /*|graphql) path=$1; shift ;;
    *) shift ;;
  esac
done

refuse() {
  printf 'gh: %s (HTTP %s)\n' "$2" "$1" >&2
  exit 1
}

if [ "$merge" -eq 1 ]; then
  if [ -f "$dir/auto-merge-off" ] && [ ! -f "$dir/allowed" ]; then
    printf '%s\n' "GraphQL: Auto merge is not allowed for this repository (enablePullRequestAutoMerge)" >&2
    exit 1
  fi
  exit 0
fi

if [ "$include" -eq 1 ]; then
  printf 'HTTP/2.0 200 OK\r\n'
  if [ -f "$dir/scopes" ]; then
    printf 'X-Oauth-Scopes: %s\r\n' "$(cat "$dir/scopes")"
  fi
  printf 'Content-Type: application/json\r\n\r\n'
  printf '%s\n' '{"login":"ada"}'
  exit 0
fi

case "$method $path" in
  "POST /orgs/acme/teams")
    [ ! -f "$dir/team-exists" ] || refuse 422 "Validation Failed"
    [ ! -f "$dir/team-down" ] || refuse 500 "Server Error"
    touch "$dir/team-exists"
    printf '%s\n' '{"name":"writers","slug":"writers","id":7}'
    ;;
  "GET /orgs/acme/teams/writers")
    printf '%s\n' '{"name":"writers","slug":"writers","id":7}'
    ;;
  "POST /orgs/acme/repos")
    [ ! -f "$dir/repo-exists" ] || refuse 422 "Repository creation failed."
    touch "$dir/repo-exists"
    printf '%s\n' '{"name":"acme-os","full_name":"acme/acme-os","clone_url":"https://github.com/acme/acme-os.git","private":true}'
    ;;
  "GET /repos/acme/acme-os")
    printf '%s\n' '{"name":"acme-os","full_name":"acme/acme-os","clone_url":"https://github.com/acme/acme-os.git","private":true}'
    ;;
  "PATCH /repos/acme/acme-os")
    [ ! -f "$dir/patch-denied" ] || refuse 403 "Must have admin rights to Repository."
    touch "$dir/allowed"
    printf '%s\n' '{"allow_auto_merge":true}'
    ;;
  "GET /orgs/acme")
    # Only an org owner sees .plan. No plan file: the answer has no plan.
    if [ -f "$dir/plan" ]; then
      jq -nc --arg plan "$(cat "$dir/plan")" '{login:"acme", plan:{name:$plan}}'
    else
      printf '%s\n' '{"login":"acme"}'
    fi
    ;;
  "GET /repos/acme/acme-os/rulesets?per_page=100&page=1")
    [ ! -f "$dir/rulesets-free" ] || refuse 403 "Upgrade to GitHub Pro or make this repository public to enable this feature."
    printf '%s\n' '[]'
    ;;
  "POST /repos/acme/acme-os/rulesets")
    printf '%s\n' '{"id":1}'
    ;;
  "DELETE /repos/acme/acme-os/branches/main/protection")
    refuse 404 "Branch not protected"
    ;;
  "GET /repos/acme/acme-os/pulls/4")
    printf '%s\n' '{"state":"open","merged":false,"head":{"sha":"abc123"}}'
    ;;
  "GET /repos/acme/acme-os/pulls/4/reviews?per_page=100&page=1")
    printf '%s\n' '[]'
    ;;
  "POST graphql")
    [ ! -f "$dir/graphql-down" ] || refuse 502 "Bad Gateway"
    printf '%s\n' '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[{"__typename":"CheckRun","name":"checks","conclusion":"SUCCESS","status":"COMPLETED"},{"__typename":"CheckRun","name":"slow","conclusion":null,"status":"IN_PROGRESS"},{"__typename":"StatusContext","context":"model-review","state":"PENDING"}]}}}}]}}}}}'
    ;;
  "GET /repos/acme/acme-os/commits/abc123/check-runs?per_page=100&page=1")
    # Fine-grained tokens get 403 here. A gh sign-in can read it.
    [ -f "$dir/rest-checks-ok" ] || refuse 403 "Resource not accessible by personal access token"
    printf '%s\n' '{"total_count":1,"check_runs":[{"name":"checks","conclusion":"failure","status":"completed"}]}'
    ;;
  "GET /repos/acme/acme-os/commits/abc123/status?per_page=100&page=1")
    printf '%s\n' '{"statuses":[]}'
    ;;
  *)
    printf '%s\n' "unexpected gh call" >&2
    exit 1
    ;;
esac
