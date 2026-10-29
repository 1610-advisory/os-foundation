#!/bin/bash
# Shared helpers for add-bot, run, and undo-run. Source this file. Do not run it.
# The mktemp function below wraps the system one. Calls with no arguments are on purpose.
# shellcheck disable=SC2119,SC2120

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf '%s\n' "Source this file. Do not run it." >&2
  exit 1
fi

bot_die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

bot_have() {
  command -v "$1" >/dev/null 2>&1
}

bot_need() {
  bot_have "$1" || bot_die 3 "$1 is not installed"
}

BOT_TMP_FILES=""
# bot_mktemp runs in $( ), so the list above never reaches this shell. Every temp file goes
# in one folder made here instead, and bot_cleanup (each entry script's EXIT trap) removes
# it. A scheduled bot run leaves nothing behind.
BOT_RUN_TMP=$(command mktemp -d "${TMPDIR:-/tmp}/os-bot.XXXXXX") || bot_die 1 "could not make a temp folder: check the free disk space"
chmod 700 "$BOT_RUN_TMP"
export TMPDIR="$BOT_RUN_TMP"
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
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

bot_mktemp() {
  local f
  f=$(mktemp)
  chmod 600 "$f"
  BOT_TMP_FILES="${BOT_TMP_FILES} ${f}"
  printf '%s\n' "$f"
}

bot_cleanup() {
  local f
  # shellcheck disable=SC2086
  for f in $BOT_TMP_FILES; do
    rm -rf "$f"
  done
  BOT_TMP_FILES=""
  rm -rf "$BOT_RUN_TMP"
}

bot_slug_ok() {
  local what=$1 val=$2
  case "$val" in
    ""|.*|*/|*[[:space:]]*)
      bot_die 1 "$what is not a plain name"
      ;;
  esac
  case "$val" in
    *[!A-Za-z0-9._-]*)
      bot_die 1 "$what has invalid characters"
      ;;
  esac
}

bot_trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Print one frontmatter value. A list prints one item per line.
# Exit 2 when the key is absent. Empty list prints nothing and exits 0.
bot_field() {
  local file=$1 key=$2
  [ -f "$file" ] || return 2
  awk -v key="$key" '
    function strip(s) {
      gsub(/\r/, "", s)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    function unquote(s) {
      if (s ~ /^".*"$/ || s ~ /^'\''.*'\''$/) {
        return substr(s, 2, length(s) - 2)
      }
      return s
    }
    BEGIN { in_fm = 0; fm_count = 0; mode = "none"; found = 0 }
    {
      gsub(/\r/, "", $0)
    }
    /^---[[:space:]]*$/ {
      fm_count++
      if (fm_count == 1) { in_fm = 1; next }
      if (fm_count >= 2) { exit }
    }
    !in_fm { next }
    mode == "list" {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        item = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        item = unquote(strip(item))
        print item
        next
      }
      exit
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      line = strip($0)
      if (line !~ /^[^:]+:/) { next }
      k = line
      sub(/:.*/, "", k)
      k = strip(k)
      if (k != key) { next }
      found = 1
      val = line
      sub(/^[^:]*:[[:space:]]*/, "", val)
      val = strip(val)
      if (val == "" || val == "|" || val == ">") {
        mode = "list"
        next
      }
      if (val == "[]") { exit }
      if (val ~ /^\[[^]]*\]$/) {
        inner = substr(val, 2, length(val) - 2)
        n = split(inner, items, ",")
        for (i = 1; i <= n; i++) {
          item = unquote(strip(items[i]))
          if (item != "") { print item }
        }
        exit
      }
      if (val !~ /^["'\''].*["'\'']$/) {
        sub(/[[:space:]]+#.*$/, "", val)
        val = strip(val)
      }
      print unquote(val)
      exit
    }
    END { if (!found) exit 2 }
  ' "$file"
}

bot_find_root() {
  local dir parent
  if [ -n "${BOT_ROOT_ARG:-}" ]; then
    [ -f "${BOT_ROOT_ARG}/company-profile.md" ] || bot_die 1 "company-profile.md not found"
    (cd "$BOT_ROOT_ARG" && pwd -P)
    return 0
  fi
  if [ -n "${OS_PROFILE:-}" ]; then
    [ -f "$OS_PROFILE" ] || bot_die 1 "OS_PROFILE is missing"
    (cd "$(dirname "$OS_PROFILE")" && pwd -P)
    return 0
  fi
  if [ -n "${OS_ROOT:-}" ] && [ -f "${OS_ROOT}/company-profile.md" ]; then
    (cd "$OS_ROOT" && pwd -P)
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
      bot_die 1 "company-profile.md not found"
    fi
    dir=$parent
  done
}

bot_profile() {
  if [ -n "${OS_PROFILE:-}" ] && [ -f "$OS_PROFILE" ]; then
    printf '%s\n' "$OS_PROFILE"
    return 0
  fi
  printf '%s\n' "${BOT_ROOT}/company-profile.md"
}

bot_has_switch() {
  local name=$1 file line
  file=$(bot_profile)
  while IFS= read -r line; do
    [ "$line" = "$name" ] && return 0
  done << EOF
$(bot_field "$file" switches || true)
EOF
  return 1
}

bot_require_switch() {
  local name=$1
  if ! bot_has_switch "$name"; then
    bot_die 2 "${name} switch is off"
  fi
}

