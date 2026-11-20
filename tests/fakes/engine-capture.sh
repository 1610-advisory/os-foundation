#!/bin/bash
# Test engine: keep a copy of the prompt in $OS_TEST_PROMPT_LOG, then answer like engine.sh.
# EXTRA-LIST-MATCH in the diff, with an "Extra holds for this computer" section in the prompt:
# hold with the first item heading (### or ##) of that section, the way a model would.
set -euo pipefail
input=$(cat)
if [ -n "${OS_TEST_PROMPT_LOG:-}" ]; then
  printf '%s\n----\n' "$input" >> "$OS_TEST_PROMPT_LOG"
fi
if printf '%s\n' "$input" | grep -q '^## Extra holds for this computer' \
  && printf '%s\n' "$input" | awk '/^DIFF:/ { d = 1 } d' | grep -q 'EXTRA-LIST-MATCH'; then
  heading=$(printf '%s\n' "$input" | awk '
    /^## Extra holds for this computer/ { s = 1; next }
    s && /^#+ / { sub(/^#+ /, ""); print; exit }')
  jq -nc --arg r "extra hold: ${heading}" '{decision:"hold", reason:$r, message:""}'
  exit 0
fi
printf '%s\n' "$input" | bash "$(dirname "$0")/engine.sh"
