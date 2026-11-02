#!/usr/bin/env bash
# Always-commit engine for the one leak test. Prompt on stdin is discarded.
set -euo pipefail
cat >/dev/null
printf '%s\n' '{"decision":"commit","reason":"ok","message":"Update note"}'
