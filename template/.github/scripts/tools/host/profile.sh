#!/bin/bash
# Print one value from company-profile.md. A list prints one item per line.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat << 'EOF'
Usage: profile.sh <key>

Print one value from company-profile.md. Walk up from the current directory
to find the file, or use OS_PROFILE. A list prints one item per line.
OS_HOST, OS_HOST_URL, OS_ORG and OS_SYNC_ENGINE override the file.
EOF
  exit 0
fi

if [ $# -ne 1 ]; then
  printf '%s\n' "Usage: profile.sh <key>" >&2
  exit 1
fi

key=$1
case "$key" in
  *[!A-Za-z0-9_-]*)
    host_die 1 "key is not a plain name"
    ;;
esac

if host_env_override "$key"; then
  exit 0
fi

file=$(host_find_profile) || host_die 1 "company-profile.md not found"
host_profile_raw "$file" "$key"
