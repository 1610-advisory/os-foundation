#!/bin/bash
# Test double for awk. Records argv only. Does not read the value file.
set -euo pipefail

log=${FAKE_ARGV_LOG:-}
if [ -n "$log" ]; then
  printf '%s\n' "$*" >> "$log"
fi
exit 0
