#!/bin/bash
# Turn a solo company folder into a team. Admin's computer. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"

usage() {
  cat << 'EOF'
usage: team-on.sh --answers <file>

Turn solo into team in one run. A second run does not push to main.
If an area main has no check tools, the second run opens a pull request.
That pull request also adds review-rules.md when main lacks it.
If origin is missing, it adds the host clone URL and fetches. If origin is set
but origin/main is missing, it fetches again. It does not push to main.
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
REVIEW_VENDOR=$(os_answer_or review_vendor "$ANSWERS" "")
REVIEW_KIND=$(os_answer_or review_kind "$ANSWERS" "")
REVIEW_MODEL=$(os_answer_or review_model "$ANSWERS" "")
case "$REVIEW_VENDOR" in
  ""|anthropic|openai|xai) ;;
  *) os_die 2 "review_vendor must be anthropic, openai, or xai" ;;
esac
case "$REVIEW_KIND" in
  "")
    if [ -n "$REVIEW_VENDOR" ]; then
      REVIEW_KIND=second-vendor
    else
      REVIEW_KIND=same-vendor
    fi
    ;;
  second-vendor|same-vendor) ;;
  *) os_die 2 "review_kind must be second-vendor or same-vendor" ;;
esac
REVIEW=$(os_review_state)
case "$REVIEW" in
  key-set)
    if [ "$REVIEW_KIND" = "same-vendor" ]; then
      printf '%s\n' "weaker review: same vendor"
    else
      printf '%s\n' "review: second-vendor"
    fi
    ;;
  *)
    printf '%s\n' "no review key: every pull request fails the model review until you add one"
    ;;
esac
mkdir -p "$ROOT/.github"
cat > "$ROOT/.github/review.conf" << EOF
vendor=${REVIEW_VENDOR}
model=${REVIEW_MODEL}
kind=${REVIEW_KIND}
EOF

os_fm_set "$ROOT/company-profile.md" company_slug "$SLUG"
os_fm_set "$ROOT/company-profile.md" level "team"
os_fm_set "$ROOT/company-profile.md" host "$HOST_KIND"
os_fm_set "$ROOT/company-profile.md" host_url "$(os_yaml_quote "$HOST_URL")"
os_fm_set "$ROOT/company-profile.md" org "$ORG"
os_fm_set "$ROOT/company-profile.md" sync_engine "$(os_yaml_quote "$ENGINE")"
os_fm_set "$ROOT/company-profile.md" runner "$RUNNER"

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
os_codeowners "$ROOT" "$(os_at_users "$ADMIN_GH" "$ADMIN_GH")"

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
      # Includes scripts/tools/, so the area check does not need skills/.
      cp -R "$ROOT/.github/scripts/." "$ROOT/areas/$area/.github/scripts/"
    fi
    if [ -f "$ROOT/.github/review.conf" ]; then
      cp "$ROOT/.github/review.conf" "$ROOT/areas/$area/.github/review.conf"
    fi
  fi
  # The area director owns this file after the first copy. Never replace it.
  if [ ! -f "$ROOT/areas/$area/review-rules.md" ]; then
    rules_src=""
    if [ -f "$ROOT/review-rules.md" ]; then
      rules_src="$ROOT/review-rules.md"
    elif [ -f "$DIR/../../review-rules.md" ]; then
      rules_src="$DIR/../../review-rules.md"
    fi
    if [ -n "$rules_src" ]; then
      cp "$rules_src" "$ROOT/areas/$area/review-rules.md"
    fi
  fi
  os_codeowners "$ROOT/areas/$area" "$(os_at_users "$ADMIN_GH" "$director_gh")"
done << EOF
$(os_areas_on_disk "$ROOT")
EOF

if [ -x "$ROOT/skills/privacy/privacy.sh" ]; then
  "$ROOT/skills/privacy/privacy.sh" --root "$ROOT"
else
  printf '%s\n' "privacy: skills/privacy/privacy.sh is not here yet"
fi

rules_on_main() {
  local dir=$1
  git -C "$dir" cat-file -e origin/main:.github/CODEOWNERS 2>/dev/null \
    && git -C "$dir" cat-file -e origin/main:.gitea/CODEOWNERS 2>/dev/null \
    && git -C "$dir" cat-file -e origin/main:.github/review.conf 2>/dev/null
}

