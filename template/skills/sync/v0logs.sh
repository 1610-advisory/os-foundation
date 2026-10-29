#!/bin/bash
# v0 kept logs on branch logs, checked out at memory/logs/ as a git worktree. The
# upgrade removes that worktree only on the computer that runs it. On every other
# clone, once main has the upgrade, the worktree must go too, without losing a log.
# The upgrade puts the old logs in memory/logs-archive/, outside memory/logs/, and push
# keeps memory/logs/ off main while the host has branch logs (sync_v0_logs_open). So a
# plain git pull on an old clone writes nothing inside its worktree. Logs pushed to branch
# logs after the upgrade come in by v0logs_catch_up.
# Sourced by sync.sh (pull) and add-teammate/join.sh. Bash 3.2. Needs git.
# The caller passes a git runner: <fn> <dir> <git args...>, so a push uses its sign-in.
# Each failure line on stderr says what happened and what to do next.

V0LOGS_ARCHIVE=memory/logs-archive

# 0 when memory/logs is a worktree of branch logs and <ref> has the upgrade (it tracks
# memory/logs-archive/ or memory/logs/).
v0logs_stuck() {
  local repo=$1 ref=${2:-origin/main} wt
  wt="$repo/memory/logs"
  [ -f "$wt/.git" ] || return 1
  [ "$(git -C "$wt" symbolic-ref --short -q HEAD 2>/dev/null)" = "logs" ] || return 1
  git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null || return 1
  [ -n "$(git -C "$repo" ls-tree --name-only "$ref" "$V0LOGS_ARCHIVE/" memory/logs/ 2>/dev/null)" ]
}

# Where a file from the old logs branch belongs, as a path in the repo. A path main tracks
# under memory/logs/ stays there (a v1 log a plain pull wrote into the old folder after the
# old branch was gone). Otherwise it goes to memory/logs-archive/, when main has it.
v0logs_target() {
  local repo=$1 rel=$2
  if git -C "$repo" cat-file -e "HEAD:memory/logs/$rel" 2>/dev/null; then
    printf 'memory/logs/%s\n' "$rel"
  elif [ -n "$(git -C "$repo" ls-tree --name-only HEAD "$V0LOGS_ARCHIVE/" 2>/dev/null)" ]; then
    printf '%s/%s\n' "$V0LOGS_ARCHIVE" "$rel"
  else
    printf 'memory/logs/%s\n' "$rel"
  fi
}

# The name beside <path> that holds the old branch's text when <path> is already taken.
v0logs_beside() {
  case "$1" in
    *.md) printf '%s.old-branch.md\n' "${1%.md}" ;;
    *) printf '%s.old-branch\n' "$1" ;;
  esac
}

# Put this computer's log commits on the host's logs branch. When the host's branch
# moved (someone else logged), merge it first, in a temporary worktree, so the person's
# folder is not touched. A conflict stops with the exact steps. Nothing is removed here.
# Then the folder moves to the host's tip, so the copy v0logs_park makes holds both sides.
v0logs_push() {
  local repo=$1 run=$2 tmp tip files
  # No logs branch on the host, or offline: the push below tells which.
  "$run" "$repo" fetch -q origin "+refs/heads/logs:refs/remotes/origin/logs" >/dev/null 2>&1 || true
  tip=$(git -C "$repo" rev-parse logs)
  if git -C "$repo" rev-parse --verify --quiet origin/logs >/dev/null; then
    if git -C "$repo" merge-base --is-ancestor logs origin/logs; then
      v0logs_follow "$repo" origin/logs
      return 0
    fi
    if ! git -C "$repo" merge-base --is-ancestor origin/logs logs; then
      tmp=$(mktemp -d)
      git -C "$repo" worktree add -q --detach "$tmp/logs" logs >/dev/null 2>&1 || {
        rm -rf "$tmp"
        printf '%s\n' "could not merge the host's logs branch. Nothing was removed. Run this again" >&2
        return 1
      }
      if ! git -C "$tmp/logs" -c user.name="$(git -C "$repo" config user.name || printf 'Company OS')" \
        -c user.email="$(git -C "$repo" config user.email || printf 'os@localhost')" \
        merge -q --no-edit origin/logs >/dev/null 2>&1; then
        files=$(git -C "$tmp/logs" diff --name-only --diff-filter=U | tr '\n' ' ' | sed 's/ $//')
        git -C "$repo" worktree remove --force "$tmp/logs" >/dev/null 2>&1 || true
        rm -rf "$tmp"
        printf 'the logs branch here and on the host both changed %s. Nothing was removed. In memory/logs run: git pull --no-rebase origin logs, keep both texts in each of those files, git commit -am "Logs: merge", git push origin logs. Then run this again\n' "${files:-a file}" >&2
        return 1
      fi
      tip=$(git -C "$tmp/logs" rev-parse HEAD)
      git -C "$repo" worktree remove --force "$tmp/logs" >/dev/null 2>&1 || true
      rm -rf "$tmp"
    fi
  fi
  if ! "$run" "$repo" push -q origin "${tip}:refs/heads/logs" >/dev/null 2>&1; then
    printf '%s\n' "could not push the logs branch. Nothing was removed. Check the internet connection and sign-in, then run this again" >&2
    return 1
  fi
  "$run" "$repo" fetch -q origin "+refs/heads/logs:refs/remotes/origin/logs" >/dev/null 2>&1 || true
  v0logs_follow "$repo" "$tip"
}

