#!/bin/bash
# Move a v0 company folder to v1. One branch, one pull request. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-teammate/lib.sh"
# shellcheck disable=SC1091
. "$DIR/rules.sh"

usage() {
  cat << 'EOF'
usage: upgrade.sh [--dry-run] [--root <dir>] [--template <dir>] [--level solo|team|app] [--answers <file>]

Dry-run prints changes and conflicts and changes nothing.
A real run makes one merge commit on upgrade/v1 and opens one pull request.
Company content is not rewritten. Keep the logs-archive tag for 90 days.
EOF
}

DRY=0
ROOT=""
TEMPLATE=""
LEVEL=""
ANSWERS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY=1
      shift
      ;;
    --root)
      [ $# -ge 2 ] || os_die 1 "missing root"
      ROOT=$2
      shift 2
      ;;
    --template)
      [ $# -ge 2 ] || os_die 1 "missing template"
      TEMPLATE=$2
      shift 2
      ;;
    --level)
      [ $# -ge 2 ] || os_die 1 "missing level"
      LEVEL=$2
      shift 2
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

os_need git
[ -n "$ROOT" ] || ROOT=$(pwd)
[ -d "$ROOT" ] || os_die 2 "company folder is missing"
ROOT=$(cd "$ROOT" && pwd)
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || os_die 2 "not a git repo"
[ -f "$ROOT/company-profile.md" ] || os_die 2 "company-profile.md is missing"

if [ -z "$TEMPLATE" ] && [ -n "${OS_TEMPLATE:-}" ]; then
  TEMPLATE=$OS_TEMPLATE
fi
if [ -z "$TEMPLATE" ]; then
  guess=$(cd "$DIR/../.." && pwd)
  if [ -f "$guess/company-profile.md" ] && grep -q '{{COMPANY_SLUG}}' "$guess/company-profile.md"; then
    TEMPLATE=$guess
  fi
fi
[ -n "$TEMPLATE" ] || os_die 1 "pass --template <dir>"
[ -d "$TEMPLATE" ] || os_die 1 "template folder is missing"

if [ -n "$ANSWERS" ] && [ -z "$LEVEL" ]; then
  LEVEL=$(os_answer_or level "$ANSWERS" "")
fi
[ -n "$LEVEL" ] || LEVEL="solo"
case "$LEVEL" in
  solo|team|app) ;;
  *) os_die 1 "level must be solo, team, or app" ;;
esac

