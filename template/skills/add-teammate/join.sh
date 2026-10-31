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
  v0_err=$(mktemp)
  # Each failure line says what happened and where the copy is, when there is one.
  if ! v0_save=$(v0logs_park "$ROOT" join_git 2>"$v0_err"); then
    os_die 3 "the old logs folder memory/logs could not be moved: $(head -n 1 "$v0_err")."
  fi
  if ! v0_n=$(v0logs_put_back "$ROOT" "$v0_save" 2>"$v0_err"); then
    os_die 3 "the old logs folder memory/logs could not be moved: $(head -n 1 "$v0_err")."
  fi
  rm -f "$v0_err"
  read -r v0_written v0_beside v0_kept <<< "$v0_n"
  printf 'v0-logs: moved, %s files kept as local changes\n' "$v0_written"
  if [ "$v0_beside" -gt 0 ]; then
    printf 'v0-logs: %s files were changed here and on the old logs branch, so the old text is beside each one as <name>.old-branch.md. Nothing was written over.\n' "$v0_beside"
  fi
  if [ "$v0_kept" -gt 0 ]; then
    printf 'v0-logs: %s files in memory/logs-archive/ have a change here that is not committed, so the copy from the old logs folder is beside each one as <name>.old-branch.md. Nothing was written over.\n' "$v0_kept"
  fi
fi

PAGE=$(os_person_file "$ROOT" "$ME" || true)
[ -n "$PAGE" ] || os_die 2 "no people page for $ME"

AREAS=$(os_answer_or areas "$ANSWERS" "")
if [ -z "$AREAS" ]; then
  AREAS=$(os_fm_get "$PAGE" areas || true)
fi
AREAS=$(printf '%s' "$AREAS" | tr -d '[]' | tr ',' ' ')

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

# The same order as sync (B43): OS_SYNC_ENGINE, then <config>/engine, then the profile.
engine=${OS_SYNC_ENGINE:-}
if [ -z "$engine" ] && [ -f "$cfg/engine" ]; then
  engine=$(tr -d '\r' < "$cfg/engine" | head -n 1)
fi
if [ -z "$engine" ]; then
  engine=$(os_fm_get "$ROOT/company-profile.md" sync_engine 2>/dev/null || true)
fi
engine=$(os_unquote "$engine")
engine=$(os_trim "$engine")
word=${engine%% *}
word=$(os_trim "$word")
if [ -z "$word" ] || ! command -v "$word" >/dev/null 2>&1; then
  # The native installer puts claude in ~/.local/bin but does not put that folder on
  # PATH. Say so, and the step. Do not edit PATH here.
  if [ -z "$word" ] || [ "$word" = "claude" ]; then
    if [ -f "$HOME/.local/bin/claude" ] || [ -f "$HOME/.local/bin/claude.exe" ]; then
      if sync_is_windows; then
        printf '%s\n' 'Claude Code is in %USERPROFILE%\.local\bin, but that folder is not on PATH. Add it to your user PATH: Start, type "environment variables for your account", open it, select Path, Edit, New, type %USERPROFILE%\.local\bin, OK. Then open a new terminal and run join again.' >&2
      else
        case "${SHELL:-}" in
          */zsh) rc_file=.zshrc ;;
          *) if [ "$(uname -s)" = "Darwin" ]; then rc_file=.bash_profile; else rc_file=.bashrc; fi ;;
        esac
        printf '%s\n' "Claude Code is in ~/.local/bin, but that folder is not on PATH. Run this once, then open a new terminal and run join again:" >&2
        # shellcheck disable=SC2016
        printf 'echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> ~/%s\n' "$rc_file" >&2
      fi
      exit 3
    fi
  fi
  if [ -n "$word" ] && [ "$word" != "claude" ]; then
    printf '%s\n' "install ${word} and put it on PATH" >&2
  elif sync_is_windows; then
    printf '%s\n' "Claude Code CLI: irm https://claude.ai/install.ps1 | iex" >&2
  else
    printf '%s\n' "Claude Code CLI: curl -fsSL https://claude.ai/install.sh | bash" >&2
  fi
  exit 3
