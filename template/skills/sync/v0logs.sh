#!/bin/bash
# v0 kept logs on branch logs, checked out at memory/logs/ as a git worktree. The
# upgrade removes that worktree only on the computer that runs it. On every other
# clone, once main tracks memory/logs/, the worktree must go too, without losing a log.
# Sourced by sync.sh (pull) and add-teammate/join.sh. Bash 3.2. Needs git.
# The caller passes a git runner: <fn> <dir> <git args...>, so a push uses its sign-in.

# 0 when memory/logs is a worktree of branch logs and <ref> tracks memory/logs/.
v0logs_stuck() {
  local repo=$1 ref=${2:-origin/main} wt
  wt="$repo/memory/logs"
  [ -f "$wt/.git" ] || return 1
  [ "$(git -C "$wt" symbolic-ref --short -q HEAD 2>/dev/null)" = "logs" ] || return 1
  git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null || return 1
  [ -n "$(git -C "$repo" ls-tree --name-only "$ref" memory/logs/ 2>/dev/null)" ]
}

# Push log commits the host lacks, copy every file out, remove the worktree.
# Prints the folder that holds the copy. On a failure it prints one plain line to
# stderr (what happened, and where the copy is when there is one) and returns 1.
v0logs_park() {
  local repo=$1 run=$2 wt save
  wt="$repo/memory/logs"
  # Commits on logs that origin/logs lacks go up first, so the host keeps them too.
  if ! git -C "$repo" rev-parse --verify --quiet origin/logs >/dev/null \
    || [ -n "$(git -C "$repo" rev-list origin/logs..logs 2>/dev/null)" ]; then
    if ! "$run" "$repo" push -q origin logs >/dev/null 2>&1; then
      printf '%s\n' "could not push the logs branch. Nothing was removed" >&2
      return 1
    fi
  fi
  # Untracked and uncommitted files come too: the copy is the folder as it is.
  save=$(mktemp -d)
  if ! cp -Rp "$wt/." "$save/"; then
    rm -rf "$save"
    printf '%s\n' "could not copy memory/logs. Nothing was removed" >&2
    return 1
  fi
  rm -f "$save/.git"
  if ! git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1; then
    # A remove can stop part way (a file lock): some files may already be gone.
    printf 'could not remove the logs worktree, and some files may be gone from memory/logs. A full copy is in %s\n' "$save" >&2
    return 1
  fi
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
  # When main has the logs already, put its copy back first.
  git -C "$repo" checkout -q HEAD -- memory/logs 2>/dev/null || true
  printf '%s\n' "$save"
}

# Copy each saved file that main lacks or holds a different copy of. The person's
# copy wins; main's copy stays in history. Prints how many files it wrote. If any copy
# fails (a file lock on Windows), the saved folder stays, one plain line names it on
# stderr, and it returns 1. Every step is checked by hand: bash 3.2 runs this in $( ),
# where set -e does not reach.
v0logs_put_back() {
  local repo=$1 save=$2 rel n=0 bad=0
  while IFS= read -r rel; do
    rel=${rel#./}
    if [ ! -f "$repo/memory/logs/$rel" ] || ! cmp -s "$save/$rel" "$repo/memory/logs/$rel"; then
      if mkdir -p "$repo/memory/logs/$(dirname "$rel")" && cp -p "$save/$rel" "$repo/memory/logs/$rel"; then
        n=$((n + 1))
      else
        bad=$((bad + 1))
      fi
    fi
  done < <(cd "$save" && find . -type f)
  if [ "$bad" -ne 0 ]; then
    printf 'could not copy %s logs back into memory/logs. A full copy is in %s\n' "$bad" "$save" >&2
    return 1
  fi
  rm -rf "$save"
  printf '%s\n' "$n"
}
