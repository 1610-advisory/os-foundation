#!/bin/bash
# Pull helpers. Sourced by sync.sh.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh." >&2
  exit 1
fi

# One parser for pull and push. -z rename is XY <to>\0<from>\0.
# Prints one path per line. A rename prints the to path, then the from path.
sync_changed_names() {
  local repo=$1
  local line xy path from
  while IFS= read -r -d '' line; do
    [ -n "$line" ] || continue
    xy=${line:0:2}
    path=${line:3}
    case "$path" in
      *$'\n'*) continue ;;
    esac
    case "$xy" in
      R*|C*)
        IFS= read -r -d '' from || true
        printf '%s\n' "$path"
        if [ -n "$from" ]; then
          printf '%s\n' "$from"
        fi
        ;;
      *)
        printf '%s\n' "$path"
        ;;
    esac
  done < <(git -C "$repo" status --porcelain -z -uall)
}

# Files the host changed since this folder's history and the host's last met.
sync_host_changed() {
  local repo=$1 base
  base=$(git -C "$repo" merge-base HEAD origin/main 2>/dev/null) || return 1
  sync_names "$repo" diff --name-only --no-renames "$base" origin/main
}

# Put one path back as HEAD has it. A copy HEAD does not track is removed.
sync_drop_local() {
  local repo=$1 path=$2
  if git -C "$repo" cat-file -e "HEAD:${path}" 2>/dev/null; then
    git -C "$repo" --literal-pathspecs checkout -q HEAD -- "$path"
  else
    git -C "$repo" --literal-pathspecs rm -q --cached --ignore-unmatch -- "$path" >/dev/null 2>&1 || true
    rm -f "$repo/$path"
  fi
}

# The blob of a path in a commit, or none.
sync_blob_of() {
  git -C "$1" rev-parse -q --verify "$2:$3" 2>/dev/null || printf '%s\n' none
}

# Before the host's commits come in, look at each file that is changed here and that the
# host changed too. The same text as the host's (a proposed rules file that merged, a
# delete that merged, B48), or deleted on both sides: drop the local copy. Different: a
# real change made while someone else changed the file. Git never merges it by machine:
# the person's version is set aside and the host's text comes in (memo 8.1).
sync_dirty_pass() {
  local repo=$1 id=$2 incoming dirty path want have
  incoming=$(sync_mktemp)
  dirty=$(sync_mktemp)
  sync_host_changed "$repo" > "$incoming" 2>/dev/null || return 0
  [ -s "$incoming" ] || return 0
  sync_changed_names "$repo" > "$dirty" || true
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    grep -Fxq -- "$path" "$incoming" || continue
    want=$(sync_blob_of "$repo" origin/main "$path")
    if [ -f "$repo/$path" ] && [ ! -L "$repo/$path" ]; then
      have=$(git -C "$repo" hash-object -- "$path" 2>/dev/null || true)
      if [ "$want" = "$have" ]; then
        sync_drop_local "$repo" "$path"
        sync_held_drop "$id" "$path"
        continue
      fi
    elif [ ! -e "$repo/$path" ] && [ ! -L "$repo/$path" ] && [ "$want" = "none" ]; then
      sync_drop_local "$repo" "$path"
      sync_held_drop "$id" "$path"
      continue
    fi
    sync_set_aside "$repo" "$id" "$path" "$(sync_blob_of "$repo" HEAD "$path")" worktree || return 1
    sync_drop_local "$repo" "$path"
  done < "$dirty"
}

# Where a set-aside copy lives: ${config}/state/reapply/<repo>/<path>.
sync_reapply_dir() {
  local id=$1
  case "$id" in
    area:*) id="area-${id#area:}" ;;
  esac
  printf '%s/reapply/%s\n' "$SYNC_STATE" "$id"
}

# Keep the person's version of one file, and the text it was edited from, and hold the
# file: the agent re-applies the change on the host's text (re-apply.md). from is
# worktree (an edit not committed), commit (a sync commit not merged yet) or held:<file>
# (a copy taken out first; no file means deleted).
sync_set_aside() {
  local repo=$1 id=$2 path=$3 base=$4 from=$5 dir slot mine basefile n=1 line tmp
  dir=$(sync_reapply_dir "$id")
  slot="${dir}/${path}"
  while [ -e "$slot" ] || [ -e "${slot}.base" ]; do
    n=$((n + 1))
    slot="${dir}/${path}.${n}"
  done
  mkdir -p "$(dirname "$slot")"
  chmod 700 "$SYNC_STATE/reapply" 2>/dev/null || true
  mine=$slot
  if [ "$from" = "commit" ]; then
    if git -C "$repo" cat-file -e "HEAD:${path}" 2>/dev/null; then
      git -C "$repo" show "HEAD:${path}" > "$mine" || return 1
    else
      mine=deleted
    fi
  elif [ "${from#held:}" != "$from" ]; then
    if [ -e "${from#held:}" ]; then
      cp -p "${from#held:}" "$mine" || return 1
    else
      mine=deleted
    fi
  elif [ -f "$repo/$path" ]; then
    cp -p "$repo/$path" "$mine" || return 1
  else
    mine=deleted
  fi
  [ "$mine" = "deleted" ] || chmod 600 "$mine"
  basefile=none
  if [ "$base" != "none" ]; then
    basefile="${slot}.base"
    git -C "$repo" cat-file blob "$base" > "$basefile" || return 1
    chmod 600 "$basefile"
  fi
  line=$(jq -nc --arg repo "$id" --arg path "$path" --arg base "$base" --arg mine "$mine" --arg basefile "$basefile" \
    '{repo:$repo, path:$path, kind:"re-apply", reason:"re-apply: changed on the host while you worked", base:$base, mine:$mine, basefile:$basefile}')
  tmp=$(sync_mktemp)
  jq --argjson f "$line" '.files += [$f]' "$SYNC_HELD" > "$tmp"
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
  sync_log "pull re-apply ${id} ${path}"
  printf '%s\n' "${id} ${path}: changed on the host while you worked. Your version is set aside and the host's text is here; the agent re-applies your change (skills/sync/re-apply.md)."
}

# Sync makes every commit in this folder, each with a Sync-Seat trailer. A commit
# without one (made by hand, or by another tool) is never pushed or merged.
sync_foreign_commits() {
  local repo=$1
  git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null 2>&1 || return 0
  git -C "$repo" log --no-merges --format='%H %(trailers:key=Sync-Seat,valueonly,separator=%x2C)' origin/main..HEAD \
    | awk 'NF < 2 { c++ } END { print c + 0 }'
}

# The commit message trailer for this computer.
sync_trailer() {
  printf '\nSync-Seat: %s\n' "$(sync_seat)"
}

sync_commit_msg() {
  local text=$1 file
  file=$(sync_mktemp)
  { printf '%s\n' "$text"; sync_trailer; } > "$file"
  printf '%s\n' "$file"
}

sync_git_commit() {
  local repo=$1 msgfile=$2 author name email
  shift 2
  author=$(sync_commit_author)
  name=$(printf '%s\n' "$author" | head -n 1)
  email=$(printf '%s\n' "$author" | tail -n 1)
  git -C "$repo" -c user.name="$name" -c user.email="$email" -c commit.gpgsign=false "$@" -F "$msgfile"
}

