#!/bin/bash
# Part B. Run from inside the company clone. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"

usage() {
  cat << 'EOF'
usage: join.sh --answers <file>

Run this from inside the company clone. Part B clones that repo first,
with git and the person's own sign-in. An existing clone is done.
This script does not clone the company repo again.

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
[ -f "$ROOT/company-profile.md" ] || os_die 2 "not a company clone"

ME=$(os_answer_or me "$ANSWERS" "")
[ -n "$ME" ] || os_die 2 "me is required"

SLUG=$(os_fm_get "$ROOT/company-profile.md" company_slug)
HOST_KIND=$(os_fm_get "$ROOT/company-profile.md" host)
HOST_URL=$(os_fm_get "$ROOT/company-profile.md" host_url || true)
ORG=$(os_fm_get "$ROOT/company-profile.md" org)
[ -n "$SLUG" ] || os_die 2 "company_slug is not set"
[ "$HOST_KIND" = "github" ] || [ "$HOST_KIND" = "forgejo" ] || os_die 2 "host is not set"

if ! OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
  os_die 3 "host.sh is missing"
fi
export OS_HOST_BIN OS_ORG="$ORG" OS_HOST="$HOST_KIND" OS_HOST_URL="$HOST_URL" OS_SLUG="$SLUG"
export OS_PROFILE="$ROOT/company-profile.md"

printf '%s\n' "company-clone: done"
printf '%s\n' "me: $ME"

PAGE=$(os_person_file "$ROOT" "$ME" || true)
[ -n "$PAGE" ] || os_die 2 "no people page for $ME"

AREAS=$(os_answer_or areas "$ANSWERS" "")
if [ -z "$AREAS" ]; then
  AREAS=$(os_fm_get "$PAGE" areas || true)
  AREAS=$(printf '%s' "$AREAS" | tr -d '[]' | tr ',' ' ')
fi

COMPANY_REPO=$(os_company_repo "$SLUG")

clone_one() {
  local name=$1 dest=$2 rc
  if [ -e "$dest/.git" ]; then
    printf 'cloned: %s\n' "$name"
    return 0
  fi
  set +e
  os_host repo-access "$name" >/dev/null
  rc=$?
  set -e
  if [ "$rc" -eq 2 ]; then
    printf 'skipped: %s\n' "$name"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi
  mkdir -p "$(dirname "$dest")"
  os_with_git_token git clone "$(os_clone_url "$HOST_KIND" "$HOST_URL" "$ORG" "$name")" "$dest"
  printf 'cloned: %s\n' "$name"
}

area=""
for area in $AREAS; do
  area=$(os_trim "$area")
  [ -n "$area" ] || continue
  clone_one "$(os_area_repo "$SLUG" "$area")" "$ROOT/areas/$area"
done

clone_one "$(os_user_repo "$SLUG" "$ME")" "$ROOT/users/$ME"

cfg=$(os_config_dir "$SLUG")
mkdir -p "$cfg"
printf '%s\n' "$ME" > "$cfg/me"
chmod 600 "$cfg/me"

if [ -x "$ROOT/skills/sync/sync.sh" ]; then
  "$ROOT/skills/sync/sync.sh" install-jobs
else
  printf '%s\n' "sync-jobs: skills/sync/sync.sh is not here yet"
fi

PROFILE="$ROOT/users/$ME/profile/PROFILE.md"
os_pointer() {
  local file=$1 line=$2 dir
  dir=$(dirname "$file")
  [ -d "$dir" ] || return 0
  if [ -f "$file" ] && grep -qxF "$line" "$file"; then
    return 0
  fi
  if [ -f "$file" ]; then
    printf '\n%s\n' "$line" >> "$file"
  else
    printf '%s\n' "$line" > "$file"
  fi
}

if [ -d "$HOME/.claude" ]; then
  os_pointer "$HOME/.claude/CLAUDE.md" "@${PROFILE}"
fi
if [ -d "$HOME/.codex" ]; then
  os_pointer "$HOME/.codex/AGENTS.md" "Read ${PROFILE}"
fi
if [ -d "$HOME/.pi/agent" ]; then
  os_pointer "$HOME/.pi/agent/AGENTS.md" "Read ${PROFILE}"
fi
if [ -f "$HOME/.cursor/rules.md" ]; then
  os_pointer "$HOME/.cursor/rules.md" "Read ${PROFILE}"
fi
if [ -f "$HOME/.cursor/User/rules.md" ]; then
  os_pointer "$HOME/.cursor/User/rules.md" "Read ${PROFILE}"
fi

accepted=$(os_fm_get "$PAGE" terms_accepted 2>/dev/null || true)
if [ -n "$accepted" ]; then
  printf '%s\n' "terms: already"
else
  branch="sync/${ME}"
  os_with_git_token git -C "$ROOT" fetch origin
  git -C "$ROOT" checkout -q -B "$branch" origin/main
  PAGE=$(os_person_file "$ROOT" "$ME")
  os_fm_set "$PAGE" terms_accepted "$(os_today)"
  os_git_commit "$ROOT" "Join: accept terms"
  os_with_git_token git -C "$ROOT" push --set-upstream origin "$branch"
  if [ -x "$ROOT/skills/sync/sync.sh" ]; then
    "$ROOT/skills/sync/sync.sh" propose join-terms "$PAGE" || true
  fi
  pr=$(os_host open-pr "$COMPANY_REPO" --head "$branch" --base main --title "sync: ${ME}")
  number=$(printf '%s' "$pr" | jq -r '.number // empty')
  printf 'terms: proposed\n'
  if [ -n "$number" ]; then
    printf 'pr: %s\n' "$number"
  fi
fi

printf '%s\n' "join: ok"
