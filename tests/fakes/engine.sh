#!/bin/bash
# Deterministic stand-in for the nightly check. Reads the prompt on stdin.
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat << 'EOF'
Usage: engine.sh

Reads the push-check prompt on stdin. Prints one JSON line.
Markers in the diff: ENGINE-FAIL, PERSONAL-FACT, PRIVATE-QUOTE, COMPANY-FACT, HOLD-ME, WORKSPACE-ME.
EOF
  exit 0
fi

input=$(cat)
decision=commit
reason=ok
file=$(printf '%s\n' "$input" | awk '/^FILE: / { print substr($0, 7); exit }')
message="update ${file}"
if [ "${#message}" -gt 72 ]; then
  message=$(printf '%s' "$message" | cut -c 1-72)
fi

if printf '%s\n' "$input" | grep -q 'ENGINE-FAIL'; then
  printf '%s\n' "engine failed" >&2
  exit 1
fi
if printf '%s\n' "$input" | grep -q 'PERSONAL-FACT'; then
  decision=hold
  reason="personal-life fact"
  message=""
elif printf '%s\n' "$input" | grep -q 'PRIVATE-QUOTE'; then
  decision=hold
  reason="private-source quote"
  message=""
elif printf '%s\n' "$input" | grep -q 'COMPANY-FACT'; then
  decision=hold
  reason="company fact in a profile"
  message=""
elif printf '%s\n' "$input" | grep -q 'WORKSPACE-ME'; then
  # push-check.md rule 5, the way a model that misreads it would answer.
  decision=hold
  reason="belongs in the workspace"
  message=""
elif printf '%s\n' "$input" | grep -q 'HOLD-ME'; then
  decision=hold
  reason="held by check"
  message=""
fi

jq -nc --arg decision "$decision" --arg reason "$reason" --arg message "$message" \
  '{decision:$decision, reason:$reason, message:$message}'
