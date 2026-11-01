#!/bin/bash
# Remove a teammate. Revoke first. File changes go by pull request. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-teammate/lib.sh"

usage() {
  cat << 'EOF'
usage: remove.sh --person <slug> [--new-bot-owner <slug>] [--root <dir>] [--date YYYY-MM-DD]

Revoke access first. Archive the workspace. Record left: by pull request.
PHI deletion is app level and is not in v1.
EOF
}

PERSON=""
NEW_OWNER=""
ROOT=""
WHEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --person)
      [ $# -ge 2 ] || os_die 1 "missing person"
      PERSON=$2
      shift 2
      ;;
    --new-bot-owner)
      [ $# -ge 2 ] || os_die 1 "missing new bot owner"
      NEW_OWNER=$2
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || os_die 1 "missing root"
      ROOT=$2
      shift 2
      ;;
    --date)
      [ $# -ge 2 ] || os_die 1 "missing date"
      WHEN=$2
      shift 2
      ;;
    *)
      os_die 1 "unknown argument: $1"
      ;;
  esac
done

[ -n "$PERSON" ] || os_die 1 "pass --person <slug>"
os_need git jq
[ -n "$ROOT" ] || ROOT=$(pwd)
[ -d "$ROOT" ] || os_die 2 "company folder is missing"
ROOT=$(cd "$ROOT" && pwd)
[ -f "$ROOT/company-profile.md" ] || os_die 2 "company-profile.md is missing"

WHEN=${WHEN:-$(os_today)}
SLUG=$(os_fm_get "$ROOT/company-profile.md" company_slug)
HOST_KIND=$(os_fm_get "$ROOT/company-profile.md" host)
HOST_URL=$(os_fm_get "$ROOT/company-profile.md" host_url || true)
ORG=$(os_fm_get "$ROOT/company-profile.md" org)

PAGE=$(os_person_file "$ROOT" "$PERSON" || true)
[ -n "$PAGE" ] || os_die 2 "no people page for $PERSON"
ROLE=$(os_fm_get "$PAGE" role || true)
LEFT=$(os_fm_get "$PAGE" left || true)
GH=$(os_fm_get "$PAGE" github)
if [ "$ROLE" = "admin" ] && [ -z "$LEFT" ]; then
  admins=$(os_count_admins "$ROOT")
  if [ "$admins" -le 1 ]; then
    os_die 2 "refusing to remove the last admin"
  fi
fi

if [ -z "$NEW_OWNER" ]; then
  NEW_OWNER=$(os_fm_get "$PAGE" manager 2>/dev/null || true)
fi
if [ -z "$NEW_OWNER" ]; then
  NEW_OWNER=$(os_admin_slug_from_pages "$ROOT" || true)
fi
[ -n "$NEW_OWNER" ] || os_die 2 "no new bot owner and no admin"
[ "$NEW_OWNER" != "$PERSON" ] || os_die 2 "new bot owner is the person leaving"

if ! OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
  os_die 3 "host.sh is missing"
fi
export OS_HOST_BIN OS_ORG="$ORG" OS_HOST="$HOST_KIND" OS_HOST_URL="$HOST_URL" OS_SLUG="$SLUG"
export OS_PROFILE="$ROOT/company-profile.md"

COMPANY_REPO=$(os_company_repo "$SLUG")
WS_REPO=$(os_user_repo "$SLUG" "$PERSON")

# A revoke step. Not found (404) is normal: already removed, or never accepted (B39).
# GitHub's text has "HTTP 404"; Forgejo's is only the line "not found or no access".
# Any other error shows. The checks after the revokes decide what is still there.
try_host() {
  local err rc
  err=$(mktemp)
  set +e
  os_host "$@" >/dev/null 2>"$err"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && ! { [ "$rc" -eq 2 ] && { grep -q 'HTTP 404' "$err" \
      || [ "$(cat "$err")" = "not found or no access" ]; }; }; then
    cat "$err" >&2
  fi
  rm -f "$err"
}

