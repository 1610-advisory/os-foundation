#!/bin/bash
# Shared helpers for the team scripts. Source this file. Do not run it.
# Bash 3.2. No token, key, or secret is passed in a child's arguments.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf '%s\n' "Source this file. Do not run it." >&2
  exit 1
fi

os_die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

os_have() {
  command -v "$1" >/dev/null 2>&1
}

os_need() {
  local cmd
  for cmd in "$@"; do
    os_have "$cmd" || os_die 3 "$cmd is not installed"
  done
}

os_today() {
  local n=${OS_NOW:-}
  if [ -n "$n" ]; then
    printf '%.10s\n' "$n"
    return 0
  fi
  date +%Y-%m-%d
}

os_stamp() {
  date +%Y%m%d%H%M%S
}

os_trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

os_unquote() {
  local s=$1
  if [ "${#s}" -ge 2 ]; then
    case "$s" in
      \"*\") s=${s#\"}; s=${s%\"} ;;
      \'*\') s=${s#\'}; s=${s%\'} ;;
    esac
  fi
  printf '%s' "$s"
}

os_yaml_quote() {
  local s=$1
  case "$s" in
    ""|*[!A-Za-z0-9._/-]*)
      s=$(printf '%s' "$s" | sed 's/\\/\\\\/g; s/"/\\"/g')
      printf '"%s"' "$s"
      ;;
    *)
      printf '%s' "$s"
      ;;
  esac
}

# Answers file: key=value, first = splits, # comments ignored.
os_answer() {
  local key=$1 file=$2 line k v
  [ -n "${file:-}" ] || return 2
  [ -f "$file" ] || return 2
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in
      ""|\#*) continue ;;
    esac
    k=${line%%=*}
    v=${line#*=}
    if [ "$k" = "$key" ]; then
      printf '%s' "$v"
      return 0
    fi
  done < "$file"
  return 2
}

os_answer_or() {
  local key=$1 file=$2 fallback=$3 val
  if val=$(os_answer "$key" "$file"); then
    printf '%s' "$val"
  else
    printf '%s' "$fallback"
  fi
}

os_person_slugs() {
  local file=$1 line slug
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in
      ""|\#*) continue ;;
      person.*) ;;
      *) continue ;;
    esac
    slug=${line#person.}
    slug=${slug%%.*}
    case "$slug" in
      ""|*[!A-Za-z0-9_-]*) continue ;;
    esac
    printf '%s\n' "$slug"
  done < "$file" | awk '!seen[$0]++'
}

os_synced_reason() {
  local path=$1 home base
  [ -d "$path" ] || return 1
  path=$(cd "$path" && pwd -P)
  case "$path" in
    /Volumes/GoogleDrive*) printf '%s\n' "Google Drive volume"; return 0 ;;
  esac
  home=${HOME:-}
  [ -n "$home" ] || return 1
  base=$(cd "$home" && pwd -P)
  case "$path" in
    "$base/Library/Mobile Documents"|"$base/Library/Mobile Documents"/*)
      printf '%s\n' "iCloud Drive"
      return 0
      ;;
    "$base/Library/CloudStorage"|"$base/Library/CloudStorage"/*)
      printf '%s\n' "a cloud storage folder"
      return 0
      ;;
    "$base"/Dropbox*)
      printf '%s\n' "Dropbox"
      return 0
      ;;
    "$base"/OneDrive*)
      printf '%s\n' "OneDrive"
      return 0
      ;;
    "$base/Google Drive"|"$base/Google Drive"/*)
      printf '%s\n' "Google Drive"
      return 0
      ;;
  esac
  if [ -d "$base/Library/Mobile Documents/com~apple~CloudDocs/Desktop" ]; then
    case "$path" in
      "$base/Desktop"|"$base/Desktop"/*)
        printf '%s\n' "iCloud Desktop"
        return 0
        ;;
      "$base/Documents"|"$base/Documents"/*)
        printf '%s\n' "iCloud Documents"
        return 0
        ;;
    esac
  fi
  return 1
}

os_refuse_synced() {
  local path=$1 reason
  if reason=$(os_synced_reason "$path"); then
    os_die 2 "refusing a company folder in a synced folder: ${reason}"
  fi
}

os_fm_get() {
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
    BEGIN { fm = 0; n = 0; found = 0 }
    {
      gsub(/\r/, "", $0)
    }
    /^---[[:space:]]*$/ {
      n++
      if (n == 1) { fm = 1; next }
      exit
    }
    fm != 1 { next }
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

os_fm_set() {
  local file=$1 key=$2 value=$3 tmp
  tmp=$(mktemp)
  awk -v key="$key" -v value="$value" '
    BEGIN { fm = 0; n = 0; done = 0 }
    {
      line = $0
      gsub(/\r/, "", line)
    }
    n == 0 && line ~ /^---[[:space:]]*$/ {
      fm = 1
      n = 1
      print line
      next
    }
    fm == 1 && line ~ /^---[[:space:]]*$/ {
      if (!done) {
        printf "%s: %s\n", key, value
      }
      fm = 0
      print line
      next
    }
    fm == 1 {
      k = line
      sub(/:.*/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k == key) {
        printf "%s: %s\n", key, value
        done = 1
        next
      }
    }
    { print line }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

