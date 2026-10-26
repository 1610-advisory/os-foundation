#!/bin/bash
# Fold a forced skill copy. No Windows, no network.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo=$tmp/acme
mkdir -p "$repo/skills/lint" "$repo/.claude" "$repo/.agents"
printf 'base\n' > "$repo/skills/lint/SKILL.md"
printf 'other\n' > "$repo/skills/lint/OTHER.md"
git -C "$repo" init -q -b main
git -C "$repo" config user.email a@b.test
git -C "$repo" config user.name t
git -C "$repo" add skills
git -C "$repo" commit -q -m seed
mkdir -p "$repo/.claude/skills" "$repo/.agents/skills"

# shellcheck disable=SC1091
. "$root/template/skills/sync/links.sh"
export SYNC_LOG=$tmp/sync.log
: > "$SYNC_LOG"

sync_materialize_repo "$repo" 1
grep -q base "$repo/.claude/skills/lint/SKILL.md"
grep -q base "$repo/.agents/skills/lint/SKILL.md"

printf 'local\n' >> "$repo/.claude/skills/lint/SKILL.md"
mkdir -p "$repo/.claude/skills/fresh"
printf 'new\n' > "$repo/.claude/skills/fresh/NOTE.md"
printf 'up\n' > "$repo/skills/lint/OTHER.md"

sync_materialize_repo "$repo" 1
grep -q local "$repo/skills/lint/SKILL.md"
grep -q new "$repo/skills/fresh/NOTE.md"
grep -q up "$repo/.claude/skills/lint/OTHER.md"
grep -q up "$repo/.agents/skills/lint/OTHER.md"
grep -q 'skills copy folded .claude/skills/lint/SKILL.md' "$SYNC_LOG"
grep -q 'skills copy folded .claude/skills/fresh/NOTE.md' "$SYNC_LOG"

printf 'local2\n' >> "$repo/.claude/skills/lint/SKILL.md"
printf 'up2\n' > "$repo/skills/lint/SKILL.md"
sync_materialize_repo "$repo" 1
grep -q local2 "$repo/.claude/skills/lint/SKILL.md"
grep -q up2 "$repo/skills/lint/SKILL.md"
grep -q 'skills copy conflict .claude/skills/lint/SKILL.md' "$SYNC_LOG"
if grep -q up2 "$repo/.claude/skills/lint/SKILL.md"; then
  printf '%s\n' "conflict overwrote the copy" >&2
  exit 1
fi

printf '%s\n' "PASS links-copy"
