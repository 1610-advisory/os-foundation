#!/bin/bash
# Turn a solo company folder into a team. Admin's computer. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"

usage() {
  cat << 'EOF'
usage: team-on.sh --answers <file>

Turn solo into team in one run. A second run changes nothing.
The review key is not an answers-file key. The script prints one command
for the admin to run in their own terminal:

  skills/_host/host.sh set-secret OS_REVIEW_KEY

See CLI.md for answers keys and exit codes.
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

HOST_KIND=$(os_answer_or host "$ANSWERS" "")
HOST_URL=$(os_answer_or host_url "$ANSWERS" "")
ORG=$(os_answer_or org "$ANSWERS" "")
ENGINE=$(os_answer_or sync_engine "$ANSWERS" "")
RUNNER=$(os_answer_or runner "$ANSWERS" "ubuntu-latest")
[ -n "$HOST_KIND" ] || os_die 2 "host is required"
[ -n "$ORG" ] || os_die 2 "org is required"
[ -n "$ENGINE" ] || os_die 2 "sync_engine is required"

SLUG=$(os_fm_get "$ROOT/company-profile.md" company_slug 2>/dev/null || true)
case "$SLUG" in
  ""|*'{{'*)
    SLUG=$(os_answer_or company_slug "$ANSWERS" "")
    ;;
esac
case "$SLUG" in
  ""|*'{{'*) os_die 2 "company_slug is not set" ;;
esac

COMPANY_NAME=$(os_answer_or company_name "$ANSWERS" "")
if [ -z "$COMPANY_NAME" ]; then
  COMPANY_NAME=$(os_company_name "$ROOT/company-profile.md")
fi
case "$COMPANY_NAME" in
  ""|*'{{'*) COMPANY_NAME="Company" ;;
esac

if ! OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
  os_die 3 "host.sh is missing"
fi
export OS_HOST_BIN OS_ORG="$ORG" OS_HOST="$HOST_KIND" OS_HOST_URL="$HOST_URL" OS_SLUG="$SLUG"
export OS_PROFILE="$ROOT/company-profile.md"

ADMIN=$(os_answer_or admin_slug "$ANSWERS" "")
if [ -z "$ADMIN" ]; then
  ADMIN=$(os_person_slugs "$ANSWERS" | while IFS= read -r s; do
    role=$(os_answer_or "person.${s}.role" "$ANSWERS" "")
    if [ "$role" = "admin" ]; then
      printf '%s\n' "$s"
      break
    fi
  done)
fi
[ -n "$ADMIN" ] || os_die 2 "name an admin"

ADMIN_GH=$(os_answer_or "person.${ADMIN}.github" "$ANSWERS" "")
[ -n "$ADMIN_GH" ] || os_die 2 "admin github username is required"

# Review key never enters this process. Print the command, then check existence only.
printf '%s\n' "review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY"
REVIEW=$(os_review_state)
case "$REVIEW" in
  key-set)
    printf '%s\n' "review: key-set"
    REVIEW_VALUE="key-set"
    ;;
  unchecked)
    printf '%s\n' "review: weaker"
    printf '%s\n' "review-check: secret-exists is not on this host yet"
    REVIEW_VALUE="weaker"
    ;;
  *)
    printf '%s\n' "review: weaker"
    REVIEW_VALUE="weaker"
    ;;
esac

os_fm_set "$ROOT/company-profile.md" company_slug "$SLUG"
os_fm_set "$ROOT/company-profile.md" level "team"
os_fm_set "$ROOT/company-profile.md" host "$HOST_KIND"
os_fm_set "$ROOT/company-profile.md" host_url "$(os_yaml_quote "$HOST_URL")"
os_fm_set "$ROOT/company-profile.md" org "$ORG"
os_fm_set "$ROOT/company-profile.md" sync_engine "$(os_yaml_quote "$ENGINE")"
os_fm_set "$ROOT/company-profile.md" runner "$RUNNER"
os_fm_set "$ROOT/company-profile.md" review "$REVIEW_VALUE"

# People pages.
slug=""
while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  name=$(os_answer_or "person.${slug}.name" "$ANSWERS" "")
  gh=$(os_answer_or "person.${slug}.github" "$ANSWERS" "")
  email=$(os_answer_or "person.${slug}.email" "$ANSWERS" "")
  role=$(os_answer_or "person.${slug}.role" "$ANSWERS" "")
  areas=$(os_answer_or "person.${slug}.areas" "$ANSWERS" "")
  manager=$(os_answer_or "person.${slug}.manager" "$ANSWERS" "")
  [ -n "$name" ] || os_die 2 "person ${slug} needs a name"
  [ -n "$gh" ] || os_die 2 "person ${slug} needs a github username"
  [ -n "$role" ] || os_die 2 "person ${slug} needs a role"
  os_write_person_page "$ROOT" "$slug" "$name" "$gh" "$email" "$role" "$areas" "$manager" >/dev/null
done << EOF
$(os_person_slugs "$ANSWERS")
EOF

COMPANY_REPO=$(os_company_repo "$SLUG")
os_codeowners "$ROOT/.github/CODEOWNERS" "$(os_at_users "$ADMIN_GH" "$ADMIN_GH")"

# Area CODEOWNERS and a copy of .github when the company root has one.
area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  director=$(os_answer_or "area.${area}.director" "$ANSWERS" "$ADMIN")
  director_gh=$(os_answer_or "person.${director}.github" "$ANSWERS" "$ADMIN_GH")
  if [ -d "$ROOT/.github" ]; then
    mkdir -p "$ROOT/areas/$area/.github"
    # Copy workflows and scripts. CODEOWNERS is rewritten below.
    if [ -d "$ROOT/.github/workflows" ]; then
      mkdir -p "$ROOT/areas/$area/.github/workflows"
      cp -R "$ROOT/.github/workflows/." "$ROOT/areas/$area/.github/workflows/"
    fi
    if [ -d "$ROOT/.github/scripts" ]; then
      mkdir -p "$ROOT/areas/$area/.github/scripts"
      cp -R "$ROOT/.github/scripts/." "$ROOT/areas/$area/.github/scripts/"
    fi
  fi
  os_codeowners "$ROOT/areas/$area/.github/CODEOWNERS" "$(os_at_users "$ADMIN_GH" "$director_gh")"
