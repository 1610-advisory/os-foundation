#!/usr/bin/env bash
# Stand-in bot engine. Writes the one line the routine asks for, then commits
# through git so the product hook can add Run-Id.
set -euo pipefail

root="${OS_ROOT:-.}"
mkdir -p "$root/notes"
printf '%s\n' "the bot ran" > "$root/notes/bot.md"
git -C "$root" add notes/bot.md
if ! git -C "$root" diff --cached --quiet; then
  git -C "$root" -c user.name="Acme Bot" -c user.email="${GIT_AUTHOR_EMAIL:-acme.bot@acme.test}" \
    -c commit.gpgsign=false commit -m "Bot note"
fi
