#!/bin/bash
# Shared helpers for sync.sh. Source this file. Do not run it.
# The mktemp function below wraps the system one. Calls with no arguments are on purpose.
# shellcheck disable=SC2119,SC2120
set -euo pipefail

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh. Do not run it."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh. Do not run it." >&2
  exit 1
fi

SYNC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SYNC_TMP_FILES=""
SYNC_LOCK_DIR=""
# One temp folder per run: every mktemp below, and in the scripts this run starts, lands
# in it, and sync_cleanup removes it. sync_mktemp runs in $( ), so a list it keeps never
# reaches this shell; the folder does. A folder that holds the person's own files during
# a step comes from sync_keep_dir instead, outside the run folder, so a crash never
# deletes it. A nightly job must leave the temp folder as it found it.
OS_KEEP_TMP=${OS_KEEP_TMP:-${TMPDIR:-/tmp}}
export OS_KEEP_TMP
SYNC_RUN_TMP=""
# macOS mktemp ignores TMPDIR. With no template, make the file in TMPDIR (the run folder).
mktemp() {
  if [ $# -eq 0 ]; then
    command mktemp "${TMPDIR:-/tmp}/tmp.XXXXXXXX"
  elif [ $# -eq 1 ] && [ "$1" = "-d" ]; then
    command mktemp -d "${TMPDIR:-/tmp}/tmp.XXXXXXXX"
  else
    command mktemp "$@"
  fi
}

sync_die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

# Called once by the entry script, before any temp file.
sync_run_tmp() {
  SYNC_RUN_TMP=$(mktemp -d "${OS_KEEP_TMP%/}/os-sync.XXXXXX") \
    || sync_die 1 "could not make a temp folder: check the free disk space"
  chmod 700 "$SYNC_RUN_TMP"
  export TMPDIR="$SYNC_RUN_TMP"
}

sync_mktemp() {
  local f
  f=$(mktemp)
  chmod 600 "$f"
  SYNC_TMP_FILES="${SYNC_TMP_FILES} ${f}"
  printf '%s\n' "$f"
}

# Paths from git diff, log or ls-files, one per line. -z and NUL reads: a path with an
# accent, an em dash or an emoji is never quoted, so it matches the same path from
# status -z. A path with a line break is left out, as sync_changed_names does.
sync_names() {
  local repo=$1 sub=$2 path
  shift 2
  while IFS= read -r -d '' path; do
    case "$path" in
      ""|*$'\n'*) continue ;;
    esac
    printf '%s\n' "$path"
  done < <(git -C "$repo" -c core.quotepath=false "$sub" -z "$@" 2>/dev/null)
}

# The caller removes it when the step is done.
sync_keep_dir() {
  local d
  d=$(mktemp -d "${OS_KEEP_TMP%/}/os-sync-keep.XXXXXX") || return 1
  chmod 700 "$d"
  printf '%s\n' "$d"
}

# One askpass file per run, written once in the run's private folder. It holds no
# secret: it prints two variables that only the git call it serves gets.
sync_askpass() {
  local ask
  if [ -n "$SYNC_RUN_TMP" ]; then
    ask="$SYNC_RUN_TMP/askpass"
  else
    ask=$(sync_mktemp)
  fi
  if [ ! -s "$ask" ]; then
    cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
    chmod 700 "$ask"
  fi
  printf '%s\n' "$ask"
}

sync_cleanup() {
  local f
  if type sync_pull_clear_secret >/dev/null 2>&1; then
    sync_pull_clear_secret
  fi
  if type sync_propose_drop_trees >/dev/null 2>&1; then
    sync_propose_drop_trees
  fi
  # shellcheck disable=SC2086
  for f in $SYNC_TMP_FILES; do
    rm -f "$f"
  done
  SYNC_TMP_FILES=""
  if [ -n "$SYNC_RUN_TMP" ]; then
    rm -rf "$SYNC_RUN_TMP"
  fi
  SYNC_RUN_TMP=""
  if [ -n "$SYNC_LOCK_DIR" ] && [ -d "$SYNC_LOCK_DIR" ]; then
    rm -rf "$SYNC_LOCK_DIR"
  fi
  SYNC_LOCK_DIR=""
}

sync_abs() {
  local target=$1
  local dir base
  if [ -d "$target" ]; then
    (CDPATH='' cd "$target" && pwd -P)
    return 0
  fi
  dir=$(dirname "$target")
  base=$(basename "$target")
  if [ -d "$dir" ]; then
    printf '%s/%s\n' "$(CDPATH='' cd "$dir" && pwd -P)" "$base"
    return 0
  fi
  printf '%s\n' "$target"
}

sync_now() {
  if [ -n "${OS_NOW:-}" ]; then
    printf '%s\n' "$OS_NOW"
    return 0
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ
}

sync_today() {
  local now
  now=$(sync_now)
  printf '%s\n' "${now%%T*}"
}

sync_find_root() {
  local dir parent
  if [ -n "${OS_COMPANY_ROOT:-}" ]; then
    [ -f "${OS_COMPANY_ROOT}/company-profile.md" ] || sync_die 1 "company-profile.md not found"
    sync_abs "$OS_COMPANY_ROOT"
    return 0
  fi
  dir=$(pwd -P)
  while true; do
    if [ -f "$dir/company-profile.md" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    parent=$(dirname "$dir")
    if [ "$parent" = "$dir" ]; then
      sync_die 1 "company-profile.md not found"
    fi
    dir=$parent
  done
}

# B70: a job that launchd starts (or an app opened from Finder) gets PATH
# /usr/bin:/bin:/usr/sbin:/sbin. Homebrew git, jq and gh, and the claude CLI, live in other
# folders. Each one that exists goes before the bare system folders, as brew shellenv puts
# them (r8): /usr/bin/git is only Apple's stand-in when the command line tools are missing.
sync_path_add() {
  local d e want="" head="" tail="" add="" sys=0
  for d in "$@"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    case ":${want}:" in
      *":${d}:"*) continue ;;
    esac
    want="${want:+${want}:}${d}"
  done
  [ -n "$want" ] || return 0
  while IFS= read -r -d : e; do
    if [ "$sys" -eq 0 ]; then
      case "$e" in
        /usr/bin|/bin|/usr/sbin|/sbin) sys=1 ;;
      esac
    fi
    if [ "$sys" -eq 0 ]; then
      head="${head:+${head}:}${e}"
    else
      case ":${want}:" in
        *":${e}:"*) continue ;;
      esac
      tail="${tail:+${tail}:}${e}"
    fi
  done < <(printf '%s:' "${PATH:-}")
  while IFS= read -r -d : d; do
    case ":${head}:" in
      *":${d}:"*) continue ;;
    esac
    add="${add:+${add}:}${d}"
  done < <(printf '%s:' "$want")
  PATH=$head
  [ -z "$add" ] || PATH="${PATH:+${PATH}:}${add}"
  [ -z "$tail" ] || PATH="${PATH:+${PATH}:}${tail}"
  export PATH
}

