#!/bin/bash
# Part B. Run from inside the company clone. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
# shellcheck disable=SC1091
. "$DIR/../sync/links.sh"

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
if sync_is_windows; then
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "install jq: winget install --id jqlang.jq -e" >&2
    exit 3
  fi
  if ! command -v gh >/dev/null 2>&1; then
    printf '%s\n' "install GitHub CLI: winget install --id GitHub.cli -e" >&2
    exit 3
  fi
fi
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

# A v0 clone that pulled the upgrade: memory/logs is still a worktree of branch logs
# while main tracks memory/logs/. Move it out without losing a log (v0logs.sh).
# shellcheck disable=SC1091
. "$DIR/../sync/v0logs.sh"
join_git() {
  local dir=$1
  shift
  os_with_git_token git -C "$dir" "$@"
}
if v0logs_stuck "$ROOT" HEAD; then
  os_with_git_token git -C "$ROOT" fetch -q origin 2>/dev/null || true
  if ! v0_save=$(v0logs_park "$ROOT" join_git); then
    os_die 3 "the old logs folder memory/logs could not be moved. Nothing was removed. Ask the admin."
  fi
  printf 'v0-logs: moved, %s files kept as local changes\n' "$(v0logs_put_back "$ROOT" "$v0_save")"
fi

PAGE=$(os_person_file "$ROOT" "$ME" || true)
[ -n "$PAGE" ] || os_die 2 "no people page for $ME"

AREAS=$(os_answer_or areas "$ANSWERS" "")
if [ -z "$AREAS" ]; then
  AREAS=$(os_fm_get "$PAGE" areas || true)
fi
AREAS=$(printf '%s' "$AREAS" | tr -d '[]' | tr ',' ' ')

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

ws_name=$(os_user_repo "$SLUG" "$ME")
ws_dest="$ROOT/users/$ME"
if [ -e "$ws_dest/.git" ]; then
  printf 'cloned: %s\n' "$ws_name"
else
  set +e
  os_host repo-access "$ws_name" >/dev/null
  ws_rc=$?
  set -e
  if [ "$ws_rc" -ne 0 ]; then
    printf 'your workspace %s is not reachable: ask the admin\n' "$ws_name" >&2
    exit 3
  fi
  mkdir -p "$(dirname "$ws_dest")"
  if ! os_with_git_token git clone "$(os_clone_url "$HOST_KIND" "$HOST_URL" "$ORG" "$ws_name")" "$ws_dest"; then
    printf 'your workspace %s is not reachable: ask the admin\n' "$ws_name" >&2
    exit 3
  fi
  printf 'cloned: %s\n' "$ws_name"
fi

cfg=$(os_config_dir "$SLUG")
mkdir -p "$cfg"
printf '%s\n' "$ME" > "$cfg/me"
chmod 600 "$cfg/me"

engine=${OS_SYNC_ENGINE:-}
if [ -z "$engine" ]; then
  engine=$(os_fm_get "$ROOT/company-profile.md" sync_engine 2>/dev/null || true)
fi
engine=$(os_unquote "$engine")
engine=$(os_trim "$engine")
word=${engine%% *}
word=$(os_trim "$word")
if [ -z "$word" ] || ! command -v "$word" >/dev/null 2>&1; then
  if [ -n "$word" ] && [ "$word" != "claude" ]; then
    printf '%s\n' "install ${word} and put it on PATH" >&2
  elif sync_is_windows; then
    printf '%s\n' "Claude Code CLI: irm https://claude.ai/install.ps1 | iex" >&2
  else
    printf '%s\n' "Claude Code CLI: curl -fsSL https://claude.ai/install.sh | bash" >&2
  fi
  exit 3
fi
sync_materialize_links "$ROOT" 1
if [ -x "$ROOT/skills/sync/sync.sh" ]; then
  OS_COMPANY_ROOT="$ROOT" "$ROOT/skills/sync/sync.sh" install-jobs
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

# Open (or reuse) the terms pull request from sync/<me>, then turn on auto-merge.
join_terms_pr() {
  local pr number
  pr=$(os_host open-pr "$COMPANY_REPO" --head "sync/${ME}" --base main --title "sync: ${ME}")
  number=$(printf '%s' "$pr" | jq -r '.number // empty')
  [ -n "$number" ] || return 0
  printf 'pr: %s\n' "$number"
  # Like push and propose: the terms pull request merges by itself when the checks pass.
  if os_host_try auto-merge "$COMPANY_REPO" "$number" >/dev/null; then
    printf '%s\n' "auto-merge: on"
  else
    printf 'auto-merge is off on %s: pull request %s stays open until someone merges it. Ask the admin to run skills/_host/host.sh protect %s --code-owners --approvals 0\n' \
      "$COMPANY_REPO" "$number" "$COMPANY_REPO"
  fi
}

# Where the terms stand comes from the host: on origin/main (merged), on
# origin/sync/<me> (pushed; a run that stopped before open-pr left no pull request), or
# not yet. The page template has an empty terms_accepted: key: only a date counts. The
# clone may still be on sync/<me> (a refused checkout), so its own page proves nothing.
# Offline, the local page decides.
terms_dated() {
  git -C "$ROOT" show "$1:${PAGE#"$ROOT"/}" 2>/dev/null | grep -Eq '^terms_accepted: *"?[0-9]{4}-'
}
if os_with_git_token git -C "$ROOT" fetch -q origin 2>/dev/null; then
  if terms_dated origin/main; then
    terms=merged
  elif terms_dated "origin/sync/${ME}"; then
    terms=pushed
  else
    terms=none
  fi
elif [ -n "$(os_fm_get "$PAGE" terms_accepted 2>/dev/null || true)" ]; then
  terms=merged
else
  terms=none
fi
case "$terms" in
  merged)
    printf '%s\n' "terms: already"
    ;;
  pushed)
    # open-pr reuses a pull request that is open, or opens one.
    printf '%s\n' "terms: already"
    os_back_to_main "$ROOT"
    join_terms_pr
    ;;
  *)
    branch="sync/${ME}"
    os_with_git_token git -C "$ROOT" fetch origin
    # Build on the host's sync/<me> when it has one, so the push is a fast-forward.
    base=origin/main
    if git -C "$ROOT" rev-parse --verify --quiet "origin/${branch}" >/dev/null; then
      base="origin/${branch}"
    fi
    git -C "$ROOT" checkout -q -B "$branch" "$base"
    PAGE=$(os_person_file "$ROOT" "$ME")
    os_fm_set "$PAGE" terms_accepted "$(os_today)"
    os_git_commit "$ROOT" "Join: accept terms" "$PAGE"
    os_with_git_token git -C "$ROOT" push --set-upstream origin "$branch"
    # The terms change is on the host now. Stay on main: push rebuilds sync/<me> on the
    # host each night, so a clone left on it never fast-forwards again.
    os_back_to_main "$ROOT"
    printf 'terms: proposed\n'
    join_terms_pr
    ;;
esac

printf '%s\n' "join: ok"