os_company_name() {
  local file=$1 line
  line=$(grep -m 1 '^# ' "$file" 2>/dev/null || true)
  line=${line#\# }
  line=$(os_trim "$line")
  printf '%s' "$line"
}

os_find_host() {
  local root=$1 script_dir=$2
  if [ -n "${OS_HOST_SH:-}" ] && [ -f "$OS_HOST_SH" ]; then
    printf '%s\n' "$OS_HOST_SH"
    return 0
  fi
  if [ -f "$root/skills/_host/host.sh" ]; then
    printf '%s\n' "$root/skills/_host/host.sh"
    return 0
  fi
  if [ -n "$script_dir" ] && [ -f "$script_dir/../_host/host.sh" ]; then
    printf '%s\n' "$script_dir/../_host/host.sh"
    return 0
  fi
  return 1
}

# Run host.sh. Stdout is the JSON. Stderr is passed through.
# Exit code is the host exit code. Never puts a secret in argv.
os_host() {
  [ -n "${OS_HOST_BIN:-}" ] || os_die 3 "host.sh is missing"
  [ -x "$OS_HOST_BIN" ] || chmod +x "$OS_HOST_BIN" 2>/dev/null || true
  "$OS_HOST_BIN" "$@"
}

os_host_try() {
  local rc
  set +e
  os_host "$@"
  rc=$?
  set -e
  return "$rc"
}

os_config_dir() {
  local slug=$1
  printf '%s/%s-os' "${XDG_CONFIG_HOME:-$HOME/.config}" "$slug"
}

os_company_repo() {
  printf '%s-os' "$1"
}

os_area_repo() {
  printf '%s-%s' "$1" "$2"
}

os_user_repo() {
  printf '%s-user-%s' "$1" "$2"
}

os_team_area() {
  printf 'area-%s' "$1"
}

os_clone_url() {
  local host=$1 host_url=$2 org=$3 name=$4 base
  case "$host" in
    github)
      if [ -n "$host_url" ]; then
        base=${host_url%/}
      else
        base="https://github.com"
      fi
      ;;
    forgejo)
      [ -n "$host_url" ] || os_die 1 "host_url is not set"
      base=${host_url%/}
      ;;
    *)
      os_die 1 "host is not supported"
      ;;
  esac
  case "$base" in
    *'@'*) os_die 3 "refusing a credential in a clone URL" ;;
  esac
  printf '%s/%s/%s.git' "$base" "$org" "$name"
}