os_team_names "$SLUG"

STILL=""

# Every area the person may have: their page, plus the areas checked out here. An area
# on the host that is not checked out here still counts.
AREAS=$(
  {
    os_areas_on_disk "$ROOT"
    os_split_areas "$(os_fm_get "$PAGE" areas 2>/dev/null | tr -d '[]"' || true)"
  } | sort -u
)

# Every repo to clear: the company, each area, the workspace, and each repo the company
# team and the area teams grant. A team that cannot be read is not checked, never gone.
REPOS=""
add_repo() {
  case " ${REPOS} " in
    *" $1 "*) ;;
    *) REPOS="${REPOS} $1" ;;
  esac
}
team_repos() {
  local team=$1 out rc r
  set +e
  out=$(os_host team-repos "$team" 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    STILL="${STILL} team ${team} (not checked)"
    return 1
  fi
  for r in $(printf '%s' "$out" | jq -r '(.repos // [])[]'); do
    add_repo "$r"
  done
}

failed=0
add_repo "$COMPANY_REPO"
team_repos "$(os_team_company)" || failed=1
area=""
for area in $AREAS; do
  add_repo "$(os_area_repo "$SLUG" "$area")"
  team_repos "$(os_team_area "$area")" || failed=1
done
add_repo "$WS_REPO"
# A direct invite on any org repo counts too, such as an area no longer on the page.
org_repos() {
  local out rc r
  set +e
  out=$(os_host org-repos 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    STILL="${STILL} org repos (not checked)"
    return 1
  fi
  # Each repo gets a revoke and a check. That can take minutes, so say so first (B44).
  printf 'checking %s repos in the org...\n' "$(printf '%s' "$out" | jq -r '(.repos // []) | length')"
  for r in $(printf '%s' "$out" | jq -r '(.repos // [])[]'); do
    add_repo "$r"
  done
}
org_repos || failed=1

# The admin's private library repo has direct grants, not a team. When it exists, clear
# it like the others. An answer the host cannot give is not checked, never gone.
LIB_REPO="${SLUG}-library"
set +e
os_host repo-access "$LIB_REPO" >/dev/null 2>&1
rc=$?
set -e
case "$rc" in
  0) add_repo "$LIB_REPO" ;;
  2) ;;
  *)
    STILL="${STILL} ${LIB_REPO} (not checked)"
    failed=1
    ;;
esac

# A person who never accepted has pending invites, not membership. Cancel those too,
# or they get access the moment they accept.
for area in $AREAS; do
  try_host team-remove "$(os_team_area "$area")" "$GH"
done
try_host team-remove "$(os_team_company)" "$GH"
repo=""
for repo in $REPOS; do
  try_host revoke "$repo" "$GH"
  try_host cancel-invites "$GH" "$repo"
done
try_host cancel-invites "$GH"
try_host org-remove "$GH"

check_gone() {
  local repo=$1 out access rc
  set +e
  out=$(os_host user-access "$repo" "$GH")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    STILL="${STILL} ${repo} (not checked)"
    return 1
  fi
  access=$(printf '%s' "$out" | jq -r '.access // "none"')
  if [ "$access" != "none" ]; then
    STILL="${STILL} ${repo} (${access})"
    return 1
  fi
  return 0
}

# The org invite is checked after the fact too.
check_org_invite() {
  local out rc n
  set +e
  out=$(os_host invites "$GH")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    STILL="${STILL} org (not checked)"
    return 1
  fi
  n=$(printf '%s' "$out" | jq '.invites | length')
  if [ "$n" != "0" ]; then
    STILL="${STILL} org (invited)"
    return 1
  fi
  return 0
}

# Org membership is read again after the fact. Only none counts as gone.
check_org_member() {
  local out rc state
  set +e
  out=$(os_host org-membership "$GH")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    STILL="${STILL} org (not checked)"
    return 1
  fi
  state=$(printf '%s' "$out" | jq -r '.state // empty')
  if [ "$state" != "none" ]; then
    STILL="${STILL} org (${state:-not checked})"
    return 1
  fi
  return 0
}

