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

try_host() {
  set +e
  os_host "$@" >/dev/null
  set -e
}

area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  try_host team-remove "$(os_team_area "$area")" "$GH"
  try_host revoke "$(os_area_repo "$SLUG" "$area")" "$GH"
done << EOF
$(os_areas_on_disk "$ROOT")
EOF
try_host team-remove company "$GH"
try_host revoke "$COMPANY_REPO" "$GH"
try_host revoke "$WS_REPO" "$GH"
try_host org-remove "$GH"

STILL=""
check_gone() {
  local repo=$1 out access rc
  set +e
  out=$(os_host user-access "$repo" "$GH")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    STILL="${STILL} ${repo}"
    return 1
  fi
  access=$(printf '%s' "$out" | jq -r '.access // "none"')
  if [ "$access" != "none" ]; then
    STILL="${STILL} ${repo}"
    return 1
  fi
  return 0
}

failed=0
check_gone "$COMPANY_REPO" || failed=1
area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  check_gone "$(os_area_repo "$SLUG" "$area")" || failed=1
done << EOF
$(os_areas_on_disk "$ROOT")
EOF
check_gone "$WS_REPO" || failed=1
if [ "$failed" -ne 0 ]; then
  printf 'revoke failed. Still has access:%s\n' "$STILL" >&2
  exit 3
fi
os_host archive-repo "$WS_REPO" >/dev/null

printf 'revoked: %s\n' "$PERSON"
printf 'archived: %s\n' "$WS_REPO"

ADMIN=$(os_admin_slug_from_pages "$ROOT" || true)
if [ "$ADMIN" = "$PERSON" ]; then
  ADMIN=$NEW_OWNER
fi
[ -n "$ADMIN" ] || ADMIN=$NEW_OWNER
branch="rules/${ADMIN}/offboard-${PERSON}"

os_with_git_token git -C "$ROOT" fetch origin
git -C "$ROOT" checkout -q -B "$branch" origin/main
PAGE=$(os_person_file "$ROOT" "$PERSON")
os_fm_set "$PAGE" left "$WHEN"

moved=0
bot=""
if [ -d "$ROOT/bots" ]; then
  for bot in "$ROOT"/bots/*/BOT.md; do
    [ -f "$bot" ] || continue
    owner=$(os_fm_get "$bot" owner 2>/dev/null || true)
    if [ "$owner" = "$PERSON" ]; then
      os_fm_set "$bot" owner "$NEW_OWNER"
      moved=1
    fi
  done
fi

os_git_commit "$ROOT" "Offboard: ${PERSON}"
os_with_git_token git -C "$ROOT" push --set-upstream origin "$branch"
pr=$(os_host open-pr "$COMPANY_REPO" --head "$branch" --base main --title "Offboard: ${PERSON}")
number=$(printf '%s' "$pr" | jq -r '.number // empty')

printf 'left: %s\n' "$WHEN"
if [ "$moved" -eq 1 ]; then
  printf 'bot-owner: %s\n' "$NEW_OWNER"
else
  printf 'bot-owner: none\n'
fi
if [ -n "$number" ]; then
  printf 'pr: %s\n' "$number"
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
