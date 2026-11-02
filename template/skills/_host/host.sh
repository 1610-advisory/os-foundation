#!/bin/bash
# Dispatch a host verb to the github or forgejo adapter.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap host_cleanup EXIT

if [ $# -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  host_usage_text
  if [ $# -eq 0 ]; then
    exit 1
  fi
  exit 0
fi

verb=$1
shift

host_load_context

case "$OS_HOST" in
  github|forgejo)
    ;;
  none)
    host_die 1 "host is not set. Run add-teammate first."
    ;;
  *)
    host_die 1 "host is not supported: ${OS_HOST}"
    ;;
esac

adapter="${DIR}/${OS_HOST}.sh"
[ -f "$adapter" ] || host_die 3 "adapter is missing"
# exec skips the EXIT trap: remove this script's temp folder first.
host_cleanup
export TMPDIR="$HOST_PARENT_TMP"
exec "$adapter" "$verb" "$@"
