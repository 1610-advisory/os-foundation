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

# The name beside <path> (in <repo>) for the old branch's text <blob>, when <path> is
# taken: <name>.old-branch.md, then <name>.old-branch-2.md and on. A name is never reused
# for other text. Returns 1 when a name beside it holds that text already.
v0logs_beside() {
  local repo=$1 path=$2 blob=$3 base ext name i=1
  case "$path" in
    *.md) base=${path%.md}; ext=.md ;;
    *) base=$path; ext="" ;;
  esac
  while :; do
    name="$base.old-branch$ext"
    [ "$i" -eq 1 ] || name="$base.old-branch-$i$ext"
    if [ ! -e "$repo/$name" ]; then
      printf '%s\n' "$name"
      return 0
    fi
    [ "$(git -C "$repo" hash-object -- "$repo/$name" 2>/dev/null)" != "$blob" ] || return 1
    i=$((i + 1))
  done
}

# 0 when <file> is a name v0logs_beside writes.
v0logs_is_beside() {
  case "$1" in
    *.old-branch.md|*.old-branch-[0-9]*.md|*.old-branch|*.old-branch-[0-9]*) return 0 ;;
  esac
  return 1
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
      return
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

# Fast-forward the old logs folder to <ref>, a later commit. A file the person changed or
# added that <ref> touches too stops a plain fast-forward. Then only those files are kept
# aside, the folder resets to <ref>, and they come back: the person's copy stays, and when
# <ref> has other text for it, that text goes beside it (v0logs_beside). Every other file
# takes the text at <ref>. If any step fails, the folder stays or goes back as it was (v0logs_undo),
# so the next run starts from the same place. It prints one plain line to stderr and
# returns 1.
v0logs_follow() {
  local repo=$1 ref=$2 wt old keep rel blob name bad=0
  wt="$repo/memory/logs"
  git -C "$wt" merge -q --ff-only "$ref" >/dev/null 2>&1 && return 0
  old=$(git -C "$wt" rev-parse HEAD)
  git -C "$wt" merge-base --is-ancestor "$old" "$ref" 2>/dev/null || return 0
  keep=$(mktemp -d "${OS_KEEP_TMP:-${TMPDIR:-/tmp}}/os-logs-keep.XXXXXX") || return 1
  # Changed against the last commit (staged or not), and every untracked file.
  { git -C "$wt" diff --name-only --no-renames HEAD; git -C "$wt" ls-files -o; } | sort -u > "$keep/.list"
  : > "$keep/.gone"
  : > "$keep/.beside"
  while IFS= read -r rel; do
    if [ ! -f "$wt/$rel" ]; then
      printf '%s\n' "$rel" >> "$keep/.gone"
      continue
    fi
    if ! { mkdir -p "$(dirname "$keep/files/$rel")" && cp -p "$wt/$rel" "$keep/files/$rel"; } 2>/dev/null; then
      bad=1
    fi
  done < "$keep/.list"
  # The copy aside failed: nothing in memory/logs was touched yet, so leave it as it is.
  if [ "$bad" -ne 0 ]; then
    printf 'could not keep aside the files changed here before bringing memory/logs up to the host'"'"'s logs branch. memory/logs was not changed. A part copy is in %s. Check the free disk space, then run this again\n' "$keep" >&2
    return 1
  fi
  if ! git -C "$wt" reset -q --hard "$ref" >/dev/null 2>&1; then
    if v0logs_undo "$wt" "$old" "$keep"; then
      printf 'could not bring memory/logs up to the host'"'"'s logs branch, so memory/logs is back as it was. Nothing was removed. A copy of the files changed here is also in %s. Check the free disk space, then run this again\n' "$keep" >&2
    else
      printf 'could not bring memory/logs up to the host'"'"'s logs branch. A copy of the files changed here is in %s. Copy them back into memory/logs, then run this again\n' "$keep" >&2
    fi
    return 1
  fi
  while IFS= read -r rel; do
    [ -f "$keep/files/$rel" ] || continue
    blob=$(git -C "$wt" rev-parse -q --verify "$ref:$rel" 2>/dev/null || true)
    if [ -n "$blob" ] && [ "$blob" != "$(git -C "$wt" rev-parse -q --verify "$old:$rel" 2>/dev/null || true)" ] \
      && [ "$blob" != "$(git -C "$wt" hash-object -- "$keep/files/$rel")" ] \
      && name=$(v0logs_beside "$wt" "$rel" "$blob"); then
      printf '%s\n' "$name" >> "$keep/.beside"
      git -C "$wt" cat-file blob "$blob" > "$wt/$name" || bad=1
    fi
    { mkdir -p "$(dirname "$wt/$rel")" && cp -p "$keep/files/$rel" "$wt/$rel"; } 2>/dev/null || bad=1
  done < "$keep/.list"
  if [ "$bad" -ne 0 ]; then
    # Never leave the folder at <ref> with a file missing: the next run would see it up
    # to date and move it out without that file.
    if v0logs_undo "$wt" "$old" "$keep"; then
      printf 'could not put the files changed here back into memory/logs, so memory/logs is back as it was. Nothing was removed. A copy of them is also in %s. Close any program that has a log open, then run this again\n' "$keep" >&2
    else
      printf 'could not put the files changed here back into memory/logs. A copy of them is in %s. Copy them back into memory/logs, then run this again\n' "$keep" >&2
    fi
    return 1
  fi
  rm -rf "$keep"
}

