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

sync_link_copy() {
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
  if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
    if git -C "$repo" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      git -C "$repo" update-index --skip-worktree -- "$rel"
    fi
    sync_link_exclude_add "$repo" "$rel"
  fi
}

# refresh=1 recopies an existing folder. A plain file is always replaced.
sync_materialize_repo() {
  local repo=$1
  local refresh=${2:-0}
  local rel path target
  [ -d "$repo" ] || return 0
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
    target=$(sync_link_target "$repo" "$rel") || continue
    sync_link_copy "$repo" "$rel" "$target"
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
