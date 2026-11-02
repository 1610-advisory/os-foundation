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

# GitHub: a team add sent this person an org invite. Until they accept it, the team's
# repos stay closed to them. Stop with the page that accepts it (v1.0.2).
if [ "$HOST_KIND" = "github" ]; then
  member=$(os_host my-membership 2>/dev/null | jq -r '.state // empty' 2>/dev/null || true)
  if [ "$member" = "pending" ]; then
    invite_host=${HOST_URL#*://}
    invite_host=${invite_host%%/*}
    os_die 2 "invite: accept the org invite first: https://${invite_host:-github.com}/orgs/${ORG}/invitation, then run join again"
  fi
fi

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
  # B73: launchd reads ~/Library/LaunchAgents only at login. On macOS join starts the jobs
  # now, as on Windows, unless OS_JOBS_LOAD=0. Only for the real jobs folder.
  jobs_load=${OS_JOBS_LOAD:-}
  if [ -z "$jobs_load" ] && [ "$(uname -s)" = "Darwin" ] && [ -z "${OS_JOBS_DIR:-}" ]; then
    jobs_load=1
  fi
  OS_JOBS_LOAD=$jobs_load OS_COMPANY_ROOT="$ROOT" "$ROOT/skills/sync/sync.sh" install-jobs
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
    # The person is the author (B54), as in every sync commit: their git name and email,
    # else their slug and the email on their people page.
    join_name=$(git -C "$ROOT" config user.name || true)
    join_email=$(git -C "$ROOT" config user.email || true)
    [ -n "$join_name" ] || join_name=$ME
    [ -n "$join_email" ] || join_email=$(os_fm_get "$PAGE" email 2>/dev/null || true)
    [ -n "$join_email" ] || join_email="${ME}@invalid"
    OS_GIT_NAME=$join_name OS_GIT_EMAIL=$join_email os_git_commit "$ROOT" "Join: accept terms

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

# B63: an old (v0) copy renamed beside this folder may hold work the host never got.
# join brings each item here itself (B69): a new file or a log is copied, and a change to
# a file the host has is set aside for this folder's agent, which applies it to the
# host's current text (skills/sync/re-apply.md). A whole-file copy would undo newer lines
# on main. Read only in the old folder: never fetch, write or delete there.
old_same_repo() {
  local dir=$1 repo=$2 url
  url=$(git -C "$dir" remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]') || return 1
  url=${url%/}
  url=${url%.git}
  case "$url" in
    */"$(printf '%s' "${ORG}/${repo}" | tr '[:upper:]' '[:lower:]')"|*:"$(printf '%s' "${ORG}/${repo}" | tr '[:upper:]' '[:lower:]')") return 0 ;;
  esac
  return 1
}

# The git folder of an old v0 logs worktree (memory/logs), read through the old folder's
# own .git (B64). git wrote an absolute link in memory/logs/.git, so after the rename it
# names the new folder. Read only: never "worktree repair" there. Prints the path, or
# fails when it cannot be found.
old_logs_gitdir() {
  local old=$1 link name gd
  [ -f "$old/memory/logs/.git" ] || return 1
  link=$(sed -n 's/^gitdir: //p' "$old/memory/logs/.git" | head -n 1)
  [ -n "$link" ] || return 1
  name=$(basename "$link")
  gd="$old/.git/worktrees/$name"
  [ -f "$gd/HEAD" ] || return 1
  printf '%s\n' "$gd"
}