# Run a command with git credentials in the environment, not in argv.
# Token is read from host.sh get-token into a mode-600 file, then into the env.
os_with_git_token() {
  local token_file ask user_json user rc was_e
  token_file=$(mktemp)
  ask=$(mktemp)
  chmod 600 "$token_file"
  chmod 700 "$ask"
  if ! os_host get-token > "$token_file"; then
    rm -f "$token_file" "$ask"
    os_die 4 "could not read the git token"
  fi
  # Drop a trailing newline. The value stays in the file.
  if [ -s "$token_file" ]; then
    user_json=$(os_host whoami)
    user=$(printf '%s' "$user_json" | jq -r '.login // empty')
  fi
  if [ -z "${user:-}" ]; then
    user=${OS_ORG:-git}
  fi
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
  chmod 700 "$ask"
  if [ "${1:-}" = "git" ]; then
    shift
    set -- git -c credential.helper= "$@"
  fi
  case $- in
    *e*) was_e=1 ;;
    *) was_e=0 ;;
  esac
  set +e
  # shellcheck disable=SC2091
  OS_GIT_USER="$user" \
    OS_GIT_TOKEN="$(tr -d '\r\n' < "$token_file")" \
    GIT_ASKPASS="$ask" \
    GIT_TERMINAL_PROMPT=0 \
    "$@"
  rc=$?
  if [ "$was_e" -eq 1 ]; then
    set -e
  fi
  rm -f "$token_file" "$ask"
  return "$rc"
}

os_git_commit() {
  local dir=$1 msg=$2
  (
    cd "$dir" || exit 1
    git add -A
    if git diff --cached --quiet; then
      exit 0
    fi
    GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
      GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
      GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
      GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
      git commit -m "$msg"
  )
}

os_origin_exists() {
  local dir=$1
  git -C "$dir" rev-parse --verify origin/main >/dev/null 2>&1
}

# Point origin at the host clone URL. Never pushes.
# fetch_if_added=1: the repo already exists. Fetch when origin was missing,
# and again when a failed fetch left no origin/main.
os_ensure_origin() {
  local dir="$1" name="$2" host="$3" host_url="$4" org="$5" fetch_if_added="$6"
  local url had=0 got current=""
  url=$(os_clone_url "$host" "$host_url" "$org" "$name")
  current=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
  if [ -n "$current" ]; then
    had=1
    if [ "$current" != "$url" ]; then
      git -C "$dir" remote set-url origin "$url"
    fi
  else
    git -C "$dir" remote add origin "$url"
  fi
  if [ "$fetch_if_added" = "1" ]; then
    if [ "$had" -eq 0 ] || ! git -C "$dir" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
      if ! os_with_git_token git -C "$dir" fetch origin; then
        os_die 3 "could not fetch origin for $name"
      fi
    fi
  fi
  got=$(git -C "$dir" remote get-url origin)
  if [ "$got" != "$url" ]; then
    os_die 3 "origin for $name is not the host clone URL"
  fi
}

os_person_file() {
  local root=$1 slug=$2 f got
  [ -d "$root/people" ] || return 1
  for f in "$root"/people/*.md; do
    [ -f "$f" ] || continue
    case "$f" in
      */README.md) continue ;;
    esac
    got=$(os_fm_get "$f" slug 2>/dev/null || true)
    if [ "$got" = "$slug" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

os_areas_on_disk() {
  local root=$1 d base
  [ -d "$root/areas" ] || return 0
  for d in "$root"/areas/*; do
    [ -d "$d" ] || continue
    [ -e "$d/.git" ] || continue
    base=$(basename "$d")
    case "$base" in
      .*) continue ;;
    esac
    printf '%s\n' "$base"
  done
}

# Write both owner files. GitHub reads .github/CODEOWNERS (globs).
# Forgejo reads .gitea/CODEOWNERS (regular expressions), not .github/CODEOWNERS.
# A file the host ignores is harmless. One writer covers both hosts.
os_codeowners() {
  local root=$1
  shift
  local users=$*
  mkdir -p "$root/.github" "$root/.gitea"
  {
    printf '%s\n' "# Rules files only. Notes have no code owner."
    printf '%s\n' "/AGENTS.md $users"
    printf '%s\n' "/CLAUDE.md $users"
    printf '%s\n' "/review-rules.md $users"
    printf '%s\n' "/skills/ $users"
    printf '%s\n' "/bots/*/BOT.md $users"
    printf '%s\n' "/.github/ $users"
    printf '%s\n' "/.gitea/ $users"
  } > "$root/.github/CODEOWNERS"
  {
    printf '%s\n' "# Rules files only. Notes have no code owner."
    printf '%s %s\n' '^AGENTS\.md$' "$users"
    printf '%s %s\n' '^CLAUDE\.md$' "$users"
    printf '%s %s\n' '^review-rules\.md$' "$users"
    printf '%s %s\n' '^skills/.*' "$users"
    printf '%s %s\n' '^bots/[^/]+/BOT\.md$' "$users"
    printf '%s %s\n' '^\.github/.*' "$users"
    printf '%s %s\n' '^\.gitea/.*' "$users"
  } > "$root/.gitea/CODEOWNERS"
}

