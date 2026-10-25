#!/bin/bash
# Device helper. Sourced by sync.sh.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh." >&2
  exit 1
fi

sync_helper_load() {
  if [ ! -f "$SYNC_HELPER" ]; then
    printf '%s\n' '{"days":[],"warned":false}' > "$SYNC_HELPER"
    chmod 600 "$SYNC_HELPER"
  fi
  if ! jq -e '.days | type == "array"' "$SYNC_HELPER" >/dev/null 2>&1; then
    sync_log "helper fail state"
    return 1
  fi
}

sync_helper_save_days() {
  local day=$1
  local tmp
  tmp=$(sync_mktemp)
  jq --arg day "$day" '.days = ((.days + [$day]) | unique)' "$SYNC_HELPER" > "$tmp"
  mv "$tmp" "$SYNC_HELPER"
  chmod 600 "$SYNC_HELPER"
}

sync_helper_reset() {
  local tmp
  tmp=$(sync_mktemp)
  jq '.days = [] | .warned = false' "$SYNC_HELPER" > "$tmp"
  mv "$tmp" "$SYNC_HELPER"
  chmod 600 "$SYNC_HELPER"
}

sync_delete_company() {
  local root home
  root=$(sync_abs "$SYNC_ROOT")
  home=$(sync_abs "$HOME")
  [ -f "$root/company-profile.md" ] || sync_die 1 "not a company folder"
  if [ "$root" = "/" ] || [ "$root" = "$home" ]; then
    sync_die 1 "refusing to delete this folder"
  fi
  if [ "${OS_TEST_MODE:-}" = "1" ]; then
    case "$root" in
      "$home"/*) ;;
      *) sync_die 1 "refusing a path outside home" ;;
    esac
  fi
  rm -rf "$root"
}

cmd_helper() {
  local today access rc count
  sync_lock
  sync_helper_load || return 1
  today=$(sync_today)
  case "$today" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) sync_die 1 "clock is not a date" ;;
  esac
  [ -f "$HOST_SH" ] || sync_die 1 "host.sh is missing"
  set +e
  access=$("$HOST_SH" repo-access "${SYNC_SLUG}-os" 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -eq 4 ]; then
    printf '%s\n' "sign in again"
    sync_log "helper sign-in"
    return 0
  fi
  if [ "$rc" -eq 5 ]; then
    sync_log "helper offline"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then
    sync_helper_reset
    sync_log "helper ok reset"
    return 0
  fi
  if [ "$rc" -ne 2 ]; then
    sync_log "helper fail host"
    return 1
  fi
  case "$access" in
    *no-access*) ;;
    *)
      sync_log "helper fail host"
      return 1
      ;;
  esac
  sync_helper_save_days "$today"
  count=$(jq '.days | length' "$SYNC_HELPER")
  if [ "$count" -ge 14 ]; then
    sync_log "helper delete ${count}"
    sync_delete_company
    return 0
  fi
  if [ "$count" -ge 7 ]; then
    printf '%s\n' "This computer has had no access to the company for ${count} days. The company folder will be deleted after 14 days with no access."
    sync_log "helper warn ${count}"
  else
    sync_log "helper count ${count}"
  fi
}
