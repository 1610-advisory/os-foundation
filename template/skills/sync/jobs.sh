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
  local line user delay patsub=0
  user=${USERID:-S-1-5-21-1}
  delay=${DELAY:-0}
  if shopt -q patsub_replacement 2>/dev/null; then
    patsub=1
  fi
  # Bash 5.2 treats & in a replacement as the matched text. Paths use &amp;.
  shopt -u patsub_replacement 2>/dev/null || true
  : > "$dest"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line//@LABEL@/$LABEL}
    line=${line//@ROOT@/$ROOT}
    line=${line//@SYNC@/$SYNC}
    line=${line//@LOG@/$LOG}
    line=${line//@HOUR@/$HOUR}
    line=${line//@MINUTE@/$MINUTE}
    line=${line//@ARG@/$ARG}
    line=${line//@DESC@/$DESC}
    line=${line//@DELAY@/$delay}
    line=${line//@USER@/$user}
    printf '%s\n' "$line"
  done < "$src" > "$dest"
  if [ "$patsub" -eq 1 ]; then
    shopt -s patsub_replacement 2>/dev/null || true
  fi
}

sync_win_path() {
  local p=$1
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
    return 0
  fi
  printf '%s\n' "$p"
}

sync_win_sid() {
  local sid
  if command -v powershell.exe >/dev/null 2>&1; then
    sid=$(powershell.exe -NoProfile -NonInteractive -Command "[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value" 2>/dev/null || true)
    sid=$(printf '%s' "$sid" | tr -d '\r\n')
    case "$sid" in
      S-1-*) printf '%s\n' "$sid"; return 0 ;;
    esac
  fi
  printf '%s\n' "S-1-5-21-1"
}

sync_win_ps1() {
  local raw ps line
  raw=$(mktemp)
  ps="${raw}.ps1"
  rm -f "$raw"
  : > "$ps"
  for line in "$@"; do
    printf '%s\r\n' "$line" >> "$ps"
  done
  printf '%s\n' "$ps"
}

sync_win_register() {
  local name=$1
  local xml=$2
  local raw ps xml_win ps_win
  # The file stays UTF-8. The API string is Unicode, so the declaration must say UTF-16.
  raw=$(mktemp)
  ps="${raw}.ps1"
  rm -f "$raw"
  awk 'BEGIN { ORS="\r\n" } { print }' > "$ps" << 'EOF'
param([string]$TaskName, [string]$XmlPath)
$ErrorActionPreference = "Stop"
$xml = Get-Content -LiteralPath $XmlPath -Raw
$xml = $xml -replace 'encoding="UTF-8"', 'encoding="UTF-16"'
Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
EOF
  xml_win=$(sync_win_path "$xml")
  ps_win=$(sync_win_path "$ps")
  MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$ps_win" -TaskName "$name" -XmlPath "$xml_win"
  rm -f "$ps"
}

sync_win_unregister() {
  local name=$1
  local ps ps_win
  # shellcheck disable=SC2016
  ps=$(sync_win_ps1 'param([string]$TaskName)' 'Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue')
  ps_win=$(sync_win_path "$ps")
  MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$ps_win" -TaskName "$name" || true
  rm -f "$ps"
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
      SYNC=$(sync_xml "\"$(sync_win_path "$SYNC_DIR/sync.ps1")\"")
      ROOT=$(sync_xml "$(sync_win_path "$SYNC_ROOT")")
      USERID=$(sync_win_sid)
      sync_install_windows "$dir" "$admin"
      ;;
    *) sync_die 1 "platform is not supported" ;;
  esac
  if [ "$bot" -eq 1 ]; then
    sync_log "jobs install bot"
  fi
  if sync_is_windows && [ "$platform" = "windows" ]; then
    if [ "${OS_JOBS_LOAD:-1}" != "0" ]; then
      sync_register_windows "$dir"
    fi
  elif [ "${OS_JOBS_LOAD:-}" = "1" ]; then
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

sync_pad2() {
  printf '%02d' "$1"
}

sync_install_windows() {
  local dir=$1
  local admin=$2
  local src
  src="$SYNC_DIR/jobs"
  DESC="os-foundation pull"
  ARG="pull"
  LABEL="osfoundation-${label}-pull"
  sync_render "$src/windows-task.xml" "$dir/${LABEL}.xml"
  printf '%s\n' "$dir/${LABEL}.xml"
  DESC="os-foundation push"
  ARG="push"
  LABEL="osfoundation-${label}-push"
  HOUR=$(sync_pad2 2)
  MINUTE=$(sync_pad2 0)
  sync_render "$src/windows-daily.xml" "$dir/${LABEL}.xml"
  printf '%s\n' "$dir/${LABEL}.xml"
  DESC="os-foundation helper"
  ARG="helper"
  LABEL="osfoundation-${label}-helper"
  HOUR=$(sync_pad2 4)
  MINUTE=$(sync_pad2 0)
  sync_render "$src/windows-daily.xml" "$dir/${LABEL}.xml"
  printf '%s\n' "$dir/${LABEL}.xml"
  if [ "$admin" -eq 1 ]; then
    DESC="os-foundation admin nightly"
    ARG="admin-run"
    LABEL="osfoundation-${label}-admin"
    HOUR=$(sync_pad2 3)
    MINUTE=$(sync_pad2 30)
    sync_render "$src/windows-daily.xml" "$dir/${LABEL}.xml"
    printf '%s\n' "$dir/${LABEL}.xml"
  fi
}

sync_register_windows() {
  local dir=$1
  local f name
  for f in "$dir"/osfoundation-"${label}"-*.xml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .xml)
    sync_win_register "$name" "$f"
  done
}

cmd_admin_run() {
  local rc=0
  if [ -x "$SYNC_ROOT/skills/nightly-review/run.sh" ]; then
    "$SYNC_ROOT/skills/nightly-review/run.sh" || rc=1
  else
    sync_log "admin fail nightly-review missing"
    rc=1
  fi
  if [ -x "$SYNC_ROOT/skills/reports/run.sh" ]; then
    "$SYNC_ROOT/skills/reports/run.sh" || rc=1
  else
    sync_log "admin fail reports missing"
    rc=1
  fi
  return "$rc"
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
      printf '%s\n' "Windows task registration runs on Windows only." >&2
      ;;
  esac
}

cmd_uninstall_jobs() {
  local platform dir f safe label
  platform=$(sync_job_platform)
  dir=$(sync_job_dir)
  safe=$(printf '%s' "$SYNC_SLUG" | tr -c 'a-z0-9-' '-')
  [ -d "$dir" ] || return 0
  case "$platform" in
    macos)
      for f in "$dir"/com.osfoundation."${safe}".*.plist; do
        [ -f "$f" ] || continue
        label=$(plutil -extract Label raw "$f" 2>/dev/null || true)
        case "$label" in
          "com.osfoundation.${safe}."*) ;;
          *) continue ;;
        esac
        if [ "${OS_JOBS_LOAD:-}" = "1" ]; then
          launchctl bootout "gui/$(id -u)" "$f" 2>/dev/null || launchctl unload -w "$f" 2>/dev/null || true
        fi
        rm -f "$f"
        printf '%s\n' "$f"
      done
      ;;
    linux)
      for f in "$dir"/osfoundation-"${safe}"-*.service "$dir"/osfoundation-"${safe}"-*.timer; do
        [ -f "$f" ] || continue
        rm -f "$f"
        printf '%s\n' "$f"
      done
      ;;
    windows)
      for f in "$dir"/osfoundation-"${safe}"-*.xml; do
        [ -f "$f" ] || continue
        if sync_is_windows; then
          sync_win_unregister "$(basename "$f" .xml)" || true
        fi
        rm -f "$f"
        printf '%s\n' "$f"
      done
      ;;
  esac
}