# A tool sync needs and cannot find: say which, never "could not reach the host". git that
# is only the macOS stand-in (xcrun: no command line tools) is not installed either (r8).
sync_need() {
  local t out
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || sync_die 1 "${t} not found: install it, or run join again"
    [ "$t" = "git" ] || continue
    if ! out=$(git --version 2>&1); then
      case "$out" in
        *"xcrun: error"*|*"invalid active developer path"*|*"CommandLineTools"*)
          sync_die 1 "git not installed: install the Xcode command line tools, or run join again" ;;
        *) sync_die 1 "git does not run ($(printf '%s' "$out" | head -n 1)): install it, or run join again" ;;
      esac
    fi
  done
}

sync_bind() {
  local line
  sync_path_add /opt/homebrew/bin /usr/local/bin "${HOME:+$HOME/.local/bin}"
  SYNC_ROOT=$(sync_find_root)
  export OS_PROFILE="${OS_PROFILE:-$SYNC_ROOT/company-profile.md}"
  if [ -n "${OS_HOST_SH:-}" ]; then
    HOST_SH=$OS_HOST_SH
  else
    HOST_SH="$SYNC_DIR/../_host/host.sh"
  fi
  if [ -n "${OS_PROFILE_SH:-}" ]; then
    PROFILE_SH=$OS_PROFILE_SH
  else
    PROFILE_SH="$(dirname "$HOST_SH")/profile.sh"
  fi
  [ -f "$PROFILE_SH" ] || sync_die 1 "profile.sh is missing"
  SYNC_SLUG=$("$PROFILE_SH" company_slug 2>/dev/null || true)
  [ -n "$SYNC_SLUG" ] || sync_die 1 "company_slug is not set"
  SYNC_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/${SYNC_SLUG}-os"
  # The folders of the tools that join found (install-jobs writes them, B70).
  if [ -f "$SYNC_CONFIG/tool-path" ]; then
    while IFS= read -r line; do
      sync_path_add "$line"
    done < "$SYNC_CONFIG/tool-path"
  fi
  sync_need git jq
  if [ "$("$PROFILE_SH" host 2>/dev/null || true)" = "github" ] && [ -z "${OS_HOST_SH:-}" ]; then
    sync_need gh
  fi
  SYNC_STATE="$SYNC_CONFIG/state"
  mkdir -p "$SYNC_STATE"
  chmod 700 "$SYNC_CONFIG" "$SYNC_STATE"
  SYNC_LOG="$SYNC_STATE/sync.log"
  SYNC_HELD="$SYNC_STATE/held.json"
  # Used by helper.sh and pull.sh after this file is sourced.
  # shellcheck disable=SC2034
  SYNC_HELPER="$SYNC_STATE/helper.json"
  # shellcheck disable=SC2034
  SYNC_REWRITE="$SYNC_STATE/rewrite"
  touch "$SYNC_LOG"
  chmod 600 "$SYNC_LOG"
  if [ ! -f "$SYNC_HELD" ]; then
    printf '%s\n' '{"last_error":"","files":[]}' > "$SYNC_HELD"
    chmod 600 "$SYNC_HELD"
  fi
}

