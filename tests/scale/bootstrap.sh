#!/usr/bin/env bash
# Create the scale org, users, area repos, and team grants. Safe to run again.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/lib/common.sh"

usage() {
  cat << 'EOF'
usage: bootstrap.sh [--users N] [--areas N]

Create one org, users, area repos, one team per area, and the grants.
Defaults: 5000 users, 200 areas, plus the company repo.
Safe to run again. Run up.sh first.
Tokens are written under the scale cache and are not printed.
Each phase prints its size and time.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

osf_need_cmd python3 docker
exec python3 -u "$here/lib/bootstrap.py" "$@"
