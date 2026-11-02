#!/bin/bash
# Test engine. Makes two commits in the company repo and one in marketing.
set -euo pipefail

cat >/dev/null
root=${OS_ROOT:?}
i=0
if [ -d "$root/.git" ] || [ -f "$root/.git" ]; then
  mkdir -p "$root/notes"
  i=$((i + 1))
  printf 'note %s\n' "$i" > "$root/notes/run-note-${i}.md"
  git -C "$root" add "notes/run-note-${i}.md"
  git -C "$root" commit -m "Bot note ${i}"
  i=$((i + 1))
  printf 'note %s\n' "$i" > "$root/notes/run-note-${i}.md"
  git -C "$root" add "notes/run-note-${i}.md"
  git -C "$root" commit -m "Bot note ${i}"
fi
area="$root/areas/marketing"
if [ -d "$area/.git" ] || [ -f "$area/.git" ]; then
  mkdir -p "$area/notes"
  i=$((i + 1))
  printf 'note %s\n' "$i" > "$area/notes/run-note-${i}.md"
  git -C "$area" add "notes/run-note-${i}.md"
  git -C "$area" commit -m "Bot note ${i}"
fi
