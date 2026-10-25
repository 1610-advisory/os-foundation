#!/usr/bin/env bash
# Nightly review and report stand-in. One JSON line. No secrets printed.
set -euo pipefail
input=$(cat)
if printf '%s\n' "$input" | grep -q 'kind: review'; then
  printf '%s\n' '{"ok":true,"findings":[{"kind":"clear-error","path":"notes/widget.md","summary":"Broken link.","author":"mia","fix":{"action":"replace","old":"[[Missing Person]]","new":"[[Ada Admin]]"}},{"kind":"judgment","path":"notes/price.md","summary":"Confirm the sample price.","author":"mia"}]}'
  exit 0
fi
if printf '%s\n' "$input" | grep -q 'kind: report'; then
  printf '%s\n' '{"ok":true,"people":[{"slug":"mia","actions":["Filed the widget note."],"results":["The note is on main."]}]}'
  exit 0
fi
if printf '%s\n' "$input" | grep -q 'kind: fold'; then
  printf '%s\n' '{"ok":true,"summary":"The month notes were folded."}'
  exit 0
fi
printf '%s\n' '{"decision":"commit","reason":"ok","message":"Update note"}'