bot_config_dir() {
  local slug file
  file=$(bot_profile)
  slug=$(bot_field "$file" company_slug) || bot_die 1 "company slug is not set"
  slug=$(bot_trim "$slug")
  bot_slug_ok "company slug" "$slug"
  printf '%s/%s-os' "${XDG_CONFIG_HOME:-$HOME/.config}" "$slug"
}

bot_now_epoch() {
  if [ -n "${OS_NOW:-}" ]; then
    case "$OS_NOW" in
      *[!0-9]*) bot_die 1 "OS_NOW must be an epoch second" ;;
    esac
    printf '%s\n' "$OS_NOW"
    return 0
  fi
  date +%s
}

bot_now_utc() {
  local epoch=$1 fmt=$2
  # GNU date -r reads a file mtime. Do not probe it.
  case "$(uname -s)" in
    Darwin)
      date -u -r "$epoch" +"$fmt"
      ;;
    *)
      date -u -d "@${epoch}" +"$fmt"
      ;;
  esac
}

# Scope is the repo name. <slug>-os is the company repo. <slug>-<area> is that area.
bot_name_scope() {
  local slug=$1 repo=$2
  if [ "$repo" = "${slug}-os" ]; then
    printf '%s\n' company
    return 0
  fi
  case "$repo" in
    "${slug}-"*)
      printf '%s\n' "${repo#"${slug}-"}"
      return 0
      ;;
  esac
  return 1
}

bot_yaml_quote() {
  local s
  s=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '"%s"' "$s"
}

bot_file_mode() {
  local mode
  if mode=$(stat -f '%OLp' "$1" 2>/dev/null); then
    printf '%s\n' "$mode"
    return 0
  fi
  stat -c '%a' "$1"
}

bot_real_path() {
  local path=$1 dir base
  dir=$(dirname "$path")
  base=$(basename "$path")
  [ -d "$dir" ] || return 1
  printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

# Refuse a path inside the company repo, a relative path, or a symlink.
# chmod 600 when the mode is looser and the file is a regular file we can change.
bot_require_secret_file() {
  local path=$1 root=$2 real root_real mode
  case "$path" in
    /*) ;;
    *) bot_die 2 "secret file path must be absolute" ;;
  esac
  [ -f "$path" ] || bot_die 4 "secret file is missing"
  [ -L "$path" ] && bot_die 2 "refusing a symlink secret file"
  real=$(bot_real_path "$path") || bot_die 2 "secret file path is not valid"
  root_real=$(cd "$root" && pwd -P)
  case "$real" in
    "$root_real"|"$root_real"/*)
      bot_die 2 "secret file must stay outside the repo"
      ;;
  esac
  chmod 600 "$path" || bot_die 4 "could not set mode 0600 on the secret file"
  mode=$(bot_file_mode "$path")
  case "$mode" in
    600|400) ;;
    *) bot_die 4 "secret file mode is not 0600" ;;
  esac
}

bot_person_file() {
  local root=$1 slug=$2 file found line
  found=""
  for file in "$root"/people/*.md; do
    [ -f "$file" ] || continue
    line=$(bot_field "$file" slug || true)
    if [ "$line" = "$slug" ]; then
      found=$file
      break
    fi
  done
  [ -n "$found" ] || return 2
  printf '%s\n' "$found"
}

bot_list_has() {
  local want=$1 line
  while IFS= read -r line; do
    [ "$line" = "$want" ] && return 0
  done
  return 1
}

bot_handoff_rule() {
  printf '%s\n' "PR only, never merge. A hand-off runs only when the cloud-handoff switch is on, only on repos in this bot's grant, and only to a target the company has turned on."
}

bot_host_sh() {
  if [ -n "${OS_HOST_SH:-}" ]; then
    [ -f "$OS_HOST_SH" ] || bot_die 3 "OS_HOST_SH is missing"
    printf '%s\n' "$OS_HOST_SH"
    return 0
  fi
  [ -f "${BOT_ROOT}/skills/_host/host.sh" ] || bot_die 3 "host.sh is missing"
  printf '%s\n' "${BOT_ROOT}/skills/_host/host.sh"
}

bot_sync_sh() {
  [ -f "${BOT_ROOT}/skills/sync/sync.sh" ] || bot_die 3 "sync.sh is missing"
  printf '%s\n' "${BOT_ROOT}/skills/sync/sync.sh"
}

# Drop any line that contains the secret in OS_SCRUB. The secret is an env var, not an argument.
bot_scrub_file() {
  local src=$1 dest=$2
  if [ -z "${OS_SCRUB:-}" ]; then
    cp "$src" "$dest"
    chmod 600 "$dest"
    return 0
  fi
  awk 'index($0, ENVIRON["OS_SCRUB"]) == 0 { print }' "$src" > "$dest"
  chmod 600 "$dest"
}

bot_repo_path() {
  local root=$1 scope=$2
  if [ "$scope" = "company" ]; then
    printf '%s\n' "$root"
    return 0
  fi
  printf '%s\n' "${root}/areas/${scope}"
}

bot_is_git() {
  local path=$1
  [ -d "$path" ] || return 1
  [ -d "$path/.git" ] || [ -f "$path/.git" ]
}

bot_origin_name() {
  local path=$1 url
  url=$(git -C "$path" remote get-url origin 2>/dev/null || true)
  [ -n "$url" ] || return 1
  case "$url" in
    *'@'*) bot_die 3 "refusing a credential in a remote URL" ;;
  esac
  url=${url%.git}
  url=${url%/}
  printf '%s\n' "${url##*/}"
}