# The host removes access a little after it says yes (B35: GitHub org membership read
# active for some seconds). Read again, up to 6 times 5 seconds apart. Only a read with
# no access left counts. A list that could not be read before this stays a failure.
before_failed=$failed
before_still=$STILL
tries=0
while :; do
  failed=$before_failed
  STILL=$before_still
  check_org_invite || failed=1
  check_org_member || failed=1
  for repo in $REPOS; do
    check_gone "$repo" || failed=1
  done
  tries=$((tries + 1))
  if [ "$failed" -eq "$before_failed" ] || [ "$tries" -ge 6 ]; then
    break
  fi
  sleep "${OS_RECHECK_WAIT:-5}"
done
if [ "$failed" -ne 0 ]; then
  printf 'revoke failed. Still has access:%s\n' "$STILL" >&2
  exit 3
fi
os_host archive-repo "$WS_REPO" >/dev/null

printf 'revoked: %s\n' "$PERSON"
printf 'archived: %s\n' "$WS_REPO"

# A pull request that adds this person would stay open and conflict forever (B37).
# Close it on the company repo and each area on the page.
for repo in "$COMPANY_REPO" $(for area in $AREAS; do os_area_repo "$SLUG" "$area"; printf '\n'; done); do
  if ! prs=$(os_host_try open-prs "$repo" 2>/dev/null); then
    printf 'could not list pull requests on %s: close any rules/*/add-%s pull request by hand\n' "$repo" "$PERSON"
    continue
  fi
  printf '%s' "$prs" | jq -r '(.prs // [])[] | "\(.number) \(.head)"' | while read -r n head; do
    case "$head" in
      rules/*/add-"$PERSON")
        if os_host_try close-pr "$repo" "$n" >/dev/null 2>&1; then
          printf 'closed: %s %s (it added %s)\n' "$repo" "$n" "$PERSON"
        else
          printf 'could not close %s %s: close it by hand\n' "$repo" "$n"
        fi
        ;;
    esac
  done
done

# The person's sync branches: one per computer (sync/<person>/<seat>), and sync/<person>
# from older code. Deleting a branch closes its pull request. Work not merged by now
# stays in the person's archived workspace and on their computer, not in the company.
for dir in "$ROOT" $(for area in $AREAS; do printf '%s\n' "$ROOT/areas/${area}"; done); do
  [ -e "$dir/.git" ] || continue
  rel=${dir#"$ROOT"}
  rel=${rel#/}
  if ! refs=$(os_with_git_token git -C "$dir" ls-remote --heads origin 2>/dev/null); then
    printf 'could not list branches in %s: delete sync/%s/* by hand\n' "${rel:-company}" "$PERSON"
    continue
  fi
  printf '%s\n' "$refs" | awk -v p="refs/heads/sync/${PERSON}" '$2 == p || index($2, p "/") == 1 { print $2 }' \
    | while IFS= read -r ref; do
      if os_with_git_token git -C "$dir" push -q origin ":${ref}" 2>/dev/null; then
        printf 'deleted: %s %s\n' "${rel:-company}" "${ref#refs/heads/}"
      else
        printf 'could not delete %s in %s: delete it by hand\n' "${ref#refs/heads/}" "${rel:-company}"
      fi
    done
done

# Take the person off every CODEOWNERS line in a worktree on origin/main. Returns 1 when
# they are on none (nothing to change).
offboard_owners() {
  local dir=$1 f hit=1
  [ -n "$GH" ] || return 1
  for f in .github/CODEOWNERS .gitea/CODEOWNERS; do
    [ -f "$dir/$f" ] || continue
    os_owner_names "$dir/$f" | grep -Fxq -- "$(printf '%s' "@$GH" | tr '[:upper:]' '[:lower:]')" || continue
    os_owner_drop "$dir/$f" "$GH" "$ADMIN_GH"
    hit=0
  done
  return "$hit"
}

# What the offboard pull request changes, and why.
offboard_body() {
  local dir=$1 bots=$2 owners=$3
  if [ "$owners" -eq 1 ]; then
    os_owners_body "$dir" "Offboard: ${PERSON} left on ${WHEN}. ${PERSON} (@${GH}) stops being a code owner; a line they owned alone now names the admin." "$ADMIN_GH"
  else
    printf 'Offboard: %s left on %s.\n' "$PERSON" "$WHEN"
  fi
  if [ -d "$dir/people" ] && [ -n "$(os_person_file "$dir" "$PERSON" 2>/dev/null || true)" ]; then
    printf '%s\n' "people: ${PERSON}'s page gets left: ${WHEN}."
  fi
  [ "$bots" -eq 0 ] || printf '%s\n' "bots: each bot ${PERSON} owned now has owner: ${NEW_OWNER}."
}

# How one offboard pull request merges. One that changes rules files (bots/, CODEOWNERS)
# is the admin's own: on GitHub the admin merges it by hand. Anything else merges by itself.
offboard_merge_line() {
  local repo=$1 number=$2 what=$3 will
  if [ -n "$what" ] && [ "$HOST_KIND" = "github" ]; then
    # An earlier run on the same branch may have turned auto-merge on: turn it off (B38).
    # Say "will not merge by itself" only when that is true.
    if os_host_try auto-merge-off "$repo" "$number" >/dev/null 2>&1; then
      will='so it will not merge by itself.'
    else
      will='but auto-merge may still be on, so it may merge by itself: open it and click "Disable auto-merge" first.'
    fi
    printf 'merge-by-hand: %s %s: it changes %s, %s When lint and the secret scan pass and the model review passes (or the admin overrides it, see the override: line), open the pull request and merge it. When the admin is the only code owner, a plain merge works. %s\n' \
      "$repo" "$number" "$what" "$will" 'If GitHub asks for a review, tick "Merge without waiting for requirements to be met (bypass rules)" and click "Bypass rules and merge".'
  elif os_host_try auto-merge "$repo" "$number" >/dev/null; then
    # Like propose: the pull request merges by itself when its checks pass.
    printf '%s\n' "auto-merge: on"
  else
    printf 'auto-merge is off on %s: pull request %s stays open until someone merges it. Ask the admin to run skills/_host/host.sh protect %s --code-owners --approvals 0\n' \
      "$repo" "$number" "$repo"
  fi
  os_override_line "$repo" "$number" "remove: offboard ${PERSON} as the body says"
}

ADMIN=$(os_admin_slug_from_pages "$ROOT" || true)
if [ "$ADMIN" = "$PERSON" ]; then
  ADMIN=$NEW_OWNER
fi
[ -n "$ADMIN" ] || ADMIN=$NEW_OWNER
branch="rules/${ADMIN}/offboard-${PERSON}"

os_with_git_token git -C "$ROOT" fetch origin
wt=$(os_branch_start "$ROOT") || exit 3
PAGE=$(os_person_file "$wt" "$PERSON")
os_fm_set "$PAGE" left "$WHEN"

moved=0
bot=""
paths=("$PAGE")
if [ -d "$wt/bots" ]; then
  for bot in "$wt"/bots/*/BOT.md; do
    [ -f "$bot" ] || continue
    owner=$(os_fm_get "$bot" owner 2>/dev/null || true)
    if [ "$owner" = "$PERSON" ]; then
      os_fm_set "$bot" owner "$NEW_OWNER"
      paths+=("$bot")
      moved=1
    fi
  done
