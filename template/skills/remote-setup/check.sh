#!/usr/bin/env bash
# Remote setup check: can this person reach a live Claude Code session from their phone?
# Prints one line per item: PASS, FAIL (with the fix) or ASK (check by eye).
# Changes nothing. Exit 0 when nothing failed, 1 when an item failed.
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OS=$(uname -s)
fails=0; asks=0; email=""

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n      Fix: %s\n' "$1" "$2"; fails=$((fails+1)); }
ask()  { printf 'ASK   %s\n' "$1"; asks=$((asks+1)); }

echo "Remote setup check for $ROOT"
echo

# 1. Claude Code
if command -v claude >/dev/null 2>&1; then
  pass "Claude Code is installed ($(claude --version 2>/dev/null | head -1))."
  st=$(claude auth status 2>/dev/null)
  if printf '%s' "$st" | grep -q '"loggedIn": *true' && printf '%s' "$st" | grep -q '"authMethod": *"claude.ai"'; then
    email=$(printf '%s' "$st" | sed -n 's/.*"email": *"\([^"]*\)".*/\1/p' | head -1)
    pass "Claude Code is signed in with a Claude account${email:+ ($email)}."
  else
    fail "Claude Code is not signed in with a Claude account (an API key does not work with Remote Control)." "run claude, type /login, pick your Claude account."
  fi
else
  fail "Claude Code is not installed." "install Claude Code (skills/remote-setup section 1)."
fi

if grep -Eq '"remoteControlAtStartup"[[:space:]]*:[[:space:]]*true' "$HOME/.claude/settings.json" 2>/dev/null; then
  pass "Remote Control turns on for each new session."
else
  fail "Remote Control is not on at startup." "add \"remoteControlAtStartup\": true to ~/.claude/settings.json, or turn it on in /config."
fi

# 2. Herdr
if command -v herdr >/dev/null 2>&1; then
  pass "Herdr is installed ($(herdr --version 2>/dev/null | head -1))."
  if herdr integration status 2>/dev/null | grep -q '^claude: current'; then
    pass "Herdr can bring Claude sessions back after a restart."
  else
    fail "The Herdr link to Claude is missing or old." "herdr integration install claude"
  fi
  if herdr status server 2>/dev/null | grep -q 'status: running'; then
    pass "Herdr is running."
    if herdr agent list 2>/dev/null | tr '{' '\n' | grep '"agent":"claude"' | grep -qF "\"cwd\":\"$ROOT"; then
      pass "A Claude session runs in Herdr in the company folder."
    else
      fail "No Claude session runs in Herdr in the company folder." "start one (skills/remote-setup section 3)."
    fi
  else
    fail "Herdr is not running." "run herdr once, then start the company session (section 3)."
  fi
else
  fail "Herdr is not installed." "install Herdr (skills/remote-setup section 2)."
fi

# 3. Start after a reboot, and stay awake
case "$OS" in
  Darwin)
    if launchctl list 2>/dev/null | grep -q 'com.company-os.herdr' || ls "$HOME/Library/LaunchAgents/"*herdr*.plist >/dev/null 2>&1; then
      pass "Herdr starts by itself at sign-in."
    else
      fail "Herdr does not start by itself after a restart." "add the start-at-sign-in job (section 5)."
    fi
    ac_sleep=$(pmset -g custom 2>/dev/null | awk '/^AC Power/{ac=1} /^Battery Power/{ac=0} ac && $1=="sleep"{print $2; exit}')
    [ -z "$ac_sleep" ] && ac_sleep=$(pmset -g 2>/dev/null | awk '$1=="sleep"{print $2; exit}')
    if [ "$ac_sleep" = "0" ]; then
      pass "The computer does not sleep on the power adapter."
    else
      fail "The computer sleeps after ${ac_sleep:-?} minutes on power, and the session drops." "sudo pmset -c sleep 0"
    fi
    batt=$(pmset -g batt 2>/dev/null)
    if printf '%s' "$batt" | grep -q 'InternalBattery'; then
      if printf '%s' "$batt" | grep -q "AC Power"; then
        pass "The laptop is on the power adapter."
      else
        fail "The laptop runs on battery. It will sleep when the battery is low." "plug in the power adapter."
      fi
      ask "The lid stays open, or the laptop uses an external display (a closed lid makes it sleep)."
    fi
    if pmset -g cap 2>/dev/null | grep -qw autorestart; then
      if pmset -g 2>/dev/null | awk '$1=="autorestart"{print $2}' | grep -q 1; then
        pass "The computer starts again after a power cut."
      else
        fail "The computer stays off after a power cut." "sudo pmset -a autorestart 1"
      fi
    fi
    if fdesetup status 2>/dev/null | grep -q 'On'; then
      ask "FileVault is on: after a restart, someone signs in once at the computer before the session comes back."
    fi
    ;;
  Linux)
    if systemctl --user is-enabled herdr.service >/dev/null 2>&1; then
      pass "Herdr starts by itself."
      if loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
        pass "Herdr starts without a sign-in (linger is on)."
      else
        fail "Herdr waits for a sign-in after a restart." "sudo loginctl enable-linger $USER"
      fi
    else
      fail "Herdr does not start by itself after a restart." "add the user service (section 5)."
    fi
    if [ "$(systemctl is-enabled sleep.target 2>/dev/null)" = "masked" ]; then
      pass "The computer does not sleep."
    else
      fail "The computer can sleep, and the session drops." "sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target"
    fi
    if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
      if grep -Eqs '^HandleLidSwitchExternalPower=ignore' /etc/systemd/logind.conf /etc/systemd/logind.conf.d/*.conf; then
        pass "Closing the lid on power does not sleep."
      else
        fail "Closing the lid makes the laptop sleep." "set HandleLidSwitchExternalPower=ignore in /etc/systemd/logind.conf"
      fi
    fi
    ;;
  *)
    ask "Windows: sleep on power is Never, lid close on power is Do nothing, Herdr is in the Startup folder (section 4 and 5)."
    ;;
esac

# 4. Same account on the phone
ask "The Claude app on the phone uses the same account as this computer${email:+ ($email)}."

echo
if [ "$fails" -eq 0 ]; then
  echo "Result: no failures. Check the $asks ASK line(s) by eye, then test from the phone."
  exit 0
fi
echo "Result: $fails item(s) failed. Fix them in order, then run this check again."
exit 1
