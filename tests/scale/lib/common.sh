# shellcheck shell=bash
# Shared helpers for the scale check. Source this file. Do not run it.
# This stack is not the Acme stack. It never uses port 3300.

osf_scale_here() {
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

osf_scale_root() {
  local lib
  lib=$(osf_scale_here)
  CDPATH='' cd -- "$lib/../../.." && pwd
}

osf_scale_url() {
  printf '%s\n' "${OSF_SCALE_URL:-http://localhost:3400}"
}

osf_scale_cache() {
  printf '%s\n' "${OSF_SCALE_CACHE:-${HOME}/.cache/os-foundation/forgejo-scale}"
}

osf_scale_compose() {
  local root
  root=$(osf_scale_root)
  docker compose -p osf-scale -f "$root/tests/scale/compose.yml" "$@"
}

osf_die() {
  echo "FAIL: $*" >&2
  exit 1
}

osf_need_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      osf_die "missing command: $cmd"
    fi
  done
}

osf_wait_http() {
  local url="$1"
  local tries="${2:-60}"
  local i=0
  while [ "$i" -lt "$tries" ]; do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}