sync_log() {
  printf '%s %s\n' "$(sync_now)" "$*" >> "$SYNC_LOG"
}

sync_lock_take() {
  local dir=$1
  local got
  if ! mkdir "$dir" 2>/dev/null; then
    return 1
  fi
  printf '%s\n' "$$" > "$dir/pid"
  got=$(cat "$dir/pid" 2>/dev/null || true)
  if [ "$got" != "$$" ]; then
    return 1
  fi
  SYNC_LOCK_DIR=$dir
  return 0
}

sync_lock() {
  local dir pid
  dir="$SYNC_STATE/lock"
  if sync_lock_take "$dir"; then
    return 0
  fi
  pid=$(cat "$dir/pid" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    sync_die 1 "another sync is running"
  fi
  rm -rf "$dir"
  if ! sync_lock_take "$dir"; then
    sync_die 1 "another sync is running"
  fi
}

sync_me() {
  local file
  file="$SYNC_CONFIG/me"
  if [ ! -f "$file" ]; then
    printf '%s\n' ""
    return 0
  fi
  tr -d '[:space:]' < "$file"
}

# One id per computer, made once (at join, or at the first push on this code): the
# host name, cut to a slug, and four random characters, so two computers with the same
# name still differ. Push sends to sync/<me>/<seat>.
sync_seat() {
  local file="$SYNC_CONFIG/seat" seat
  if [ -f "$file" ]; then
    seat=$(tr -d '[:space:]' < "$file")
    if sync_safe_slug "$seat"; then
      printf '%s\n' "$seat"
      return 0
    fi
  fi
  seat=$( (hostname 2>/dev/null || uname -n) | cut -d. -f1 | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9\n' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c 1-24 | sed 's/-$//')
  sync_safe_slug "$seat" || seat=seat
  seat="${seat}-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s\n' "$seat" > "$file"
  chmod 600 "$file"
  printf '%s\n' "$seat"
}

sync_profile() {
  local key=$1
  "$PROFILE_SH" "$key" 2>/dev/null || true
}

sync_level() {
  sync_profile level
}

sync_people_field() {
  local slug=$1 key=$2
  local f line
  for f in "$SYNC_ROOT"/people/*.md; do
    [ -f "$f" ] || continue
    line=$(awk -v key="slug" '
      BEGIN { fm = 0 }
      /^---[[:space:]]*$/ { fm++; if (fm == 2) exit; next }
      fm == 1 && $0 ~ "^" key ":[[:space:]]*" {
        sub("^" key ":[[:space:]]*", "")
        gsub(/^["'\'']|["'\'']$/, "")
        print
        exit
      }
    ' "$f")
    if [ "$line" = "$slug" ]; then
      awk -v key="$key" '
        BEGIN { fm = 0 }
        /^---[[:space:]]*$/ { fm++; if (fm == 2) exit; next }
        fm == 1 && $0 ~ "^" key ":[[:space:]]*" {
          sub("^" key ":[[:space:]]*", "")
          gsub(/^["'\'']|["'\'']$/, "")
          print
          exit
        }
      ' "$f"
      return 0
    fi
  done
  return 1
}

sync_is_rules() {
  local path=$1
  local base
  base=$(basename "$path")
  case "$base" in
    AGENTS.md|CLAUDE.md|review-rules.md|CODEOWNERS|company-rules.md|area-rules.md) return 0 ;;
  esac
  case "$path" in
    skills/*|*/skills/*|.github/*|*/.github/*|.gitea/*|*/.gitea/*|.forgejo/*|*/.forgejo/*|.claude/*|*/.claude/*|docs/CODEOWNERS|*/docs/CODEOWNERS|bots/*/BOT.md) return 0 ;;
  esac
  return 1
}

sync_safe_slug() {
  local v=$1
  case "$v" in
    ""|*[!a-z0-9-]*|*/*|-*|*-) return 1 ;;
  esac
  return 0
}

sync_xml() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

sync_held_error() {
  local msg=$1
  local tmp
  if [ -n "$msg" ]; then
    # push.sh reads it: a later repo in the same run must not clear this error.
    # shellcheck disable=SC2034
    SYNC_RUN_ERROR=1
  fi
  tmp=$(sync_mktemp)
  jq --arg e "$msg" '.last_error = $e' "$SYNC_HELD" > "$tmp"
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
}

# A pull or push that went through for every repo clears the last error, whatever left
# it. Never one this run set: a later repo's error stays.
sync_clear_error() {
  [ -z "${SYNC_RUN_ERROR:-}" ] || return 0
  [ -f "${SYNC_HELD:-}" ] || return 0
  [ -n "$(jq -r '.last_error // ""' "$SYNC_HELD")" ] || return 0
  sync_held_error ""
}

# Push holds for one repo are worked out again each push. A re-apply hold stays until
# the agent is done with it (re-apply.sh done).
sync_held_replace() {
  local repo=$1
  local added=$2
  local tmp
  tmp=$(sync_mktemp)
  if [ -s "$added" ]; then
    jq -s --arg repo "$repo" '.[0].files = ([.[0].files[] | select(.repo != $repo or .kind == "re-apply")] + .[1:]) | .[0]' \
      "$SYNC_HELD" "$added" > "$tmp"
  else
    jq --arg repo "$repo" '.files = [.files[] | select(.repo != $repo or .kind == "re-apply")]' "$SYNC_HELD" > "$tmp"
  fi
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
}

# A push hold on a file main now has (a rules file whose pull request merged) is over.
sync_held_drop() {
  local tmp
  [ -f "${SYNC_HELD:-}" ] || return 0
  tmp=$(sync_mktemp)
  jq --arg repo "$1" --arg path "$2" \
    '.files = [.files[] | select(.repo != $repo or .path != $path or .kind == "re-apply")]' "$SYNC_HELD" > "$tmp"
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
}

# Drop held files that are gone, so a session never tells the person about a file that is
# not there. Ids: root, area:<name>, workspace. An unknown id stays.
sync_held_prune() {
  local tmp keep id path dir me line mine
  [ -f "$SYNC_HELD" ] || return 0
  me=$(sync_me 2>/dev/null || true)
  keep=$(sync_mktemp)
  printf '%s\n' '[]' > "$keep"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(printf '%s' "$line" | jq -r '.repo // ""')
    path=$(printf '%s' "$line" | jq -r '.path // ""')
    case "$id" in
      root) dir=$SYNC_ROOT ;;
      area:*) dir="$SYNC_ROOT/areas/${id#area:}" ;;
      workspace) dir="$SYNC_ROOT/users/${me}" ;;
      *) dir="" ;;
    esac
    # A re-apply hold names a file the host may have deleted. It goes with its set-aside copy.
    if [ "$(printf '%s' "$line" | jq -r '.kind // ""')" = "re-apply" ]; then
      mine=$(printf '%s' "$line" | jq -r '.mine // ""')
      if [ "$mine" != "deleted" ] && [ ! -f "$mine" ]; then
        sync_log "held gone ${id} ${path} re-apply"
        continue
      fi
    elif [ -n "$dir" ] && [ -n "$path" ] && [ ! -e "$dir/$path" ] && [ ! -L "$dir/$path" ]; then
      sync_log "held gone ${id} ${path}"
      continue
    fi
    tmp=$(sync_mktemp)
    jq --argjson f "$line" '. + [$f]' "$keep" > "$tmp"
    mv "$tmp" "$keep"
  done << EOF