# One path of the old folder, brought here. mine: a file with the person's text, or - when
# they deleted it. base: a file with the text they edited, or - for none. The same text
# here already is nothing to do. A new file the host does not have is copied. Anything
# else is set aside for re-apply.
old_bring() {
  local id=$1 new=$2 rel=$3 mine=$4 base=$5 what=$6 dest=$7 out
  if [ "$mine" = "-" ]; then
    [ -e "$new/$rel" ] || return 0
  elif [ -f "$new/$rel" ] && cmp -s "$mine" "$new/$rel"; then
    return 0
  fi
  OLD_N=$((OLD_N + 1))
  if [ "$mine" != "-" ] && [ "$base" = "-" ] && [ ! -e "$new/$rel" ] && ! git -C "$new" cat-file -e "HEAD:${rel}" 2>/dev/null; then
    # Never write through a link in this folder (r8): it could point outside it.
    if old_through_link "$new" "$rel"; then
      printf 'old-folder: %s was not copied: %s%s goes through a link in this folder. Copy it by hand before deleting the old folder.\n' "$what" "$dest" "$rel"
      OLD_UNCHECKED=1
      return 0
    fi
    if mkdir -p "$(dirname "$new/$rel")" && cp "$mine" "$new/$rel"; then
      printf 'old-folder: %s copied to %s%s: sync sends it.\n' "$what" "$dest" "$rel"
    else
      printf 'old-folder: %s could not be copied to %s%s. Copy it by hand before deleting the old folder.\n' "$what" "$dest" "$rel"
      OLD_UNCHECKED=1
    fi
    return 0
  fi
  if out=$(OS_COMPANY_ROOT="$ROOT" OS_PROFILE_SH="${OS_PROFILE_SH:-$DIR/../_host/profile.sh}" \
    bash "$DIR/../sync/sync.sh" set-aside "$id" "$rel" "$mine" "$base" 2>&1); then
    if [ "$out" = "done" ]; then
      # Set aside by an earlier join and re-applied since.
      OLD_N=$((OLD_N - 1))
    elif [ "$out" = "already" ]; then
      printf 'old-folder: %s is already set aside for %s%s: the agent re-applies it (skills/sync/sync.sh re-apply list).\n' "$what" "$dest" "$rel"
    else
      printf 'old-folder: %s is set aside for %s%s: the agent re-applies the change to the host'"'"'s current text (skills/sync/sync.sh re-apply list). Nothing to copy.\n' "$what" "$dest" "$rel"
    fi
  else
    printf 'old-folder: %s could not be set aside (%s). Redo that change in %s%s by hand before deleting the old folder.\n' "$what" "$(printf '%s' "$out" | tail -n 1)" "$dest" "$rel"
    OLD_UNCHECKED=1
  fi
}

# A file's text at a commit in a git dir, into a temp file; - when it is not there.
old_blob_file() {
  local gitdir=$1 spec=$2 f
  git --git-dir "$gitdir" cat-file -e "$spec" 2>/dev/null || { printf '%s\n' "-"; return 0; }
  f=$(mktemp "${OLD_TMP}/f.XXXXXX") || { printf '%s\n' "-"; return 0; }
  git --git-dir "$gitdir" cat-file -p "$spec" > "$f" || { printf '%s\n' "-"; return 0; }
  printf '%s\n' "$f"
}

# The same rule as sync propose (sync_propose_bad_path): no .., no leading /, no empty
# part, no new line or tab. Such a name is never written here (r8).
old_bad_path() {
  local path=$1 seg segs
  [ -n "$path" ] || return 0
  case "$path" in
    /*|..|../*|*/..|*/../*) return 0 ;;
    *$'\n'*|*$'\t'*) return 0 ;;
  esac
  IFS=/ read -ra segs <<< "$path"
  for seg in "${segs[@]}"; do
    [ -n "$seg" ] && [ "$seg" != ".." ] || return 0
  done
  return 1
}

# Does a path here go through a link (any part of it, or the file itself)?
old_through_link() {
  local base=$1 rel=$2 p="" seg segs
  IFS=/ read -ra segs <<< "$rel"
  for seg in "${segs[@]}"; do
    p="${p:+${p}/}${seg}"
    [ ! -L "$base/$p" ] || return 0
  done
  return 1
}

# NUL-separated paths in (git -z), one per line out, each after the prefix. mode status:
# git status -z records, where a rename or copy is followed by its old path as a record
# of its own, which is skipped. A name join must not use (old_bad_path) comes out as
# "/" and the name, with ? for each new line or tab: the caller names it and sets the
# unchecked flag (r8: the records stay whole, so a new line cannot make a second path).
old_paths_z() {
  local mode=$1 prefix=${2:-} rec rel skip=0
  while IFS= read -r -d '' rec; do
    if [ "$skip" -eq 1 ]; then
      skip=0
      continue
    fi
    rel=$rec
    if [ "$mode" = "status" ]; then
      case "$rec" in
        R*|C*|?R*|?C*) skip=1 ;;
      esac
      rel=${rec:3}
    fi
    [ -n "$rel" ] || continue
    # git lists a folder that is a repo of its own with a / at the end.
    case "$rel" in
      ?*/) rel=${rel%/} ;;
    esac
    if old_bad_path "$rel"; then
      printf '/%s\n' "$(printf '%s' "$rel" | tr '\n\t' '??')"
    else
      printf '%s%s\n' "$prefix" "$rel"
    fi
  done
}

