#!/bin/bash
# Add one person to a team that is already on. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"

usage() {
  cat << 'EOF'
usage: add-person.sh --answers <file>

Add one person. The team must already be on. The people page goes by pull request.
See CLI.md.
EOF
}

ANSWERS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --answers)
      [ $# -ge 2 ] || os_die 1 "missing answers file"
      ANSWERS=$2
      shift 2
      ;;
    *)
      os_die 1 "unknown argument: $1"
      ;;
  esac
done

[ -n "$ANSWERS" ] || os_die 1 "pass --answers <file>"
[ -f "$ANSWERS" ] || os_die 1 "answers file is missing"
os_need git jq

ROOT=$(os_answer_or root "$ANSWERS" "$(pwd)")
[ -d "$ROOT" ] || os_die 2 "company folder is missing"
ROOT=$(cd "$ROOT" && pwd)
os_refuse_synced "$ROOT"
[ -f "$ROOT/company-profile.md" ] || os_die 2 "company-profile.md is missing"

LEVEL=$(os_fm_get "$ROOT/company-profile.md" level || true)
[ "$LEVEL" = "team" ] || [ "$LEVEL" = "app" ] || os_die 2 "team is not on yet"

SLUG=$(os_fm_get "$ROOT/company-profile.md" company_slug)
HOST_KIND=$(os_fm_get "$ROOT/company-profile.md" host)
HOST_URL=$(os_fm_get "$ROOT/company-profile.md" host_url || true)
ORG=$(os_fm_get "$ROOT/company-profile.md" org)
COMPANY_NAME=$(os_company_name "$ROOT/company-profile.md")
case "$COMPANY_NAME" in
  ""|*'{{'*) COMPANY_NAME="Company" ;;
esac

if ! OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
  os_die 3 "host.sh is missing"
fi
export OS_HOST_BIN OS_ORG="$ORG" OS_HOST="$HOST_KIND" OS_HOST_URL="$HOST_URL" OS_SLUG="$SLUG"
export OS_PROFILE="$ROOT/company-profile.md"
os_team_names "$SLUG"
os_team_guard "$(os_team_company)" "$(os_company_repo "$SLUG")"

PERSON=$(os_person_slugs "$ANSWERS" | head -n 1)
[ -n "$PERSON" ] || os_die 2 "name one person"
name=$(os_answer_or "person.${PERSON}.name" "$ANSWERS" "")
gh=$(os_answer_or "person.${PERSON}.github" "$ANSWERS" "")
email=$(os_answer_or "person.${PERSON}.email" "$ANSWERS" "")
role=$(os_answer_or "person.${PERSON}.role" "$ANSWERS" "")
areas=$(os_answer_or "person.${PERSON}.areas" "$ANSWERS" "")
manager=$(os_answer_or "person.${PERSON}.manager" "$ANSWERS" "")
[ -n "$name" ] || os_die 2 "person needs a name"
[ -n "$gh" ] || os_die 2 "person needs a github username"
[ -n "$role" ] || os_die 2 "person needs a role"

ADMIN=$(os_admin_slug_from_pages "$ROOT" || true)
[ -n "$ADMIN" ] || ADMIN=$(os_answer_or admin_slug "$ANSWERS" "")
[ -n "$ADMIN" ] || os_die 2 "no admin on the people pages"
ADMIN_PAGE=$(os_person_file "$ROOT" "$ADMIN" || true)
ADMIN_GH=$(os_fm_get "$ADMIN_PAGE" github)

COMPANY_REPO=$(os_company_repo "$SLUG")
branch="rules/${ADMIN}/add-${PERSON}"

(
  cd "$ROOT" || exit 1
  git fetch origin >/dev/null 2>&1 || true
  git checkout -q -B "$branch" origin/main
)

page=$(os_write_person_page "$ROOT" "$PERSON" "$name" "$gh" "$email" "$role" "$areas" "$manager")

# Director updates CODEOWNERS on the area repo, by its own PR, after the page.
os_git_commit "$ROOT" "People: add ${PERSON}" "$page"
# The branch is this script's own, rebuilt from origin/main. A retry replaces it.
os_with_git_token git -C "$ROOT" push --force --set-upstream origin "$branch"
# The change is on the host. Leave the admin's folder on main, so pull fast-forwards.
os_back_to_main "$ROOT"
os_show_branch_files "$ROOT" "$branch" "$page"
pr=$(os_host open-pr "$COMPANY_REPO" --head "$branch" --base main --title "People: add ${PERSON}")
number=$(printf '%s' "$pr" | jq -r '.number // empty')

