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

sync_changed_names() {
  local repo=$1
  local line path
  while IFS= read -r -d '' line; do
    [ -n "$line" ] || continue
    path=${line:3}
    case "$path" in
      *" -> "*) path=${path##* -> } ;;
    esac
    case "$path" in
      *$'\n'*) continue ;;
    esac
    printf '%s\n' "$path"
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

sync_carry_nested() {
  local repo=$1
  local dest=$2
  local d
  for d in "$repo"/areas/* "$repo"/users/*; do
    [ -e "$d/.git" ] || continue
    mkdir -p "$dest/$(dirname "${d#"$repo/"}")"
    mv "$d" "$dest/${d#"$repo/"}"
  done
}

sync_reclone() {
  local repo=$1
  local id=$2
  local tag=$3
  local url parent new rules rule path scanner hit
  url=$(git -C "$repo" remote get-url origin)
  case "$url" in
    *://*@*) sync_die 1 "refusing a credential in the remote URL" ;;
  esac
  if [ "${OS_TEST_MODE:-}" = "1" ]; then
    sync_under_home "$repo" || sync_die 1 "refusing a path outside home"
  fi
  parent=$(dirname "$repo")
  new="$parent/.sync-reclone-$$"
  rm -rf "$new"
  if ! sync_git "$repo" clone -- "$url" "$new"; then
    sync_log "pull fail ${id} could not reach origin"
    return 1
  fi
  rules=$(sync_mktemp)
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
    mkdir -p "$new/$(dirname "$path")"
    cp "$repo/$path" "$new/$path"
  done < <(sync_changed_names "$repo")
  sync_carry_nested "$repo" "$new"
  local old="$parent/.sync-old-$$"
  mv "$repo" "$old"
  mv "$new" "$repo"
  rm -rf "$old"
  sync_record_rewrite "$id" "$tag"
  sync_log "pull reclone ${id} ${tag}"
}

sync_pull_one() {
  local repo=$1
  local id=$2
  local save tag
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
