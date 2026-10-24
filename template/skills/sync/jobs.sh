#!/bin/bash
# OS job templates. Sourced by sync.sh.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh." >&2
  exit 1
fi

sync_job_platform() {
  if [ -n "${OS_JOBS_PLATFORM:-}" ]; then
    printf '%s\n' "$OS_JOBS_PLATFORM"
    return 0
  fi
  case "$(uname -s)" in
    Darwin) printf '%s\n' macos ;;
    Linux) printf '%s\n' linux ;;
    *) printf '%s\n' windows ;;
  esac
}

sync_job_dir() {
  if [ -n "${OS_JOBS_DIR:-}" ]; then
    printf '%s\n' "$OS_JOBS_DIR"
    return 0
  fi
  case "$(sync_job_platform)" in
    macos) printf '%s\n' "$HOME/Library/LaunchAgents" ;;
    linux) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" ;;
    *) printf '%s\n' "${LOCALAPPDATA:-$HOME/AppData/Local}/os-foundation/tasks" ;;
  esac
}

sync_render() {
  local src=$1
  local dest=$2
  awk -v label="$LABEL" -v root="$ROOT" -v sync="$SYNC" -v log="$LOG" \
    -v hour="$HOUR" -v minute="$MINUTE" -v arg="$ARG" -v desc="$DESC" \
    -v delay="${DELAY:-0}" '
    {
      gsub(/@LABEL@/, label)
      gsub(/@ROOT@/, root)
      gsub(/@SYNC@/, sync)
      gsub(/@LOG@/, log)
      gsub(/@HOUR@/, hour)
      gsub(/@MINUTE@/, minute)
      gsub(/@ARG@/, arg)
      gsub(/@DESC@/, desc)
      gsub(/@DELAY@/, delay)
      print
    }
  ' "$src" > "$dest"
}

cmd_install_jobs() {
  local admin=0 bot=0 level platform dir slug label
  while [ $# -gt 0 ]; do
    case "$1" in
      --admin) admin=1 ;;
      --bot) bot=1 ;;
      *) sync_die 1 "unknown flag" ;;
    esac
    shift
  done
  level=$(sync_level)
  if [ "$level" = "solo" ] || [ -z "$level" ]; then
    sync_die 1 "OS jobs are not installed at solo"
  fi
  platform=$(sync_job_platform)
  dir=$(sync_job_dir)
  mkdir -p "$dir"
  slug=$SYNC_SLUG
  label=$(printf '%s' "$slug" | tr -c 'a-z0-9-' '-')
  ROOT=$(sync_xml "$SYNC_ROOT")
  SYNC=$(sync_xml "$SYNC_DIR/sync.sh")
  LOG=$(sync_xml "$SYNC_LOG")
  HOUR=2
  MINUTE=0
  ARG=""
  DESC=""
  LABEL="com.osfoundation.${label}"
  case "$platform" in
    macos) sync_install_macos "$dir" "$admin" ;;
    linux) sync_install_linux "$dir" "$admin" "$label" ;;
    windows)
      SYNC=$(sync_xml "$SYNC_DIR/sync.ps1")
      sync_install_windows "$dir" "$admin"
      ;;
    *) sync_die 1 "platform is not supported" ;;
  esac
  if [ "$bot" -eq 1 ]; then
    sync_log "jobs install bot"
  fi
  if [ "${OS_JOBS_LOAD:-}" = "1" ]; then
    sync_load_jobs "$platform" "$dir"
  fi
}

sync_install_macos() {
  local dir=$1
  local admin=$2
  local src
  src="$SYNC_DIR/jobs"
  LABEL="com.osfoundation.${label}.pull"
  ARG="pull"
  HOUR=""
  sync_render "$src/macos-interval.plist" "$dir/${LABEL}.plist"
  printf '%s\n' "$dir/${LABEL}.plist"
  LABEL="com.osfoundation.${label}.push"
  ARG="push"
  HOUR=2
  MINUTE=0
  sync_render "$src/macos-calendar.plist" "$dir/${LABEL}.plist"
  printf '%s\n' "$dir/${LABEL}.plist"
  LABEL="com.osfoundation.${label}.helper"
  ARG="helper"
  HOUR=4
  MINUTE=0
  sync_render "$src/macos-calendar.plist" "$dir/${LABEL}.plist"
  printf '%s\n' "$dir/${LABEL}.plist"
  if [ "$admin" -eq 1 ]; then
    LABEL="com.osfoundation.${label}.admin"
    ARG=$(sync_xml "bash -c '${SYNC_ROOT}/skills/nightly-review/run.sh && ${SYNC_ROOT}/skills/reports/run.sh'")
    HOUR=3
    MINUTE=30
    sync_render "$src/macos-admin.plist" "$dir/${LABEL}.plist"
    printf '%s\n' "$dir/${LABEL}.plist"
  fi
}

