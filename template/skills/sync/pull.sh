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
  # Skip the clone's own top-level .git. A nested repo is deeper.
  found=$(find "$tree" -mindepth 2 -name .git -print -prune 2>/dev/null | head -n 1 || true)
  if [ -n "$found" ]; then
    sync_log "pull fail ${id} reclone: left ${tree}"
    sync_held_error "reclone left ${tree}"
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

sync_pull_fetched() {
  local repo=$1
  local id=$2
  local save tag old link_save
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
    old=$(git -C "$repo" rev-parse HEAD)
    link_save=$(sync_stash_link_dirs "$repo")
    if ! git -C "$repo" merge --ff-only origin/main >/dev/null 2>&1; then
      sync_restore_ff "$repo" "$save"
      git -C "$repo" checkout -q HEAD -- .agents/skills .claude/skills 2>/dev/null || true
      sync_put_back_stashed_links "$repo" "$link_save"
      rm -rf "$link_save"
      rm -f "${link_save}.has"
      sync_log "pull fail ${id} not fast-forward"
      return 1
    fi
    rm -rf "$save"
    if [ "$old" != "$(git -C "$repo" rev-parse HEAD)" ]; then
      sync_log "pull ok ${id}"
    fi
    if [ -f "${link_save}.has" ]; then
      sync_replace_plain_link_files "$repo"
    fi
    sync_finish_stashed_links "$repo" "$link_save"
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
  SYNC_PULL_ASK=$(mktemp) || return 1
  chmod 700 "$SYNC_PULL_ASK" || return 1
  SYNC_TMP_FILES="${SYNC_TMP_FILES} ${SYNC_PULL_ASK}"
  cat > "$SYNC_PULL_ASK" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
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
  return "$rc"
}
