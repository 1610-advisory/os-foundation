#!/usr/bin/env bash
# Nightly review and report stand-in. One JSON line. No secrets printed.
set -euo pipefail
tmp=$(mktemp)
cat > "$tmp"
if grep -q 'kind: review' "$tmp"; then
  if grep -q 'Missing Person' "$tmp"; then
    rm -f "$tmp"
    printf '%s\n' '{"ok":true,"findings":[{"kind":"clear-error","path":"notes/widget.md","summary":"Broken link.","author":"mia","fix":{"action":"replace","old":"[[Missing Person]]","new":"[[Ada Admin]]"}},{"kind":"judgment","path":"notes/price.md","summary":"Confirm the sample price.","author":"mia"}]}'
    exit 0
  fi
  rm -f "$tmp"
  printf '%s\n' '{"ok":true,"findings":[]}'
  exit 0
fi
if grep -q 'kind: report' "$tmp"; then
  rm -f "$tmp"
  printf '%s\n' '{"ok":true,"people":[{"slug":"mia","actions":["Filed the widget note."],"results":["The note is on main."]}]}'
  exit 0
fi
if grep -q 'kind: fold' "$tmp"; then
  rm -f "$tmp"
  printf '%s\n' '{"ok":true,"summary":"The month notes were folded."}'
  exit 0
fi
rm -f "$tmp"
printf '%s\n' '{"ok":true,"findings":[]}'