# A name old_paths_z refused: say so, and never "You may delete it".
old_refused() {
  printf 'old-folder: %s%s was not brought: its name has .., a leading /, a tab or a new line. Check it by hand before deleting the old folder.\n' "$1" "${2#/}"
  OLD_UNCHECKED=1
}

# r8: on Windows git checks text out with CRLF (core.autocrlf=true) and commits LF. Read the
# person's worktree file the way git keeps it: when the other side (the base, else this
# folder's copy) has no CR, CRLF line ends become LF. Not for a file with a NUL byte.
old_mine_eol() {
  local mine=$1 other=$2 f
  # tr, not grep: a grep on Windows may drop CR before it matches.
  if [ ! -f "$other" ] || ! old_has_byte '\r' "$mine" || old_has_byte '\r' "$other" || old_has_byte '\000' "$mine"; then
    printf '%s\n' "$mine"
    return 0
  fi
  if ! f=$(mktemp "${OLD_TMP}/m.XXXXXX") || ! LC_ALL=C sed $'s/\r$//' "$mine" > "$f"; then
    printf '%s\n' "$mine"
    return 0
  fi
  printf '%s\n' "$f"
}

# Does the file hold this byte (a tr escape: '\r', '\000')?
old_has_byte() {
  [ "$(LC_ALL=C tr -cd "$1" < "$2" 2>/dev/null | wc -c | tr -d ' ')" != "0" ]
}

# A path that is there but is not a plain file (a link, or a special file): never brought.
old_not_plain() {
  printf 'old-folder: %s is not a plain file (a link or a special file), so join did not bring it. Check it by hand before deleting the old folder.\n' "$1"
  OLD_UNCHECKED=1
}

# Stashed changes: git keeps them outside every branch. join does not open a stash. A
# worktree shares its repo's stash: list it once.
old_stash() {
  local gitdir=$1 label=$2 old=$3 out n top
  if ! out=$(git --git-dir "$gitdir" for-each-ref --format='%(refname)' refs/stash 2>/dev/null) \
    || { [ -n "$out" ] && ! n=$(git --git-dir "$gitdir" log -g --format=%gd refs/stash 2>/dev/null | wc -l | tr -d ' '); }; then
    printf 'old-folder: %s could not be checked for stashed changes (git stash list failed there). Check it by hand before deleting it.\n' "$label"
    OLD_UNCHECKED=1
    return 0
  fi
  [ -n "$out" ] || return 0
  top=$(git --git-dir "$gitdir" rev-parse -q --verify refs/stash 2>/dev/null || true)
  if [ -n "$top" ] && [ -f "${OLD_TMP}/stash-seen" ] && grep -Fxq -- "$top" "${OLD_TMP}/stash-seen"; then
    return 0
  fi
  printf '%s\n' "$top" >> "${OLD_TMP}/stash-seen"
  OLD_N=$((OLD_N + 1))
  OLD_STASH=$((OLD_STASH + 1))
  # B71: sync.sh status names it until the old folder is gone or has no stash, so the agent
  # never says to delete the old folder while a stash is only there.
  printf '%s\t%s\n' "$gitdir" "$old" >> "$OLD_STASH_NOTE"
  printf 'old-folder: %s has %s stashed changes the host lacks (git -C %s stash list). join does not open a stash: git -C %s stash show -p shows each one. Redo it here before deleting the old folder.\n' \
    "$label" "$n" "$old" "$old"
}