fi

# The person stops being a code owner (R6). A line they owned alone names the admin.
ADMIN_GH=""
admin_page=$(os_person_file "$ROOT" "$ADMIN" 2>/dev/null || true)
[ -z "$admin_page" ] || ADMIN_GH=$(os_fm_get "$admin_page" github 2>/dev/null || true)
owners=0
if offboard_owners "$wt"; then
  owners=1
  for f in .github/CODEOWNERS .gitea/CODEOWNERS; do
    [ ! -f "$wt/$f" ] || paths+=("$wt/$f")
  done
fi

os_git_commit "$wt" "Offboard: ${PERSON}" "${paths[@]}"
body=$(mktemp)
offboard_body "$wt" "$moved" "$owners" > "$body"
os_branch_push "$ROOT" "$wt" "$branch"
# The change is on the host. Leave the admin's folder on main, so pull fast-forwards.
os_back_to_main "$ROOT"
pr=$(os_host open-pr "$COMPANY_REPO" --head "$branch" --base main --title "Offboard: ${PERSON}" --body-file "$body")
rm -f "$body"
number=$(printf '%s' "$pr" | jq -r '.number // empty')

printf 'left: %s\n' "$WHEN"
if [ "$moved" -eq 1 ]; then
  printf 'bot-owner: %s\n' "$NEW_OWNER"