fi
# Claude Code outside the desktop app needs its own sign-in. One short call, at most
# OS_ENGINE_TIMEOUT seconds (default 60), before any job is installed.
if [ "$word" = "claude" ]; then
  check_out=$(mktemp)
  # shellcheck disable=SC2086
  printf '%s\n' "Print the word ok and nothing else." | $engine > "$check_out" 2>/dev/null &
  check_pid=$!
  limit=${OS_ENGINE_TIMEOUT:-60}
  waited=0
  # Ask it to stop at the limit. Some programs ignore that, so force it 5 seconds later.
  while kill -0 "$check_pid" 2>/dev/null; do
    if [ "$waited" -eq "$limit" ]; then
      kill "$check_pid" 2>/dev/null || true
    elif [ "$waited" -ge $((limit + 5)) ]; then
      # On Git Bash, kill -9 can miss a native program (claude.exe). Ask Windows too.
      winpid=""
      if sync_is_windows && [ -r "/proc/$check_pid/winpid" ]; then
        winpid=$(cat "/proc/$check_pid/winpid" 2>/dev/null || true)
      fi
      kill -9 "$check_pid" 2>/dev/null || true
      if [ -n "$winpid" ]; then
        taskkill //F //T //PID "$winpid" >/dev/null 2>&1 || true
      fi
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  # Never wait on a program that is still running: it could block forever.
  if ! kill -0 "$check_pid" 2>/dev/null; then
    wait "$check_pid" 2>/dev/null || true
  fi
  # Only the word ok counts, so a program that repeats the question does not pass.
  answer=$(tr -d ' \t\r\n' < "$check_out" | tr '[:upper:]' '[:lower:]')
  if [ "$answer" != "ok" ] && [ "$answer" != "ok." ]; then
    rm -f "$check_out"
    printf '%s\n' "sign in once: run claude, sign in, then /exit" >&2
    exit 3
  fi
  rm -f "$check_out"
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

# The terms are a sync commit like any other: commit the dated page here, then push. Push
# sends it to sync/<me>/<seat> and opens that computer's pull request, which merges by
# itself when the checks pass. A run that stopped after the commit pushes it again.
# The page template has an empty terms_accepted: key: only a date counts.
terms_dated() {
  git -C "$ROOT" show "$1:${PAGE#"$ROOT"/}" 2>/dev/null | grep -Eq '^terms_accepted: *"?[0-9]{4}-'
}
os_with_git_token git -C "$ROOT" fetch -q origin 2>/dev/null \
  || os_die 3 "could not reach the host: run join again when online; the terms pull request may not be open yet"
if terms_dated origin/main; then
  printf '%s\n' "terms: already"
else
  sync_sh="$DIR/../sync/sync.sh"
  [ -f "$sync_sh" ] || os_die 2 "skills/sync/sync.sh is not here yet: ask the admin"
  export OS_PROFILE_SH="${OS_PROFILE_SH:-$DIR/../_host/profile.sh}"
  # A clone made by older join code may sit on sync/<me>. Sync works on main.
  if [ "$(git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null || true)" != "main" ]; then
    os_back_to_main "$ROOT" 2>/dev/null
    [ "$(git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null || true)" = "main" ] \
      || os_die 3 "could not go back to main (a local change is in the way): run git checkout main, then run join again"
  fi
  if terms_dated HEAD; then
    printf '%s\n' "terms: already"
  else
    [ -f "$PAGE" ] || os_die 2 "no people page for $ME on the host: ask the admin"
    seat=$(OS_COMPANY_ROOT="$ROOT" bash "$sync_sh" seat) \
      || os_die 3 "could not make this computer's seat id: run join again"
    os_fm_set "$PAGE" terms_accepted "$(os_today)"
    os_git_commit "$ROOT" "Join: accept terms

${ME} joined and accepted the terms on ${PAGE#"$ROOT"/}.

Sync-Seat: ${seat}" "$PAGE" >/dev/null \
      || os_die 3 "could not commit the terms: run join again"
    printf '%s\n' "terms: proposed"
  fi
  if ! OS_COMPANY_ROOT="$ROOT" bash "$sync_sh" push; then
    why=$(OS_COMPANY_ROOT="$ROOT" bash "$sync_sh" status 2>/dev/null | sed -n 's/^last error: //p' | head -n 1)
    case "$why" in
      # The terms are on the host with a pull request; only the merge waits for the admin.
      "auto-merge is off on "*) printf '%s\n' "$why" ;;
      *) os_die 3 "sync push stopped (${why:-no reason given}). The terms are committed in this folder: fix that, then run join again" ;;
    esac
  fi
fi

printf '%s\n' "join: ok"