os_sha() {
  if os_have shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

V0_LOGS=0
V0_LINKS=0
V0_LEVEL=0
V0_FOLDER=0
if git -C "$ROOT" show-ref --verify --quiet refs/heads/logs; then
  V0_LOGS=1
fi
if [ ! -L "$ROOT/.agents/skills" ]; then
  V0_LINKS=1
fi
if ! os_fm_get "$ROOT/company-profile.md" level >/dev/null 2>&1; then
  V0_LEVEL=1
fi
if [ -d "$ROOT/skills/logs-folder" ]; then
  V0_FOLDER=1
fi

if [ "$DRY" -eq 1 ]; then
  printf '%s\n' "upgrade: dry-run"
else
  if [ "$V0_LOGS" -eq 0 ] && [ "$V0_LINKS" -eq 0 ] && [ "$V0_LEVEL" -eq 0 ] && [ "$V0_FOLDER" -eq 0 ]; then
    os_die 2 "not a v0 folder"
  fi
fi

[ "$V0_LOGS" -eq 1 ] && printf '%s\n' "v0: logs-branch"
[ "$V0_LINKS" -eq 1 ] && printf '%s\n' "v0: no-links"
[ "$V0_LEVEL" -eq 1 ] && printf '%s\n' "v0: no-level"
[ "$V0_FOLDER" -eq 1 ] && printf '%s\n' "v0: logs-folder"

HASHES="$DIR/v0-hashes.txt"
[ -f "$HASHES" ] || os_die 3 "v0-hashes.txt is missing"

plan_skills() {
  local hash path got
  while read -r hash path; do
    [ -n "$hash" ] || continue
    case "$hash" in
      \#*) continue ;;
    esac
    case "$path" in
      skills/*) ;;
      *) continue ;;
    esac
    if [ ! -f "$ROOT/$path" ]; then
      continue
    fi
    got=$(os_sha "$ROOT/$path")
    if [ "$got" = "$hash" ]; then
      if [ -f "$TEMPLATE/$path" ]; then
        printf 'change: %s\n' "$path"
      fi
    elif [ -f "$TEMPLATE/$path" ] && cmp -s "$ROOT/$path" "$TEMPLATE/$path"; then
      :
    else
      printf 'conflict: %s\n' "$path"
    fi
  done < "$HASHES"
}

apply_skills() {
  local hash path got
  while read -r hash path; do
    [ -n "$hash" ] || continue
    case "$hash" in
      \#*) continue ;;
    esac
    case "$path" in
      skills/*) ;;
      *) continue ;;
    esac
    if [ ! -f "$ROOT/$path" ] || [ ! -f "$TEMPLATE/$path" ]; then
      continue
    fi
    got=$(os_sha "$ROOT/$path")
    if [ "$got" = "$hash" ]; then
      cp -p "$TEMPLATE/$path" "$ROOT/$path"
    fi
  done < "$HASHES"
}

# New files inside a skill the company already has. A company-added file is not here.
plan_skill_files() {
  local skill name rel new f
  [ -d "$TEMPLATE/skills" ] || return 0
  for skill in "$TEMPLATE"/skills/*; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    [ "$name" = "logs-folder" ] && continue
    if [ ! -e "$ROOT/skills/$name" ]; then
      printf 'change: skills/%s\n' "$name"
      continue
    fi
    new=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="skills/${name}/${f#"$skill"/}"
      if [ ! -e "$ROOT/$rel" ]; then
        new=$((new + 1))
      fi
    done < <(find "$skill" \( -type f -o -type l \) -print)
    if [ "$new" -gt 0 ]; then
      printf 'change: skill-files skills/%s new=%s\n' "$name" "$new"
    fi
  done
}

copy_skill_files() {
  local skill name rel f
  [ -d "$TEMPLATE/skills" ] || return 0
  for skill in "$TEMPLATE"/skills/*; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    [ "$name" = "logs-folder" ] && continue
    if [ ! -e "$ROOT/skills/$name" ]; then
      mkdir -p "$ROOT/skills"
      cp -Rp "$skill" "$ROOT/skills/$name"
      continue
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="skills/${name}/${f#"$skill"/}"
      [ -e "$ROOT/$rel" ] && continue
      mkdir -p "$(dirname "$ROOT/$rel")"
      cp -Pp "$f" "$ROOT/$rel"
    done < <(find "$skill" \( -type f -o -type l \) -print)
  done
}

plan_skills
plan_skill_files

LOGS_FOLDER_SAME=0
if [ -d "$ROOT/skills/logs-folder" ]; then
  same=1
  for f in "$ROOT"/skills/logs-folder/*; do
    [ -f "$f" ] || continue
    rel="skills/logs-folder/$(basename "$f")"
    want=$(awk -v p="$rel" '$2 == p { print $1 }' "$HASHES")
    if [ -z "$want" ] || [ "$(os_sha "$f")" != "$want" ]; then
      same=0
    fi
  done
  if [ "$same" -eq 1 ]; then
    LOGS_FOLDER_SAME=1
    printf '%s\n' "change: remove-logs-folder"
  else
    printf '%s\n' "conflict: skills/logs-folder"
  fi
fi

printf '%s\n' "change: links"
printf '%s\n' "change: level-block"
if [ "$V0_LOGS" -eq 1 ]; then
  printf '%s\n' "change: logs-history"
fi
# Rules merge replaces the old stock-hash copy. A v1 file is left alone.
rules_plan_company 0
rules_maybe_attrs "$ROOT" "" 0 ""
if [ "$LEVEL" = "team" ] || [ "$LEVEL" = "app" ]; then
  if [ -f "$ROOT/AGENTS.md" ]; then
    printf '%s\n' "change: tier-table"
  fi
fi

if [ -f "$ROOT/app-link.json" ] || [ "${OS_APP_LINK:-}" = "1" ]; then
  printf '%s\n' "app-groups: needs Track K"
else
  printf '%s\n' "app-groups: not linked"
fi

if [ "$V0_LOGS" -eq 1 ]; then
  printf 'tag: logs-archive-%s\n' "$(os_today)"
  printf '%s\n' "keep: 90 days"
fi

if [ -d "$TEMPLATE/.github/scripts/tools" ]; then
  printf '%s\n' "change: .github/scripts/tools"
fi
# 0 when the area main has no review-rules.md. A local file counts when
# origin/main is not here yet. Does not fetch.
area_lacks_review_rules() {
  local area=$1
  if git -C "$area" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    if git -C "$area" cat-file -e "origin/main:review-rules.md" 2>/dev/null; then
      return 1
    fi
    return 0
  fi
  if [ -f "$area/review-rules.md" ]; then
    return 1
  fi
  if git -C "$area" rev-parse --verify --quiet HEAD >/dev/null 2>&1 \
    && git -C "$area" cat-file -e "HEAD:review-rules.md" 2>/dev/null; then
    return 1
  fi
  return 0
}

review_rules_source() {
  if [ -f "$ROOT/review-rules.md" ]; then
    printf '%s\n' "$ROOT/review-rules.md"
    return 0
  fi
  if [ -f "$TEMPLATE/review-rules.md" ]; then
    printf '%s\n' "$TEMPLATE/review-rules.md"
    return 0
  fi
  return 1
}

plan_area_scripts() {
  local area name repo slug files
  [ -d "$TEMPLATE/.github/scripts" ] || return 0
  [ -d "$ROOT/areas" ] || return 0
  slug=$(os_fm_get "$ROOT/company-profile.md" company_slug 2>/dev/null || true)
  case "$slug" in
    ""|*'{{'*) slug="" ;;
  esac
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    name=$(basename "$area")
    if [ -n "$slug" ]; then
      repo=$(os_area_repo "$slug" "$name")
    else
      repo="areas/${name}"
    fi
    files=".github/scripts"
    if area_lacks_review_rules "$area" && review_rules_source >/dev/null; then
      files=".github/scripts review-rules.md"
    fi
    printf 'pr-plan: %s branch upgrade/scripts files %s auto-merge\n' "$repo" "$files"
    rules_one_area "$area" 0
  done
}
plan_area_scripts

if [ "$DRY" -eq 1 ]; then
  exit 0
fi

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  os_die 2 "the company folder has uncommitted changes. Commit or stash them, then run upgrade again."
fi
if [ -e "$ROOT/memory/logs/.git" ]; then
  if [ -n "$(git -C "$ROOT/memory/logs" status --porcelain)" ]; then
    os_die 2 "memory/logs has uncommitted changes. Commit them on the logs branch, then run upgrade again."
  fi
fi

if ! git filter-repo -h >/dev/null 2>&1; then
  os_die 3 "git filter-repo is not installed"
fi

# Save logs, drop the worktree, tag the old tip.
if [ "$V0_LOGS" -eq 1 ]; then
  if [ -d "$ROOT/memory/logs" ]; then
    if ! git -C "$ROOT" worktree remove --force "$ROOT/memory/logs"; then
      os_die 3 "could not remove the logs worktree. Upgrade stopped. The logs files are still in place."
    fi
  fi
  if ! git -C "$ROOT" rev-parse --verify "refs/tags/logs-archive-$(os_today)" >/dev/null 2>&1; then
    git -C "$ROOT" tag -a "logs-archive-$(os_today)" logs -m "Kept for 90 days. Delete this tag after 90 days."
  fi
fi

git -C "$ROOT" checkout -q -B upgrade/work main

# Rules merge is its own commit, first in the one upgrade pull request.
rules_plan_company 1
rules_maybe_attrs "$ROOT" "" 1 ""
rules_stage_rules "$ROOT"
if ! git -C "$ROOT" diff --cached --quiet; then
  rules_commit_msg "$ROOT" "Upgrade: rules merge"
fi

if [ "$V0_LOGS" -eq 1 ]; then
  tmp=$(mktemp -d)
  git clone --quiet --branch logs --single-branch "$ROOT" "$tmp/logs"
  git -C "$tmp/logs" filter-repo --to-subdirectory-filter memory/logs --force
  git -C "$ROOT" remote remove logs-prefixed 2>/dev/null || true
  git -C "$ROOT" remote add logs-prefixed "$tmp/logs"
  git -C "$ROOT" fetch --quiet logs-prefixed
  git -C "$ROOT" merge --allow-unrelated-histories --no-commit logs-prefixed/logs
  git -C "$ROOT" remote remove logs-prefixed
  rm -rf "$tmp"
fi

mkdir -p "$ROOT/.agents" "$ROOT/.claude"
ln -sfn ../skills "$ROOT/.agents/skills"
ln -sfn ../skills "$ROOT/.claude/skills"

if [ -f "$ROOT/.gitignore" ]; then
  grep -v '^/memory/logs/$' "$ROOT/.gitignore" | grep -v 'skills/logs-folder' > "$ROOT/.gitignore.tmp" || true
  mv "$ROOT/.gitignore.tmp" "$ROOT/.gitignore"
fi

OS_VER=""
if [ -n "$ANSWERS" ]; then
  OS_VER=$(os_answer_or os_version "$ANSWERS" "")
  HOST_KIND=$(os_answer_or host "$ANSWERS" "")
  HOST_URL=$(os_answer_or host_url "$ANSWERS" "")
  ORG=$(os_answer_or org "$ANSWERS" "")
  ENGINE=$(os_answer_or sync_engine "$ANSWERS" "")
  RUNNER=$(os_answer_or runner "$ANSWERS" "")
fi
[ -n "${OS_VER:-}" ] || OS_VER="v1.0.0"
case "$OS_VER" in
  *'{{'*) OS_VER="v1.0.0" ;;
esac

os_fm_set "$ROOT/company-profile.md" level "$LEVEL"
if ! os_fm_get "$ROOT/company-profile.md" switches >/dev/null 2>&1; then
  os_fm_set "$ROOT/company-profile.md" switches "[]"
fi
os_fm_set "$ROOT/company-profile.md" os_version "$OS_VER"
if [ -n "${HOST_KIND:-}" ]; then
  os_fm_set "$ROOT/company-profile.md" host "$HOST_KIND"
fi
if [ -n "${ANSWERS:-}" ] && val=$(os_answer host_url "$ANSWERS"); then
  os_fm_set "$ROOT/company-profile.md" host_url "$(os_yaml_quote "$val")"
fi
if [ -n "${ORG:-}" ]; then
  os_fm_set "$ROOT/company-profile.md" org "$ORG"
fi
if [ -n "${ENGINE:-}" ]; then
  os_fm_set "$ROOT/company-profile.md" sync_engine "$(os_yaml_quote "$ENGINE")"
fi
if [ -n "${RUNNER:-}" ]; then
  os_fm_set "$ROOT/company-profile.md" runner "$RUNNER"
fi

apply_skills
if [ "$LOGS_FOLDER_SAME" -eq 1 ]; then
  rm -rf "$ROOT/skills/logs-folder"
fi
copy_skill_files

if [ -f "$ROOT/.gitignore" ] && ! grep -qx '/users/' "$ROOT/.gitignore"; then
  printf '\n%s\n' "/users/" >> "$ROOT/.gitignore"
fi

refresh_check_tools() {
  local src
  src="$TEMPLATE/.github/scripts/tools"
  [ -d "$src" ] || return 0
  mkdir -p "$ROOT/.github/scripts"
  rm -rf "$ROOT/.github/scripts/tools"
  cp -R "$src" "$ROOT/.github/scripts/tools"
}
refresh_check_tools

# Area folders are separate repos. /areas/ is gitignored in the company repo.
# Commit the scripts in each area repo and open a pull request. Never git add them here.
push_area_scripts() {
  local area name repo branch pr number src rules_src
  src="$TEMPLATE/.github/scripts"
  [ -d "$src" ] || return 0
  [ -d "$ROOT/areas" ] || return 0
  case "${SLUG:-}" in
    ""|*'{{'*) return 0 ;;
  esac
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    name=$(basename "$area")
    repo=$(os_area_repo "$SLUG" "$name")
    if [ ! -e "$area/.git" ]; then
      printf 'pr-plan: %s skipped: not a git repo\n' "$repo" >&2
      continue
    fi
    branch="upgrade/scripts"
    if ! os_with_git_token git -C "$area" fetch origin; then
      os_die 3 "could not fetch ${repo}"
    fi
    git -C "$area" checkout -q -f -B "$branch" origin/main
    rules_one_area "$area" 1
    rules_stage_rules "$area"
    if ! git -C "$area" diff --cached --quiet; then
      rules_commit_msg "$area" "Upgrade: rules merge"
    fi
    mkdir -p "$area/.github"
    rm -rf "$area/.github/scripts"
    cp -R "$src" "$area/.github/scripts"
    # Add the file only when main lacks it. Never replace the director's copy.
    if ! git -C "$area" cat-file -e "origin/main:review-rules.md" 2>/dev/null; then
      if [ ! -f "$area/review-rules.md" ]; then
        rules_src=""
        if rules_src=$(review_rules_source); then
          cp "$rules_src" "$area/review-rules.md"
        fi
      fi
      if [ -f "$area/review-rules.md" ]; then
        git -C "$area" add -- review-rules.md
      fi
    fi
    git -C "$area" add -- .github/scripts
    if ! git -C "$area" diff --cached --quiet; then
      GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
        GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
        GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
        GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
        git -C "$area" commit -q -m "Upgrade: check scripts"
    fi
    if git -C "$area" diff --quiet origin/main..HEAD; then
      printf 'pr-plan: %s nothing to commit\n' "$repo"
      continue
    fi
    if ! os_with_git_token git -C "$area" push origin "HEAD:${branch}"; then
      os_die 3 "could not push ${branch} for ${repo}"
    fi
    area_body=$(mktemp)
    rules_pr_body "$area" origin/main "$area_body"
    pr=$(os_host open-pr "$repo" --head "$branch" --base main --title "Upgrade: check scripts" --body-file "$area_body")
    rm -f "$area_body"
    number=$(printf '%s' "$pr" | jq -r '.number // empty')
    if [ -z "$number" ]; then
      os_die 3 "could not open a pull request for ${repo}"
    fi
    os_host auto-merge "$repo" "$number" >/dev/null
    printf 'pr: %s %s\n' "$repo" "$number"
  done
}

stage_upgrade() {
  local path
  for path in .gitignore company-profile.md AGENTS.md CLAUDE.md company-rules.md .gitattributes; do
    if [ -e "$ROOT/$path" ]; then
      git -C "$ROOT" add -- "$path"
    fi
  done
  if [ -e "$ROOT/.agents" ] || [ -L "$ROOT/.agents/skills" ]; then
    git -C "$ROOT" add -- .agents .claude
  fi
  if [ -d "$ROOT/skills" ]; then
    git -C "$ROOT" add -- skills
  fi
  if [ -d "$ROOT/.github/scripts/tools" ]; then
    git -C "$ROOT" add -- .github/scripts/tools
  fi
  if [ -d "$ROOT/memory/logs" ]; then
    git -C "$ROOT" add -f -- memory/logs
  fi
}
stage_upgrade
if git -C "$ROOT" diff --cached --quiet && [ "$V0_LOGS" -eq 0 ]; then
  if ! git -C "$ROOT" log --format='%s' main..HEAD | grep -qx 'Upgrade: rules merge'; then
    os_die 3 "upgrade had nothing to commit"
  fi
fi
if ! git -C "$ROOT" diff --cached --quiet; then
  GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    git -C "$ROOT" commit -q -m "Upgrade to v1"
fi
pr_body=$(mktemp)
rules_pr_body "$ROOT" main "$pr_body"
git -C "$ROOT" checkout -q main
git -C "$ROOT" checkout -q -B upgrade/v1 main
GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
  GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
  GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
  GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
  git -C "$ROOT" merge --no-ff --no-edit upgrade/work -m "Upgrade to v1"
git -C "$ROOT" branch -D upgrade/work >/dev/null

if [ -f "$ROOT/company-profile.md" ]; then
  HOST_KIND=$(os_fm_get "$ROOT/company-profile.md" host 2>/dev/null || true)
  HOST_URL=$(os_fm_get "$ROOT/company-profile.md" host_url 2>/dev/null || true)
  ORG=$(os_fm_get "$ROOT/company-profile.md" org 2>/dev/null || true)
  SLUG=$(os_fm_get "$ROOT/company-profile.md" company_slug 2>/dev/null || true)
fi
if [ "$HOST_KIND" = "github" ] || [ "$HOST_KIND" = "forgejo" ]; then
  if OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
    export OS_HOST_BIN OS_ORG="$ORG" OS_HOST="$HOST_KIND" OS_HOST_URL="$HOST_URL" OS_SLUG="$SLUG"
    export OS_PROFILE="$ROOT/company-profile.md"
    push_area_scripts
    os_with_git_token git -C "$ROOT" push --set-upstream origin upgrade/v1
    pr=$(os_host open-pr "$(os_company_repo "$SLUG")" --head upgrade/v1 --base main --title "Upgrade to v1" --body-file "$pr_body")
    number=$(printf '%s' "$pr" | jq -r '.number // empty')
    if [ -n "$number" ]; then
      printf 'pr: %s\n' "$number"
    fi
  fi
elif [ -d "$ROOT/areas" ]; then
  # No host: still merge area rules on upgrade/scripts so the folder gets v1 rules.
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    [ -e "$area/.git" ] || continue
    if [ -n "$(git -C "$area" status --porcelain)" ]; then
      os_die 2 "an area folder has uncommitted changes. Commit them, then run upgrade again."
    fi
    git -C "$area" checkout -q -B upgrade/scripts
    rules_one_area "$area" 1
    rules_stage_rules "$area"
    if ! git -C "$area" diff --cached --quiet; then
      rules_commit_msg "$area" "Upgrade: rules merge"
    fi
  done
fi
rm -f "$pr_body"

printf '%s\n' "upgrade: ok"