# Every file a ref's commits changed since it met main has the same text on main: main
# holds that work, whatever commits it came in by. Prints how many files.
sync_files_on_main() {
  local repo=$1 ref=$2 base path n=0
  base=$(git -C "$repo" merge-base "$ref" origin/main 2>/dev/null) || return 1
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ "$(sync_blob_of "$repo" "$ref" "$path")" = "$(sync_blob_of "$repo" origin/main "$path")" ] || return 1
    n=$((n + 1))
  done < <(sync_names "$repo" diff --name-only --no-renames "$base" "$ref")
  printf '%s\n' "$n"
}

# A squash merge puts the person's change on main as a new commit. The folder's own
# commits then never reach main, so nothing fast-forwards again. Seen when every file the
# local commits changed already has the same text on main.
sync_squashed() {
  local n
  n=$(sync_files_on_main "$1" HEAD) || return 1
  [ "$n" -gt 0 ]
}

# Put back every file sync_after_squash copied out: the folder is as it was.
sync_squash_restore() {
  local repo=$1 hold=$2 i=1 path
  while [ -f "${hold}/${i}.path" ]; do
    path=$(cat "${hold}/${i}.path")
    rm -f "$repo/$path"
    if [ -e "${hold}/${i}" ] || [ -L "${hold}/${i}" ]; then
      mkdir -p "$(dirname "$repo/$path")"
      cp -pP "${hold}/${i}" "$repo/$path"
    fi
    i=$((i + 1))
  done
}

# After a squash, main has every file these commits changed, with the same text, so
# nothing is lost by taking main as it is. The folder takes main's text for every file
# main has and this commit lacks, a teammate's note merged since too: a reset that kept
# the old text would make the next push put it back. A file changed here that main changed
# too is copied out and put back as HEAD has it, so git can take main. Only once main is
# in is it set aside (8.1). Every other change here stays. Returns 1 when main could not be
# taken: every copied file is put back, so nothing changed and the branch stays. Returns 2
# when a file could not be set aside after main came in: its copy stays where the line
# says. The old commits are never pushed again: this computer's branch on the host is
# deleted, so the next push starts from main.
sync_after_squash() {
  local repo=$1 id=$2 me seat ref old dirty hold path i n=0
  old=$(git -C "$repo" rev-parse HEAD)
  dirty=$(sync_mktemp)
  sync_changed_names "$repo" > "$dirty" || true
  mkdir -p "$SYNC_STATE"
  hold=$(mktemp -d "${SYNC_STATE}/squash.XXXXXX") || return 1
  chmod 700 "$hold"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    grep -Fxq -- "$path" "$dirty" || continue
    n=$((n + 1))
    printf '%s' "$path" > "${hold}/${n}.path"
    if [ -e "$repo/$path" ] || [ -L "$repo/$path" ]; then
      cp -pP "$repo/$path" "${hold}/${n}" || { sync_squash_restore "$repo" "$hold"; rm -rf "$hold"; return 1; }
    fi
    if [ -f "$repo/$path" ] && [ ! -L "$repo/$path" ] \
      && [ "$(git -C "$repo" hash-object -- "$path" 2>/dev/null)" = "$(sync_blob_of "$repo" origin/main "$path")" ]; then
      : > "${hold}/${n}.same"
    fi
  done < <(sync_names "$repo" diff --name-only --no-renames HEAD origin/main)
  i=1
  while [ "$i" -le "$n" ]; do
    sync_drop_local "$repo" "$(cat "${hold}/${i}.path")"
    i=$((i + 1))
  done
  if [ "${OS_SYNC_SQUASH_FAIL:-}" = "1" ] || ! git -C "$repo" reset -q \
    || ! git -C "$repo" reset -q --merge origin/main >/dev/null 2>&1; then
    sync_squash_restore "$repo" "$hold"
    rm -rf "$hold"
    sync_log "pull squash ${id} could not take main"
    return 1
  fi
  sync_log "pull squash ${id} took main"
  i=1
  while [ "$i" -le "$n" ]; do
    path=$(cat "${hold}/${i}.path")
    if [ ! -e "${hold}/${i}.same" ] \
      && ! sync_set_aside "$repo" "$id" "$path" "$(sync_blob_of "$repo" "$old" "$path")" "held:${hold}/${i}"; then
      sync_log "pull squash ${id} could not set aside ${path}"
      printf '%s\n' "${id} ${path}: could not set your version aside. Your copy is at ${hold}/${i}. Ask the admin." >&2
      return 2
    fi
    i=$((i + 1))
  done
  rm -rf "$hold"
  [ "$id" != "workspace" ] || return 0
  me=$(sync_me)
  seat=$(sync_seat)
  ref="refs/remotes/origin/sync/${me}/${seat}"
  git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null || return 0
  git -C "$repo" merge-base --is-ancestor "$ref" "$old" || return 0
  if sync_git "$repo" push origin ":refs/heads/sync/${me}/${seat}" >/dev/null 2>&1; then
    git -C "$repo" update-ref -d "$ref" 2>/dev/null || true
  else
    sync_log "pull squash ${id} could not delete sync/${me}/${seat}"
    printf '%s\n' "${id}: could not delete the branch sync/${me}/${seat} on the host. It holds only work main already has. The next push deletes it first, then sends." >&2
  fi
}

# This folder has sync commits the host has not merged, and the host's main moved on.
# Bring main in with a merge commit, as the host would. A file both sides changed is set
# aside (its change is undone in one sync commit, so the host's text wins the merge).
sync_merge_host() {
  local repo=$1 id=$2 msg conflicts base path n
  git -C "$repo" reset -q
  msg=$(sync_commit_msg "Take main from the host")
  if sync_git_commit "$repo" "$msg" merge --no-ff -q origin/main >/dev/null 2>&1; then
    return 0
  fi
  conflicts=$(sync_mktemp)
  sync_names "$repo" diff --name-only --diff-filter=U > "$conflicts" || true
  git -C "$repo" merge --abort >/dev/null 2>&1 || true
  if [ ! -s "$conflicts" ]; then
    return 1
  fi
  base=$(git -C "$repo" merge-base HEAD origin/main) || return 1
  n=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    sync_set_aside "$repo" "$id" "$path" "$(sync_blob_of "$repo" "$base" "$path")" commit || return 1
    if git -C "$repo" cat-file -e "${base}:${path}" 2>/dev/null; then
      git -C "$repo" --literal-pathspecs checkout -q "$base" -- "$path" || return 1
    else
      git -C "$repo" --literal-pathspecs rm -q -- "$path" >/dev/null || return 1
    fi
    n=$((n + 1))
  done < "$conflicts"
  msg=$(sync_commit_msg "Set aside ${n} files the host changed too")
  sync_git_commit "$repo" "$msg" commit -q >/dev/null 2>&1 || return 1
  msg=$(sync_commit_msg "Take main from the host")
  if ! sync_git_commit "$repo" "$msg" merge --no-ff -q origin/main >/dev/null 2>&1; then
    git -C "$repo" merge --abort >/dev/null 2>&1 || true
    return 1
  fi
}

