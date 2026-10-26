#!/bin/bash
# Shared helpers for sync.sh. Source this file. Do not run it.
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

sync_die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

sync_mktemp() {
  local f
  f=$(mktemp)
  chmod 600 "$f"
  SYNC_TMP_FILES="${SYNC_TMP_FILES} ${f}"
  printf '%s\n' "$f"
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

sync_bind() {
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
  tmp=$(sync_mktemp)
  jq --arg e "$msg" '.last_error = $e' "$SYNC_HELD" > "$tmp"
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
}

sync_held_replace() {
  local repo=$1
  local added=$2
  local tmp
  tmp=$(sync_mktemp)
  if [ -s "$added" ]; then
    jq -s --arg repo "$repo" '.[0].files = ([.[0].files[] | select(.repo != $repo)] + .[1:]) | .[0]' \
      "$SYNC_HELD" "$added" > "$tmp"
  else
    jq --arg repo "$repo" '.files = [.files[] | select(.repo != $repo)]' "$SYNC_HELD" > "$tmp"
  fi
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
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
  ask=$(sync_mktemp)
  chmod 700 "$ask"
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
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
  rm -f "$ask"
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
