#!/bin/bash
# Move a v0 company folder to v1. One branch, one pull request. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-teammate/lib.sh"

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
      cp "$TEMPLATE/$path" "$ROOT/$path"
    fi
  done < "$HASHES"
}

plan_skills

if [ -d "$TEMPLATE/skills" ]; then
  for skill in "$TEMPLATE"/skills/*; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    [ "$name" = "logs-folder" ] && continue
    if [ ! -e "$ROOT/skills/$name" ]; then
      printf 'change: skills/%s\n' "$name"
    fi
  done
fi

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
if [ "$LEVEL" = "team" ] || [ "$LEVEL" = "app" ]; then
  agents_hash=$(awk '$2 == "AGENTS.md" { print $1 }' "$HASHES")
  if [ -n "$agents_hash" ] && [ -f "$ROOT/AGENTS.md" ] && [ "$(os_sha "$ROOT/AGENTS.md")" = "$agents_hash" ]; then
    printf '%s\n' "change: tier-table"
  elif [ -f "$ROOT/AGENTS.md" ] && grep -q 'Approval tiers' "$ROOT/AGENTS.md"; then
    printf '%s\n' "change: tier-table"
  else
    printf '%s\n' "conflict: AGENTS.md"
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
  if [ -d "$ROOT/areas" ]; then
    for area in "$ROOT"/areas/*; do
      [ -d "$area" ] || continue
      printf 'change: areas/%s/.github/scripts/tools\n' "$(basename "$area")"
    done
  fi
fi

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

agents_hash=$(awk '$2 == "AGENTS.md" { print $1 }' "$HASHES")
if [ -n "$agents_hash" ] && [ -f "$ROOT/AGENTS.md" ] && [ "$(os_sha "$ROOT/AGENTS.md")" = "$agents_hash" ]; then
  if [ -f "$TEMPLATE/AGENTS.md" ]; then
    cp "$TEMPLATE/AGENTS.md" "$ROOT/AGENTS.md"
  fi
fi
claude_hash=$(awk '$2 == "CLAUDE.md" { print $1 }' "$HASHES")
if [ -n "$claude_hash" ] && [ -f "$ROOT/CLAUDE.md" ] && [ "$(os_sha "$ROOT/CLAUDE.md")" = "$claude_hash" ]; then
  if [ -f "$TEMPLATE/CLAUDE.md" ]; then
    cp "$TEMPLATE/CLAUDE.md" "$ROOT/CLAUDE.md"
  fi
fi

apply_skills
if [ "$LOGS_FOLDER_SAME" -eq 1 ]; then
  rm -rf "$ROOT/skills/logs-folder"
fi
if [ -d "$TEMPLATE/skills" ]; then
  for skill in "$TEMPLATE"/skills/*; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    [ "$name" = "logs-folder" ] && continue
    if [ ! -e "$ROOT/skills/$name" ]; then
      cp -R "$skill" "$ROOT/skills/$name"
    fi
  done
fi

if [ -f "$ROOT/.gitignore" ] && ! grep -qx '/users/' "$ROOT/.gitignore"; then
  printf '\n%s\n' "/users/" >> "$ROOT/.gitignore"
fi

refresh_check_tools() {
  local src area
  src="$TEMPLATE/.github/scripts/tools"
  [ -d "$src" ] || return 0
  mkdir -p "$ROOT/.github/scripts"
  rm -rf "$ROOT/.github/scripts/tools"
  cp -R "$src" "$ROOT/.github/scripts/tools"
  if [ -d "$ROOT/areas" ]; then
    for area in "$ROOT"/areas/*; do
      [ -d "$area" ] || continue
      mkdir -p "$area/.github/scripts"
      rm -rf "$area/.github/scripts/tools"
      cp -R "$src" "$area/.github/scripts/tools"
    done
  fi
}
refresh_check_tools

stage_upgrade() {
  local path
  for path in .gitignore company-profile.md AGENTS.md CLAUDE.md; do
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
  os_die 3 "upgrade had nothing to commit"
fi
if ! git -C "$ROOT" diff --cached --quiet; then
  GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    git -C "$ROOT" commit -q -m "Upgrade to v1"
fi
git -C "$ROOT" checkout -q main
git -C "$ROOT" checkout -q -B upgrade/v1 main
GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
  GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
  GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
  GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
  git -C "$ROOT" merge --no-ff --no-edit upgrade/work -m "Upgrade to v1"

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
    os_with_git_token git -C "$ROOT" push --set-upstream origin upgrade/v1
    pr=$(os_host open-pr "$(os_company_repo "$SLUG")" --head upgrade/v1 --base main --title "Upgrade to v1")
    number=$(printf '%s' "$pr" | jq -r '.number // empty')
    if [ -n "$number" ]; then
      printf 'pr: %s\n' "$number"
    fi
  fi
fi

printf '%s\n' "upgrade: ok"
