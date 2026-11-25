#!/usr/bin/env bash
# Stand-in automation engine. Writes the one line the routine asks for, then commits
# through git so the product hook can add Run-Id.
set -euo pipefail

root="${OS_ROOT:-.}"
mkdir -p "$root/notes"
printf '%s\n' "the automation ran" > "$root/notes/automation.md"
git -C "$root" add notes/automation.md
if ! git -C "$root" diff --cached --quiet; then
  git -C "$root" -c user.name="Acme Automation" -c user.email="${GIT_AUTHOR_EMAIL:-acme.automation@acme.test}" \
    -c commit.gpgsign=false commit -m "Automation note"
fi