# Put memory/logs (<wt>) back as it was before v0logs_follow: the folder at <old>, no file
# it wrote beside, every file kept aside back, and every file the person had removed gone
# again. Returns 1 when a step fails.
v0logs_undo() {
  local wt=$1 old=$2 keep=$3 rel bad=0
  # Before the reset: a beside name can be a file <old> tracks, which the reset brings back.
  while IFS= read -r rel; do
    rm -f "$wt/$rel" || bad=1
  done < "$keep/.beside"
  git -C "$wt" reset -q --hard "$old" >/dev/null 2>&1 || bad=1
  if [ -d "$keep/files" ]; then
    cp -Rp "$keep/files/." "$wt/" 2>/dev/null || bad=1
  fi
  while IFS= read -r rel; do
    rm -f "$wt/$rel" || bad=1
  done < "$keep/.gone"
  [ "$bad" -eq 0 ]
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

# Copy each saved file to its place (v0logs_target). A file the person changed or added
# (it differs from the folder's last commit, branch logs) is their copy: it wins over
# main's, and main's copy stays in history. A file still as committed is the old branch's
# text: it goes in only when main lacks it, or when main's copy is an earlier version of
# it on branch logs. So an older text never replaces a newer one. A place with a change not
# committed on main (an edit made in memory/logs-archive/) is never written over: the
# person's copy goes beside it (v0logs_beside). Prints "<written> <beside> <kept>": beside
# counts the v0logs_beside files v0logs_follow made, kept the places left as they were with
# the copy beside. If any copy fails (a file lock on Windows), the saved folder stays, one
# plain line names it on stderr, and it returns 1. Every step is checked by hand: bash 3.2
# runs this in $( ), where set -e does not reach.
v0logs_put_back() {
  local repo=$1 save=$2 rel target dest name n=0 m=0 k=0 bad=0 head blob
  head=$(git -C "$repo" rev-parse -q --verify refs/heads/logs 2>/dev/null || true)
  while IFS= read -r rel; do
    rel=${rel#./}
    target=$(v0logs_target "$repo" "$rel")
    dest="$repo/$target"
    if [ -f "$dest" ]; then
      cmp -s "$save/$rel" "$dest" && continue
      blob=$(git -C "$repo" hash-object -- "$save/$rel")
      if [ -n "$head" ] && [ "$blob" = "$(git -C "$repo" rev-parse -q --verify "$head:$rel" 2>/dev/null || true)" ]; then
        v0logs_committed "$repo" "$target" "$dest" || continue
        v0logs_earlier "$repo" "$head" "$rel" "$dest" || continue
      elif ! v0logs_committed "$repo" "$target" "$dest"; then
        name=$(v0logs_beside "$repo" "$target" "$blob") || continue
        if cp -p "$save/$rel" "$repo/$name"; then
          k=$((k + 1))
        else
          bad=$((bad + 1))
        fi
        continue
      fi
    fi
    if mkdir -p "$(dirname "$dest")" && cp -p "$save/$rel" "$dest"; then
      n=$((n + 1))
      ! v0logs_is_beside "$rel" || m=$((m + 1))
    else
      bad=$((bad + 1))
    fi
  done < <(cd "$save" && find . -type f)
  if [ "$bad" -ne 0 ]; then
    printf 'could not copy %s logs back into memory/logs. A full copy is in %s. Keep that folder: close any program that has a log open, then ask the admin to copy the logs back from it\n' "$bad" "$save" >&2
    return 1
  fi
  rm -rf "$save"
  printf '%s %s %s\n' "$((n - m))" "$m" "$k"
}

# 0 when <file> holds the text main's last commit has at <path>.
v0logs_committed() {
  local repo=$1 path=$2 file=$3 blob
  blob=$(git -C "$repo" rev-parse -q --verify "HEAD:$path" 2>/dev/null) || return 1
  [ "$(git -C "$repo" hash-object -- "$file" 2>/dev/null)" = "$blob" ]
}

# 0 when the text of <file> is one of the versions <rel> had on <commit>'s history.
v0logs_earlier() {
  local repo=$1 commit=$2 rel=$3 file=$4 blob
  blob=$(git -C "$repo" hash-object -- "$file" 2>/dev/null) || return 1
  case " $(git -C "$repo" log --format= --raw -m --root --no-abbrev --no-renames "$commit" -- "$rel" 2>/dev/null | tr '\n' ' ') " in
    *" $blob "*) return 0 ;;
  esac
  return 1
}

# Logs pushed to branch logs after the upgrade never reach main by themselves. Compare
# the newest logs-archive-<date> tag (the upgrade's snapshot) with origin/logs. Write each
# file added or changed since then to its place as a local change; the next push sends
# it. A place that is taken (main's file, or one the person has) is never written over:
# the old branch's text goes beside it (v0logs_beside), once per text. Prints "<written>
# <beside>". A
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
      dest=$(v0logs_beside "$repo" "$dest" "$blob") || continue
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
