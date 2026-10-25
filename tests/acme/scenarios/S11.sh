#!/usr/bin/env bash
# S11 — upgrade a v0 Acme folder built from os-foundation c2034af.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/scenario.sh"

OSF_ID=S11
trap 'echo "$OSF_ID FAIL unexpected error"' ERR

osf_need_product S11 team template/skills/upgrade/upgrade.sh

root=$(osf_acme_root)
work=$(osf_work s11)
osf_sandbox "$work/box"
archive="$work/archive"
mkdir -p "$archive"
git -C "$root" archive c2034af template | tar -x -C "$archive"
dest="$work/company"
mv "$archive/template" "$dest"
day=$(osf_today)
OSF_DEST="$dest" OSF_DAY="$day" python3 - << 'PY'
import os
from pathlib import Path
dest = Path(os.environ["OSF_DEST"])
repl = {
    "{{COMPANY_NAME}}": "Acme Co",
    "{{COMPANY_SLUG}}": "acme",
    "{{OWNER_NAME}}": "Ada Admin",
    "{{OWNER_ROLE}}": "Owner",
    "{{DATE}}": os.environ["OSF_DAY"],
    "{{ONE_LINER}}": "Acme Co makes sample goods.",
    "{{AREAS}}": "none yet",
}
for path in dest.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    if "skills" in path.parts:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    new = text
    for key, value in repl.items():
        new = new.replace(key, value)
    if new != text:
        path.write_text(new, encoding="utf-8")
PY
mkdir -p "$dest/notes"
printf '%s\n' "Keep this company sentence." > "$dest/notes/keep.md"
before=$(cksum "$dest/notes/keep.md" | awk '{print $1}')
git -C "$dest" init -b main
git -C "$dest" add -A
git -C "$dest" -c user.name="Ada Admin" -c user.email="ada.admin@acme.test" \
  commit -m "Company OS: start"
git -C "$dest" checkout --orphan logs
git -C "$dest" rm -rf . >/dev/null 2>&1 || true
printf '%s\n' "Old log line." > "$dest/${day}-ada.md"
git -C "$dest" add "${day}-ada.md"
git -C "$dest" -c user.name="Ada Admin" -c user.email="ada.admin@acme.test" \
  commit -m "Log the day"
git -C "$dest" checkout main

bash "$root/template/skills/upgrade/upgrade.sh" --dry-run --root "$dest" --template "$root/template" \
  >"$work/dry.log" 2>&1 || osf_result "S11 FAIL dry-run"
if ! grep -q 'upgrade: dry-run' "$work/dry.log"; then
  osf_result "S11 FAIL dry-run report missing"
fi
bash "$root/template/skills/upgrade/upgrade.sh" --root "$dest" --template "$root/template" --level solo \
  >"$work/upgrade.log" 2>&1 || osf_result "S11 FAIL upgrade"
after=$(cksum "$dest/notes/keep.md" | awk '{print $1}')
if [ "$before" != "$after" ]; then
  osf_result "S11 FAIL company content changed"
fi
if ! git -C "$dest" cat-file -e "HEAD:memory/logs/${day}-ada.md" 2>/dev/null; then
  osf_result "S11 FAIL logs were not moved onto the branch"
fi
if ! git -C "$dest" tag --list 'logs-archive-*' | grep -q 'logs-archive-'; then
  osf_result "S11 FAIL old logs branch was not tagged"
fi
merge=$(git -C "$dest" rev-parse HEAD)
git -C "$dest" revert -m 1 "$merge" --no-edit || osf_result "S11 FAIL revert"
if git -C "$dest" cat-file -e "HEAD:memory/logs/${day}-ada.md" 2>/dev/null; then
  osf_result "S11 FAIL revert did not restore the old state"
fi

osf_result "S11 PASS"
