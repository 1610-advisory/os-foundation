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
# Review 5: a model that repeats the holds file. The first plain line of the list (not a
# heading) goes into the reason (LEAK-REASON) or the commit message (LEAK-MESSAGE).
# BAD-HEADING: a heading the list does not have.
diff_part=$(printf '%s\n' "$input" | awk '/^DIFF:/ { d = 1 } d')
line=$(printf '%s\n' "$input" | awk '
  /^## Extra holds for this computer/ { s = 1; next }
  s && /^(REPO|AREA|OWNER|FILE): / { exit }
  s && NF && !/^#/ && !/^Hold a file/ && !/^Check them/ { print; exit }')
if printf '%s\n' "$diff_part" | grep -q 'LEAK-REASON'; then
  jq -nc --arg r "extra hold: ${line}" '{decision:"hold", reason:$r, message:""}'
  exit 0
fi
if printf '%s\n' "$diff_part" | grep -q 'LEAK-MESSAGE'; then
  jq -nc --arg m "add ${line}" '{decision:"commit", reason:"ok", message:$m}'
  exit 0
fi
if printf '%s\n' "$diff_part" | grep -q 'BAD-HEADING'; then
  jq -nc '{decision:"hold", reason:"extra hold: words the model made up", message:""}'
  exit 0
fi
printf '%s\n' "$input" | bash "$(dirname "$0")/engine.sh"
