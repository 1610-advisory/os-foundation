#!/bin/bash
# Run the bots suite. Prints PASS or FAIL per check.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fail=0
for name in test_unit.sh test_argv.sh test_github.sh test_forgejo.sh; do
  if bash "$here/$name"; then
    :
  else
    code=$?
    printf 'FAIL %s (exit %s)\n' "$name" "$code" >&2
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  exit 1
fi
printf '%s\n' "PASS bots suite"