old_report_repo() {
  local old=$1 new=$2 label=$3 id rel sha subject out dest gd ref base_ref base_commit commits mine base paths logs_dest head_ref fresh
  id=root
  dest=""
  if [ "$new" != "$ROOT" ]; then
    id="area:$(basename "$new")"
    dest="${new#"$ROOT"/}/"
  fi
  logs_dest="${dest}memory/logs/"
  if [ ! -e "$new/.git" ]; then
    printf 'old-folder: %s is an area this folder has not joined, so join brought nothing from it. Join that area here, then run join again.\n' "$label"
    OLD_UNCHECKED=1
    return 0
  fi
  # Each local branch (not logs) and HEAD (a detached HEAD too; Grok r6), with the commits on it
  # this folder (a fresh clone of the host) does not have. A branch's change is what it
  # holds beyond where it left main; main's is beyond the host's main as the old folder
  # last saw it. The checked-out one adds the changes not committed (git status).
  head_ref=$(git -C "$old" symbolic-ref -q HEAD 2>/dev/null || printf '%s' HEAD)
  if ! out=$(git -C "$old" for-each-ref --format='%(refname)' refs/heads/ 2>/dev/null); then
    printf 'old-folder: %s could not be checked (git could not list its branches). Compare it with this folder by hand before deleting it.\n' "$label"
    OLD_UNCHECKED=1
    out=""
  fi
  for ref in HEAD $out; do
    [ "$ref" != "refs/heads/logs" ] || continue
    [ "$ref" = "HEAD" ] || [ "$ref" != "$head_ref" ] || continue
    if ! commits=$(git -C "$old" rev-list "$ref" --not --remotes 2>/dev/null); then
      printf 'old-folder: %s could not be checked (git log failed there). Compare it with this folder by hand before deleting it.\n' "$label"
      OLD_UNCHECKED=1
      continue
    fi
    fresh=0
    for sha in $commits; do
      git -C "$new" cat-file -e "${sha}^{commit}" 2>/dev/null || { fresh=1; break; }
    done
    if [ "$ref" = "HEAD" ] && [ "$head_ref" = "refs/heads/main" ]; then
      base_ref=refs/remotes/origin/main
    elif git -C "$old" rev-parse -q --verify refs/heads/main >/dev/null 2>&1 && [ "$ref" != "refs/heads/main" ]; then
      base_ref=refs/heads/main
    else
      base_ref=refs/remotes/origin/main
    fi
    paths=""
    if [ "$fresh" -eq 1 ]; then
      base_commit=$(git -C "$old" merge-base "$ref" "$base_ref" 2>/dev/null) \
        || base_commit=$(git hash-object -t tree /dev/null)
      paths=$(git -C "$old" diff -z --name-only --no-renames "$base_commit" "$ref" 2>/dev/null | old_paths_z names) || {
        printf 'old-folder: %s could not be checked (git diff failed there). Compare it with this folder by hand before deleting it.\n' "$label"
        OLD_UNCHECKED=1
        continue
      }
      subject=$(git -C "$old" log -1 --format='%h "%s"' "$ref" 2>/dev/null || true)
    else
      base_commit=$ref
    fi
    if [ "$ref" = "HEAD" ]; then
      # Changed and untracked files.
      if ! out=$(git --no-optional-locks -C "$old" status --porcelain -z --untracked-files=all 2>/dev/null | old_paths_z status); then
        printf 'old-folder: %s could not be checked (git status failed there). Compare it with this folder by hand before deleting it.\n' "$label"
        OLD_UNCHECKED=1
        out=""
      fi
      paths=$(printf '%s\n%s\n' "$paths" "$out" | awk 'NF && !seen[$0]++')
    fi
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      case "$rel" in
        /*) old_refused "${label}/" "$rel"; continue ;;
        memory/logs|memory/logs/*) [ ! -e "$old/memory/logs/.git" ] || continue ;;
      esac
      base=$(old_blob_file "$old/.git" "${base_commit}:${rel}")
      if [ "$ref" = "HEAD" ]; then
        if [ -f "$old/$rel" ] && [ ! -L "$old/$rel" ]; then
          if [ "$base" != "-" ]; then
            mine=$(old_mine_eol "$old/$rel" "$base")
          else
            mine=$(old_mine_eol "$old/$rel" "$new/$rel")
          fi
        elif [ -d "$old/$rel" ] && [ ! -L "$old/$rel" ]; then
          # A repo of its own inside (an area is checked on its own).
          continue
        elif [ -e "$old/$rel" ] || [ -L "$old/$rel" ]; then
          old_not_plain "${label}/${rel}"
          continue
        else
          # Gone from the worktree. A commit the host lacks may still hold it (r8): bring
          # that text. Else it is the person's delete.
          mine=$(old_blob_file "$old/.git" "HEAD:${rel}")
          if [ "$mine" != "-" ] && [ "$base" != "-" ] && cmp -s "$mine" "$base"; then
            mine="-"
          fi
        fi
      else
        mine=$(old_blob_file "$old/.git" "${ref}:${rel}")
      fi
      [ "$mine" != "-" ] || [ "$base" != "-" ] || continue
      if [ "$ref" = "HEAD" ]; then
        old_bring "$id" "$new" "$rel" "$mine" "$base" "${label}/${rel}" "$dest"
      else
        old_bring "$id" "$new" "$rel" "$mine" "$base" "${label} branch ${ref#refs/heads/} (last commit ${subject}): ${rel}" "$dest"
      fi
    done <<< "$paths"
  done
  old_stash "$old/.git" "$label" "$old"
  # The old logs folder: logs not committed, or committed and never pushed, on the logs
  # branch or on whatever is checked out there (both; Grok r6). Each is copied into
  # memory/logs/ here: v1 keeps logs there and sync sends them. Never push the old logs
  # branch: that would bring back the branch the admin deleted.
  [ -e "$old/memory/logs/.git" ] || return 0
  if ! gd=$(old_logs_gitdir "$old"); then
    printf 'old-folder: %s/memory/logs could not be checked (git cannot open it). Copy each log in it that %s does not have into %s by hand before deleting the old folder.\n' \
      "$label" "$logs_dest" "$logs_dest"
    OLD_UNCHECKED=1
    return 0
  fi
  if ! out=$(git --no-optional-locks --git-dir "$gd" --work-tree "$old/memory/logs" \
    status --porcelain -z --untracked-files=all 2>/dev/null | old_paths_z status); then
    printf 'old-folder: %s/memory/logs could not be checked (git status failed there). Copy each log in it that %s does not have into %s by hand before deleting the old folder.\n' \
      "$label" "$logs_dest" "$logs_dest"
    OLD_UNCHECKED=1
    return 0
  fi
  paths=$out
  for ref in HEAD refs/heads/logs; do
    if ! commits=$(git --git-dir "$gd" rev-list "$ref" --not --remotes 2>/dev/null); then
      printf 'old-folder: %s/memory/logs could not be checked (git log %s failed there). Copy each log in it that %s does not have into %s by hand before deleting the old folder.\n' \
        "$label" "${ref#refs/heads/}" "$logs_dest" "$logs_dest"
      OLD_UNCHECKED=1
      continue
    fi
    for sha in $commits; do
      git -C "$new" cat-file -e "${sha}^{commit}" 2>/dev/null && continue
      out=$(git --git-dir "$gd" diff-tree -z --no-commit-id --name-only -r --no-renames "$sha" 2>/dev/null \
        | old_paths_z names "${ref}	") || true
      paths=$(printf '%s\n%s\n' "$paths" "$out")
    done
  done
  old_stash "$gd" "${label}/memory/logs" "$old/memory/logs"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    ref=""
    case "$rel" in
      *"	"*) ref=${rel%%	*}; rel=${rel#*	} ;;
    esac
    case "$rel" in
      /*) old_refused "${label}/memory/logs/" "$rel"; continue ;;
    esac
    if [ -f "$old/memory/logs/$rel" ] && [ ! -L "$old/memory/logs/$rel" ] && { [ -z "$ref" ] || [ "$ref" = "HEAD" ]; }; then
      mine=$(old_mine_eol "$old/memory/logs/$rel" "$new/memory/logs/$rel")
    elif [ -n "$ref" ]; then
      mine=$(old_blob_file "$gd" "${ref}:${rel}")
    elif [ -e "$old/memory/logs/$rel" ] || [ -L "$old/memory/logs/$rel" ]; then
      old_not_plain "${label}/memory/logs/${rel}"
      continue
    else
      # Gone from the worktree (r8): a commit the host lacks may hold it. Bring that text.
      ref=$(printf '%s\n' "$paths" | REL="$rel" awk -F'\t' 'NF == 2 && $2 == ENVIRON["REL"] && !n++ { print $1 }')
      [ -n "$ref" ] || continue
      mine=$(old_blob_file "$gd" "${ref}:${rel}")
    fi
    [ "$mine" != "-" ] || continue
    old_bring "$id" "$new" "memory/logs/${rel}" "$mine" "-" "${label}/memory/logs/${rel}" "$dest"
  done <<< "$(printf '%s\n' "$paths" | awk -F'\t' 'NF && !seen[$NF]++')"
}

old_folder_report() {
  local cand area stash_say left state
  state="$(os_config_dir "$SLUG")/state"
  mkdir -p "$state"
  OLD_STASH_NOTE=$(mktemp "${state}/old-stash.XXXXXX") || OLD_STASH_NOTE=/dev/null
  for cand in "$(dirname "$ROOT")"/*; do
    [ -d "$cand" ] && [ -e "$cand/.git" ] || continue
    [ "$(cd "$cand" && pwd)" != "$ROOT" ] || continue
    old_same_repo "$cand" "$(os_company_repo "$SLUG")" || continue
    OLD_N=0
    OLD_UNCHECKED=0
    OLD_STASH=0
    OLD_TMP=$(mktemp -d) || os_die 1 "could not make a temp folder: check the free disk space"
    old_report_repo "$cand" "$ROOT" "$cand"
    for area in "$cand"/areas/*; do
      [ -e "$area/.git" ] || continue
      old_same_repo "$area" "$(os_area_repo "$SLUG" "$(basename "$area")")" || continue
      old_report_repo "$area" "$ROOT/areas/$(basename "$area")" "$area"
    done
    rm -rf "$OLD_TMP"
    # r8, B71: a stash is never set aside or copied. It is only in the old folder until it
    # is redone here, and the delete rule names it.
    left=$((OLD_N - OLD_STASH))
    stash_say=""
    [ "$OLD_STASH" -eq 0 ] \
      || stash_say=" Its stashed changes are still only in the old folder: redo each one here first (git -C ${cand} stash show -p)."
    if [ "$OLD_UNCHECKED" -eq 1 ] && [ "$OLD_N" -eq 0 ]; then
      printf 'old-folder: %s: some of it could not be checked (listed above). Check that part by hand. Nothing was deleted. Do not delete it yet.\n' "$cand"
    elif [ "$OLD_UNCHECKED" -eq 1 ]; then
      # Never "you may delete it" when a part could not be read (B64).
      printf 'old-folder: %s held %s the host lacks (listed above), and some of it could not be checked. Check that part by hand.%s Nothing was deleted. Do not delete it yet.\n' "$cand" "$(old_items "$OLD_N")" "$stash_say"
    elif [ "$OLD_STASH" -gt 0 ] && [ "$left" -eq 0 ]; then
      printf 'old-folder: %s has nothing else the host lacks, only the stash listed above.%s Nothing was deleted. Delete the old folder only after each stash is redone here.\n' "$cand" "$stash_say"
    elif [ "$OLD_STASH" -gt 0 ]; then
      # Never the delete-after-re-apply line alone while a stash is only there.
      printf 'old-folder: %s held %s the host lacks (listed above). join copied %s here or set %s aside for the agent.%s Nothing was deleted. Delete the old folder only after each stash is redone here, the agent has re-applied what was set aside, and sync has sent it to the host.\n' \
        "$cand" "$(old_items "$OLD_N")" "$(old_it "$left")" "$(old_it "$left")" "$stash_say"
    elif [ "$OLD_N" -eq 0 ]; then
      printf 'old-folder: %s has nothing the host lacks. You may delete it.\n' "$cand"
    else
      printf 'old-folder: %s held %s the host lacks (listed above). join copied %s here or set %s aside for the agent. Nothing was deleted. Delete the old folder only after the agent has re-applied what was set aside and sync has sent it to the host.\n' \
        "$cand" "$(old_items "$OLD_N")" "$(old_it "$OLD_N")" "$(old_it "$OLD_N")"
    fi
  done
  if [ "$OLD_STASH_NOTE" != "/dev/null" ]; then
    if [ -s "$OLD_STASH_NOTE" ]; then
      mv -f "$OLD_STASH_NOTE" "${state}/old-stash"
      chmod 600 "${state}/old-stash"
    else
      rm -f "$OLD_STASH_NOTE" "${state}/old-stash"
    fi
  fi
}

# "1 item", "2 items"; "it", "them".
old_items() {
  if [ "$1" -eq 1 ]; then printf '1 item'; else printf '%s items' "$1"; fi
}
old_it() {
  if [ "$1" -eq 1 ]; then printf 'it'; else printf 'them'; fi
}
old_folder_report || true

printf '%s\n' "join: ok"
