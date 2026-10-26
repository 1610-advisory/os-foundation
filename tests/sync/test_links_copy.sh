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
grep -q up "$repo/.claude/skills/lint/OTHER.md"

# A copy edit with no upstream skills change is folded on pull.
: > "$SYNC_LOG"
old=$(git -C "$repo" rev-parse HEAD)
printf 'only-copy\n' >> "$repo/.claude/skills/lint/OTHER.md"
sync_refresh_after_pull "$repo" "$old"
grep -q only-copy "$repo/skills/lint/OTHER.md"
grep -q 'skills copy folded .claude/skills/lint/OTHER.md' "$SYNC_LOG"

# The same fold runs at push start. The copy itself is not staged.
printf 'push-fold\n' >> "$repo/.claude/skills/lint/OTHER.md"
sync_materialize_repo "$repo"
grep -q push-fold "$repo/skills/lint/OTHER.md"
git -C "$repo" add -A
staged=$(git -C "$repo" diff --cached --name-only)
case "$staged" in
  *'.claude/skills'*|*'.agents/skills'*)
    printf '%s\n' "copy was staged" >&2
    exit 1
    ;;
esac
git -C "$repo" reset -q

# The same bytes on both sides is not a conflict. The manifest moves forward.
: > "$SYNC_LOG"
printf 'same\n' > "$repo/.claude/skills/lint/SKILL.md"
printf 'same\n' > "$repo/skills/lint/SKILL.md"
sync_materialize_repo "$repo"
if grep -q 'skills copy conflict .claude/skills/lint/SKILL.md' "$SYNC_LOG"; then
  printf '%s\n' "equal change was a conflict" >&2
  exit 1
fi
man=$(sync_copy_manifest_path "$repo" ".claude/skills")
want=$(git -C "$repo" hash-object -- "$repo/.claude/skills/lint/SKILL.md")
grep -q "${want}.*lint/SKILL.md" "$man"

# One conflict does not block an upstream change to another file.
: > "$SYNC_LOG"
printf 'mine\n' > "$repo/.claude/skills/lint/SKILL.md"
printf 'theirs\n' > "$repo/skills/lint/SKILL.md"
printf 'fresh-up\n' > "$repo/skills/lint/OTHER.md"
sync_materialize_repo "$repo"
grep -q mine "$repo/.claude/skills/lint/SKILL.md"
grep -q fresh-up "$repo/.claude/skills/lint/OTHER.md"
grep -q 'skills copy conflict .claude/skills/lint/SKILL.md' "$SYNC_LOG"
if grep -q 'skills copy conflict .claude/skills/lint/OTHER.md' "$SYNC_LOG"; then
  printf '%s\n' "upstream file was marked conflict" >&2
  exit 1
fi

# A second pull with nothing to fold does not rewrite the manifest.
sync_materialize_repo "$repo"
man=$(sync_copy_manifest_path "$repo" ".claude/skills")
if stat -c %Y "$man" >/dev/null 2>&1; then
  mtime1=$(stat -c %Y "$man")
else
  mtime1=$(stat -f %m "$man")
fi
sleep 1
sync_refresh_after_pull "$repo" "$(git -C "$repo" rev-parse HEAD)"
if stat -c %Y "$man" >/dev/null 2>&1; then
  mtime2=$(stat -c %Y "$man")
else
  mtime2=$(stat -f %m "$man")
fi
if [ "$mtime1" != "$mtime2" ]; then
  printf '%s\n' "steady pull rewrote the manifest" >&2
  exit 1
fi

printf '%s\n' "PASS links-copy"
