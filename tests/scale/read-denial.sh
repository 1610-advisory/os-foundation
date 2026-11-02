#!/usr/bin/env bash
# Check that allowed reads work and denied reads fail. Zero wrong answers passes.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/lib/common.sh"

usage() {
  cat << 'EOF'
usage: read-denial.sh [--pairs N]

Check clone and API read for a fixed-seed sample of user and repo pairs.
Half are allowed. Half are not. N is at least 200 and even.
Default: 200. Exit 0 only when every answer is right.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

osf_need_cmd python3 git
exec python3 -u "$here/lib/read_denial.py" "$@"