repo_exists() {
  local rc
  set +e
  os_host repo-access "$1" >/dev/null
  rc=$?
  set -e
  [ "$rc" -eq 0 ]
}

# Rules files must be on main before protect. Never push to a protected main.
commit_rules_before_protect() {
  local dir=$1 msg=$2
  if ! os_origin_exists "$dir"; then
    os_git_commit "$dir" "$msg"
    return 0
  fi
  os_with_git_token git -C "$dir" fetch origin
  if rules_on_main "$dir"; then
    return 0
  fi
  os_git_commit "$dir" "$msg"
  if os_with_git_token git -C "$dir" push origin HEAD:main; then
    return 0
  fi
  printf '%s\n' "main is protected and .github/CODEOWNERS, .gitea/CODEOWNERS, or review.conf is missing. Propose them with skills/sync/sync.sh propose." >&2
  exit 2
}

push_new_repo() {
  local name=$1 source=$2 existed=0
  if repo_exists "$name"; then
    existed=1
  else
    os_host create-repo "$name" --private --source "$source" --push >/dev/null
  fi
  # Existing repo: add a missing origin and fetch. Never push to main.
  os_ensure_origin "$source" "$name" "$HOST_KIND" "$HOST_URL" "$ORG" "$existed"
  printf 'repo: %s\n' "$name"
}

# Stage review-rules.md when origin/main lacks it. Never overwrites a file
# already on this commit or in the work tree. The area director owns it.
stage_missing_review_rules() {
  local dir=$1 src=""
  if git -C "$dir" cat-file -e "origin/main:review-rules.md" 2>/dev/null; then
    return 0
  fi
  if git -C "$dir" cat-file -e "HEAD:review-rules.md" 2>/dev/null; then
    return 0
  fi
  if [ ! -f "$dir/review-rules.md" ]; then
    if [ -f "$ROOT/review-rules.md" ]; then
      src="$ROOT/review-rules.md"
    elif [ -f "$DIR/../../review-rules.md" ]; then
      src="$DIR/../../review-rules.md"
    else
      return 0
    fi
    cp "$src" "$dir/review-rules.md"
  fi
  git -C "$dir" add -- review-rules.md
}

commit_staged() {
  local dir=$1 msg=$2
  if git -C "$dir" diff --cached --quiet; then
    return 1
  fi
  GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    git -C "$dir" commit -q -m "$msg"
}

# Never pushes to main. Main may be protected.
push_tools_branch() {
  local dir=$1 name=$2 branch=$3
  if ! os_with_git_token git -C "$dir" push origin "HEAD:${branch}"; then
    printf '%s\n' "could not push ${branch} for ${name}" >&2
    exit 2
  fi
}