done << EOF
$(os_areas_on_disk "$ROOT")
EOF

if [ -x "$ROOT/skills/privacy/privacy.sh" ]; then
  "$ROOT/skills/privacy/privacy.sh" --root "$ROOT"
else
  printf '%s\n' "privacy: skills/privacy/privacy.sh is not here yet"
fi

# Commit on main only before the first push. After origin/main exists, main is protected.
if ! os_origin_exists "$ROOT"; then
  os_git_commit "$ROOT" "Team: turn on"
fi

(
  cd "$ROOT" || exit 1
  os_host create-repo "$COMPANY_REPO" --private --source "$ROOT" --push >/dev/null
)
printf 'repo: %s\n' "$COMPANY_REPO"

area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  if ! os_origin_exists "$ROOT/areas/$area"; then
    os_git_commit "$ROOT/areas/$area" "Team: area rules"
  fi
  os_host create-repo "$(os_area_repo "$SLUG" "$area")" --private --source "$ROOT/areas/$area" --push >/dev/null
  printf 'repo: %s\n' "$(os_area_repo "$SLUG" "$area")"
done << EOF
$(os_areas_on_disk "$ROOT")
EOF

# Workspaces. Copy the template as a whole, including CLAUDE.md when present.
WS_TEMPLATE="$DIR/workspace"
slug=""
while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  name=$(os_answer_or "person.${slug}.name" "$ANSWERS" "$slug")
  ws_dir="$ROOT/users/$slug"
  if [ ! -d "$ws_dir/.git" ]; then
    os_write_workspace "$ws_dir" "$slug" "$name" "$SLUG" "$COMPANY_NAME" "$WS_TEMPLATE"
  fi
  os_host create-repo "$(os_user_repo "$SLUG" "$slug")" --private --source "$ws_dir" --push >/dev/null
  printf 'workspace: %s\n' "$(os_user_repo "$SLUG" "$slug")"
done << EOF
$(os_person_slugs "$ANSWERS")
EOF

# Protect after the initial push. Not the workspace repos.
os_host protect "$COMPANY_REPO" --code-owners --approvals 0 >/dev/null
printf 'protected: %s\n' "$COMPANY_REPO"
area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  os_host protect "$(os_area_repo "$SLUG" "$area")" --code-owners --approvals 0 >/dev/null
  printf 'protected: %s\n' "$(os_area_repo "$SLUG" "$area")"
done << EOF
$(os_areas_on_disk "$ROOT")
EOF

# Teams and grants.
os_host team-create company >/dev/null
os_host grant "$COMPANY_REPO" "team:company" write >/dev/null

area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  os_host team-create "$(os_team_area "$area")" >/dev/null
  os_host grant "$(os_area_repo "$SLUG" "$area")" "team:$(os_team_area "$area")" write >/dev/null
done << EOF
$(os_areas_on_disk "$ROOT")
EOF

slug=""
while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  gh=$(os_answer_or "person.${slug}.github" "$ANSWERS" "")
  areas=$(os_answer_or "person.${slug}.areas" "$ANSWERS" "")
  os_host team-add company "$gh" >/dev/null
  a=""
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    os_host team-create "$(os_team_area "$a")" >/dev/null
    os_host team-add "$(os_team_area "$a")" "$gh" >/dev/null
    os_host grant "$(os_area_repo "$SLUG" "$a")" "team:$(os_team_area "$a")" write >/dev/null
    os_host grant "$(os_area_repo "$SLUG" "$a")" "$gh" write >/dev/null
  done << AREAS
$(os_split_areas "$areas")
AREAS
  os_host grant "$(os_user_repo "$SLUG" "$slug")" "$gh" write >/dev/null
done << EOF
$(os_person_slugs "$ANSWERS")
EOF

# Directors who are not already listed on the area still approve, so they join the team.
area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  director=$(os_answer_or "area.${area}.director" "$ANSWERS" "$ADMIN")
  director_gh=$(os_answer_or "person.${director}.github" "$ANSWERS" "$ADMIN_GH")
  os_host team-add "$(os_team_area "$area")" "$director_gh" >/dev/null
done << EOF
$(os_areas_on_disk "$ROOT")
EOF

cfg=$(os_config_dir "$SLUG")
mkdir -p "$cfg"
printf '%s\n' "$ADMIN" > "$cfg/me"
chmod 600 "$cfg/me"

if [ -x "$ROOT/skills/sync/sync.sh" ]; then
  OS_JOBS_DIR="${OS_JOBS_DIR:-}" "$ROOT/skills/sync/sync.sh" install-jobs --admin
else
  printf '%s\n' "sync-jobs: skills/sync/sync.sh is not here yet"
fi

slug=""
while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  [ "$slug" = "$ADMIN" ] && continue
  name=$(os_answer_or "person.${slug}.name" "$ANSWERS" "$slug")
  areas=$(os_answer_or "person.${slug}.areas" "$ANSWERS" "")
  os_hand_off "$slug" "$name" "$ORG" "$COMPANY_REPO" "$areas" "$(os_user_repo "$SLUG" "$slug")"
done << EOF
$(os_person_slugs "$ANSWERS")
EOF

printf '%s\n' "team-on: ok"
printf '%s\n' "level: team"