os_at_users() {
  local admin=$1 director=$2
  if [ -z "$director" ] || [ "$director" = "$admin" ]; then
    printf '@%s' "$admin"
  else
    printf '@%s @%s' "$director" "$admin"
  fi
}

os_fill_placeholders() {
  local dest=$1 slug=$2 name=$3 company_slug=$4 company_name=$5 f ob cb
  # Split the braces. A line that holds both pairs looks like a placeholder.
  ob='{{'
  cb='}}'
  # Text files only. Do not print file contents.
  find "$dest" -type f | while IFS= read -r f; do
    case "$f" in
      *.png|*.jpg|*.gif|*.webp|*.pdf) continue ;;
    esac
    sed -i '' \
      -e "s/${ob}PERSON_SLUG${cb}/${slug}/g" \
      -e "s/${ob}PERSON${cb}/${name}/g" \
      -e "s/${ob}COMPANY_SLUG${cb}/${company_slug}/g" \
      -e "s/${ob}COMPANY_NAME${cb}/${company_name}/g" \
      "$f" 2>/dev/null || \
    sed -i \
      -e "s/${ob}PERSON_SLUG${cb}/${slug}/g" \
      -e "s/${ob}PERSON${cb}/${name}/g" \
      -e "s/${ob}COMPANY_SLUG${cb}/${company_slug}/g" \
      -e "s/${ob}COMPANY_NAME${cb}/${company_name}/g" \
      "$f"
  done
}

os_write_workspace() {
  local dest=$1 slug=$2 name=$3 company_slug=$4 company_name=$5 template=$6
  mkdir -p "$dest"
  if [ -d "$template" ]; then
    cp -R "$template/." "$dest/"
    os_fill_placeholders "$dest" "$slug" "$name" "$company_slug" "$company_name"
    printf '%s\n' "workspace-template: copied"
  else
    mkdir -p "$dest/profile" "$dest/skills" "$dest/drafts" "$dest/memory/logs"
    printf '%s\n' "# Workspace" > "$dest/AGENTS.md"
    printf '%s\n' "# Profile" > "$dest/profile/PROFILE.md"
    printf '%s\n' "Skills for this person." > "$dest/skills/README.md"
    printf '%s\n' "Drafts stay here until you share them." > "$dest/drafts/README.md"
    printf '%s\n' "One log file per day." > "$dest/memory/logs/README.md"
    printf '%s\n' "workspace-template: fallback"
  fi
  if [ ! -d "$dest/.git" ]; then
    git -C "$dest" init -q
    git -C "$dest" checkout -q -b main 2>/dev/null || git -C "$dest" symbolic-ref HEAD refs/heads/main
    os_git_commit "$dest" "Workspace: start"
  fi
}