WS_TEMPLATE="$DIR/workspace"
ws_dir="$ROOT/users/$PERSON"
if [ ! -d "$ws_dir/.git" ]; then
  os_write_workspace "$ws_dir" "$PERSON" "$name" "$SLUG" "$COMPANY_NAME" "$WS_TEMPLATE"
fi
os_host create-repo "$(os_user_repo "$SLUG" "$PERSON")" --private --source "$ws_dir" --push >/dev/null
os_host grant "$(os_user_repo "$SLUG" "$PERSON")" "$gh" write >/dev/null
os_host team-add "$(os_team_company)" "$gh" >/dev/null
os_host grant "$COMPANY_REPO" "$gh" write >/dev/null

a=""
for a in $(printf '%s' "$areas" | tr ',' ' '); do
  a=$(os_trim "$a")
  [ -n "$a" ] || continue
  if [ -d "$ROOT/areas/$a" ]; then
    os_team_guard "$(os_team_area "$a")" "$(os_area_repo "$SLUG" "$a")"
    os_host team-create "$(os_team_area "$a")" >/dev/null
    os_host team-add "$(os_team_area "$a")" "$gh" >/dev/null
    os_host grant "$(os_area_repo "$SLUG" "$a")" "team:$(os_team_area "$a")" write >/dev/null
    os_host grant "$(os_area_repo "$SLUG" "$a")" "$gh" write >/dev/null
  fi
done

for a in $(printf '%s' "$areas" | tr ',' ' '); do
  a=$(os_trim "$a")
  [ -n "$a" ] || continue
  director=$(os_answer_or "area.${a}.director" "$ANSWERS" "")
  if [ "$director" != "$PERSON" ]; then
    continue
  fi
  [ -e "$ROOT/areas/$a/.git" ] || continue
  abranch="rules/${ADMIN}/add-${PERSON}"
  os_with_git_token git -C "$ROOT/areas/$a" fetch origin
  git -C "$ROOT/areas/$a" checkout -q -B "$abranch" origin/main
  os_codeowners "$ROOT/areas/$a" "$(os_at_users "$ADMIN_GH" "$gh")" "$(os_forgejo_owner "$ADMIN_GH" "$gh")"
  os_git_commit "$ROOT/areas/$a" "Rules: director for ${a}" .github/CODEOWNERS .gitea/CODEOWNERS
  os_with_git_token git -C "$ROOT/areas/$a" push --force --set-upstream origin "$abranch"
  os_back_to_main "$ROOT/areas/$a"
  set +e
  pr=$(os_host open-pr "$(os_area_repo "$SLUG" "$a")" --head "$abranch" --base main --title "Rules: add ${PERSON}")
  pr_rc=$?
  set -e
  area_number=$(printf '%s' "$pr" | jq -r '.number // empty' 2>/dev/null || true)
  if [ "$pr_rc" -ne 0 ] || [ -z "$area_number" ]; then
    printf '%s\n' "could not open a pull request for $(os_area_repo "$SLUG" "$a")" >&2
    exit 2
  fi
done

printf 'add-person: ok\n'
printf 'person: %s\n' "$PERSON"
printf 'workspace: %s\n' "$(os_user_repo "$SLUG" "$PERSON")"
if [ -n "$number" ]; then
  printf 'pr: %s\n' "$number"
  # Like join: the page is not a rules file, so it merges by itself when the checks pass (B37).
  if os_host_try auto-merge "$COMPANY_REPO" "$number" >/dev/null; then
    printf '%s\n' "auto-merge: on"
  else
    printf 'auto-merge is off on %s: pull request %s stays open until someone merges it. Ask the admin to run skills/_host/host.sh protect %s --code-owners --approvals 0\n' \
      "$COMPANY_REPO" "$number" "$COMPANY_REPO"
  fi
fi
os_hand_off "$PERSON" "$name" "$ORG" "$COMPANY_REPO" "$areas" "$(os_user_repo "$SLUG" "$PERSON")" "$HOST_KIND" "$HOST_URL"
