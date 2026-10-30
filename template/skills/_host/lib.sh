#!/bin/bash
# Shared helpers for the host layer. Source this file. Do not run it.
# The mktemp function below wraps the system one. Calls with no arguments are on purpose.
# shellcheck disable=SC2119,SC2120

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf '%s\n' "Source this file from host.sh. Do not run it." >&2
  exit 1
fi

host_die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

host_have() {
  command -v "$1" >/dev/null 2>&1
}

host_require_bin() {
  if ! host_have "$1"; then
    host_die 3 "$1 is not installed"
  fi
}

# Temp files removed on exit. host_mktemp runs in $( ), so the list below never reaches
# this shell: every temp file goes in one folder made here, and host_cleanup removes it.
# The trap is set here too, so a script that only sources this file cleans up.
HOST_TMP_FILES=""
HOST_PARENT_TMP=${HOST_PARENT_TMP:-${TMPDIR:-/tmp}}
# A second source in the same shell keeps the first folder.
if [ -z "${HOST_RUN_TMP:-}" ] || [ ! -d "$HOST_RUN_TMP" ]; then
  HOST_RUN_TMP=$(command mktemp -d "${TMPDIR:-/tmp}/os-host.XXXXXX") || host_die 1 "could not make a temp folder: check the free disk space"
  chmod 700 "$HOST_RUN_TMP"
  export TMPDIR="$HOST_RUN_TMP"
fi
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
trap host_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

host_mktemp() {
  local f
  f=$(mktemp)
  chmod 600 "$f"
  HOST_TMP_FILES="${HOST_TMP_FILES} ${f}"
  printf '%s\n' "$f"
}

host_cleanup() {
  local f
  # shellcheck disable=SC2086
  for f in $HOST_TMP_FILES; do
    rm -f "$f"
  done
  HOST_TMP_FILES=""
  rm -rf "$HOST_RUN_TMP"
}

host_find_profile() {
  local dir parent
  if [ -n "${OS_PROFILE:-}" ]; then
    if [ -f "$OS_PROFILE" ]; then
      printf '%s\n' "$OS_PROFILE"
      return 0
    fi
    return 1
  fi
  dir=$(pwd -P)
  while true; do
    if [ -f "$dir/company-profile.md" ]; then
      printf '%s\n' "$dir/company-profile.md"
      return 0
    fi
    parent=$(dirname "$dir")
    if [ "$parent" = "$dir" ]; then
      return 1
    fi
    dir=$parent
  done
}

# Print one frontmatter value. A list prints one item per line.
# Exit 2 when the key is absent.
host_profile_raw() {
  local file=$1 key=$2
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
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) { next }
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        item = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        item = strip(item)
        if (item !~ /^".*"$/ && item !~ /^['].*[']$/) {
          sub(/[[:space:]]+#.*$/, "", item)
          item = strip(item)
        }
        item = unquote(item)
        if (item != "") { print item }
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
      if (val !~ /^".*"$/ && val !~ /^['].*[']$/) {
        sub(/[[:space:]]+#.*$/, "", val)
        val = strip(val)
      }
      if (val ~ /^#/) {
        val = ""
      }
      if (val == "" || val == "|" || val == ">") {
        mode = "list"
        next
      }
      if (val == "[]") { exit }
      if (val ~ /^\[[^]]*\]$/) {
        inner = substr(val, 2, length(val) - 2)
        n = split(inner, items, ",")
        for (i = 1; i <= n; i++) {
          item = strip(items[i])
          if (item !~ /^".*"$/ && item !~ /^['].*[']$/) {
            sub(/[[:space:]]+#.*$/, "", item)
            item = strip(item)
          }
          item = unquote(item)
          if (item != "") { print item }
        }
        exit
      }
      print unquote(val)
      exit
    }
    END { if (!found) exit 2 }
  ' "$file"
}

