#!/bin/sh
# Test double. Writes its arguments to the file named by FAKE_ARGV_LOG.
# Prints nothing that it was given. Exits 0 unless FAKE_ARGV_EXIT is set.
set -eu
log=${FAKE_ARGV_LOG:-}
if [ -n "$log" ]; then
  printf '%s\n' "$*" >> "$log"
fi
if [ -n "${FAKE_ARGV_STDOUT:-}" ]; then
  printf '%s\n' "$FAKE_ARGV_STDOUT"
fi
exit "${FAKE_ARGV_EXIT:-0}"
