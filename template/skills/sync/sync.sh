#!/bin/bash
# Pull, push, propose, jobs, device helper, and traces collector.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
# shellcheck disable=SC1091
. "$DIR/pull.sh"
# shellcheck disable=SC1091
. "$DIR/push.sh"
# shellcheck disable=SC1091
. "$DIR/jobs.sh"
# shellcheck disable=SC1091
. "$DIR/helper.sh"
# shellcheck disable=SC1091
. "$DIR/collect.sh"

trap sync_cleanup EXIT

usage() {
  cat << 'EOF'
Usage: sync.sh <command> [flags]

Commands:
  pull
  push
  propose <topic> <file>...
  status
  install-jobs [--admin] [--bot]
  uninstall-jobs
  helper
  collect

The person does not run git. See CLI.md for the full contract.
EOF
}

cmd_status() {
  local err
  sync_bind
  err=$(jq -r '.last_error // ""' "$SYNC_HELD")
  if [ -n "$err" ]; then
    printf 'last error: %s\n' "$err"
  else
    printf '%s\n' "last error: none"
  fi
  if jq -e '.files | length > 0' "$SYNC_HELD" >/dev/null; then
    printf '%s\n' "held:"
    jq -r '.files[] | "- \(.repo) \(.path): \(.reason)"' "$SYNC_HELD"
  else
    printf '%s\n' "nothing held"
  fi
}

main() {
  local cmd=${1:-}
  if [ -z "$cmd" ] || [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ]; then
    usage
    if [ -z "$cmd" ]; then
      exit 1
    fi
    exit 0
  fi
  shift
  case "$cmd" in
    status)
      cmd_status
      ;;
    pull|push|propose|install-jobs|uninstall-jobs|helper|collect)
      sync_bind
      case "$cmd" in
        pull) cmd_pull ;;
        push) cmd_push ;;
        propose) cmd_propose "$@" ;;
        install-jobs) cmd_install_jobs "$@" ;;
        uninstall-jobs) cmd_uninstall_jobs ;;
        helper) cmd_helper ;;
        collect) cmd_collect ;;
      esac
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
