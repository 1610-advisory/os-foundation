#!/bin/bash
# Test double for skills/sync/sync.sh. Not the product sync skill.
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: sync.sh install-jobs --bot
       sync.sh push

Test double. OS_SYNC_RECORD=1 records the command and does not push.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

cmd=${1:-}
root=$(pwd -P)
log=${OS_SYNC_LOG:-}
if [ -n "$log" ]; then
  printf '%s\n' "$*" >> "$log"
fi

case "$cmd" in
  install-jobs)
    [ "${2:-}" = "--bot" ] || {
      printf '%s\n' "install-jobs needs --bot" >&2
      exit 1
    }
    if [ -n "${OS_JOBS_DIR:-}" ]; then
      mkdir -p "$OS_JOBS_DIR"
      printf '%s\n' "bot" > "${OS_JOBS_DIR}/installed"
    fi
    exit 0
    ;;
  push) ;;
  "")
    usage >&2
    exit 1
    ;;
  *)
    printf '%s\n' "unknown command" >&2
    exit 1
    ;;
esac

if [ "${OS_SYNC_RECORD:-}" = "1" ]; then
  exit 0
fi

profile="${OS_PROFILE:-$root/company-profile.md}"
slug=$(awk '
  BEGIN { fm = 0; n = 0 }
  /^---[[:space:]]*$/ { n++; if (n == 1) { fm = 1; next } if (n >= 2) { exit } }
  fm && /^company_slug:/ {
    sub(/^company_slug:[[:space:]]*/, "")
    gsub(/"/, "")
    print
    exit
  }
' "$profile")
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/${slug}-os"
bot=$(tr -d '[:space:]' < "${cfg}/me")
host="${OS_HOST_SH:-${root}/skills/_host/host.sh}"
export OS_PROFILE="$profile"
export OS_GIT_TOKEN
OS_GIT_TOKEN=$(bash "$host" get-token --bot "$bot")
OS_GIT_USER=$(bash "$host" whoami | jq -r '.login // empty')
[ -n "$OS_GIT_USER" ] || exit 4
export OS_GIT_USER

ask=$(mktemp)
chmod 700 "$ask"
cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF

push_one() {
  local path=$1 name pr number status merged i
  git -C "$path" show-ref --verify --quiet "refs/heads/sync/${bot}" || return 0
  GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -C "$path" -c credential.helper= push -u origin "sync/${bot}"
  name=$(git -C "$path" remote get-url origin)
  name=${name%.git}
  name=${name%/}
  name=${name##*/}
  pr=$(bash "$host" open-pr "$name" --head "sync/${bot}" --base main --title "sync: ${bot}")
  number=$(printf '%s' "$pr" | jq -r '.number')
  bash "$host" auto-merge "$name" "$number" >/dev/null
  i=0
  merged=false
  while [ "$i" -lt 90 ]; do
    status=$(bash "$host" pr-status "$name" "$number")
    merged=$(printf '%s' "$status" | jq -r '.merged')
    if [ "$merged" = "true" ]; then
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  if [ "$merged" != "true" ]; then
    printf '%s\n' "pull request did not merge" >&2
    printf '%s\n' "$status" >&2
    exit 3
  fi
  GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -C "$path" -c credential.helper= fetch origin
}

push_one "$root"
if [ -d "$root/areas" ]; then
  for dir in "$root"/areas/*; do
    if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
      push_one "$dir"
    fi
  done
fi
rm -f "$ask"
