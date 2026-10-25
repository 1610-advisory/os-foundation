#!/usr/bin/env bash
# Simulate the spread nightly push. Time is compressed. The factor is printed.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/lib/common.sh"

usage() {
  cat << 'EOF'
usage: push-window.sh [--users N] [--window-min M] [--factor F] [--concurrency C] [--merges K]

Each person pushes one small log file to sync/<person> on their area repos.
The push starts at a random offset inside the window. Time is compressed.
A sample of standing pull requests is merged through the API.
Default window is 180 minutes (spread over hours). Default users is 1000.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

osf_need_cmd python3 git
exec python3 -u "$here/lib/push_window.py" "$@"