host_env_override() {
  local key=$1
  case "$key" in
    host)
      if [ -n "${OS_HOST+x}" ]; then
        printf '%s\n' "$OS_HOST"
        return 0
      fi
      ;;
    host_url)
      if [ -n "${OS_HOST_URL+x}" ]; then
        printf '%s\n' "$OS_HOST_URL"
        return 0
      fi
      ;;
    org)
      if [ -n "${OS_ORG+x}" ]; then
        printf '%s\n' "$OS_ORG"
        return 0
      fi
      ;;
    sync_engine)
      if [ -n "${OS_SYNC_ENGINE+x}" ]; then
        printf '%s\n' "$OS_SYNC_ENGINE"
        return 0
      fi
      ;;
    *)
      return 1
      ;;
  esac
  return 1
}

host_load_context() {
  local file val
  file=""
  file=$(host_find_profile) || true
  if [ -n "$file" ]; then
    OS_ROOT=$(dirname "$file")
    export OS_ROOT
  fi

  if ! host_env_override host >/dev/null; then
    [ -n "$file" ] || host_die 1 "company-profile.md not found"
    val=$(host_profile_raw "$file" host) || true
    OS_HOST=$val
  fi
  if ! host_env_override host_url >/dev/null; then
    val=""
    if [ -n "$file" ]; then
      val=$(host_profile_raw "$file" host_url) || true
    fi
    OS_HOST_URL=$val
  fi
  if ! host_env_override org >/dev/null; then
    val=""
    if [ -n "$file" ]; then
      val=$(host_profile_raw "$file" org) || true
    fi
    OS_ORG=$val
  fi
  if [ -z "${OS_SLUG+x}" ]; then
    val=""
    if [ -n "$file" ]; then
      val=$(host_profile_raw "$file" company_slug) || true
    fi
    OS_SLUG=$val
  fi

  OS_HOST_URL=${OS_HOST_URL%/}
  export OS_HOST OS_HOST_URL OS_ORG OS_SLUG
  if [ -z "${OS_HOST}" ]; then
    host_die 1 "host is not set. Run add-teammate first."
  fi
}

host_require_org() {
  if [ -z "${OS_ORG:-}" ]; then
    host_die 1 "org is not set"
  fi
}

host_require_name() {
  local what=$1 val=$2
  case "$val" in
    ""|.*|*/|*\\*|*[[:space:]]*)
      host_die 1 "$what is not a plain name"
      ;;
  esac
  case "$val" in
    *[!A-Za-z0-9._-]*)
      host_die 1 "$what has invalid characters"
      ;;
  esac
}

