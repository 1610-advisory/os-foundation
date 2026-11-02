#!/usr/bin/env bash
# Start the scale Forgejo. Safe to run again. Does not touch the Acme stack.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/lib/common.sh"

usage() {
  cat << 'EOF'
usage: up.sh

Start the scale Forgejo on port 3400.
Safe to run again. Does not delete data.
This command only touches the osf-scale project.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
if [ $# -ne 0 ]; then
  usage >&2
  exit 1
fi

osf_need_cmd docker curl python3
if ! docker info >/dev/null 2>&1; then
  echo "FAIL: Docker is not running" >&2
  exit 1
fi

osf_scale_compose up -d

if ! osf_wait_http "$(osf_scale_url)/api/healthz" 60; then
  if ! osf_wait_http "$(osf_scale_url)/api/v1/version" 15; then
    echo "FAIL: Forgejo did not become ready" >&2
    exit 1
  fi
fi

python3 -u "$here/lib/machine.py"
echo "forgejo OK"