$(jq -c '.files[]?' "$SYNC_HELD")
EOF
  tmp=$(sync_mktemp)
  jq --slurpfile k "$keep" '.files = $k[0]' "$SYNC_HELD" > "$tmp"
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
  rm -f "$keep"
}

sync_hold_line() {
  local repo=$1 path=$2 reason=$3
  jq -nc --arg repo "$repo" --arg path "$path" --arg reason "$reason" \
    '{repo:$repo, path:$path, reason:$reason}'
}

sync_remote_name() {
  local repo=$1
  local url name
  url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
  [ -n "$url" ] || return 1
  case "$url" in
    *://*@*) sync_die 1 "refusing a credential in the remote URL" ;;
  esac
  name=${url##*/}
  name=${name%.git}
  printf '%s\n' "$name"
}

sync_git_login() {
  local me login
  me=$(sync_me)
  if [ -n "$me" ]; then
    login=$(sync_people_field "$me" github || true)
    if [ -n "$login" ]; then
      printf '%s\n' "$login"
      return 0
    fi
  fi
  printf '%s\n' "git"
}

sync_token() {
  local me token err rc
  me=$(sync_me)
  err=$(sync_mktemp)
  set +e
  if [ -n "$me" ] && [ -f "$SYNC_ROOT/bots/$me/BOT.md" ]; then
    token=$("$HOST_SH" get-token --bot "$me" 2>"$err" | tr -d '\r\n')
    rc=$?
  else
    token=$("$HOST_SH" get-token 2>"$err" | tr -d '\r\n')
    rc=$?
  fi
  set -e
  if [ "$rc" -ne 0 ] || [ -z "$token" ]; then
    token=""
    return "$rc"
  fi
  printf '%s' "$token"
  token=""
}

sync_git() {
  local dir=$1
  shift
  local ask token user rc
  ask=$(sync_askpass)
  set +e
  token=$(sync_token)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] || [ -z "$token" ]; then
    token=""
    return "${rc:-4}"
  fi
  user=$(sync_git_login)
  set +e
  OS_GIT_USER="$user" OS_GIT_TOKEN="$token" GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
    git -C "$dir" -c credential.helper= -c commit.gpgsign=false "$@"
  rc=$?
  set -e
  token=""
  return "$rc"
}

sync_under_home() {
  local path home
  path=$(sync_abs "$1")
  home=$(sync_abs "$HOME")
  case "$path" in
    "$home"|"$home"/*) return 0 ;;
  esac
  return 1
}

sync_company_of() {
  local p=$1
  if [ ! -d "$p" ]; then
    p=$(dirname "$p")
  fi
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    if [ -f "$p/company-profile.md" ]; then
      sync_abs "$p"
      return 0
    fi
    p=$(dirname "$p")
  done
  return 1
}

sync_on_shared() {
  local path=$1
  local list line
  list="${XDG_CONFIG_HOME:-$HOME/.config}/os-shared-list"
  [ -f "$list" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
    esac
    line=${line%/}
    case "$path" in
      "$line"|"$line"/*) return 0 ;;
    esac
  done < "$list"
  return 1
}