sync_install_linux() {
  local dir=$1
  local admin=$2
  local safe=$3
  local src unit
  src="$SYNC_DIR/jobs"
  unit="osfoundation-${safe}"
  LABEL="${unit}-pull"
  ARG="pull"
  DESC="os-foundation pull"
  sync_render "$src/linux.service" "$dir/${LABEL}.service"
  sync_render "$src/linux-interval.timer" "$dir/${LABEL}.timer"
  printf '%s\n' "$dir/${LABEL}.service" "$dir/${LABEL}.timer"
  LABEL="${unit}-push"
  ARG="push"
  DESC="os-foundation push"
  HOUR=2
  MINUTE=0
  DELAY=1800
  sync_render "$src/linux.service" "$dir/${LABEL}.service"
  sync_render "$src/linux-calendar.timer" "$dir/${LABEL}.timer"
  printf '%s\n' "$dir/${LABEL}.service" "$dir/${LABEL}.timer"
  LABEL="${unit}-helper"
  ARG="helper"
  DESC="os-foundation helper"
  HOUR=4
  MINUTE=0
  DELAY=0
  sync_render "$src/linux.service" "$dir/${LABEL}.service"
  sync_render "$src/linux-calendar.timer" "$dir/${LABEL}.timer"
  printf '%s\n' "$dir/${LABEL}.service" "$dir/${LABEL}.timer"
  if [ "$admin" -eq 1 ]; then
    LABEL="${unit}-admin"
    ARG="admin-run"
    DESC="os-foundation nightly review and reports"
    HOUR=3
    MINUTE=30
    DELAY=0
    sync_render "$src/linux-admin.service" "$dir/${LABEL}.service"
    sync_render "$src/linux-calendar.timer" "$dir/${LABEL}.timer"
    printf '%s\n' "$dir/${LABEL}.service" "$dir/${LABEL}.timer"
  fi
}

sync_install_windows() {
  local dir=$1
  local admin=$2
  local src
  src="$SYNC_DIR/jobs"
  DESC="os-foundation pull. Not tested."
  ARG="pull"
  LABEL="osfoundation-${label}-pull"
  sync_render "$src/windows-task.xml" "$dir/${LABEL}.xml"
  printf '%s\n' "$dir/${LABEL}.xml"
  DESC="os-foundation push. Not tested."
  ARG="push"
  LABEL="osfoundation-${label}-push"
  HOUR=2
  MINUTE=0
  sync_render "$src/windows-daily.xml" "$dir/${LABEL}.xml"
  printf '%s\n' "$dir/${LABEL}.xml"
  DESC="os-foundation helper. Not tested."
  ARG="helper"
  LABEL="osfoundation-${label}-helper"
  HOUR=4
  MINUTE=0
  sync_render "$src/windows-daily.xml" "$dir/${LABEL}.xml"
  printf '%s\n' "$dir/${LABEL}.xml"
  if [ "$admin" -eq 1 ]; then
    DESC="os-foundation admin nightly. Not tested."
    ARG="admin"
    LABEL="osfoundation-${label}-admin"
    HOUR=3
    MINUTE=30
    sync_render "$src/windows-daily.xml" "$dir/${LABEL}.xml"
    printf '%s\n' "$dir/${LABEL}.xml"
  fi
}

sync_load_jobs() {
  local platform=$1
  local dir=$2
  local f
  case "$platform" in
    macos)
      for f in "$dir"/com.osfoundation."${label}".*.plist; do
        [ -f "$f" ] || continue
        launchctl bootstrap "gui/$(id -u)" "$f" 2>/dev/null || launchctl load -w "$f"
      done
      ;;
    linux)
      systemctl --user daemon-reload
      systemctl --user enable --now osfoundation-"${label}"-pull.timer \
        osfoundation-"${label}"-push.timer osfoundation-"${label}"-helper.timer
      ;;
    windows)
      printf '%s\n' "Windows jobs are not tested. Import the XML with Task Scheduler." >&2
      ;;
  esac
}

cmd_uninstall_jobs() {
  local platform dir f safe
  platform=$(sync_job_platform)
  dir=$(sync_job_dir)
  safe=$(printf '%s' "$SYNC_SLUG" | tr -c 'a-z0-9-' '-')
  [ -d "$dir" ] || return 0
  case "$platform" in
    macos)
      for f in "$dir"/com.osfoundation."${safe}".*.plist; do
        [ -f "$f" ] || continue
        if [ "${OS_JOBS_LOAD:-}" = "1" ]; then
          launchctl bootout "gui/$(id -u)" "$f" 2>/dev/null || launchctl unload -w "$f" 2>/dev/null || true
        fi
        rm -f "$f"
        printf '%s\n' "$f"
      done
      ;;
    linux)
      for f in "$dir"/osfoundation-*.service "$dir"/osfoundation-*.timer; do
        [ -f "$f" ] || continue
        rm -f "$f"
        printf '%s\n' "$f"
      done
      ;;
    windows)
      for f in "$dir"/osfoundation-*.xml; do
        [ -f "$f" ] || continue
        rm -f "$f"
        printf '%s\n' "$f"
      done
      ;;
  esac
}