sync_rewrite_tag() {
  local repo=$1
  local id=$2
  local listed newest recorded line name
  listed=$(sync_mktemp)
  if ! sync_git "$repo" ls-remote --tags origin 'refs/tags/os-rewrite-*' > "$listed"; then
    return 1
  fi
  newest=""
  while IFS= read -r line; do
    name=${line##*refs/tags/}
    name=${name%\^\{\}}
    case "$name" in
      os-rewrite-[0-9]*) ;;
      *) continue ;;
    esac
    if [ -z "$newest" ] || [ "$name" \> "$newest" ]; then
      newest=$name
    fi
  done < "$listed"
  [ -n "$newest" ] || return 1
  recorded=""
  if [ -f "$SYNC_REWRITE" ]; then
    recorded=$(awk -v id="$id" '$1 == id { print $2; exit }' "$SYNC_REWRITE")
  fi
  if [ -n "$recorded" ] && [ ! "$newest" \> "$recorded" ]; then
    return 1
  fi
  printf '%s\n' "$newest"
}

sync_tag_rules() {
  local repo=$1
  local tag=$2
  local obj
  if ! sync_git "$repo" fetch origin "refs/tags/${tag}:refs/tags/${tag}" >/dev/null 2>&1; then
    return 0
  fi
  obj=$(git -C "$repo" cat-file -p "refs/tags/${tag}" 2>/dev/null || true)
  printf '%s\n' "$obj" | awk '/^rule: / { print $2 }'
}

sync_record_rewrite() {
  local id=$1
  local tag=$2
  local tmp
  tmp=$(sync_mktemp)
  if [ -f "$SYNC_REWRITE" ]; then
    awk -v id="$id" '$1 != id { print }' "$SYNC_REWRITE" > "$tmp"
  fi
  printf '%s %s\n' "$id" "$tag" >> "$tmp"
  mv "$tmp" "$SYNC_REWRITE"
  chmod 600 "$SYNC_REWRITE"
}

