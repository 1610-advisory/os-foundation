#!/usr/bin/env bash
# Stop the local Forgejo stack. --wipe also removes its volumes.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/common.sh"

usage() {
  cat << 'EOF'
usage: down.sh [--wipe]

Stop the Acme Forgejo containers. Volumes stay unless you pass --wipe.
This command only touches the osf-acme project.
EOF
}

wipe=0
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
if [ "${1:-}" = "--wipe" ]; then
  wipe=1
  shift
fi
if [ $# -ne 0 ]; then
  usage >&2
  exit 1
fi

osf_need_cmd docker
if ! docker info >/dev/null 2>&1; then
  echo "FAIL: Docker is not running" >&2
  exit 1
fi

if [ "$wipe" -eq 1 ]; then
  osf_acme_compose down -v --remove-orphans
else
  osf_acme_compose down --remove-orphans
fi
echo "down OK"