open_rules_pr() {
  local name=$1 branch=$2 pr number
  pr=$(os_host open-pr "$name" --head "$branch" --base main --title "Team: add review rules")
  number=$(printf '%s' "$pr" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    printf '%s\n' "could not open a pull request for ${name}" >&2
    exit 2
  fi
  printf 'pr: %s %s\n' "$name" "$number"
}

# Tools may already be on main. A missing review-rules.md still needs a pull
# request. The checks job can pass from the default shipped with the scripts.
propose_missing_review_rules() {
  local dir=$1 name=$2 branch="team/review-rules"
  if git -C "$dir" cat-file -e "origin/main:review-rules.md" 2>/dev/null; then
    return 0
  fi
  if ! git -C "$dir" cat-file -e "origin/${branch}:review-rules.md" 2>/dev/null; then
    git -C "$dir" checkout -q -f -B "$branch" origin/main
    stage_missing_review_rules "$dir"
    if ! git -C "$dir" diff --cached --quiet; then
      commit_staged "$dir" "Team: add review rules"
      push_tools_branch "$dir" "$name" "$branch"
    fi
  fi
  open_rules_pr "$name" "$branch"
}

open_tools_pr() {
  local name=$1 branch=$2 pr number
  pr=$(os_host open-pr "$name" --head "$branch" --base main --title "Team: add check tools")
  number=$(printf '%s' "$pr" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    printf '%s\n' "could not open a pull request for ${name}" >&2
    exit 2
  fi
  printf 'pr: %s %s\n' "$name" "$number"
}

# An area that already has rules on main never gets a second push to main.
# If that main has no check tools, commit them on a branch and open a pull request.
# The same branch gets review-rules.md when main lacks it.
propose_missing_tools() {
  local dir=$1 name=$2 src branch
  if ! os_origin_exists "$dir"; then
    return 0
  fi
  os_with_git_token git -C "$dir" fetch origin
  if git -C "$dir" cat-file -e "origin/main:.github/scripts/tools/secret-scan.sh" 2>/dev/null; then
    propose_missing_review_rules "$dir" "$name"
    return 0
  fi
  branch="team/scripts-tools"
  if git -C "$dir" cat-file -e "origin/${branch}:.github/scripts/tools/secret-scan.sh" 2>/dev/null; then
    if ! git -C "$dir" cat-file -e "origin/main:review-rules.md" 2>/dev/null \
      && ! git -C "$dir" cat-file -e "origin/${branch}:review-rules.md" 2>/dev/null; then
      git -C "$dir" checkout -q -f -B "$branch" "origin/${branch}"
      stage_missing_review_rules "$dir"
      if ! git -C "$dir" diff --cached --quiet; then
        commit_staged "$dir" "Team: add review rules"
        push_tools_branch "$dir" "$name" "$branch"
      fi
    fi
    open_tools_pr "$name" "$branch"
    return 0
  fi
  if [ -d "$ROOT/.github/scripts/tools" ]; then
    src="$ROOT/.github/scripts"
  else
    src="$DIR/../../.github/scripts"
  fi
  [ -d "$src/tools" ] || os_die 3 "check tools are missing from the template"
  git -C "$dir" checkout -q -f -B "$branch" origin/main
  mkdir -p "$dir/.github"
  rm -rf "$dir/.github/scripts"
  cp -R "$src" "$dir/.github/scripts"
  stage_missing_review_rules "$dir"
  git -C "$dir" add -- .github/scripts
  if git -C "$dir" diff --cached --quiet; then
    return 0
  fi
  commit_staged "$dir" "Team: add check tools"
  push_tools_branch "$dir" "$name" "$branch"
  open_tools_pr "$name" "$branch"
}

commit_rules_before_protect "$ROOT" "Team: turn on"
push_new_repo "$COMPANY_REPO" "$ROOT"

area=""
while IFS= read -r area; do
  [ -n "$area" ] || continue
  commit_rules_before_protect "$ROOT/areas/$area" "Team: area rules"
  push_new_repo "$(os_area_repo "$SLUG" "$area")" "$ROOT/areas/$area"
  propose_missing_tools "$ROOT/areas/$area" "$(os_area_repo "$SLUG" "$area")"
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
  ws_name=$(os_user_repo "$SLUG" "$slug")
  ws_existed=0
  if repo_exists "$ws_name"; then
    ws_existed=1
  else
    os_host create-repo "$ws_name" --private --source "$ws_dir" --push >/dev/null
  fi
  os_ensure_origin "$ws_dir" "$ws_name" "$HOST_KIND" "$HOST_URL" "$ORG" "$ws_existed"
  printf 'workspace: %s\n' "$ws_name"
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
  while IFS= read -r a || [ -n "$a" ]; do
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
  OS_COMPANY_ROOT="$ROOT" OS_JOBS_DIR="${OS_JOBS_DIR:-}" "$ROOT/skills/sync/sync.sh" install-jobs --admin
else
  printf '%s\n' "sync-jobs: skills/sync/sync.sh is not here yet"
fi

slug=""
while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  [ "$slug" = "$ADMIN" ] && continue
  name=$(os_answer_or "person.${slug}.name" "$ANSWERS" "$slug")
  areas=$(os_answer_or "person.${slug}.areas" "$ANSWERS" "")
  os_hand_off "$slug" "$name" "$ORG" "$COMPANY_REPO" "$areas" "$(os_user_repo "$SLUG" "$slug")" "$HOST_KIND" "$HOST_URL"
done << EOF
$(os_person_slugs "$ANSWERS")
EOF

printf '%s\n' "team-on: ok"
printf '%s\n' "level: team"