host_require_team() {
  local val=$1
  case "$val" in
    ""|.*|*/*)
      host_die 1 "team name is not valid"
      ;;
  esac
  case "$val" in
    *[!A-Za-z0-9._\ -]*)
      host_die 1 "team name has invalid characters"
      ;;
  esac
}

host_require_int() {
  local what=$1 val=$2
  case "$val" in
    ""|*[!0-9]*)
      host_die 1 "$what must be a number"
      ;;
  esac
}

host_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | tr -cd 'a-z0-9.-'
}

host_permission() {
  case "$1" in
    read|write|admin) printf '%s\n' "$1" ;;
    *) host_die 1 "permission must be read, write, or admin" ;;
  esac
}

host_github_permission() {
  case "$1" in
    read) printf '%s\n' "pull" ;;
    write) printf '%s\n' "push" ;;
    admin) printf '%s\n' "admin" ;;
    *) host_die 1 "permission must be read, write, or admin" ;;
  esac
}

# Flags and positionals. Sets POS1 POS2 POS3 and the flag variables.
host_parse_args() {
  PRIVATE=0
  PUSH=0
  CODE_OWNERS=1
  APPROVALS=0
  BASE="main"
  CHECKS=""
  SOURCE=""
  HEAD=""
  TITLE=""
  BODY_FILE=""
  BOT=""
  YES=0
  POS1=""
  POS2=""
  POS3=""
  local n=0 arg
  while [ $# -gt 0 ]; do
    arg=$1
    case "$arg" in
      --private) PRIVATE=1; shift ;;
      --push) PUSH=1; shift ;;
      --code-owners) CODE_OWNERS=1; shift ;;
      --yes-test-only) YES=1; shift ;;
      --source)
        [ $# -ge 2 ] || host_die 1 "--source needs a directory"
        SOURCE=$2
        shift 2
        ;;
      --check)
        [ $# -ge 2 ] || host_die 1 "--check needs a context"
        if [ -z "$CHECKS" ]; then
          CHECKS=$2
        else
          CHECKS="${CHECKS}
${2}"
        fi
        shift 2
        ;;
      --approvals)
        [ $# -ge 2 ] || host_die 1 "--approvals needs a number"
        host_require_int "approvals" "$2"
        APPROVALS=$2
        shift 2
        ;;
      --head)
        [ $# -ge 2 ] || host_die 1 "--head needs a branch"
        HEAD=$2
        shift 2
        ;;
      --base)
        [ $# -ge 2 ] || host_die 1 "--base needs a branch"
        BASE=$2
        shift 2
        ;;
      --title)
        [ $# -ge 2 ] || host_die 1 "--title needs text"
        TITLE=$2
        shift 2
        ;;
      --body-file)
        [ $# -ge 2 ] || host_die 1 "--body-file needs a file"
        BODY_FILE=$2
        shift 2
        ;;
      --bot)
        [ $# -ge 2 ] || host_die 1 "--bot needs a name"
        BOT=$2
        shift 2
        ;;
      --help|-h)
        return 2
        ;;
      --)
        shift
        break
        ;;
      --*)
        host_die 1 "unknown flag: $arg"
        ;;
      *)
        n=$((n + 1))
        case "$n" in
          1) POS1=$arg ;;
          2) POS2=$arg ;;
          3) POS3=$arg ;;
          *) host_die 1 "too many arguments" ;;
        esac
        shift
        ;;
    esac
  done
  while [ $# -gt 0 ]; do
    n=$((n + 1))
    case "$n" in
      1) POS1=$1 ;;
      2) POS2=$1 ;;
      3) POS3=$1 ;;
      *) host_die 1 "too many arguments" ;;
    esac
    shift
  done
  : "$PRIVATE $PUSH $CODE_OWNERS $YES $SOURCE $CHECKS $APPROVALS $HEAD $BASE $TITLE $BODY_FILE $BOT $POS1 $POS2 $POS3"
}

host_read_body_file() {
  local raw
  if [ -z "${BODY_FILE}" ]; then
    printf '%s' ""
    return 0
  fi
  [ -f "$BODY_FILE" ] || host_die 1 "body file is missing"
  raw=$(cat "$BODY_FILE")
  printf '%s' "${raw%$'\n'}"
}

host_check_lines() {
  local default=$1
  if [ -z "$CHECKS" ]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$CHECKS"
  fi
}

host_emit_call() {
  local method=$1 path=$2 body=${3-}
  local hostname=${4-}
  host_require_bin jq
  if [ -n "$body" ] && [ -n "$hostname" ]; then
    jq -nc -S --arg m "$method" --arg p "$path" --arg h "$hostname" --argjson b "$body" \
      '{method:$m,path:$p,body:$b,hostname:$h}'
  elif [ -n "$body" ]; then
    jq -nc -S --arg m "$method" --arg p "$path" --argjson b "$body" \
      '{method:$m,path:$p,body:$b}'
  elif [ -n "$hostname" ]; then
    jq -nc -S --arg m "$method" --arg p "$path" --arg h "$hostname" \
      '{method:$m,path:$p,body:null,hostname:$h}'
  else
    jq -nc -S --arg m "$method" --arg p "$path" \
      '{method:$m,path:$p,body:null}'
  fi
}

host_scrub_file() {
  local file=$1 extra_file=${2-}
  local p1 p2 p3 p4 p5
  # Build prefixes at runtime so the source file has no token prefix.
  # The value to hide is read from a file. It is not an awk argument.
  p1=$(printf '%s%s_' gh s)
  p2=$(printf '%s%s_' gh o)
  p3=$(printf '%s%s_' gh p)
  p4=$(printf '%s%s_' gh u)
  p5=$(printf '%s_%s_' github pat)
  awk -v extrafile="$extra_file" -v p1="$p1" -v p2="$p2" -v p3="$p3" -v p4="$p4" -v p5="$p5" '
    function hide_prefix(line, pre,    out, rest, i, c) {
      if (pre == "") return line
      out = ""
      rest = line
      while (index(rest, pre) > 0) {
        i = index(rest, pre)
        out = out substr(rest, 1, i - 1) "<redacted>"
        rest = substr(rest, i + length(pre))
        while (length(rest) > 0) {
          c = substr(rest, 1, 1)
          if (c ~ /[A-Za-z0-9_]/) rest = substr(rest, 2)
          else break
        }
      }
      return out rest
    }
    function hide_value(line, value,    out, rest, i) {
      if (value == "") return line
      out = ""
      rest = line
      while (index(rest, value) > 0) {
        i = index(rest, value)
        out = out substr(rest, 1, i - 1) "<redacted>"
        rest = substr(rest, i + length(value))
      }
      return out rest
    }
    function scrub(line) {
      gsub(/Authorization:[[:space:]]*(Bearer|bearer|token|Basic|basic)[[:space:]]+[^[:space:]]+/, "Authorization: <redacted>", line)
      line = hide_prefix(line, p1)
      line = hide_prefix(line, p2)
      line = hide_prefix(line, p3)
      line = hide_prefix(line, p4)
      line = hide_prefix(line, p5)
      gsub(/[?&](token|access_token)=[^&[:space:]]+/, "<redacted>", line)
      line = hide_value(line, extra)
      return line
    }
    BEGIN {
      extra = ""
      if (extrafile != "") {
        while ((getline line < extrafile) > 0) {
          if (extra != "") extra = extra "\n"
          extra = extra line
        }
        close(extrafile)
      }
    }
    { print scrub($0) }
  ' "$file"
}

host_b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '=\n\r'
}

host_github_app_jwt() {
  local app_id=$1 key_path=$2
  local now iat exp header payload signing sig
  host_require_bin openssl
  host_require_bin jq
  [ -f "$key_path" ] || host_die 4 "App key file is missing"
  now=$(date +%s)
  iat=$((now - 60))
  exp=$((now + 540))
  header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | host_b64url)
  payload=$(jq -nc --argjson iat "$iat" --argjson exp "$exp" --arg iss "$app_id" \
    'if ($iss | test("^[0-9]+$")) then {iat:$iat, exp:$exp, iss:($iss|tonumber)} else {iat:$iat, exp:$exp, iss:$iss} end')
  payload=$(printf '%s' "$payload" | host_b64url)
  signing="${header}.${payload}"
  sig=$(printf '%s' "$signing" | openssl dgst -sha256 -sign "$key_path" | host_b64url)
  printf '%s' "${signing}.${sig}"
}

host_bot_page() {
  local bot=$1
  host_require_name "bot" "$bot"
  if [ -z "${OS_ROOT:-}" ]; then
    host_die 1 "company root is not set"
  fi
  printf '%s\n' "${OS_ROOT}/bots/${bot}/BOT.md"
}

host_bot_field() {
  local bot=$1 key=$2 page val
  page=$(host_bot_page "$bot")
  [ -f "$page" ] || host_die 4 "bot page is missing"
  val=$(host_profile_raw "$page" "$key") || host_die 4 "bot page has no ${key}"
  if [ -z "$val" ]; then
    host_die 4 "bot page has no ${key}"
  fi
  printf '%s\n' "$val"
}

host_config_dir() {
  local slug=${OS_SLUG:-}
  if [ -z "$slug" ]; then
    host_die 4 "company slug is not set"
  fi
  host_require_name "company slug" "$slug"
  printf '%s/%s-os' "${XDG_CONFIG_HOME:-$HOME/.config}" "$slug"
}

host_forgejo_token() {
  local path token
  if [ -n "${FORGEJO_TOKEN:-}" ]; then
    token=$FORGEJO_TOKEN
  else
    path="$(host_config_dir)/forgejo-token"
    [ -f "$path" ] || host_die 4 "Forgejo token file is missing"
    token=$(tr -d '\r\n' < "$path")
  fi
  if [ -z "$token" ]; then
    host_die 4 "Forgejo token is empty"
  fi
  printf '%s' "$token"
}

host_clone_url() {
  local name=$1 base
  case "${OS_HOST}" in
    github)
      if [ -n "${OS_HOST_URL:-}" ]; then
        base=${OS_HOST_URL%/}
      else
        base="https://github.com"
      fi
      ;;
    forgejo)
      [ -n "${OS_HOST_URL:-}" ] || host_die 1 "host_url is not set"
      base=${OS_HOST_URL%/}
      ;;
    *)
      host_die 1 "host is not supported: ${OS_HOST}"
      ;;
  esac
  printf '%s/%s/%s.git' "$base" "$OS_ORG" "$name"
}

host_push_source() {
  local dir=$1 url=$2 ask user token
  [ -d "$dir" ] || host_die 1 "source directory is missing"
  if [ ! -d "$dir/.git" ] && [ ! -f "$dir/.git" ]; then
    host_die 1 "source is not a git repository"
  fi
  if [ "${HOST_DRY_RUN:-}" = "1" ]; then
    return 0
  fi
  if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    git -C "$dir" remote set-url origin "$url"
  else
    git -C "$dir" remote add origin "$url"
  fi
  if [ "$OS_HOST" = "github" ]; then
    host_git_push "$dir" github
    return 0
  fi
  ask="$HOST_RUN_TMP/askpass"
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
  user=${OS_GIT_USER:-$OS_ORG}
  token=$(host_forgejo_token)
  OS_GIT_USER="$user" OS_GIT_TOKEN="$token" GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
    host_git_push "$dir" forgejo
}

host_git_push() {
  local dir=$1 kind=$2
  if git -C "$dir" show-ref --verify --quiet refs/heads/main; then
    host_one_push "$dir" "$kind" origin refs/heads/main:refs/heads/main
  fi
  host_one_push "$dir" "$kind" --all origin
  host_one_push "$dir" "$kind" --tags origin
}

host_one_push() {
  local dir=$1 kind=$2 err rc
  shift 2
  err=$(host_mktemp)
  set +e
  if [ "$kind" = "github" ]; then
    git -C "$dir" -c credential.helper='!gh auth git-credential' push "$@" 2>"$err"
  else
    git -C "$dir" -c credential.helper= push "$@" 2>"$err"
  fi
  rc=$?
  set -e
  host_scrub_file "$err" >&2
  if [ "$rc" -ne 0 ]; then
    host_push_refused "$err"
  fi
  rm -f "$err"
}

# A refused push is a host error (exit 3) with one plain line.
host_push_refused() {
  local err=$1
  if grep -qi 'workflow' "$err"; then
    host_die 3 "push refused: the sign-in cannot write workflow files. Add the workflow scope (gh auth refresh -s workflow), or give the token Workflows: write."
  fi
  # git says "unable to access" for an HTTP 403 too, so the refusals go first.
  if grep -qiE 'authentication failed|permission to .* denied|error: 40[13]|push to create' "$err"; then
    host_die 3 "push refused: the sign-in cannot write to this repo"
  fi
  if grep -qiE 'could not resolve|unable to access|connection refused|timed out' "$err"; then
    host_die 5 "push failed: the host is offline"
  fi
  host_die 3 "push refused by the host: see the git message above"
}

host_usage_text() {
  cat << 'EOF'
Usage: host.sh <verb> [flags]

Call the git host. Do not call gh or the Forgejo API from any other skill.

Verbs:
  whoami
  create-repo <name> [--private] [--source <dir>] [--push]
  repo-access <name>
  protect <name> [--check <ctx>]... [--code-owners] [--approvals 0]
  unprotect <name>
  secret-exists <name>
  user-access <repo> <user>
  team-create <team>
  team-add <team> <user>
  team-remove <team> <user>
  team-repos <team>
  grant <name> <user|team:<team>> <read|write|admin>
  revoke <name> <user|team:<team>>
  org-remove <user>
  org-membership <user>
  invites <user> [<repo>]
  cancel-invites <user> [<repo>]
  archive-repo <name>
  open-pr <name> --head <branch> --base main --title <text> [--body-file <file>]
  auto-merge <name> <number>
  pr-status <name> <number>
  pr-comment <name> <number> --body-file <file>
  set-secret <name>              (value on stdin)
  get-token [--bot <bot>]
  purge-request <name>
  delete-repo <name> --yes-test-only

Exit: 0 ok, 1 usage, 2 not found or no access, 3 host error, 4 auth failed, 5 offline.
JSON on stdout. get-token prints the token only. It is the one exception.
HOST_DRY_RUN=1 prints each GitHub call and changes nothing.
EOF
}
