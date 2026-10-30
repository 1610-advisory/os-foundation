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

# Host context, set once before any host call. The answers file first, then the profile.
# A v0 team profile has no host: line, and host.sh reads only the profile or OS_HOST.
UP_HOST=""
UP_HOST_URL=""
UP_ORG=""
if [ -n "$ANSWERS" ]; then
  UP_HOST=$(os_answer_or host "$ANSWERS" "")
  UP_HOST_URL=$(os_answer_or host_url "$ANSWERS" "")
  UP_ORG=$(os_answer_or org "$ANSWERS" "")
fi
[ -n "$UP_HOST" ] || UP_HOST=$(os_fm_get "$ROOT/company-profile.md" host 2>/dev/null || true)
[ -n "$UP_HOST_URL" ] || UP_HOST_URL=$(os_fm_get "$ROOT/company-profile.md" host_url 2>/dev/null || true)
[ -n "$UP_ORG" ] || UP_ORG=$(os_fm_get "$ROOT/company-profile.md" org 2>/dev/null || true)
# The slug names every repo. It goes into company-profile.md with the other profile lines.
SLUG=$(rules_resolve_slug || true)
HOST_ON=0
case "$UP_HOST" in
  github|forgejo)
    if OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
      HOST_ON=1
      export OS_HOST_BIN OS_HOST="$UP_HOST" OS_HOST_URL="$UP_HOST_URL" OS_ORG="$UP_ORG" OS_SLUG="$SLUG"
      export OS_PROFILE="$ROOT/company-profile.md"
    fi
    ;;
esac
# Team on a host: check tools on main and rulesets. Solo keeps its host as it is.
TEAM_ON=0
if [ "$HOST_ON" -eq 1 ]; then
  case "$LEVEL" in
    team|app) TEAM_ON=1 ;;
  esac
fi
# Rulesets on private repos need a paid GitHub plan. host.sh prints the plain line.
# A real run stops before any write. A dry run reports it and goes on.
PLAN_FINDING=""
if [ "$TEAM_ON" -eq 1 ] && [ "$UP_HOST" = "github" ]; then
  set +e
  plan_err=$(os_host plan-check 2>&1 >/dev/null)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    if [ "$DRY" -eq 0 ]; then
      printf '%s\n' "$plan_err" >&2
      exit "$rc"
    fi
    PLAN_FINDING=$(printf '%s' "$plan_err" | tail -n 1)
    [ -n "$PLAN_FINDING" ] || PLAN_FINDING="plan-check failed (exit ${rc})"
  fi
fi

os_sha() {
  if os_have shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

upgrade_uname() {
  if [ -n "${OS_UPGRADE_UNAME:-}" ]; then
    printf '%s\n' "$OS_UPGRADE_UNAME"
    return 0
  fi
  uname -s
}

case "$(upgrade_uname)" in
  MINGW*|MSYS*|CYGWIN*)
    os_die 2 "run the upgrade from a Mac or Linux clone of the company repo"
    ;;
esac

main_link_mode() {
  git -C "$ROOT" ls-tree main -- "$1" 2>/dev/null | awk '{print $1}'
}

# Read main, not the work tree. A leftover logs branch does not matter.
if git -C "$ROOT" cat-file -e main:company-profile.md 2>/dev/null \
  && git -C "$ROOT" show main:company-profile.md | grep -q '^level:' \
  && [ "$(main_link_mode .agents/skills)" = "120000" ] \
  && [ "$(main_link_mode .claude/skills)" = "120000" ]; then
  printf '%s\n' "upgrade: already v1"
  exit 0
fi

# An earlier run's branches: upgrade/v1 in the company folder, upgrade/scripts in each area.
# This script made a branch when its last commit is one it makes. A run rebuilds its own
# branches from main and replaces them on the host. Anything else on them stops the run.
upgrade_made() {
  git -C "$1" log -1 --format=%s "$2" 2>/dev/null | grep -qE '^Upgrade( to v1$|: )'
}

# One plain line with the exact commands for a branch that holds someone else's commits.
# $4: local, host, or both.
FOREIGN=0
foreign_branch() {
  local where=$1 label=$2 branch=$3 side=$4 cmds=""
  case "$side" in
    local|both) cmds="git checkout main && git branch -D ${branch}" ;;
  esac
  case "$side" in
    host|both) cmds="${cmds:+${cmds} && }git push origin --delete ${branch}" ;;
  esac
  printf 'upgrade: stopped: %s has commits on %s that the upgrade did not make. To keep them, merge or close its pull request first. To start over, in %s run: %s (that also closes its pull request). Then run upgrade again.\n' \
    "$label" "$branch" "$where" "$cmds"
  FOREIGN=1
}

# The folder is on its own upgrade branch from an earlier run: go back to main.
upgrade_branch_local() {
  local dir=$1 where=$2 label=$3 branch=$4
  git -C "$dir" show-ref --verify --quiet "refs/heads/${branch}" || return 0
  if ! upgrade_made "$dir" "refs/heads/${branch}"; then
    return 1
  fi
  if [ "$(git -C "$dir" symbolic-ref -q --short HEAD || true)" = "$branch" ] \
    && [ -z "$(git -C "$dir" status --porcelain)" ]; then
    git -C "$dir" checkout -q main || os_die 3 "could not switch ${where} to main"
    printf 'switched %s to main from %s (an earlier upgrade run)\n' "$where" "$branch"
  fi
  return 0
}

