#!/bin/bash
# Test double for gh. Records the call. Never prints a real token.
set -euo pipefail

log=${FAKE_GH_LOG:-}
if [ -n "$log" ]; then
  printf '%s\n' "$*" >> "$log"
fi

joined="$*"
case "$joined" in
  *"access_tokens"*)
    printf '%s\n' '{"token":"test-install-token"}'
    ;;
  *)
    printf '%s\n' "unexpected gh call" >&2
    exit 1
    ;;
esac