else
  printf 'bot-owner: none\n'
fi
if [ -n "$number" ]; then
  printf 'pr: %s\n' "$number"
  what=""
  [ "$moved" -eq 0 ] || what="bots/"
  [ "$owners" -eq 0 ] || what="${what:+${what} and }CODEOWNERS"
  offboard_merge_line "$COMPANY_REPO" "$number" "$what"
fi

# Each area repo where the person is a code owner: its own rules pull request (R6).
if [ -n "$GH" ]; then
  for area in $AREAS; do
    adir="$ROOT/areas/$area"
    [ -e "$adir/.git" ] || continue
    os_with_git_token git -C "$adir" fetch origin || continue
    awt=$(os_branch_start "$adir") || continue
    if ! offboard_owners "$awt"; then
      git -C "$adir" worktree remove --force "$awt" >/dev/null 2>&1 || true
      rm -rf "$(dirname "$awt")"
      continue
    fi
    apaths=()
    for f in .github/CODEOWNERS .gitea/CODEOWNERS; do
      [ ! -f "$awt/$f" ] || apaths+=("$f")
    done
    os_git_commit "$awt" "Offboard: ${PERSON}" "${apaths[@]}"
    body=$(mktemp)
    offboard_body "$awt" 0 1 > "$body"
    os_branch_push "$adir" "$awt" "$branch"
    os_back_to_main "$adir"
    arepo=$(os_area_repo "$SLUG" "$area")
    pr=$(os_host open-pr "$arepo" --head "$branch" --base main --title "Offboard: ${PERSON}" --body-file "$body")
    rm -f "$body"
    anum=$(printf '%s' "$pr" | jq -r '.number // empty')
    if [ -z "$anum" ]; then
      printf 'could not open the offboard pull request for %s: run remove again\n' "$arepo" >&2
      continue
    fi
    printf 'rules-pr: %s %s (%s)\n' "$arepo" "$anum" "${apaths[*]}"
    offboard_merge_line "$arepo" "$anum" CODEOWNERS
  done
fi
printf '%s\n' "phi: app-level-not-in-v1"

if [ -f "$ROOT/architecture.md" ]; then
  awk '
    BEGIN { on = 0 }
    /^#+[ ]+Connections[ ]*$/ { on = 1; next }
    on && /^#+[ ]/ { exit }
    on && /^- / {
      sub(/^- /, "")
      print
      next
    }
    on && /^\|/ && $0 !~ /^\|[[:space:]:|-]+\|/ {
      line = $0
      gsub(/^\|[[:space:]]*/, "", line)
      gsub(/[[:space:]]*\|$/, "", line)
      gsub(/[[:space:]]*\|[[:space:]]*/, " ", line)
      if (line != "" && line !~ /^Tool / && line !~ /^What /) print line
    }
  ' "$ROOT/architecture.md" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf 'seat: %s\n' "$line"
  done
else
  printf '%s\n' "seat: none listed"
fi

printf '%s\n' "remove: ok"