sync_move_nested() {
  local repo=$1
  local dest=$2
  local d rel
  if [ "${OS_SYNC_MOVE_BACK_FAIL:-}" = "1" ]; then
    return 1
  fi
  # library/ is the admin's private repo. The company repo ignores it, so a
  # clone never has it. Move it even without a .git: media is the only copy.
  for d in "$repo"/areas/* "$repo"/users/* "$repo"/library; do
    rel=${d#"$repo/"}
    if [ "$rel" = "library" ]; then
      [ -e "$d" ] || continue
    else
      [ -e "$d/.git" ] || continue
    fi
    if [ -e "$dest/$rel" ]; then
      return 1
    fi
    mkdir -p "$dest/$(dirname "$rel")"
    if ! mv "$d" "$dest/$rel"; then
      return 1
    fi
  done
  return 0
}

# A temp tree that still has a git dir is left in place. Never delete it.
# repo, when given, is the company folder library/ belongs in.
sync_rm_temp() {
  local tree=$1
  local id=$2
  local repo=${3:-}
  local found
  if [ ! -e "$tree" ]; then
    return 0
  fi
  # library/ may have no .git, and its media is the only copy. Say where it goes back.
  if [ -e "$tree/library" ]; then
    sync_pull_fail "$id" "reclone: library at ${tree}/library -> ${repo:-the company folder}/library"
    return 1
  fi
  # Skip the clone's own top-level .git. A nested repo is deeper.
  found=$(find "$tree" -mindepth 2 -name .git -print -prune 2>/dev/null | head -n 1 || true)
  if [ -n "$found" ]; then
    sync_pull_fail "$id" "reclone: left ${tree}"
    return 1
  fi
  rm -rf "$tree"
  return 0
}

sync_reclone_restore() {
  local repo=$1
  local old=$2
  local new=$3
  local id=$4
  sync_move_nested "$repo" "$old" || true
  if [ -d "$repo" ] && [ -d "$old" ]; then
    mv "$repo" "$new.fail" 2>/dev/null || true
    mv "$old" "$repo" 2>/dev/null || true
    sync_rm_temp "$new.fail" "$id" "$repo" || return 1
  fi
  return 0
}

sync_reclone() {
  local repo=$1
  local id=$2
  local tag=$3
  local url parent new rules rule path scanner hit copied old
  url=$(git -C "$repo" remote get-url origin)
  case "$url" in
    *://*@*) sync_die 1 "refusing a credential in the remote URL" ;;
  esac
  if [ "${OS_TEST_MODE:-}" = "1" ]; then
    sync_under_home "$repo" || sync_die 1 "refusing a path outside home"
  fi
  parent=$(dirname "$repo")
  new="$parent/.sync-reclone-$$"
  if ! sync_git "$repo" clone -- "$url" "$new"; then
    sync_pull_fail "$id" "could not reach origin"
    return 1
  fi
  rules=$(sync_mktemp)
  copied=$(sync_mktemp)
  sync_tag_rules "$repo" "$tag" > "$rules" || true
  scanner="$SYNC_DIR/secret-scan.sh"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -f "$repo/$path" ] || continue
    case "$path" in
      areas/*|users/*|library/*) continue ;;
    esac
    hit=0
    if [ -s "$rules" ]; then
      set +e
      scan=$("$scanner" --files "$repo/$path" 2>/dev/null)
      src=$?
      set -e
      if [ "$src" -eq 1 ]; then
        while IFS= read -r rule; do
          [ -n "$rule" ] || continue
          case "$scan" in
            *":$rule"*) hit=1 ;;
          esac
        done < "$rules"
      fi
    fi
    if [ "$hit" -eq 1 ]; then
      sync_log "pull drop ${id} ${path}"
      continue
    fi
    mkdir -p "$new/$(dirname "$path")" || true
    if ! cp "$repo/$path" "$new/$path"; then
      sync_pull_fail "$id" "reclone: could not copy ${path}; nothing removed"
      sync_rm_temp "$new" "$id" || true
      return 1
    fi
    printf '%s\n' "$path" >> "$copied"
  done < <(sync_changed_names "$repo")
  if ! git -C "$new" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    sync_pull_fail "$id" "reclone: could not copy ${new}; nothing removed"
    sync_rm_temp "$new" "$id" || true
    return 1
  fi
  local old="$parent/.sync-old-$$"
  if ! mv "$repo" "$old"; then
    sync_pull_fail "$id" "reclone: could not copy ${repo}; nothing removed"
    sync_rm_temp "$new" "$id" || true
    return 1
  fi
  if ! mv "$new" "$repo"; then
    mv "$old" "$repo" || true
    sync_pull_fail "$id" "reclone: could not copy ${repo}; nothing removed"
    sync_rm_temp "$new" "$id" || true
    return 1
  fi
  if [ "${OS_SYNC_RECLONE_FAIL:-}" = "nested" ]; then
    sync_reclone_restore "$repo" "$old" "$new" "$id" || true
    sync_pull_fail "$id" "reclone"
    return 1
  fi
  if ! sync_move_nested "$old" "$repo"; then
    sync_reclone_restore "$repo" "$old" "$new" "$id" || true
    sync_pull_fail "$id" "reclone: could not copy areas; nothing removed"
    return 1
  fi
  if [ "${OS_SYNC_RECLONE_FAIL:-}" = "after-nested" ]; then
    OS_SYNC_MOVE_BACK_FAIL=1
    sync_reclone_restore "$repo" "$old" "$new" "$id" || true
    sync_pull_fail "$id" "reclone: could not copy areas; nothing removed"
    return 1
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! cmp -s "$old/$path" "$repo/$path"; then
      sync_reclone_restore "$repo" "$old" "$new" "$id" || true
      sync_pull_fail "$id" "reclone: could not copy ${path}; nothing removed"
      return 1
    fi
  done < "$copied"
  rm -rf "$old"
  sync_record_rewrite "$id" "$tag"
  sync_log "pull reclone ${id} ${tag}"
}

# A failed pull: the log line, one plain line for the person, and last_error, so
# sync.sh status shows it. The log keeps the short reason; the person gets the fix.
sync_pull_fail() {
  local id=$1 reason=$2 plain detail
  case "$reason" in
    "could not reach origin") plain="could not reach the host. Check the internet connection and sign-in, then run it again." ;;
    "no origin/main") plain="the host has no main branch. Ask the admin." ;;
    "local changes") plain="files changed here are in the way. Run sync.sh push, then pull again." ;;
    "not fast-forward") plain="this copy could not take the host's changes. Nothing was changed here. Ask the admin before you change anything." ;;
    "not on main") plain="this folder is not on its main branch. Nothing was changed. Ask the admin." ;;
    "upgrade not merged: "*) plain="this folder is on ${reason#upgrade not merged: } until the upgrade pull request merges. Nothing was changed. When it has merged, run skills/sync/sync.sh pull again: it puts the folder back on main." ;;
    "foreign commit") plain="this folder has a change that sync did not make. Nothing was pushed or changed. Ask the admin." ;;
    "squash") plain="your last changes reached main by a squash merge. Main has your text, so this copy now has main, and your other changes are kept. Sync needs merge commits: ask the admin never to squash a sync pull request." ;;
    "squash: could not take main") plain="your last changes reached main by a squash merge, but this copy could not take main. Nothing was changed or pushed. Ask the admin." ;;
    "squash: could not set a file aside") plain="your last changes reached main by a squash merge. This copy now has main, but a file changed here could not be set aside: the line above says where its copy is. Nothing was pushed. Ask the admin." ;;
    "merge left open") plain="a merge stopped halfway here and could not be undone. Nothing was changed or pushed. Ask the admin." ;;
    "v0 logs: "*) plain="the old logs folder memory/logs could not be moved: ${reason#v0 logs: }." ;;
    "v0 catch-up: "*) plain="${reason#v0 catch-up: }." ;;
    "unpushed: "*) plain="this copy has ${reason#unpushed: } commits (on any local branch) that are not on the host, so it was not swapped for a fresh copy after the host history was rewritten. Nothing was removed. Ask the admin." ;;
    "reclone: left "*) plain="a temporary copy was left at ${reason#reclone: left }. Check it, then delete it." ;;
    "reclone: library at "*)
      detail=${reason#reclone: library at }
      plain="the library at ${detail%% -> *} is the only copy: move it back to ${detail#* -> }. Then check the rest of ${detail%%/library -> *} and delete it."
      ;;
    reclone*)
      detail=${reason#reclone}
      detail=${detail#: }
      plain="could not swap in a fresh copy from the host${detail:+ (${detail})}. Nothing was removed. Ask the admin."
      ;;
    *) plain=$reason ;;
  esac
  sync_log "pull fail ${id} ${reason}"
  # One line per repo. The first reason is the one to act on.
  [ "${SYNC_PULL_FAILED:-}" != "$id" ] || return 0
  SYNC_PULL_FAILED=$id
  if [ "$reason" = "could not reach origin" ]; then
    # Every repo fails the same way when the host is down: one line at the end names them.
    SYNC_UNREACHED="${SYNC_UNREACHED:+${SYNC_UNREACHED}, }${id}"
    SYNC_UNREACHED_PLAIN=$plain
  else
    printf 'pull failed for %s: %s\n' "$id" "$plain" >&2
  fi
  if [ -z "${SYNC_RUN_ERROR:-}" ]; then
    sync_held_error "pull failed for ${id}: ${plain}"
  fi
}


# The one line for every repo the host could not be reached for.
sync_unreached_flush() {
  [ -n "${SYNC_UNREACHED:-}" ] || return 0
  printf 'pull failed for %s: %s\n' "$SYNC_UNREACHED" "$SYNC_UNREACHED_PLAIN" >&2
  SYNC_UNREACHED=""
}

sync_pull_mark() {
  SYNC_PULL_DONE="${SYNC_PULL_DONE:-}|$1|"
}

sync_pull_seen() {
  case "${SYNC_PULL_DONE:-}" in
    *"|$1|"*) return 0 ;;
  esac
  return 1
}

# OS_SYNC_NO_COPY_REFRESH=1 skips the fold. The timing check uses it.
sync_pull_refresh_one() {
  local repo=$1
  if [ "${OS_SYNC_NO_COPY_REFRESH:-}" = "1" ]; then
    return 0
  fi
  sync_materialize_repo "$repo"
}

# Repos sync_pull_one skipped (no origin) still get one pass.
sync_materialize_undone() {
  local root=$1
  local area
  if [ "${OS_SYNC_NO_COPY_REFRESH:-}" = "1" ]; then
    return 0
  fi
  if [ -d "$root" ] && ! sync_pull_seen "$root"; then
    sync_materialize_repo "$root"
  fi
  if [ -d "$root/areas" ]; then
    for area in "$root"/areas/*; do
      [ -d "$area" ] || continue
      if ! sync_pull_seen "$area"; then
        sync_materialize_repo "$area"
      fi
    done
  fi
}

sync_pull_one() {
  local repo=$1
  local id=$2
  local rc=0
  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  sync_pull_fetched "$repo" "$id" || rc=$?
  sync_pull_refresh_one "$repo"
  sync_pull_mark "$repo"
  return "$rc"
}

# Moving from the old sync code (keep for one release, then delete): a clone that join
# or v0 left on sync/<me> goes back to main. Only HEAD moves: the files stay as they are,
# so what the branch held is now a local change, which the pass below drops when main
# already has it, and the next push sends when it does not.
#
# The admin's folder after an upgrade on a host is the same case (B52): the upgrade leaves
# the company folder on upgrade/v1 and each area on upgrade/scripts. Once that branch is
# on the host's main (its pull request merged), the folder goes back to main the same way.
# Files team-on wrote meanwhile that main now has drop in the pass below.
sync_pull_leave_own_branch() {
  local repo=$1 id=$2 me cur base
  me=$(sync_me)
  cur=$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)
  case "$cur" in
    upgrade/*)
      git -C "$repo" merge-base --is-ancestor HEAD origin/main 2>/dev/null || return 0
      ;;
    *)
      [ -n "$me" ] && [ "$cur" = "sync/${me}" ] || return 0
      ;;
  esac
  if git -C "$repo" rev-parse --verify --quiet refs/heads/main >/dev/null \
    && ! git -C "$repo" merge-base --is-ancestor refs/heads/main origin/main; then
    sync_log "pull hold ${id} on ${cur}: main has commits the host lacks"
    return 0
  fi
  base=$(git -C "$repo" merge-base HEAD origin/main 2>/dev/null) || return 0
  git -C "$repo" update-ref refs/heads/main "$base" || return 0
  git -C "$repo" symbolic-ref HEAD refs/heads/main || return 0
  git -C "$repo" reset -q
  sync_log "pull ok ${id} back on main from ${cur}"
}

# A v0 clone keeps memory/logs as a worktree of branch logs after the upgrade lands
# (v0logs.sh). It goes before the fast-forward; its files come back after it.
sync_pull_fetched() {
  local repo=$1
  local id=$2
  local rc=0 n err written beside kept
  SYNC_V0_SAVE=""
  sync_pull_ff "$repo" "$id" || rc=$?
  if [ -n "$SYNC_V0_SAVE" ]; then
    err=$(sync_mktemp)
    if n=$(v0logs_put_back "$repo" "$SYNC_V0_SAVE" 2>"$err"); then
      read -r written beside kept <<< "$n"
      if [ "$beside" -gt 0 ]; then
        printf 'logs: %s files in the old logs folder were changed here and on the old logs branch in %s, so the old text is beside each one as <name>.old-branch.md. Nothing was written over.\n' "$beside" "$id"
      fi
      if [ "$kept" -gt 0 ]; then
        printf 'logs: %s files in memory/logs-archive/ have a change here that is not committed in %s, so the copy from the old logs folder is beside each one as <name>.old-branch.md. Nothing was written over.\n' "$kept" "$id"
      fi
      sync_log "pull v0-logs ${id} worktree removed, ${written} files kept as local changes, ${beside} beside, ${kept} beside a change not committed"
    else
      sync_pull_fail "$id" "v0 logs: $(head -n 1 "$err")"
      rc=1
    fi
    SYNC_V0_SAVE=""
  fi
  # Logs pushed to the old logs branch after the upgrade come in as local changes.
  if [ "$rc" -eq 0 ]; then
    err=$(sync_mktemp)
    if n=$(v0logs_catch_up "$repo" 2>"$err"); then
      if [ "${n% *}" -gt 0 ]; then
        printf 'logs: %s files written to the old logs branch after the upgrade are now in memory/logs-archive/ in %s. The next push sends them.\n' "${n% *}" "$id"
      fi
      if [ "${n#* }" -gt 0 ]; then
        printf 'logs: %s files from the old logs branch had a different copy here in %s, so the old text is beside each one as <name>.old-branch.md. Nothing was written over.\n' "${n#* }" "$id"
      fi
      [ "$n" = "0 0" ] || sync_log "pull logs-catch-up ${id} ${n% *} files ${n#* } beside"
    else
      sync_pull_fail "$id" "v0 catch-up: $(head -n 1 "$err")"
      rc=1
    fi
  fi
  return "$rc"
}

# Commits on HEAD or any local branch that no origin branch holds or ever held here. A
# rewrite moves the host branches, so their old tips (kept in this clone's reflog) count
# as on the host. No reflog to read: every commit not on a host branch now counts.
sync_unpushed_count() {
  local repo=$1 ref
  {
    printf '%s\n' HEAD
    git -C "$repo" for-each-ref --format='%(refname)' refs/heads
    git -C "$repo" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r ref; do
      printf '^%s\n' "$ref"
      git -C "$repo" reflog show --format='^%H' "$ref" -- 2>/dev/null || true
    done
  } | git -C "$repo" rev-list --count --stdin 2>/dev/null || printf '%s\n' unknown
}

# A pull that could not leave this repo safe. The push in the same run commits nothing
# there and sends nothing.
sync_pull_stop() {
  SYNC_PULL_STOPPED="${SYNC_PULL_STOPPED:-}|$1|"
}

sync_pull_stopped() {
  case "${SYNC_PULL_STOPPED:-}" in
    *"|$1|"*) return 0 ;;
  esac
  return 1
}

# A run that died inside sync's own merge leaves MERGE_HEAD and conflict lines in the
# files. Undo that merge before anything resets: a reset would clear the merge and keep
# the conflict lines, and the next push would send them.
sync_abort_open_merge() {
  local repo=$1 id=$2
  git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 || return 0
  if [ "${OS_SYNC_ABORT_FAIL:-}" != "1" ] && git -C "$repo" merge --abort >/dev/null 2>&1; then
    sync_log "pull merge-abort ${id}"
    return 0
  fi
  return 1
}

sync_pull_ff() {
  local repo=$1
  local id=$2
  local tag old link_save err n branch rc
  if ! sync_abort_open_merge "$repo" "$id"; then
    sync_pull_stop "$id"
    sync_pull_fail "$id" "merge left open"
    return 1
  fi
  if ! sync_git "$repo" fetch --prune origin >/dev/null 2>&1; then
    sync_pull_fail "$id" "could not reach origin"
    return 1
  fi
  if ! git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null; then
    sync_pull_fail "$id" "no origin/main"
    return 1
  fi
  if v0logs_stuck "$repo" origin/main; then
    err=$(sync_mktemp)
    if ! SYNC_V0_SAVE=$(v0logs_park "$repo" sync_git 2>"$err"); then
      SYNC_V0_SAVE=""
      sync_pull_fail "$id" "v0 logs: $(head -n 1 "$err")"
      return 1
    fi
  fi
  sync_pull_leave_own_branch "$repo" "$id"
  branch=$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)
  case "$branch" in
    main) ;;
    upgrade/*)
      sync_pull_fail "$id" "upgrade not merged: ${branch}"
      return 1
      ;;
    *)
      sync_pull_fail "$id" "not on main"
      return 1
      ;;
  esac
  # The host rewrote its history (remove-leak): a fresh copy, unless work is not pushed.
  if ! git -C "$repo" merge-base --is-ancestor HEAD origin/main \
    && ! git -C "$repo" merge-base --is-ancestor origin/main HEAD; then
    tag=$(sync_rewrite_tag "$repo" "$id" || true)
    if [ -n "$tag" ]; then
      # A reclone keeps only changed files. Commits the host never had would be lost.
      n=$(sync_unpushed_count "$repo")
      if [ "$n" != "0" ]; then
        sync_pull_fail "$id" "unpushed: ${n}"
        return 1
      fi
      sync_reclone "$repo" "$id" "$tag"
      return $?
    fi
  fi
  # Both have commits the other lacks. A commit sync did not make, or a squash, is seen
  # from the commits alone, before any file here is touched: a stop changes nothing, and
  # the squash heal sets files aside only once main is in.
  if ! git -C "$repo" merge-base --is-ancestor HEAD origin/main \
    && ! git -C "$repo" merge-base --is-ancestor origin/main HEAD; then
    if [ "$id" != "workspace" ] && [ "$(sync_foreign_commits "$repo")" != "0" ]; then
      sync_pull_fail "$id" "foreign commit"
      return 1
    fi
    if sync_squashed "$repo"; then
      rc=0
      sync_after_squash "$repo" "$id" || rc=$?
      case "$rc" in
        0) sync_pull_fail "$id" "squash" ;;
        2) sync_pull_fail "$id" "squash: could not set a file aside" ;;
        *)
          sync_pull_stop "$id"
          sync_pull_fail "$id" "squash: could not take main"
          ;;
      esac
      return 1
    fi
  fi
  if ! sync_dirty_pass "$repo" "$id"; then
    sync_pull_fail "$id" "re-apply: could not set a file aside"
    return 1
  fi
  old=$(git -C "$repo" rev-parse HEAD)
  if git -C "$repo" merge-base --is-ancestor origin/main HEAD; then
    # Up to date. Local commits wait for their pull request.
    return 0
  fi
  if ! git -C "$repo" merge-base --is-ancestor HEAD origin/main; then
    if ! sync_merge_host "$repo" "$id"; then
      sync_pull_fail "$id" "not fast-forward"
      return 1
    fi
    sync_log "pull ok ${id} merged"
    return 0
  fi
  link_save=$(sync_stash_link_dirs "$repo")
  if ! git -C "$repo" merge --ff-only origin/main >/dev/null 2>&1; then
    git -C "$repo" checkout -q HEAD -- .agents/skills .claude/skills 2>/dev/null || true
    sync_put_back_stashed_links "$repo" "$link_save"
    rm -rf "$link_save"
    rm -f "${link_save}.has"
    sync_pull_fail "$id" "local changes"
    return 1
  fi
  if [ "$old" != "$(git -C "$repo" rev-parse HEAD)" ]; then
    sync_log "pull ok ${id}"
  fi
  if [ -f "${link_save}.has" ]; then
    sync_replace_plain_link_files "$repo"
  fi
  sync_finish_stashed_links "$repo" "$link_save"
  return 0
}

sync_each() {
  local fn=$1
  local me d name rc=0
  me=$(sync_me)
  if [ -e "$SYNC_ROOT/.git" ]; then
    "$fn" "$SYNC_ROOT" "root" || rc=1
  fi
  for d in "$SYNC_ROOT"/areas/*; do
    [ -d "$d" ] || continue
    [ -e "$d/.git" ] || continue
    name=$(basename "$d")
    "$fn" "$d" "area:${name}" || rc=1
  done
  if [ -n "$me" ] && [ -e "$SYNC_ROOT/users/$me/.git" ]; then
    "$fn" "$SYNC_ROOT/users/$me" "workspace" || rc=1
  fi
  return "$rc"
}

# Quick pull state lives in the root git dir, next to skills-copy/. Never committed.
# A write failure must not fail the pull. The token is a shell variable only.
sync_pull_clear_secret() {
  SYNC_PULL_TOKEN=""
  unset OS_GIT_TOKEN 2>/dev/null || true
  unset OS_GIT_USER 2>/dev/null || true
}

sync_pull_state_dir() {
  local gitdir
  [ -e "${SYNC_ROOT:-}/.git" ] || return 1
  gitdir=$(sync_copy_gitdir "$SYNC_ROOT") || return 1
  [ -n "$gitdir" ] || return 1
  printf '%s\n' "$gitdir/os-foundation"
}

sync_pull_state_path() {
  local dir
  dir=$(sync_pull_state_dir) || return 1
  printf '%s\n' "$dir/pull-state"
}

sync_pull_me_token() {
  local me
  me=$(sync_me)
  if [ -z "$me" ]; then
    printf '%s\n' "-"
    return 0
  fi
  printf '%s\n' "$me"
}

sync_pull_bot_token() {
  local me
  me=$(sync_me)
  if [ -n "$me" ] && [ -f "$SYNC_ROOT/bots/$me/BOT.md" ]; then
    printf '%s\n' "1"
    return 0
  fi
  printf '%s\n' "0"
}

sync_pull_me_ok() {
  local me=$1
  [ "$me" = "-" ] && return 0
  case "$me" in
    *[!A-Za-z0-9-]*) return 1 ;;
  esac
  [ -n "$me" ]
}

# Use the path sync_each passed. Do not resolve links: a linked area must stay areas/<name>.
sync_pull_rel() {
  local repo=$1
  if [ "$repo" = "$SYNC_ROOT" ]; then
    printf '%s\n' "."
    return 0
  fi
  case "$repo" in
    "$SYNC_ROOT"/*)
      printf '%s\n' "${repo#"$SYNC_ROOT"/}"
      ;;
    *)
      printf '%s\n' "$repo"
      ;;
  esac
}

sync_pull_rel_ok() {
  local rel=$1
  local name
  case "$rel" in
    .) return 0 ;;
    areas/*) name=${rel#areas/} ;;
    users/*) name=${rel#users/} ;;
    *) return 1 ;;
  esac
  [ -n "$name" ] || return 1
  case "$name" in
    *[!A-Za-z0-9._-]*|.*|*..*) return 1 ;;
  esac
  return 0
}

sync_pull_sha_ok() {
  local s=$1
  local n
  [ "$s" = "none" ] && return 0
  case "$s" in
    *[!0-9a-f]*) return 1 ;;
  esac
  n=${#s}
  [ "$n" -eq 40 ] || [ "$n" -eq 64 ]
}

sync_pull_has_origin() {
  git -C "$1" remote get-url origin >/dev/null 2>&1
}

sync_pull_origin_sha() {
  local repo=$1
  local sha
  if ! sync_pull_has_origin "$repo"; then
    printf '%s\n' "none"
    return 0
  fi
  sha=$(git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/main 2>/dev/null || true)
  if [ -z "$sha" ]; then
    printf '%s\n' "none"
    return 0
  fi
  printf '%s\n' "$sha"
}

sync_pull_repo() {
  local rel=$1
  case "$rel" in
    .) printf '%s\n' "$SYNC_ROOT" ;;
    areas/*|users/*) printf '%s\n' "$SYNC_ROOT/$rel" ;;
    *) return 1 ;;
  esac
}

sync_pull_id() {
  local rel=$1
  local name
  case "$rel" in
    .) printf '%s\n' "root" ;;
    areas/*)
      name=${rel#areas/}
      printf '%s\n' "area:${name}"
      ;;
    users/*) printf '%s\n' "workspace" ;;
    *) return 1 ;;
  esac
}

# One date call. OS_SYNC_CLOCK="<unix seconds> <seconds since local midnight>".
sync_pull_clock() {
  local raw now mid h m s
  if [ -n "${OS_SYNC_CLOCK:-}" ]; then
    raw=$OS_SYNC_CLOCK
    case "$raw" in
      *\ *) ;;
      *) return 1 ;;
    esac
    now=${raw%% *}
    mid=${raw#* }
    case "$mid" in
      *\ *) return 1 ;;
    esac
    case "$now" in
      *[!0-9]*|"") return 1 ;;
    esac
    case "$mid" in
      *[!0-9]*|"") return 1 ;;
    esac
    SYNC_CLOCK_NOW=$((10#$now))
    SYNC_CLOCK_MID=$((10#$mid))
    return 0
  fi
  raw=$(date '+%s %H %M %S')
  now=${raw%% *}
  raw=${raw#* }
  h=${raw%% *}
  raw=${raw#* }
  m=${raw%% *}
  s=${raw#* }
  case "$now$h$m$s" in
    *[!0-9]*) return 1 ;;
  esac
  SYNC_CLOCK_NOW=$((10#$now))
  SYNC_CLOCK_MID=$((10#$h * 3600 + 10#$m * 60 + 10#$s))
  return 0
}

# 0 when a full pull is due (full is before the most recent local 04:00).
sync_pull_full_due() {
  local since boundary
  sync_pull_clock || return 0
  case "${SYNC_PULL_FULL:-}" in
    ""|*[!0-9]*) return 0 ;;
  esac
  if [ "$SYNC_PULL_FULL" -gt "$((SYNC_CLOCK_NOW + 86400))" ]; then
    return 0
  fi
  since=$((SYNC_CLOCK_MID - 4 * 3600))
  since=$(((since % 86400 + 86400) % 86400))
  boundary=$((SYNC_CLOCK_NOW - since))
  [ "$SYNC_PULL_FULL" -lt "$boundary" ]
}

sync_pull_load_state() {
  local path line n=0 rest status sha rel
  path=$(sync_pull_state_path) || return 1
  [ -f "$path" ] || return 1
  [ -s "$path" ] || return 1
  SYNC_PULL_FULL=""
  SYNC_PULL_STATE_ME=""
  SYNC_PULL_STATE_BOT=""
  SYNC_PULL_SEEN="|"
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      *$'\r'*) return 1 ;;
    esac
    case "$n" in
      1)
        [ "$line" = "os-sync-state 1" ] || return 1
        ;;
      2)
        case "$line" in
          full\ [0-9]*) ;;
          *) return 1 ;;
        esac
        rest=${line#full }
        case "$rest" in
          *[!0-9]*) return 1 ;;
        esac
        SYNC_PULL_FULL=$rest
        ;;
      3)
        case "$line" in
          me\ *) ;;
          *) return 1 ;;
        esac
        rest=${line#me }
        sync_pull_me_ok "$rest" || return 1
        SYNC_PULL_STATE_ME=$rest
        ;;
      4)
        case "$line" in
          "bot 0"|"bot 1") ;;
          *) return 1 ;;
        esac
        SYNC_PULL_STATE_BOT=${line#bot }
        ;;
      *)
        case "$line" in
          repo\ ok\ *|repo\ retry\ *) ;;
          *) return 1 ;;
        esac
        rest=${line#repo }
        status=${rest%% *}
        rest=${rest#* }
        sha=${rest%% *}
        rel=${rest#* }
        [ "$line" = "repo $status $sha $rel" ] || return 1
        sync_pull_sha_ok "$sha" || return 1
        sync_pull_rel_ok "$rel" || return 1
        case "$SYNC_PULL_SEEN" in
          *"|$rel|"*) return 1 ;;
        esac
        SYNC_PULL_SEEN="${SYNC_PULL_SEEN}${rel}|"
        ;;
    esac
  done < "$path"
  [ "$n" -ge 4 ] || return 1
  [ -n "$SYNC_PULL_FULL" ] || return 1
  [ -n "$SYNC_PULL_STATE_ME" ] || return 1
  [ -n "$SYNC_PULL_STATE_BOT" ] || return 1
  return 0
}

sync_pull_line_for() {
  local rel=$1
  local path line rest status sha got
  path=$(sync_pull_state_path) || return 1
  [ -f "$path" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      repo\ ok\ *|repo\ retry\ *) ;;
      *) continue ;;
    esac
    rest=${line#repo }
    status=${rest%% *}
    rest=${rest#* }
    sha=${rest%% *}
    got=${rest#* }
    if [ "$got" = "$rel" ]; then
      printf '%s\n' "$line"
      return 0
    fi
  done < "$path"
  return 1
}

sync_pull_note_add() {
  SYNC_PULL_NOTES="${SYNC_PULL_NOTES:-}${1} ${2} ${3}"$'
'
}

sync_pull_note_get() {
  local rel=$1
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in
      "$rel "*)
        printf '%s\n' "${line#"$rel "}"
        return 0
        ;;
    esac
  done << EOF
${SYNC_PULL_NOTES:-}
EOF
  return 1
}

sync_pull_mark_changed() {
  SYNC_PULL_CHANGED="${SYNC_PULL_CHANGED:-}${1}"$'
'
}

sync_pull_mark_copyonly() {
  SYNC_PULL_COPYONLY="${SYNC_PULL_COPYONLY:-}|${1}|"
}

sync_pull_is_copyonly() {
  case "${SYNC_PULL_COPYONLY:-}" in
    *"|$1|"*) return 0 ;;
  esac
  return 1
}

sync_pull_token_begin() {
  local rc
  SYNC_PULL_ASK=$(sync_askpass) || return 1
  set +e
  SYNC_PULL_TOKEN=$(sync_token)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] || [ -z "${SYNC_PULL_TOKEN:-}" ]; then
    SYNC_PULL_TOKEN=""
    return 1
  fi
  SYNC_PULL_USER=$(sync_git_login)
  return 0
}

sync_pull_ls_remote() {
  local repo=$1
  (
    unset GIT_TRACE
    unset GIT_TRACE_CURL
    unset GIT_TRACE_PACKET
    unset GIT_CURL_VERBOSE
    unset GIT_TRACE_REDACT
    OS_GIT_USER="${SYNC_PULL_USER:-}" OS_GIT_TOKEN="${SYNC_PULL_TOKEN:-}" \
      GIT_ASKPASS="${SYNC_PULL_ASK:-}" GIT_TERMINAL_PROMPT=0 \
      git -C "$repo" -c credential.helper= -c commit.gpgsign=false \
      ls-remote origin refs/heads/main
  )
}

sync_pull_remote_sha() {
  local raw=$1
  local line sha
  line=${raw%%$'
'*}
  sha=${line%%$'	'*}
  sha=${sha%% *}
  sync_pull_sha_ok "$sha" || return 1
  [ "$sha" = "none" ] && return 1
  printf '%s\n' "$sha"
}

sync_pull_probe() {
  local repo=$1
  local rel line rest status sha remote rc got
  rel=$(sync_pull_rel "$repo")
  if ! sync_pull_rel_ok "$rel"; then
    SYNC_PULL_NEED_FULL=1
    return 0
  fi
  if ! sync_pull_has_origin "$repo"; then
    line=$(sync_pull_line_for "$rel" || true)
    if [ "$line" = "repo ok none $rel" ]; then
      return 0
    fi
    sync_pull_mark_changed "$rel"
    sync_pull_mark_copyonly "$rel"
    return 0
  fi
  line=$(sync_pull_line_for "$rel" || true)
  if [ -z "$line" ]; then
    sync_pull_mark_changed "$rel"
    return 0
  fi
  rest=${line#repo }
  status=${rest%% *}
  rest=${rest#* }
  sha=${rest%% *}
  if [ "$status" != "ok" ] || [ "$sha" = "none" ]; then
    sync_pull_mark_changed "$rel"
    return 0
  fi
  if [ "${SYNC_PULL_NO_TOKEN:-}" = "1" ]; then
    sync_pull_mark_changed "$rel"
    return 0
  fi
  set +e
  remote=$(sync_pull_ls_remote "$repo" 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] || [ -z "$remote" ]; then
    sync_pull_mark_changed "$rel"
    return 0
  fi
  got=$(sync_pull_remote_sha "$remote" || true)
  if [ -z "$got" ] || [ "$got" != "$sha" ]; then
    sync_pull_mark_changed "$rel"
    return 0
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$sha" HEAD >/dev/null 2>&1; then
    sync_pull_mark_changed "$rel"
  fi
  return 0
}

sync_pull_and_note() {
  local repo=$1
  local id=$2
  local rc=0
  local rel status sha
  rel=$(sync_pull_rel "$repo")
  sync_pull_one "$repo" "$id" || rc=$?
  if ! sync_pull_has_origin "$repo"; then
    sha=none
    if [ "$rc" -eq 0 ]; then
      status=ok
    else
      status=retry
    fi
  else
    sha=$(sync_pull_origin_sha "$repo")
    status=retry
    if [ "$rc" -eq 0 ] && [ "$sha" != "none" ]; then
      if git -C "$repo" merge-base --is-ancestor refs/remotes/origin/main HEAD >/dev/null 2>&1; then
        status=ok
      fi
    fi
  fi
  sync_pull_note_add "$rel" "$status" "$sha"
  return "$rc"
}

sync_pull_emit() {
  local repo=$1
  local rel note old status sha
  rel=$(sync_pull_rel "$repo")
  if ! sync_pull_rel_ok "$rel"; then
    SYNC_PULL_BODY_FAIL=1
    return 0
  fi
  note=$(sync_pull_note_get "$rel" || true)
  if [ -n "$note" ]; then
    status=${note%% *}
    sha=${note#* }
    SYNC_PULL_BODY="${SYNC_PULL_BODY}repo ${status} ${sha} ${rel}"$'
'
    return 0
  fi
  old=$(sync_pull_line_for "$rel" || true)
  if [ -n "$old" ]; then
    SYNC_PULL_BODY="${SYNC_PULL_BODY}${old}"$'
'
  fi
  return 0
}

sync_pull_write_state() {
  local kind=$1
  local dir path tmp full me bot
  dir=$(sync_pull_state_dir) || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  if ! sync_pull_clock; then
    SYNC_CLOCK_NOW=$(date '+%s')
  fi
  if [ "$kind" = "full" ]; then
    full=$SYNC_CLOCK_NOW
    me=$(sync_pull_me_token)
    bot=$(sync_pull_bot_token)
  else
    full=${SYNC_PULL_FULL:-}
    me=${SYNC_PULL_STATE_ME:-}
    bot=${SYNC_PULL_STATE_BOT:-}
  fi
  case "$full" in
    ""|*[!0-9]*) return 0 ;;
  esac
  sync_pull_me_ok "$me" || return 0
  case "$bot" in
    0|1) ;;
    *) return 0 ;;
  esac
  SYNC_PULL_BODY=""
  SYNC_PULL_BODY_FAIL=0
  sync_each sync_pull_emit || return 0
  if [ "$SYNC_PULL_BODY_FAIL" = "1" ]; then
    return 0
  fi
  path="$dir/pull-state"
  tmp="$dir/.pull-state.$$"
  if ! {
    printf '%s\n' "os-sync-state 1"
    printf '%s\n' "full $full"
    printf '%s\n' "me $me"
    printf '%s\n' "bot $bot"
    printf '%s' "$SYNC_PULL_BODY"
  } > "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  if ! mv "$tmp" "$path"; then
    rm -f "$tmp"
    return 0
  fi
  return 0
}

sync_pull_status_line() {
  local full utc
  if ! sync_pull_load_state; then
    printf '%s\n' "last full pull: never"
    return 0
  fi
  full=$SYNC_PULL_FULL
  if utc=$(date -u -r "$full" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
    printf 'last full pull: %s\n' "$utc"
    return 0
  fi
  if utc=$(date -u -d "@$full" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
    printf 'last full pull: %s\n' "$utc"
    return 0
  fi
  printf '%s\n' "last full pull: never"
}

sync_pull_run_full() {
  local rc=0
  SYNC_PULL_NOTES=""
  SYNC_PULL_DONE='|'
  sync_each sync_pull_and_note || rc=1
  sync_materialize_undone "$SYNC_ROOT"
  SYNC_PULL_DONE='|'
  sync_pull_write_state full || true
  return "$rc"
}

sync_pull_run_quick() {
  local rc=0
  local rel repo id
  SYNC_PULL_CHANGED=""
  SYNC_PULL_COPYONLY="|"
  SYNC_PULL_NOTES=""
  SYNC_PULL_NO_TOKEN=0
  SYNC_PULL_NEED_FULL=0
  if ! sync_pull_token_begin; then
    SYNC_PULL_NO_TOKEN=1
    sync_pull_clear_secret
  fi
  sync_each sync_pull_probe || rc=1
  sync_pull_clear_secret
  if [ "$SYNC_PULL_NEED_FULL" = "1" ]; then
    sync_pull_run_full || rc=$?
    return "$rc"
  fi
  if [ -z "$SYNC_PULL_CHANGED" ]; then
    return 0
  fi
  SYNC_PULL_DONE='|'
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    repo=$(sync_pull_repo "$rel") || continue
    id=$(sync_pull_id "$rel") || continue
    if sync_pull_is_copyonly "$rel"; then
      copy_rc=0
      sync_pull_refresh_one "$repo" || copy_rc=$?
      if [ "$copy_rc" -eq 0 ]; then
        sync_pull_note_add "$rel" "ok" "none"
      else
        rc=1
        sync_pull_note_add "$rel" "retry" "none"
      fi
      continue
    fi
    sync_pull_and_note "$repo" "$id" || rc=1
  done << EOF
$SYNC_PULL_CHANGED
EOF
  SYNC_PULL_DONE='|'
  sync_pull_write_state keep || true
  return "$rc"
}

cmd_pull() {
  local mode
  case "${1:-}" in
    "") mode=quick ;;
    --full) mode=full ;;
    *) sync_die 1 "unknown flag" ;;
  esac
  if [ -n "${2:-}" ]; then
    sync_die 1 "unknown flag"
  fi
  sync_lock
  local rc=0
  if [ "$mode" = "full" ] || ! sync_pull_load_state || sync_pull_full_due; then
    sync_pull_run_full || rc=$?
  else
    sync_pull_run_quick || rc=$?
  fi
  sync_unreached_flush
  [ "$rc" -ne 0 ] || sync_clear_error
  return "$rc"
}
