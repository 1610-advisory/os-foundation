#!/usr/bin/env bash
# S1 — solo setup and numbered step count. Results come from git, not chat.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S1
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

root=$(osf_acme_root)
old=$(osf_steps_rev c2034af)
new=$(osf_steps_file "$root/start-core.md")
if [ "$new" -ne $((old - 1)) ]; then
  osf_result "S1 FAIL step count new=$new old=$old expected new=old-1"
fi

work=$(osf_work s1)
dest="$work/company"
day=$(osf_setup_solo "$dest" acme)
problems=$(
  cd "$dest"
  osf_solo_problems "$dest" "$day"
)
if [ -n "$problems" ]; then
  osf_result "S1 FAIL $problems"
fi

osf_result "S1 PASS step count $new = $old - 1"
