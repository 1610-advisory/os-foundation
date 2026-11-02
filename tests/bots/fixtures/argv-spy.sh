#!/bin/bash
# Record argv. Flag a hit when an argument contains a secret from OS_ARGV_SECRETS.
set -euo pipefail

log=${OS_ARGV_LOG:?}
hits=${OS_ARGV_HITS:?}
{
  printf '%s' "$0"
  for arg in "$@"; do
    printf ' %s' "$arg"
  done
  printf '\n'
} >> "$log"

if [ -n "${OS_ARGV_SECRETS:-}" ] && [ -f "$OS_ARGV_SECRETS" ]; then
  while IFS= read -r secret || [ -n "$secret" ]; do
    [ -n "$secret" ] || continue
    for arg in "$@"; do
      case "$arg" in
        *"$secret"*)
          printf '%s\n' "hit" >> "$hits"
          ;;
      esac
    done
  done < "$OS_ARGV_SECRETS"
fi

if [ "${OS_ARGV_EXEC:-}" = "1" ]; then
  real=${OS_ARGV_REAL:?}
  exec "$real" "$@"
fi
exit 0
