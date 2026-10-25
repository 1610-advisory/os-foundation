#!/usr/bin/env bash
# Deterministic nightly-check stand-in for Tier A. Prompt on stdin, one JSON line out.
set -euo pipefail

input=$(cat)
# The prompt names the hold rules and includes an example DIFF: line.
# Judge only the diff after the last DIFF: line.
diff=$(printf '%s\n' "$input" | awk '/^DIFF:$/ { buf=""; on=1; next } on { buf = buf $0 ORS } END { printf "%s", buf }')
file=$(printf '%s\n' "$input" | awk '/^FILE: / { f = $0; sub(/^FILE: /, "", f) } END { print f }')
decision="commit"
reason="ok"
message="Update note"
if [ -z "$file" ]; then
  file="note"
fi
case "$file" in
  */*)
    message="Update ${file##*/}"
    ;;
  *)
    message="Update ${file}"
    ;;
esac

if printf '%s\n' "$diff" | grep -q 'source: private'; then
  decision="hold"
  reason="private source"
  message=""
fi
if printf '%s\n' "$diff" | grep -q 'OSF-LIFE'; then
  decision="hold"
  reason="personal-life fact"
  message=""
fi
if printf '%s\n' "$diff" | grep -q 'OSF-DM'; then
  decision="hold"
  reason="private source"
  message=""
fi
case "$file" in
  profile/PROFILE.md|*/profile/PROFILE.md)
    if printf '%s\n' "$diff" | grep -q 'OSF-COMPANY-FACT'; then
      decision="hold"
      reason="company fact in a profile"
      message=""
    fi
    ;;
esac

printf '{"decision":"%s","reason":"%s","message":"%s"}\n' "$decision" "$reason" "$message"