os_write_person_page() {
  local root=$1 slug=$2 name=$3 github=$4 email=$5 role=$6 areas=$7 manager=$8
  local page dir area_yaml a first
  dir="$root/people"
  mkdir -p "$dir"
  page="$dir/${name}.md"
  area_yaml="["
  first=1
  # shellcheck disable=SC2086
  for a in $(printf '%s' "$areas" | tr ',' ' '); do
    a=$(os_trim "$a")
    [ -n "$a" ] || continue
    if [ "$first" -eq 1 ]; then
      area_yaml="${area_yaml}${a}"
      first=0
    else
      area_yaml="${area_yaml}, ${a}"
    fi
  done
  area_yaml="${area_yaml}]"
  if [ -f "$page" ]; then
    os_fm_set "$page" slug "$slug"
    os_fm_set "$page" github "$github"
    os_fm_set "$page" email "$(os_yaml_quote "$email")"
    os_fm_set "$page" role "$role"
    os_fm_set "$page" areas "$area_yaml"
    if [ -n "$manager" ]; then
      os_fm_set "$page" manager "$manager"
    fi
  else
    cat > "$page" << EOF
---
type: person
summary: ""
job_title: ""
company: ""
related: []
slug: ${slug}
github: ${github}
email: $(os_yaml_quote "$email")
role: ${role}
areas: ${area_yaml}
kernel_id: ""
left: ""
manager: ${manager}
terms_accepted: ""
---

# ${name}

## Who they are

## Notes
EOF
  fi
  printf '%s\n' "$page"
}

os_review_state() {
  local out rc
  set +e
  out=$(os_host secret-exists OS_REVIEW_KEY 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "unchecked"
    return 0
  fi
  if printf '%s' "$out" | jq -e '.exists == true' >/dev/null 2>&1; then
    printf '%s\n' "key-set"
    return 0
  fi
  printf '%s\n' "weaker"
}

os_repo_url() {
  local host=$1 host_url=$2 org=$3 name=$4 base
  case "$host" in
    github)
      if [ -n "$host_url" ]; then
        base=${host_url%/}
      else
        base="https://github.com"
      fi
      ;;
    *)
      base=${host_url%/}
      ;;
  esac
  printf '%s/%s/%s' "$base" "$org" "$name"
}

os_hand_off() {
  local slug=$1 name=$2 org=$3 company_repo=$4 areas=$5 ws=$6 host=$7 host_url=$8
  local company_url ws_url
  company_url=$(os_repo_url "$host" "$host_url" "$org" "$company_repo")
  ws_url=$(os_repo_url "$host" "$host_url" "$org" "$ws")
  printf 'hand-off: %s\n' "$slug"
  printf 'Hand-off for %s. Company repo: %s. Host: %s. Areas: %s. Workspace: %s. Clone the company repo with your own sign-in, then run skills/add-teammate/join.sh from inside that clone.\n' \
    "$name" "$company_url" "$host_url" "$areas" "$ws_url"
}

os_split_areas() {
  local a
  # A trailing newline is required. read drops a last line that has none.
  printf '%s\n' "$1" | tr ',' '\n' | while IFS= read -r a || [ -n "$a" ]; do
    a=$(os_trim "$a")
    [ -n "$a" ] || continue
    printf '%s\n' "$a"
  done
}

os_admin_slug_from_pages() {
  local root=$1 f role left slug
  for f in "$root"/people/*.md; do
    [ -f "$f" ] || continue
    case "$f" in
      */README.md) continue ;;
    esac
    role=$(os_fm_get "$f" role 2>/dev/null || true)
    left=$(os_fm_get "$f" left 2>/dev/null || true)
    slug=$(os_fm_get "$f" slug 2>/dev/null || true)
    if [ "$role" = "admin" ] && [ -z "$left" ] && [ -n "$slug" ]; then
      printf '%s\n' "$slug"
      return 0
    fi
  done
  return 1
}

os_count_admins() {
  local root=$1 f role left n=0
  for f in "$root"/people/*.md; do
    [ -f "$f" ] || continue
    case "$f" in
      */README.md) continue ;;
    esac
    role=$(os_fm_get "$f" role 2>/dev/null || true)
    left=$(os_fm_get "$f" left 2>/dev/null || true)
    if [ "$role" = "admin" ] && [ -z "$left" ]; then
      n=$((n + 1))
    fi
  done
  printf '%s\n' "$n"
}

os_epoch() {
  local d=$1 s
  if s=$(date -j -f "%Y-%m-%d" "$d" "+%s" 2>/dev/null); then
    printf '%s' "$s"
    return 0
  fi
  date -d "$d" "+%s"
}
