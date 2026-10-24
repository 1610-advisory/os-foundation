#!/bin/bash
# Shared test helpers. Not shipped. Never print a token or a secret.
set -euo pipefail

team_root() {
  CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

team_fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

team_need() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || team_fail "missing $cmd"
  done
}

team_sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}
