#!/bin/bash
# Pull, push, propose, jobs, device helper, and traces collector.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
# shellcheck disable=SC1091
. "$DIR/links.sh"
# shellcheck disable=SC1091
. "$DIR/v0logs.sh"
# shellcheck disable=SC1091
. "$DIR/pull.sh"
# shellcheck disable=SC1091
. "$DIR/push.sh"
# shellcheck disable=SC1091
. "$DIR/reapply.sh"
# shellcheck disable=SC1091
. "$DIR/jobs.sh"
# shellcheck disable=SC1091
. "$DIR/helper.sh"
# shellcheck disable=SC1091
. "$DIR/collect.sh"

trap sync_cleanup EXIT
# A stopped job (Ctrl-C, a closed terminal, a scheduler timeout) still cleans up.
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
sync_run_tmp

usage() {
  cat << 'EOF'
Usage: sync.sh <command> [flags]

Commands:
  pull [--full]
  push
  propose <topic> <file>...
  status
  seat
  re-apply [list | done <repo> <path> | ask <repo> <path> <question>]
  install-jobs [--admin] [--bot]
  uninstall-jobs
  helper
  collect
  admin-run

The person does not run git. See CLI.md for the full contract.
EOF
}

cmd_status() {
  local err
  sync_bind
  sync_held_prune
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
  sync_each sync_status_unpushed || true
  sync_pull_status_line
}

# Commits here that no branch on the host has: they go up with the next push.
sync_status_unpushed() {
  local repo=$1 id=$2 n
  n=$(git -C "$repo" rev-list --count --no-merges HEAD --not --remotes=origin 2>/dev/null || printf '0')
  if [ "$n" = "1" ]; then
    printf '%s\n' "${id}: 1 change here is not on the host yet"
  elif [ "$n" != "0" ]; then
    printf '%s\n' "${id}: ${n} changes here are not on the host yet"
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
    re-apply)
      sync_bind
      cmd_reapply "$@"
      ;;
    seat)
      [ $# -eq 0 ] || { usage >&2; exit 1; }
      sync_bind
      sync_seat
      ;;
    pull|push|propose|install-jobs|uninstall-jobs|helper|collect|admin-run)
      sync_bind
      case "$cmd" in
        pull) cmd_pull "$@" ;;
        push) cmd_push ;;
        propose) cmd_propose "$@" ;;
        install-jobs) cmd_install_jobs "$@" ;;
        uninstall-jobs) cmd_uninstall_jobs ;;
        helper) cmd_helper ;;
        collect) cmd_collect ;;
        admin-run) cmd_admin_run ;;
      esac
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
