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

# Fold clear local edits into skills/ before a refresh. A conflict leaves the copy alone.
# Returns 0 when the copy may be replaced, 2 when it must be kept.
sync_link_fold() {
  local repo=$1
  local rel=$2
  local target=$3
  local dest man copy_list f copy_hash man_hash skills_hash conflict=0
  dest="$repo/$rel"
  man=$(sync_copy_manifest_path "$repo" "$rel")
  if [ ! -f "$man" ]; then
    if [ -z "$(ls -A "$dest" 2>/dev/null || true)" ]; then
      return 0
    fi
    if ! diff -rq "$dest" "$target" >/dev/null 2>&1; then
      sync_copy_log "skills copy conflict ${rel}"
      return 2
    fi
    return 0
  fi
  copy_list=$(mktemp)
  sync_copy_list "$dest" "$copy_list"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    copy_hash=$(sync_copy_hash "$repo" "$dest/$f")
    man_hash=$(sync_manifest_hash "$man" "$f" || true)
    skills_hash=""
    if [ -f "$target/$f" ]; then
      skills_hash=$(sync_copy_hash "$repo" "$target/$f")
    fi
    if [ -z "$man_hash" ]; then
      if [ -z "$skills_hash" ]; then
        mkdir -p "$target/$(dirname "$f")"
        cp "$dest/$f" "$target/$f"
        sync_copy_log "skills copy folded ${rel}/${f}"
      elif [ "$skills_hash" != "$copy_hash" ]; then
        sync_copy_log "skills copy conflict ${rel}/${f}"
        conflict=1
      fi
      continue
    fi
    if [ "$copy_hash" = "$man_hash" ]; then
      continue
    fi
    if [ -n "$skills_hash" ] && [ "$skills_hash" = "$man_hash" ]; then
      mkdir -p "$target/$(dirname "$f")"
      cp "$dest/$f" "$target/$f"
      sync_copy_log "skills copy folded ${rel}/${f}"
      continue
    fi
    sync_copy_log "skills copy conflict ${rel}/${f}"
    conflict=1
  done < "$copy_list"
  rm -f "$copy_list"
  if [ "$conflict" -eq 1 ]; then
    return 2
  fi
  return 0
}

# refresh=1 recopies an existing folder. A plain file is always replaced.
# A copy with a conflict is left in place. Clear local edits are folded into skills/ first.
sync_materialize_repo() {
  local repo=$1
  local refresh=${2:-0}
  local rel path target hold
  [ -d "$repo" ] || return 0
  hold=$(mktemp)
  : > "$hold"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    path="$repo/$rel"
    if [ -L "$path" ] || [ ! -d "$path" ] || [ "$refresh" != "1" ]; then
      continue
    fi
    target=$(sync_link_target "$repo" "$rel") || continue
    if ! sync_link_fold "$repo" "$rel" "$target"; then
      printf '%s\n' "$rel" >> "$hold"
    fi
  done << EOF
$(sync_link_rels)
EOF
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    path="$repo/$rel"
    if [ -L "$path" ] || [ ! -e "$path" ]; then
      continue
    fi
    if [ -d "$path" ] && [ "$refresh" != "1" ]; then
      continue
    fi
    if [ ! -f "$path" ] && [ ! -d "$path" ]; then
      continue
    fi
    if grep -qxF "$rel" "$hold"; then
      continue
    fi
    target=$(sync_link_target "$repo" "$rel") || continue
    sync_link_replace "$repo" "$rel" "$target"
  done << EOF
$(sync_link_rels)
EOF
  rm -f "$hold"
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
  local old=$2
  local new refresh=0
  new=$(git -C "$repo" rev-parse HEAD)
  if [ "$old" != "$new" ]; then
    if git -C "$repo" diff --name-only "$old" "$new" | grep -q '^skills/'; then
      refresh=1
    fi
  fi
  sync_materialize_repo "$repo" "$refresh"
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
