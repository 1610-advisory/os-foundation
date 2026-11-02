#!/bin/bash
# Test double for curl. Records argv only. Never reads a config file.
set -euo pipefail

log=${FAKE_CURL_LOG:-}
if [ -n "$log" ]; then
  printf '%s\n' "$*" >> "$log"
fi
exit 7
