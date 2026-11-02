#!/usr/bin/env bash
# Stop the scale Forgejo. --wipe also removes its volume and local token files.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/lib/common.sh"

usage() {
  cat << 'EOF'
usage: down.sh [--wipe]

Stop the scale Forgejo containers. Volumes stay unless you pass --wipe.
--wipe also removes the scale token cache. It does not print token values.
This command only touches the osf-scale project.
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
  osf_scale_compose down -v --remove-orphans
  docker volume rm osf-scale-forgejo-data >/dev/null 2>&1 || true
  docker network rm osf-scale >/dev/null 2>&1 || true
  cache=$(osf_scale_cache)
  if [ -d "$cache" ]; then
    rm -rf "$cache"
  fi
else
  osf_scale_compose down --remove-orphans
fi
echo "down OK"
