#!/bin/bash
# Windows skill-link copies. Source this file. Do not run it.
# On Mac and Linux a real link is left alone.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh or join.sh."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh or join.sh." >&2
  exit 1
fi

sync_is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

sync_link_rels() {
  printf '%s\n' ".agents/skills" ".claude/skills"
}

sync_link_exclude_add() {
  local repo=$1
  local rel=$2
  local file line
  [ -d "$repo/.git" ] || return 0
  mkdir -p "$repo/.git/info"
  file="$repo/.git/info/exclude"
  line="/${rel}/"
  if [ -f "$file" ] && grep -qxF "$line" "$file"; then
    return 0
  fi
  printf '%s\n' "$line" >> "$file"
}

sync_link_target() {
  local repo=$1
  local rel=$2
  local parent
  parent=$(dirname "$rel")
  if ! (cd "$repo/$parent" && cd ../skills) >/dev/null 2>&1; then
    return 1
  fi
  (cd "$repo/$parent" && cd ../skills && pwd)
}

sync_copy_log() {
  if [ -z "${SYNC_LOG:-}" ]; then
    return 0
  fi
  if type sync_log >/dev/null 2>&1; then
    sync_log "$*"
    return 0
  fi
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$SYNC_LOG"
}

sync_copy_gitdir() {
  local repo=$1
  local gitdir
  gitdir=$(cd "$repo" && git rev-parse --git-dir)
  case "$gitdir" in
    /*|[A-Za-z]:*|[A-Za-z]:/*) ;;
    *) gitdir="$repo/$gitdir" ;;
  esac
  printf '%s\n' "$gitdir"
}

sync_copy_manifest_path() {
  local repo=$1
  local rel=$2
  local gitdir safe
  gitdir=$(sync_copy_gitdir "$repo")
  safe=$(printf '%s' "$rel" | tr '/' '_')
  printf '%s\n' "$gitdir/os-foundation/skills-copy/${safe}.manifest"
}

sync_copy_hash() {
  local repo=$1
  local file=$2
  git -C "$repo" hash-object -- "$file"
}

sync_copy_list() {
  local dir=$1
  local out=$2
  local f rel
  : > "$out"
  [ -d "$dir" ] || return 0
  find "$dir" -type f -print | sort | while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel=${f#"$dir"/}
    printf '%s\n' "$rel"
  done > "$out"
}

sync_copy_write_manifest() {
  local repo=$1
  local rel=$2
  local dest=$3
  local man list f hash
  man=$(sync_copy_manifest_path "$repo" "$rel")
  mkdir -p "$(dirname "$man")"
  list=$(mktemp)
  sync_copy_list "$dest" "$list"
  : > "$man"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    hash=$(sync_copy_hash "$repo" "$dest/$f")
    printf '%s\t%s\n' "$hash" "$f" >> "$man"
  done < "$list"
  rm -f "$list"
}

sync_manifest_hash() {
  local man=$1
  local rel=$2
  [ -f "$man" ] || return 1
  awk -F '\t' -v p="$rel" '$2 == p { print $1; exit }' "$man"
}

sync_link_replace() {
  local repo=$1
  local rel=$2
  local target=$3
  local dest
  dest="$repo/$rel"
  rm -rf "$dest"
  mkdir -p "$dest"
  if [ -n "$(ls -A "$target" 2>/dev/null || true)" ]; then
    cp -R "$target/." "$dest/"
  fi
  sync_copy_write_manifest "$repo" "$rel" "$dest"
  if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
    if git -C "$repo" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      git -C "$repo" update-index --skip-worktree -- "$rel"
    fi
    sync_link_exclude_add "$repo" "$rel"
  fi
}

sync_manifest_set() {
  local man=$1
  local rel=$2
  local hash=$3
  local tmp
  mkdir -p "$(dirname "$man")"
  tmp=$(mktemp)
  if [ -f "$man" ]; then
    awk -F '\t' -v p="$rel" '$2 != p { print }' "$man" > "$tmp"
  fi
  printf '%s\t%s\n' "$hash" "$rel" >> "$tmp"
  mv "$tmp" "$man"
}

sync_manifest_drop() {
  local man=$1
  local rel=$2
  local tmp
  [ -f "$man" ] || return 0
  tmp=$(mktemp)
  awk -F '\t' -v p="$rel" '$2 != p { print }' "$man" > "$tmp"
  mv "$tmp" "$man"
}

# One file. A conflict leaves that copy file. Every other file still refreshes.
sync_link_sync_file() {
  local repo=$1
  local rel=$2
  local target=$3
  local dest=$4
  local man=$5
  local f=$6
  local copy_hash="" skills_hash="" man_hash=""
  if [ -f "$dest/$f" ]; then
    copy_hash=$(sync_copy_hash "$repo" "$dest/$f")
  fi
  if [ -f "$target/$f" ]; then
    skills_hash=$(sync_copy_hash "$repo" "$target/$f")
  fi
  man_hash=$(sync_manifest_hash "$man" "$f" || true)
  if [ -n "$copy_hash" ] && [ -n "$skills_hash" ] && [ "$copy_hash" = "$skills_hash" ]; then
    sync_manifest_set "$man" "$f" "$copy_hash"
    return 0
  fi
  if [ -n "$copy_hash" ] && [ -z "$man_hash" ] && [ -z "$skills_hash" ]; then
    mkdir -p "$target/$(dirname "$f")"
    cp "$dest/$f" "$target/$f"
    sync_manifest_set "$man" "$f" "$copy_hash"
    sync_copy_log "skills copy folded ${rel}/${f}"
    return 0
  fi
  if [ -n "$copy_hash" ] && [ -n "$man_hash" ] && [ "$copy_hash" = "$man_hash" ]; then
    if [ -n "$skills_hash" ] && [ "$skills_hash" != "$man_hash" ]; then
      mkdir -p "$dest/$(dirname "$f")"
      cp "$target/$f" "$dest/$f"
      sync_manifest_set "$man" "$f" "$skills_hash"
    elif [ -z "$skills_hash" ]; then
      rm -f "$dest/$f"
      sync_manifest_drop "$man" "$f"
    fi
    return 0
  fi
  if [ -n "$copy_hash" ] && [ -n "$man_hash" ] && [ "$copy_hash" != "$man_hash" ]; then
    if [ -n "$skills_hash" ] && [ "$skills_hash" = "$man_hash" ]; then
      mkdir -p "$target/$(dirname "$f")"
      cp "$dest/$f" "$target/$f"
      sync_manifest_set "$man" "$f" "$copy_hash"
      sync_copy_log "skills copy folded ${rel}/${f}"
      return 0
    fi
    sync_copy_log "skills copy conflict ${rel}/${f}"
    return 0
  fi
  if [ -z "$copy_hash" ] && [ -n "$skills_hash" ] && [ -z "$man_hash" ]; then
    mkdir -p "$dest/$(dirname "$f")"
    cp "$target/$f" "$dest/$f"
    sync_manifest_set "$man" "$f" "$skills_hash"
    return 0
  fi
  if [ -z "$copy_hash" ] && [ -n "$man_hash" ]; then
    if [ -n "$skills_hash" ] && [ "$skills_hash" = "$man_hash" ]; then
      mkdir -p "$dest/$(dirname "$f")"
      cp "$target/$f" "$dest/$f"
      return 0
    fi
    if [ -n "$skills_hash" ]; then
      sync_copy_log "skills copy conflict ${rel}/${f}"
    else
      sync_manifest_drop "$man" "$f"
    fi
  fi
  return 0
}

sync_link_sync_files() {
  local repo=$1
  local rel=$2
  local target=$3
  local dest man names f
  dest="$repo/$rel"
  man=$(sync_copy_manifest_path "$repo" "$rel")
  mkdir -p "$(dirname "$man")"
  [ -f "$man" ] || : > "$man"
  names=$(mktemp)
  sync_copy_list "$dest" "$names"
  if [ -d "$target" ]; then
    find "$target" -type f -print | while IFS= read -r f; do
      [ -n "$f" ] || continue
      printf '%s\n' "${f#"$target"/}"
    done >> "$names"
  fi
  if [ -f "$man" ]; then
    awk -F '\t' 'NF >= 2 { print $2 }' "$man" >> "$names"
  fi
  sort -u "$names" -o "$names"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sync_link_sync_file "$repo" "$rel" "$target" "$dest" "$man" "$f"
  done < "$names"
  rm -f "$names"
  if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
    if git -C "$repo" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      git -C "$repo" update-index --skip-worktree -- "$rel"
    fi
    sync_link_exclude_add "$repo" "$rel"
  fi
}

# A real link is left alone. A plain file becomes a copy. A copy folder is
# folded and refreshed per file on every call, even when skills/ did not change.
sync_materialize_repo() {
  local repo=$1
  local rel path target
  [ -d "$repo" ] || return 0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    path="$repo/$rel"
    if [ -L "$path" ] || [ ! -e "$path" ]; then
      continue
    fi
    target=$(sync_link_target "$repo" "$rel") || continue
    if [ -f "$path" ]; then
      sync_link_replace "$repo" "$rel" "$target"
      continue
    fi
    if [ -d "$path" ]; then
      sync_link_sync_files "$repo" "$rel" "$target"
    fi
  done << EOF
$(sync_link_rels)
EOF
}

sync_materialize_links() {
  local root=$1
  local refresh=${2:-0}
  local area
  sync_materialize_repo "$root" "$refresh"
  if [ -d "$root/areas" ]; then
    for area in "$root"/areas/*; do
      [ -d "$area" ] || continue
      sync_materialize_repo "$area" "$refresh"
    done
  fi
}

sync_refresh_after_pull() {
  local repo=$1
  sync_materialize_repo "$repo"
}

# Upstream is about to replace a tracked copy folder with a link. Move untracked
# files aside and remove the folder so the fast-forward can write the link.
sync_stash_link_dirs() {
  local repo=$1
  local save rel path f relpath mode
  save=$(mktemp -d)
  chmod 700 "$save"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mode=$(git -C "$repo" ls-tree origin/main -- "$rel" 2>/dev/null | awk '{ print $1; exit }')
    [ "$mode" = "120000" ] || continue
    path="$repo/$rel"
    [ -d "$path" ] && [ ! -L "$path" ] || continue
    find "$path" -type f -print | while IFS= read -r f; do
      [ -n "$f" ] || continue
      relpath=${f#"$repo"/}
      if git -C "$repo" ls-files --error-unmatch -- "$relpath" >/dev/null 2>&1; then
        continue
      fi
      mkdir -p "$save/$(dirname "$relpath")"
      cp "$f" "$save/$relpath"
    done
    rm -rf "$path"
  done << EOF
$(sync_link_rels)
EOF
  printf '%s\n' "$save"
}

sync_put_back_stashed_links() {
  local repo=$1
  local save=$2
  local f rel
  [ -d "$save" ] || return 0
  find "$save" -type f -print | while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel=${f#"$save"/}
    mkdir -p "$repo/$(dirname "$rel")"
    cp "$f" "$repo/$rel"
  done
}

sync_finish_stashed_links() {
  local repo=$1
  local save=$2
  sync_put_back_stashed_links "$repo" "$save"
  sync_materialize_repo "$repo"
  rm -rf "$save"
}

# Drop a Windows copy from a path list. A real link stays in the list.
sync_drop_link_copies() {
  local repo=$1
  local list=$2
  local out path parent
  out=$(mktemp)
  chmod 600 "$out"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      .agents/skills|.claude/skills)
        if [ -e "$repo/$path" ] && [ ! -L "$repo/$path" ]; then
          continue
        fi
        ;;
      .agents/skills/*)
        parent="$repo/.agents/skills"
        if [ -d "$parent" ] && [ ! -L "$parent" ]; then
          continue
        fi
        ;;
      .claude/skills/*)
        parent="$repo/.claude/skills"
        if [ -d "$parent" ] && [ ! -L "$parent" ]; then
          continue
        fi
        ;;
    esac
    printf '%s\n' "$path" >> "$out"
  done < "$list"
  mv "$out" "$list"
}

sync_unstage_link_copies() {
  local repo=$1
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -L "$repo/$rel" ] || [ ! -e "$repo/$rel" ]; then
      continue
    fi
    if git -C "$repo" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      git -C "$repo" reset -q -- "$rel" || true
    fi
  done << EOF
$(sync_link_rels)
EOF
}