# Fast-forward the old logs folder to <ref>. A file the person changed and the other side
# changed too stops it: the person's copy stays, and catch-up puts the other text beside it.
v0logs_follow() {
  git -C "$1/memory/logs" merge -q --ff-only "$2" >/dev/null 2>&1 || true
}

# Push log commits the host lacks, copy every file out, remove the worktree.
# Prints the folder that holds the copy. On a failure it prints one plain line to
# stderr (what happened, what to do, and where the copy is when there is one) and returns 1.
v0logs_park() {
  local repo=$1 run=$2 wt save
  wt="$repo/memory/logs"
  v0logs_push "$repo" "$run" || return 1
  # Untracked and uncommitted files come too: the copy is the folder as it is.
  # Outside the run's temp folder: on a failure the person keeps this copy.
  save=$(mktemp -d "${OS_KEEP_TMP:-${TMPDIR:-/tmp}}/os-logs-copy.XXXXXX")
  if ! cp -Rp "$wt/." "$save/"; then
    rm -rf "$save"
    printf '%s\n' "could not copy memory/logs. Nothing was removed. Check the free disk space, then run this again" >&2
    return 1
  fi
  rm -f "$save/.git"
  if ! git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1; then
    # A remove can stop part way (a file lock): some files may already be gone.
    printf 'could not remove the logs worktree, and some files may be gone from memory/logs. A full copy is in %s. Keep that folder: close any program that has a log open, then ask the admin to copy the logs back from it\n' "$save" >&2
    return 1
  fi
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
  # When main has the logs already, put its copy back first.
  git -C "$repo" checkout -q HEAD -- memory/logs 2>/dev/null || true
  printf '%s\n' "$save"
}

# Copy each saved file to its place (v0logs_target) when main lacks it or holds a
# different copy. The person's copy wins; main's copy stays in history. Prints how many
# files it wrote. If any copy fails (a file lock on Windows), the saved folder stays, one
# plain line names it on stderr, and it returns 1. Every step is checked by hand: bash
# 3.2 runs this in $( ), where set -e does not reach.
v0logs_put_back() {
  local repo=$1 save=$2 rel dest n=0 bad=0
  while IFS= read -r rel; do
    rel=${rel#./}
    dest="$repo/$(v0logs_target "$repo" "$rel")"
    if [ ! -f "$dest" ] || ! cmp -s "$save/$rel" "$dest"; then
      if mkdir -p "$(dirname "$dest")" && cp -p "$save/$rel" "$dest"; then
        n=$((n + 1))
      else
        bad=$((bad + 1))
      fi
    fi
  done < <(cd "$save" && find . -type f)
  if [ "$bad" -ne 0 ]; then
    printf 'could not copy %s logs back into memory/logs. A full copy is in %s. Keep that folder: close any program that has a log open, then ask the admin to copy the logs back from it\n' "$bad" "$save" >&2
    return 1
  fi
  rm -rf "$save"
  printf '%s\n' "$n"
}

# Logs pushed to branch logs after the upgrade never reach main by themselves. Compare
# the newest logs-archive-<date> tag (the upgrade's snapshot) with origin/logs. Write each
# file added or changed since then to its place as a local change; the next push sends
# it. A place that is taken (main's file, or one the person has) is never written over:
# the old branch's text goes beside it (v0logs_beside). Prints "<written> <beside>". A
# failed write prints one plain line on stderr and returns 1. Needs main to have
# memory/logs-archive/.
v0logs_catch_up() {
  local repo=$1 tag rel dest n=0 m=0 blob
  [ -n "$(git -C "$repo" ls-tree --name-only HEAD "$V0LOGS_ARCHIVE/" 2>/dev/null)" ] || { printf '0 0\n'; return 0; }
  git -C "$repo" rev-parse --verify --quiet origin/logs >/dev/null || { printf '0 0\n'; return 0; }
  tag=$(git -C "$repo" for-each-ref --sort=-creatordate --count=1 --format='%(refname)' 'refs/tags/logs-archive-*')
  [ -n "$tag" ] || { printf '0 0\n'; return 0; }
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    dest=$(v0logs_target "$repo" "$rel")
    blob=$(git -C "$repo" rev-parse -q --verify "origin/logs:$rel") || continue
    if [ -e "$repo/$dest" ]; then
      [ "$(git -C "$repo" hash-object -- "$repo/$dest" 2>/dev/null)" = "$blob" ] && continue
      dest=$(v0logs_beside "$dest")
      [ ! -e "$repo/$dest" ] || continue
      m=$((m + 1))
    else
      n=$((n + 1))
    fi
    if ! mkdir -p "$(dirname "$repo/$dest")" 2>/dev/null || ! { git -C "$repo" cat-file blob "$blob" > "$repo/$dest"; } 2>/dev/null; then
      printf '%s\n' "could not write ${dest} from the old logs branch. Check the free disk space, then run skills/sync/sync.sh pull --full again" >&2
      return 1
    fi
  done < <(git -C "$repo" diff --name-only --no-renames --diff-filter=AM "${tag}^{commit}" origin/logs 2>/dev/null)
  printf '%s %s\n' "$n" "$m"
}
