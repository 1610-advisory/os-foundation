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

# Rename pairs: from<TAB>to. Push deletes from only when to is approved.
sync_rename_pairs() {
  local repo=$1
  local line xy path from
  while IFS= read -r -d '' line; do
    [ -n "$line" ] || continue
    xy=${line:0:2}
    path=${line:3}
    case "$xy" in
      R*|C*)
        IFS= read -r -d '' from || true
        printf '%s\t%s\n' "$from" "$path"
        ;;
    esac
  done < <(git -C "$repo" status --porcelain -z -uall)
}

sync_prepare_ff() {
  local repo=$1
  local incoming dirty path incfile save
  local blocked=0
  incoming=$(sync_mktemp)
  dirty=$(sync_mktemp)
  save=$(mktemp -d)
  chmod 700 "$save"
  git -C "$repo" diff --name-only HEAD origin/main > "$incoming" || true
  sync_changed_names "$repo" > "$dirty" || true
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! grep -Fxq "$path" "$incoming"; then
      continue
    fi
    incfile=$(sync_mktemp)
    if ! git -C "$repo" show "origin/main:$path" > "$incfile" 2>/dev/null; then
      blocked=1
      break
    fi
    if [ -f "$repo/$path" ] && cmp -s "$repo/$path" "$incfile"; then
      mkdir -p "$save/$(dirname "$path")"
      cp "$repo/$path" "$save/$path"
      continue
    fi
    blocked=1
    break
  done < "$dirty"
  if [ "$blocked" -eq 1 ]; then
    rm -rf "$save"
    return 1
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -f "$save/$path" ] || continue
    if git -C "$repo" ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
      git -C "$repo" checkout HEAD -- "$path"
    else
      rm -f "$repo/$path"
    fi
  done < "$dirty"
  printf '%s\n' "$save"
}

sync_restore_ff() {
  local repo=$1
  local save=$2
  local path
  [ -d "$save" ] || return 0
  find "$save" -type f | while IFS= read -r path; do
    rel=${path#"$save/"}
    mkdir -p "$repo/$(dirname "$rel")"
    cp "$path" "$repo/$rel"
  done
  rm -rf "$save"
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
  for d in "$repo"/areas/* "$repo"/users/*; do
    [ -e "$d/.git" ] || continue
    rel=${d#"$repo/"}
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
sync_rm_temp() {
  local tree=$1
  local id=$2
  local found
  if [ ! -e "$tree" ]; then
    return 0
  fi
  found=$(find "$tree" -name .git -print -prune 2>/dev/null | head -n 1 || true)
  if [ -n "$found" ]; then
    sync_log "pull fail ${id} reclone: left ${tree}"
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
    sync_rm_temp "$new.fail" "$id" || return 1
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
    sync_log "pull fail ${id} could not reach origin"
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
      areas/*|users/*) continue ;;
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
      sync_log "pull fail ${id} reclone: could not copy ${path}; nothing removed"
      sync_rm_temp "$new" "$id" || true
      return 1
    fi
    printf '%s\n' "$path" >> "$copied"
  done < <(sync_changed_names "$repo")
  if ! git -C "$new" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    sync_log "pull fail ${id} reclone: could not copy ${new}; nothing removed"
    sync_rm_temp "$new" "$id" || true
    return 1
  fi
  local old="$parent/.sync-old-$$"
  if ! mv "$repo" "$old"; then
    sync_log "pull fail ${id} reclone: could not copy ${repo}; nothing removed"
    sync_rm_temp "$new" "$id" || true
    return 1
  fi
  if ! mv "$new" "$repo"; then
    mv "$old" "$repo" || true
    sync_log "pull fail ${id} reclone: could not copy ${repo}; nothing removed"
    sync_rm_temp "$new" "$id" || true
    return 1
  fi
  if [ "${OS_SYNC_RECLONE_FAIL:-}" = "nested" ]; then
    sync_reclone_restore "$repo" "$old" "$new" "$id" || true
    sync_log "pull fail ${id} reclone"
    return 1
  fi
  if ! sync_move_nested "$old" "$repo"; then
    sync_reclone_restore "$repo" "$old" "$new" "$id" || true
    sync_log "pull fail ${id} reclone: could not copy areas; nothing removed"
    return 1
  fi
  if [ "${OS_SYNC_RECLONE_FAIL:-}" = "after-nested" ]; then
    OS_SYNC_MOVE_BACK_FAIL=1
    sync_reclone_restore "$repo" "$old" "$new" "$id" || true
    sync_log "pull fail ${id} reclone: could not copy areas; nothing removed"
    return 1
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! cmp -s "$old/$path" "$repo/$path"; then
      sync_reclone_restore "$repo" "$old" "$new" "$id" || true
      sync_log "pull fail ${id} reclone: could not copy ${path}; nothing removed"
      return 1
    fi
  done < "$copied"
  rm -rf "$old"
  sync_record_rewrite "$id" "$tag"
  sync_log "pull reclone ${id} ${tag}"
}

sync_pull_one() {
  local repo=$1
  local id=$2
  local save tag
  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  if ! sync_git "$repo" fetch origin >/dev/null 2>&1; then
    sync_log "pull fail ${id} could not reach origin"
    return 1
  fi
  if ! git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null; then
    sync_log "pull fail ${id} no origin/main"
    return 1
  fi
  if git -C "$repo" merge-base --is-ancestor HEAD origin/main; then
    save=$(sync_prepare_ff "$repo" || true)
    if [ -z "$save" ]; then
      sync_log "pull fail ${id} local changes"
      return 1
    fi
    if ! git -C "$repo" merge --ff-only origin/main >/dev/null 2>&1; then
      sync_restore_ff "$repo" "$save"
      sync_log "pull fail ${id} not fast-forward"
      return 1
    fi
    rm -rf "$save"
    return 0
  fi
  tag=$(sync_rewrite_tag "$repo" "$id" || true)
  if [ -n "$tag" ]; then
    sync_reclone "$repo" "$id" "$tag"
    return $?
  fi
  sync_log "pull fail ${id} not fast-forward"
  return 1
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

cmd_pull() {
  sync_lock
  local rc=0
  sync_each sync_pull_one || rc=1
  return "$rc"
}