# No host: the person merges upgrade/v1 by hand, so a second run leaves it as it is.
if [ "$HOST_ON" -eq 0 ] && git -C "$ROOT" show-ref --verify --quiet refs/heads/upgrade/v1; then
  over="in the company folder: git checkout main && git branch -D upgrade/v1"
  for area in "$ROOT"/areas/*; do
    [ -e "$area/.git" ] || continue
    if git -C "$area" show-ref --verify --quiet refs/heads/upgrade/scripts; then
      over="${over}; in areas/$(basename "$area"): git checkout main && git branch -D upgrade/scripts"
    fi
  done
  printf '%s\n' "upgrade: pending upgrade/v1"
  printf 'To start over, run %s. Then run upgrade again.\n' "$over"
  exit 0
fi

LOCAL_FOREIGN=""
if ! upgrade_branch_local "$ROOT" "the company folder" "the company folder" upgrade/v1; then
  LOCAL_FOREIGN=" root "
fi
for area in "$ROOT"/areas/*; do
  [ -e "$area/.git" ] || continue
  if ! upgrade_branch_local "$area" "areas/$(basename "$area")" "areas/$(basename "$area")" upgrade/scripts; then
    LOCAL_FOREIGN="${LOCAL_FOREIGN} areas/$(basename "$area") "
  fi
done

# The v0 logs branch: the local one, else origin/logs. A fresh clone has only origin/logs.
# A local logs that is not the same as origin/logs stops a real run: one of them has
# logs the other lacks. A real run makes the local branch from origin/logs when needed.
logs_source() {
  local dir=$1 label=$2 has_local=0 has_remote=0
  git -C "$dir" show-ref --verify --quiet refs/heads/logs && has_local=1
  if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    if [ "$HOST_ON" -eq 1 ]; then
      os_with_git_token git -C "$dir" fetch -q origin "+refs/heads/logs:refs/remotes/origin/logs" >/dev/null 2>&1 || true
    else
      git -C "$dir" fetch -q origin "+refs/heads/logs:refs/remotes/origin/logs" >/dev/null 2>&1 || true
    fi
  fi
  git -C "$dir" show-ref --verify --quiet refs/remotes/origin/logs && has_remote=1
  if [ "$has_local" -eq 1 ] && [ "$has_remote" -eq 1 ] \
    && [ "$(git -C "$dir" rev-parse logs)" != "$(git -C "$dir" rev-parse origin/logs)" ]; then
    if [ "$DRY" -eq 1 ]; then
      printf 'conflict: logs %s: the local logs branch is not the same as origin/logs\n' "$label"
      return 0
    fi
    os_die 2 "${label}: the local logs branch is not the same as origin/logs. Make them match first: push the local one (git push origin logs), or, if it is only behind, git branch -f logs origin/logs. Then run upgrade again."
  fi
  [ "$has_local" -eq 1 ] && return 0
  [ "$has_remote" -eq 1 ] || return 1
  if [ "$DRY" -eq 0 ]; then
    git -C "$dir" branch -q logs origin/logs
  fi
  return 0
}

V0_LOGS=0
V0_LINKS=0
V0_LEVEL=0
V0_FOLDER=0
if logs_source "$ROOT" "the company"; then
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
  if [ -n "$PLAN_FINDING" ]; then
    printf 'finding: plan: %s\n' "$PLAN_FINDING"
    printf '%s\n' "finding: plan blocks: check tools on main, protect, and the upgrade pull requests. A real run stops before any change."
  fi
else
  if [ "$V0_LOGS" -eq 0 ] && [ "$V0_LINKS" -eq 0 ] && [ "$V0_LEVEL" -eq 0 ] && [ "$V0_FOLDER" -eq 0 ]; then
    os_die 2 "not a v0 folder"
  fi
fi

[ "$V0_LOGS" -eq 1 ] && printf '%s\n' "v0: logs-branch"
[ "$V0_LINKS" -eq 1 ] && printf '%s\n' "v0: no-links"
[ "$V0_LEVEL" -eq 1 ] && printf '%s\n' "v0: no-level"
[ "$V0_FOLDER" -eq 1 ] && printf '%s\n' "v0: logs-folder"

# Teammates with an old logs branch: the company or an area has one, and a host.
TEAM_LOGS=0
if git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
  if [ "$V0_LOGS" -eq 1 ]; then
    TEAM_LOGS=1
  else
    for area in "$ROOT"/areas/*; do
      [ -e "$area/.git" ] || continue
      if git -C "$area" show-ref --quiet --verify refs/heads/logs \
        || git -C "$area" show-ref --quiet --verify refs/remotes/origin/logs; then
        TEAM_LOGS=1
      fi
    done
  fi
fi
if [ "$TEAM_LOGS" -eq 1 ]; then
  printf '%s\n' 'log-freeze: before the real run, every teammate saves their logs in each folder that has memory/logs: git -C memory/logs add -A, git -C memory/logs commit -m "Logs: before v1", git -C memory/logs pull --rebase, git -C memory/logs push. Nobody writes a log until the upgrade pull requests merge.'
fi

HASHES="$DIR/v0-hashes.txt"
[ -f "$HASHES" ] || os_die 3 "v0-hashes.txt is missing"

# die=1 stops the real run. Dry run only prints.
preflight_spills() {
  local die=$1 path rel hit=0 area name
  if [ -f "$ROOT/company-rules.md" ] \
    || git -C "$ROOT" cat-file -e main:company-rules.md 2>/dev/null; then
    printf '%s\n' "conflict: company-rules.md exists"
    hit=1
  fi
  if [ -d "$ROOT/areas" ]; then
    for path in "$ROOT"/areas/*/area-rules.md; do
      [ -f "$path" ] || continue
      rel=${path#"$ROOT"/}
      printf 'conflict: %s exists\n' "$rel"
      hit=1
    done
    # Hosted areas are checked after fetch, against origin/main.
    if ! preflight_wants_host; then
      for area in "$ROOT"/areas/*; do
        [ -d "$area" ] || continue
        [ -e "$area/.git" ] || continue
        name=$(basename "$area")
        rel="areas/$name/area-rules.md"
        [ -f "$area/area-rules.md" ] && continue
        if git -C "$area" cat-file -e "main:area-rules.md" 2>/dev/null; then
          printf 'conflict: %s exists\n' "$rel"
          hit=1
        fi
      done
    fi
  fi
  if [ "$hit" -eq 1 ] && [ "$die" -eq 1 ]; then
    exit 2
  fi
}

preflight_wants_host() {
  local kind=""
  if [ -n "${ANSWERS:-}" ] && [ -f "$ANSWERS" ]; then
    kind=$(os_answer_or host "$ANSWERS" "")
  fi
  if [ -z "$kind" ] && [ -f "$ROOT/company-profile.md" ]; then
    kind=$(os_fm_get "$ROOT/company-profile.md" host 2>/dev/null || true)
  fi
  case "$kind" in
    github|forgejo) ;;
    *) return 1 ;;
  esac
  os_find_host "$ROOT" "$DIR" >/dev/null
}

preflight_areas() {
  local die=$1 area name rel repo slug found=0 bin
  [ -d "$ROOT/areas" ] || return 0
  slug=$(os_fm_get "$ROOT/company-profile.md" company_slug 2>/dev/null || true)
  if [ -n "${ANSWERS:-}" ] && [ -f "$ANSWERS" ]; then
    case "$slug" in
      ""|*'{{'*) slug=$(os_answer_or slug "$ANSWERS" "$slug") ;;
    esac
    case "$slug" in
      ""|*'{{'*) slug=$(os_answer_or company_slug "$ANSWERS" "$slug") ;;
    esac
  fi
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    [ -e "$area/.git" ] || continue
    name=$(basename "$area")
    rel="areas/$name"
    if [ -n "$(git -C "$area" status --porcelain)" ]; then
      printf 'the area %s has uncommitted changes. Commit or stash them, then run upgrade again.\n' "$rel" >&2
      found=1
      if [ "$die" -eq 1 ]; then
        exit 2
      fi
    fi
    if [ -e "$area/memory/logs/.git" ] && [ -n "$(git -C "$area/memory/logs" status --porcelain)" ]; then
      printf '%s/memory/logs has uncommitted changes. Commit them on the logs branch, then run upgrade again.\n' "$rel" >&2
      found=1
      if [ "$die" -eq 1 ]; then
        exit 2
      fi
    fi
  done
  [ "$found" -eq 0 ] || return 0
  preflight_wants_host || return 0
  bin=$(os_find_host "$ROOT" "$DIR")
  export OS_HOST_BIN="$bin"
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    [ -e "$area/.git" ] || continue
    name=$(basename "$area")
    rel="areas/$name"
    repo=$rel
    case "$slug" in
      ""|*'{{'*) ;;
      *) repo=$(os_area_repo "$slug" "$name") ;;
    esac
    if [ "$die" -eq 0 ]; then
      if ! (os_with_git_token git -C "$area" fetch origin); then
        printf 'could not fetch %s\n' "$repo" >&2
        continue
      fi
    elif ! os_with_git_token git -C "$area" fetch origin; then
      printf 'could not fetch %s\n' "$repo" >&2
      exit 3
    fi
    if git -C "$area" cat-file -e "origin/main:area-rules.md" 2>/dev/null \
      && [ ! -f "$area/area-rules.md" ]; then
      printf 'conflict: areas/%s/area-rules.md exists\n' "$name"
      if [ "$die" -eq 1 ]; then
        exit 2
      fi
    fi
  done
}

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

# .agents/skills and .claude/skills. A folder of copies is not a link.
# Never ln -sfn onto that folder: it nests a link inside the copies.
skill_link_hash() {
  awk -v p="$1" '$2 == p { print $1; exit }' "$HASHES"
}

fix_skill_link() {
  local repo=$1 linkrel=$2 write=$3
  local dest="$repo/$linkrel" target conflict rel f got want moves tracked unsafe
  if [ -L "$dest" ]; then
    target=$(readlink "$dest")
    if [ "$target" = "../skills" ]; then
      return 0
    fi
    printf 'change: %s\n' "$linkrel"
    if [ "$write" = "1" ]; then
      rm -f "$dest"
      mkdir -p "$(dirname "$dest")" "$repo/skills"
      ln -s ../skills "$dest"
      git -C "$repo" add -- "$linkrel"
    fi
    return 0
  fi
  if [ ! -e "$dest" ] || [ ! -d "$dest" ]; then
    printf 'change: %s\n' "$linkrel"
    if [ "$write" = "1" ]; then
      if [ -e "$dest" ]; then
        if git -C "$repo" ls-files --error-unmatch -- "$linkrel" >/dev/null 2>&1; then
          git -C "$repo" rm -q -- "$linkrel"
        else
          rm -f "$dest"
        fi
      fi
      mkdir -p "$(dirname "$dest")" "$repo/skills"
      ln -s ../skills "$dest"
      git -C "$repo" add -- "$linkrel"
    fi
    return 0
  fi
  conflict=0
  moves=$(mktemp)
  : > "$moves"
  tracked=0
  if git -C "$repo" ls-files -- "$linkrel" | grep -q .; then
    tracked=1
  fi
  if [ "$tracked" -eq 0 ]; then
    unsafe=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ -L "$f" ]; then
        unsafe=1
        break
      fi
      rel="${f#"$dest"/}"
      if [ -f "$repo/skills/$rel" ] && cmp -s "$f" "$repo/skills/$rel"; then
        continue
      fi
      want=$(skill_link_hash "skills/$rel")
      if [ -n "$want" ] && [ "$(os_sha "$f")" = "$want" ]; then
        continue
      fi
      unsafe=1
      break
    done < <(find "$dest" \( -type f -o -type l \) -print)
    if [ "$unsafe" -eq 1 ]; then
      printf 'conflict: %s (untracked; commit it first)\n' "$linkrel"
      rm -f "$moves"
      return 0
    fi
    printf 'change: %s\n' "$linkrel"
    if [ "$write" = "1" ]; then
      rm -rf "$dest"
      mkdir -p "$(dirname "$dest")" "$repo/skills"
      ln -s ../skills "$dest"
      git -C "$repo" add -- "$linkrel"
    fi
    rm -f "$moves"
    return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$dest"/}"
    if [ -L "$f" ]; then
      if [ -L "$repo/skills/$rel" ] && [ "$(readlink "$f")" = "$(readlink "$repo/skills/$rel")" ]; then
        continue
      fi
      if [ ! -e "$repo/skills/$rel" ] && [ ! -L "$repo/skills/$rel" ]; then
        printf '%s\n' "$rel" >> "$moves"
        continue
      fi
      printf 'conflict: %s/%s\n' "$linkrel" "$rel"
      conflict=1
      continue
    fi
    if [ -f "$repo/skills/$rel" ] && cmp -s "$f" "$repo/skills/$rel"; then
      continue
    fi
    want=$(skill_link_hash "skills/$rel")
    if [ -n "$want" ]; then
      got=$(os_sha "$f")
      if [ "$got" = "$want" ]; then
        continue
      fi
    fi
    if [ ! -e "$repo/skills/$rel" ]; then
      printf '%s\n' "$rel" >> "$moves"
      continue
    fi
    printf 'conflict: %s/%s\n' "$linkrel" "$rel"
    conflict=1
  done < <(find "$dest" \( -type f -o -type l \) -print)
  if [ "$conflict" -eq 1 ]; then
    printf 'conflict: %s left: resolve the files above first\n' "$linkrel"
    rm -f "$moves"
    return 0
  fi
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf 'change: skill-moved skills/%s\n' "$rel"
    if [ "$write" = "1" ]; then
      mkdir -p "$(dirname "$repo/skills/$rel")"
      if [ -L "$dest/$rel" ]; then
        cp -Pp "$dest/$rel" "$repo/skills/$rel"
      else
        cp -p "$dest/$rel" "$repo/skills/$rel"
      fi
      git -C "$repo" add -- "skills/$rel"
    fi
  done < "$moves"
  rm -f "$moves"
  printf 'change: %s\n' "$linkrel"
  if [ "$write" != "1" ]; then
    return 0
  fi
  if git -C "$repo" ls-files -- "$linkrel" | grep -q .; then
    git -C "$repo" rm -r -q -- "$linkrel"
  fi
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    rm -rf "$dest"
  fi
  mkdir -p "$(dirname "$dest")" "$repo/skills"
  ln -s ../skills "$dest"
  git -C "$repo" add -- "$linkrel"
}

fix_skill_links() {
  local repo=$1 write=$2
  fix_skill_link "$repo" .agents/skills "$write"
  fix_skill_link "$repo" .claude/skills "$write"
}

# A folder already at team level keeps its owner files. Add the spill names if missing.
ensure_spill_owners() {
  local root=$1 gh gitea owners
  gh="$root/.github/CODEOWNERS"
  if [ -f "$gh" ] && ! grep -q '/company-rules.md' "$gh"; then
    owners=$(awk '$1 == "/AGENTS.md" { $1=""; sub(/^ /, ""); print; exit }' "$gh")
    if [ -n "$owners" ]; then
      awk -v o="$owners" '
        $1 == "/CLAUDE.md" && !done {
          print
          print "/company-rules.md " o
          print "/area-rules.md " o
          done = 1
          next
        }
        { print }
        END {
          if (!done) {
            print "/company-rules.md " o
            print "/area-rules.md " o
          }
        }
      ' "$gh" > "$gh.tmp"
      mv "$gh.tmp" "$gh"
    fi
  fi
  gitea="$root/.gitea/CODEOWNERS"
  if [ -f "$gitea" ] && ! grep -q 'company-rules' "$gitea"; then
    owners=$(awk '$1 == "^AGENTS\\.md$" { $1=""; sub(/^ /, ""); print; exit }' "$gitea")
    if [ -n "$owners" ]; then
      awk -v o="$owners" '
        $1 == "^CLAUDE\\.md$" && !done {
          print
          print "^company-rules\\.md$ " o
          print "^area-rules\\.md$ " o
          done = 1
          next
        }
        { print }
        END {
          if (!done) {
            print "^company-rules\\.md$ " o
            print "^area-rules\\.md$ " o
          }
        }
      ' "$gitea" > "$gitea.tmp"
      mv "$gitea.tmp" "$gitea"
    fi
  fi
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -f "$gh" ]; then
      git -C "$root" add -- .github/CODEOWNERS
    fi
    if [ -f "$gitea" ]; then
      git -C "$root" add -- .gitea/CODEOWNERS
    fi
  fi
}

fill_profile_one_liner() {
  local val cur
  [ -n "${ANSWERS:-}" ] && [ -f "$ANSWERS" ] || return 0
  val=$(os_answer_or one_liner "$ANSWERS" "")
  [ -n "$val" ] || return 0
  [ -f "$ROOT/company-profile.md" ] || return 0
  cur=$(os_fm_get "$ROOT/company-profile.md" summary 2>/dev/null || true)
  case "$cur" in
    '{{ONE_LINER}}')
      os_fm_set "$ROOT/company-profile.md" summary "$(os_yaml_quote "$val")"
      ;;
  esac
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
  if [ "$same" -eq 1 ] && [ "$V0_LOGS" -eq 0 ]; then
    # Never delete the logs skill unless the logs move runs.
    printf '%s\n' "keep: skills/logs-folder (no logs branch here or on origin, so no logs move)"
  elif [ "$same" -eq 1 ]; then
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
fix_skill_links "$ROOT" 0
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

# How an upgrade pull request merges. GitHub team: by the admin's bypass click, so it
# never gets auto-merge (that hides the bypass box). Forgejo team: auto-merge.
pr_merge_word() {
  if [ "$TEAM_ON" -eq 1 ] && [ "$UP_HOST" = "github" ]; then
    printf '%s\n' merge-by-hand
  else
    printf '%s\n' auto-merge
  fi
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
    printf 'pr-plan: %s branch upgrade/scripts files %s %s\n' "$repo" "$files" "$(pr_merge_word)"
    if logs_source "$area" "areas/${name}"; then
      printf 'change: logs-history areas/%s\n' "$name"
    fi
    rules_one_area "$area" 0
    fix_skill_links "$area" 0
  done
}
plan_area_scripts

# Host on: the checks run their tools from main, so main gets them before any pull request.
plan_host_steps() {
  local area
  [ "$HOST_ON" -eq 1 ] || return 0
  if [ -z "$SLUG" ]; then
    printf '%s\n' "todo: answer slug (the company slug; repos are <slug>-os and <slug>-<area>)"
    return 0
  fi
  [ "$TEAM_ON" -eq 1 ] || return 0
  printf 'change: checks-on-main %s\n' "$(os_company_repo "$SLUG")"
  printf 'change: protect %s\n' "$(os_company_repo "$SLUG")"
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    [ -e "$area/.git" ] || continue
    printf 'change: checks-on-main %s\n' "$(os_area_repo "$SLUG" "$(basename "$area")")"
    printf 'change: protect %s\n' "$(os_area_repo "$SLUG" "$(basename "$area")")"
  done
  if [ -z "$(os_answer_or review_vendor "${ANSWERS:-/dev/null}" "")" ]; then
    printf '%s\n' "todo: answer review_vendor (anthropic, openai or xai) for .github/review.conf"
  fi
}
plan_host_steps

# Each upgrade branch, in the folder and on the host. An earlier run's own branch is
# replaced. Someone else's commits stop a real run, before any change.
upgrade_branch_check() {
  local dir=$1 where=$2 repo=$3 branch=$4 key=$5 side="" ok
  case "$LOCAL_FOREIGN" in
    *" ${key} "*) side=local ;;
  esac
  if [ "$HOST_ON" -eq 1 ] && [ -n "$SLUG" ] && git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    if [ "$DRY" -eq 1 ]; then
      ok=0
      (os_with_git_token git -C "$dir" fetch -q --prune origin) || ok=1
    else
      ok=0
      os_with_git_token git -C "$dir" fetch -q --prune origin || ok=1
    fi
    if [ "$ok" -ne 0 ]; then
      printf 'could not fetch %s\n' "$repo" >&2
      [ "$DRY" -eq 1 ] || exit 3
    elif git -C "$dir" rev-parse -q --verify "refs/remotes/origin/${branch}" >/dev/null; then
      if upgrade_made "$dir" "refs/remotes/origin/${branch}"; then
        printf 'change: replace %s %s (an earlier upgrade run made it; its pull request is reused)\n' "$repo" "$branch"
      else
        side=${side:+both}
        side=${side:-host}
      fi
    fi
  fi
  [ -z "$side" ] || foreign_branch "$where" "$repo" "$branch" "$side"
}

preflight_upgrade_branches() {
  local area name repo=root
  [ "$HOST_ON" -eq 1 ] && [ -n "$SLUG" ] && repo=$(os_company_repo "$SLUG")
  upgrade_branch_check "$ROOT" "the company folder" "$repo" upgrade/v1 root
  for area in "$ROOT"/areas/*; do
    [ -e "$area/.git" ] || continue
    name=$(basename "$area")
    repo="areas/${name}"
    [ "$HOST_ON" -eq 1 ] && [ -n "$SLUG" ] && repo=$(os_area_repo "$SLUG" "$name")
    upgrade_branch_check "$area" "areas/${name}" "$repo" upgrade/scripts "areas/${name}"
  done
  if [ "$FOREIGN" -eq 1 ] && [ "$DRY" -eq 0 ]; then
    exit 2
  fi
}

preflight_spills 0
preflight_areas 0

if [ "$DRY" -eq 1 ]; then
  preflight_upgrade_branches
  exit 0
fi

preflight_spills 1
preflight_areas 1
preflight_upgrade_branches

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

author_env() {
  GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    "$@"
}

# The checks job copies its tools from main, never from the pull request head.
# A v0 main has none, so an upgrade pull request could never pass its checks.
# Like team-on: lift protection, push one commit with only the check files to main,
# then protect with the v1 rules (this also replaces a v0 classic rule and turns on auto-merge).
# The release of a set of check tools: digits in .github/scripts/tools-release.
# Tools from before the marker are release 0.
tools_release() {
  local rel
  rel=$(tr -cd '0-9' < "$1" 2>/dev/null || true)
  printf '%s\n' "${rel:-0}"
}

checks_on_main() {
  local dir=$1 repo=$2 tmp err owners first f done_line main_rel new_rel
  if ! os_with_git_token git -C "$dir" fetch origin; then
    os_die 3 "could not fetch ${repo}"
  fi
  tmp=$(mktemp -d)
  git -C "$dir" worktree add -q --detach "$tmp/main" origin/main
  if [ -f "$tmp/main/.github/workflows/checks.yml" ] \
    && [ -f "$tmp/main/.github/scripts/checkout.sh" ] \
    && [ -f "$tmp/main/.github/scripts/tools/secret-scan.sh" ] \
    && [ -f "$tmp/main/.github/review.conf" ]; then
    # main has check tools. The checks run them from main, so a fix in a newer release
    # reaches the company only here. Never put older tools over newer ones.
    main_rel=$(tools_release "$tmp/main/.github/scripts/tools-release")
    new_rel=$(tools_release "$TEMPLATE/.github/scripts/tools-release")
    cp "$TEMPLATE/.github/workflows/checks.yml" "$tmp/main/.github/workflows/checks.yml"
    rm -rf "$tmp/main/.github/scripts"
    cp -R "$TEMPLATE/.github/scripts" "$tmp/main/.github/scripts"
    git -C "$tmp/main" add -A -- .github/workflows/checks.yml .github/scripts
    if git -C "$tmp/main" diff --cached --quiet; then
      done_line="checks-on-main: ${repo} already"
    elif [ "$main_rel" -ge "$new_rel" ]; then
      done_line="checks-on-main: ${repo} already: kept the check tools on main (release ${main_rel}; this upgrade has ${new_rel})"
    else
      author_env git -C "$tmp/main" commit -q -m "Upgrade: update check tools on main"
      done_line="checks-on-main: ${repo} updated the check tools on main (release ${main_rel} to ${new_rel})"
    fi
    if [ "$(git -C "$tmp/main" rev-parse HEAD)" = "$(git -C "$dir" rev-parse origin/main)" ]; then
      git -C "$dir" worktree remove --force "$tmp/main" >/dev/null 2>&1 || true
      rm -rf "$tmp"
      printf '%s\n' "$done_line"
      reprotect "$repo"
      printf 'protected: %s\n' "$repo"
      return 0
    fi
  else
    done_line="checks-on-main: ${repo}"
    mkdir -p "$tmp/main/.github/workflows"
    cp "$TEMPLATE/.github/workflows/checks.yml" "$tmp/main/.github/workflows/checks.yml"
    rm -rf "$tmp/main/.github/scripts"
    cp -R "$TEMPLATE/.github/scripts" "$tmp/main/.github/scripts"
    if [ ! -f "$tmp/main/.github/review.conf" ]; then
      printf 'vendor=%s\nmodel=%s\nkind=%s\n' "$REVIEW_VENDOR" "$REVIEW_MODEL" "$REVIEW_KIND" > "$tmp/main/.github/review.conf"
    fi
    # v0 owned every file ("* @admin"). v1 owns rules files only, so notes merge on green checks.
    # Replace only that stock line. Every line the company added stays, after the rules lines,
    # so it still wins where it did before (the last matching line wins).
    owners=""
    if [ -f "$tmp/main/.github/CODEOWNERS" ]; then
      owners=$(awk '$1 == "*" { $1 = ""; sub(/^ /, ""); print; exit }' "$tmp/main/.github/CODEOWNERS")
    fi
    if [ -n "$owners" ]; then
      first=${owners%% *}
      for f in .github/CODEOWNERS .gitea/CODEOWNERS; do
        : > "$tmp/keep"
        if [ -f "$tmp/main/$f" ]; then
          awk '$1 == "*" || $1 == ".*" { next } { print }' "$tmp/main/$f" > "$tmp/keep"
        fi
        mv "$tmp/keep" "$tmp/keep-${f%%/*}"
      done
      os_codeowners "$tmp/main" "$owners" "$first"
      for f in .github/CODEOWNERS .gitea/CODEOWNERS; do
        if grep -q '[^[:space:]]' "$tmp/keep-${f%%/*}"; then
          { printf '\n%s\n' "# Kept from before the upgrade."; cat "$tmp/keep-${f%%/*}"; } >> "$tmp/main/$f"
        fi
        rm -f "$tmp/keep-${f%%/*}"
      done
      git -C "$tmp/main" add -- .github/CODEOWNERS .gitea/CODEOWNERS
    fi
    git -C "$tmp/main" add -- .github/workflows/checks.yml .github/scripts .github/review.conf
    author_env git -C "$tmp/main" commit -q -m "Upgrade: check tools on main"
  fi
  # unprotect lifts the v1 rulesets and, on GitHub, the v0 classic rule. Both would
  # refuse this push. From here until protect, every way out puts protection back
  # (upgrade_on_exit covers a stop this function does not catch).
  UNPROTECTED=$repo
  os_host unprotect "$repo" >/dev/null
  err=$(mktemp)
  if ! os_with_git_token git -C "$tmp/main" push origin HEAD:refs/heads/main 2>"$err"; then
    cat "$err" >&2
    git -C "$dir" worktree remove --force "$tmp/main" >/dev/null 2>&1 || true
    rm -rf "$tmp"
    reprotect "$repo"
    if grep -qi 'workflow' "$err"; then
      rm -f "$err"
      os_die 3 "push refused for ${repo}: the sign-in cannot write workflow files. Add the workflow scope: gh auth refresh -s workflow. Then run upgrade again. Protection on ${repo} is back on."
    fi
    rm -f "$err"
    os_die 3 "could not put the check tools on main of ${repo}. Protection on ${repo} is back on. Fix the push, then run upgrade again."
  fi
  rm -f "$err"
  git -C "$dir" worktree remove --force "$tmp/main" >/dev/null 2>&1 || true
  rm -rf "$tmp"
  os_with_git_token git -C "$dir" fetch origin >/dev/null 2>&1 || true
  printf '%s\n' "$done_line"
  reprotect "$repo"
  printf 'protected: %s\n' "$repo"
}

# Protect main with the v1 rules. If that fails, say plainly that main is open.
reprotect() {
  local repo=$1
  UNPROTECTED=""
  if ! os_host_try protect "$repo" --code-owners --approvals 0 >/dev/null; then
    os_die 3 "PROTECTION IS OFF on ${repo}: run skills/_host/host.sh protect ${repo} --code-owners --approvals 0"
  fi
}

# Any exit between unprotect and protect (a host error, set -e) protects main again,
# or prints that main is open.
UNPROTECTED=""
upgrade_on_exit() {
  local rc=$? repo=$UNPROTECTED
  # This trap replaces the one add-teammate/lib.sh set. The temp folder goes last: protect
  # below still needs it.
  if [ -z "$repo" ]; then
    os_cleanup
    return "$rc"
  fi
  UNPROTECTED=""
  if os_host_try protect "$repo" --code-owners --approvals 0 >/dev/null 2>&1; then
    printf 'upgrade stopped. Protection on %s is back on.\n' "$repo" >&2
  else
    printf 'PROTECTION IS OFF on %s: run skills/_host/host.sh protect %s --code-owners --approvals 0\n' "$repo" "$repo" >&2
  fi
  [ "$rc" -ne 0 ] || rc=3
  os_cleanup
  exit "$rc"
}
trap upgrade_on_exit EXIT

REVIEW_VENDOR=""
REVIEW_MODEL=""
REVIEW_KIND=""
if [ -n "$ANSWERS" ]; then
  REVIEW_VENDOR=$(os_answer_or review_vendor "$ANSWERS" "")
  REVIEW_MODEL=$(os_answer_or review_model "$ANSWERS" "")
  REVIEW_KIND=$(os_answer_or review_kind "$ANSWERS" "")
fi
case "$REVIEW_VENDOR" in
  ""|anthropic|openai|xai) ;;
  *) os_die 2 "review_vendor must be anthropic, openai, or xai" ;;
esac
if [ -z "$REVIEW_KIND" ]; then
  if [ -n "$REVIEW_VENDOR" ]; then
    REVIEW_KIND="second-vendor"
  else
    REVIEW_KIND="same-vendor"
  fi
fi

if [ "$HOST_ON" -eq 1 ]; then
  case "$SLUG" in
    ""|*'{{'*) os_die 2 "the company slug is not known. Add slug=<slug> to the answers file, then run upgrade again." ;;
  esac
fi
if [ "$TEAM_ON" -eq 1 ]; then
  printf '%s\n' "review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY"
  if [ "$(os_review_state)" != "key-set" ]; then
    printf '%s\n' "no review key yet: the checks fail until the admin runs the review command above"
  fi
  checks_on_main "$ROOT" "$(os_company_repo "$SLUG")"
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    [ -e "$area/.git" ] || continue
    checks_on_main "$area" "$(os_area_repo "$SLUG" "$(basename "$area")")"
  done
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
  # memory/logs-archive/, outside memory/logs/: a teammate's old clone has its logs
  # worktree at memory/logs/, which its main ignores. Its first plain git pull writes over
  # any ignored file in the way, so main puts nothing under memory/logs/ (sync push holds
  # logs there until the host's logs branch is deleted).
  git -C "$tmp/logs" filter-repo --to-subdirectory-filter memory/logs-archive --force
  git -C "$ROOT" remote remove logs-prefixed 2>/dev/null || true
  git -C "$ROOT" remote add logs-prefixed "$tmp/logs"
  git -C "$ROOT" fetch --quiet logs-prefixed
  git -C "$ROOT" merge --allow-unrelated-histories --no-commit logs-prefixed/logs
  git -C "$ROOT" remote remove logs-prefixed
  rm -rf "$tmp"
fi

fix_skill_links "$ROOT" 1

if [ -f "$ROOT/.gitignore" ]; then
  grep -v '^/memory/logs/$' "$ROOT/.gitignore" | grep -v 'skills/logs-folder' > "$ROOT/.gitignore.tmp" || true
  mv "$ROOT/.gitignore.tmp" "$ROOT/.gitignore"
fi

OS_VER=""
if [ -n "$ANSWERS" ]; then
  OS_VER=$(os_answer_or os_version "$ANSWERS" "")
  HOST_KIND=$(os_answer_or host "$ANSWERS" "")
  ORG=$(os_answer_or org "$ANSWERS" "")
  ENGINE=$(os_answer_or sync_engine "$ANSWERS" "")
  RUNNER=$(os_answer_or runner "$ANSWERS" "")
fi
[ -n "${OS_VER:-}" ] || OS_VER="v1.0.0"
case "$OS_VER" in
  *'{{'*) OS_VER="v1.0.0" ;;
esac

os_fm_set "$ROOT/company-profile.md" level "$LEVEL"
if [ -n "$SLUG" ]; then
  os_fm_set "$ROOT/company-profile.md" company_slug "$SLUG"
fi
fill_profile_one_liner
ensure_spill_owners "$ROOT"
if ! os_fm_get "$ROOT/company-profile.md" switches >/dev/null 2>&1; then
  os_fm_set "$ROOT/company-profile.md" switches "[]"
fi
os_fm_set "$ROOT/company-profile.md" os_version "$OS_VER"
if [ -n "${HOST_KIND:-}" ]; then
  os_fm_set "$ROOT/company-profile.md" host "$HOST_KIND"
elif [ -z "$(os_fm_get "$ROOT/company-profile.md" host 2>/dev/null || true)" ]; then
  # No host answer and none in the profile: write it like the template does.
  os_fm_set "$ROOT/company-profile.md" host none
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

# v0 kept area logs on a logs branch too, checked out at memory/logs/.
# Run before the area checkout: drop the worktree and tag the old tip.
area_logs_park() {
  local area=$1 name
  name=$(basename "$area")
  logs_source "$area" "areas/${name}" || return 0
  if [ -e "$area/memory/logs/.git" ]; then
    if ! git -C "$area" worktree remove --force "$area/memory/logs"; then
      os_die 3 "could not remove the logs worktree in areas/${name}. Upgrade stopped. The logs files are still in place."
    fi
  fi
  if ! git -C "$area" rev-parse --verify "refs/tags/logs-archive-$(os_today)" >/dev/null 2>&1; then
    git -C "$area" tag -a "logs-archive-$(os_today)" logs -m "Kept for 90 days. Delete this tag after 90 days."
  fi
}

# Then merge the logs under memory/logs-archive/ with their history, on the area branch.
area_logs_merge() {
  local area=$1 name tmp
  name=$(basename "$area")
  git -C "$area" show-ref --verify --quiet refs/heads/logs || return 0
  if git -C "$area" merge-base --is-ancestor logs HEAD 2>/dev/null; then
    return 0
  fi
  tmp=$(mktemp -d)
  git clone --quiet --branch logs --single-branch "$area" "$tmp/logs"
  git -C "$tmp/logs" filter-repo --to-subdirectory-filter memory/logs-archive --force
  git -C "$area" fetch --quiet "$tmp/logs" "logs:refs/os-upgrade/logs"
  rm -rf "$tmp"
  if git -C "$area" merge-base --is-ancestor refs/os-upgrade/logs HEAD 2>/dev/null; then
    git -C "$area" update-ref -d refs/os-upgrade/logs
    return 0
  fi
  author_env git -C "$area" merge -q --allow-unrelated-histories -m "Upgrade: logs history" refs/os-upgrade/logs
  git -C "$area" update-ref -d refs/os-upgrade/logs
  if [ -f "$area/.gitignore" ]; then
    grep -v '^/memory/logs/$' "$area/.gitignore" | grep -v 'skills/logs-folder' > "$area/.gitignore.tmp" || true
    mv "$area/.gitignore.tmp" "$area/.gitignore"
    git -C "$area" add -- .gitignore
  fi
  printf 'change: logs-history areas/%s\n' "$name"
}

# Area folders are separate repos. /areas/ is gitignored in the company repo.
# Commit the scripts in each area repo and open a pull request. Never git add them here.
# Pull requests that will not merge by themselves. upgrade: ok only when there are none.
HAND=""
pr_merge_path() {
  local repo=$1 number=$2
  if [ "$TEAM_ON" -ne 1 ]; then
    # Solo: no protection and no auto-merge. The person merges.
    HAND="${HAND:+${HAND}, }${repo} ${number}"
    return 0
  fi
  if [ "$UP_HOST" = "github" ]; then
    # The admin wrote it and it changes rules files. GitHub never counts the author's own
    # code-owner approval. The admin bypass on rules-review is a click on the merge box.
    # Auto-merge stays off: with it on, GitHub shows "Disable auto-merge" in place of
    # that box.
    printf 'merge-by-hand: %s %s: it will not merge by itself. When its checks are green, the admin opens it, ticks "Merge without waiting for requirements to be met (bypass rules)" and clicks "Bypass rules and merge".\n' \
      "$repo" "$number"
    HAND="${HAND:+${HAND}, }${repo} ${number}"
    return 0
  fi
  if ! os_host_try auto-merge "$repo" "$number" >/dev/null; then
    printf 'auto-merge is off on %s: pull request %s stays open until the admin merges it.\n' "$repo" "$number"
    HAND="${HAND:+${HAND}, }${repo} ${number}"
  fi
}

# Push an upgrade branch. Replace the host's copy only when an earlier upgrade run made
# it, and only if it has not moved since this run looked (force-with-lease).
push_upgrade_branch() {
  local dir=$1 where=$2 repo=$3 branch=$4 expect=""
  shift 4
  if ! os_with_git_token git -C "$dir" fetch -q --prune origin; then
    os_die 3 "could not fetch ${repo}"
  fi
  if git -C "$dir" rev-parse -q --verify "refs/remotes/origin/${branch}" >/dev/null; then
    if ! upgrade_made "$dir" "refs/remotes/origin/${branch}"; then
      foreign_branch "$where" "$repo" "$branch" host
      exit 2
    fi
    expect=$(git -C "$dir" rev-parse "refs/remotes/origin/${branch}")
  fi
  if ! os_with_git_token git -C "$dir" push "$@" --force-with-lease="refs/heads/${branch}:${expect}" \
    origin "HEAD:refs/heads/${branch}"; then
    os_die 3 "could not push ${branch} for ${repo}. The host branch changed while the upgrade ran. Run upgrade again."
  fi
  if [ -n "$expect" ]; then
    printf 'replaced: %s %s (an earlier upgrade run made it)\n' "$repo" "$branch"
  fi
}

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
    area_logs_park "$area"
    git -C "$area" checkout -q -B "$branch" origin/main
    area_logs_merge "$area"
    rules_one_area "$area" 1
    rules_stage_rules "$area"
    if ! git -C "$area" diff --cached --quiet; then
      rules_commit_msg "$area" "Upgrade: rules merge"
    fi
    fix_skill_links "$area" 1
    ensure_spill_owners "$area"
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
    push_upgrade_branch "$area" "areas/${name}" "$repo" "$branch"
    push_logs_tags "$area" "$repo"
    area_body=$(mktemp)
    rules_pr_body "$area" origin/main "$area_body"
    pr=$(os_host open-pr "$repo" --head "$branch" --base main --title "Upgrade: check scripts" --body-file "$area_body")
    rm -f "$area_body"
    number=$(printf '%s' "$pr" | jq -r '.number // empty')
    if [ -z "$number" ]; then
      os_die 3 "could not open a pull request for ${repo}"
    fi
    printf 'pr: %s %s\n' "$repo" "$number"
    pr_merge_path "$repo" "$number"
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
    git -C "$ROOT" add -A -- skills
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

# Every clone needs the snapshot tag: sync pull brings in logs pushed to the old logs
# branch after it (v0logs_catch_up). Not fatal: this computer still has the tag.
push_logs_tags() {
  local dir=$1 repo=$2 tags
  tags=$(git -C "$dir" for-each-ref --format='%(refname)' 'refs/tags/logs-archive-*')
  [ -n "$tags" ] || return 0
  # shellcheck disable=SC2086
  if ! os_with_git_token git -C "$dir" push -q origin $tags >/dev/null 2>&1; then
    printf 'logs-tag: could not push the logs-archive tag to %s. Logs written to the old logs branch after this run reach main only from this computer: run skills/sync/sync.sh pull --full here after the merge.\n' "$repo"
  fi
}

if [ "$HOST_ON" -eq 1 ]; then
  push_area_scripts
  push_upgrade_branch "$ROOT" "the company folder" "$(os_company_repo "$SLUG")" upgrade/v1 --set-upstream
  push_logs_tags "$ROOT" "$(os_company_repo "$SLUG")"
  pr=$(os_host open-pr "$(os_company_repo "$SLUG")" --head upgrade/v1 --base main --title "Upgrade to v1" --body-file "$pr_body")
  number=$(printf '%s' "$pr" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    os_die 3 "could not open a pull request for $(os_company_repo "$SLUG")"
  fi
  printf 'pr: %s\n' "$number"
  pr_merge_path "$(os_company_repo "$SLUG")" "$number"
elif [ -d "$ROOT/areas" ]; then
  # No host: still merge area rules on upgrade/scripts so the folder gets v1 rules.
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    [ -e "$area/.git" ] || continue
    area_logs_park "$area"
    git -C "$area" checkout -q -B upgrade/scripts
    area_logs_merge "$area"
    rules_one_area "$area" 1
    rules_stage_rules "$area"
    fix_skill_links "$area" 1
    ensure_spill_owners "$area"
    if ! git -C "$area" diff --cached --quiet; then
      rules_commit_msg "$area" "Upgrade: rules merge"
    fi
  done
fi
rm -f "$pr_body"

if [ "$TEAM_LOGS" -eq 1 ]; then
  printf '%s\n' "teammates: in an old (v0) copy of this folder, do not run git pull. It can write over logs there. Each teammate does this instead:"
  printf '%s\n' 'teammates: 1. In the old folder, save the logs: git -C memory/logs add -A, git -C memory/logs commit -m "Logs: before v1", git -C memory/logs pull --rebase, git -C memory/logs push.'
  printf '%s\n' "teammates: 2. After the upgrade pull requests merge and the admin runs add-teammate Part A again: rename the old folder, then join as a new teammate (add-teammate Part B; on Windows join.sh runs in Git Bash). The old logs are in memory/logs-archive/. Logs pushed after this run come in by the next full sync pull."
  printf '%s\n' "teammates: 3. When the new folder has their logs, delete the old folder. A teammate who already has the v1 sync skill runs skills/sync/sync.sh pull in place of steps 1 to 3. Full steps: skills/upgrade/SKILL.md section 11."
  printf '%s\n' "admin: until the old logs branch is gone, sync push keeps logs in each folder (held), so a plain pull on an old copy can write over nothing. When every teammate has moved, delete it: git push origin --delete logs, in the company folder and in each area that had one."
fi

if [ -n "$HAND" ]; then
  if [ "$TEAM_ON" -eq 1 ] && [ "$UP_HOST" = "github" ]; then
    printf '%s\n' 'admin, on GitHub: wait for the green checks. Open each pull request. If it shows "Disable auto-merge", click that first. Tick "Merge without waiting for requirements to be met (bypass rules)". Click "Bypass rules and merge".'
  fi
  printf 'upgrade: open pull requests: %s. Merge each one when its checks pass.\n' "$HAND"
else
  printf '%s\n' "upgrade: ok"
fi
