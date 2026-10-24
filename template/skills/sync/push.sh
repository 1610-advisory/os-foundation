#!/bin/bash
# Push and propose. Sourced by sync.sh.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh." >&2
  exit 1
fi

RULES_REASON="rules file: propose it with sync.sh propose"

sync_engine_cmd() {
  local cmd
  if [ -n "${OS_SYNC_ENGINE:-}" ]; then
    printf '%s\n' "$OS_SYNC_ENGINE"
    return 0
  fi
  if [ -f "$SYNC_CONFIG/engine" ]; then
    cmd=$(tr -d '\r' < "$SYNC_CONFIG/engine" | head -n 1)
    if [ -n "$cmd" ]; then
      printf '%s\n' "$cmd"
      return 0
    fi
  fi
  cmd=$(sync_profile sync_engine)
  printf '%s\n' "$cmd"
}

sync_identity() {
  local me login github err rc
  me=$(sync_me)
  if ! sync_safe_slug "$me"; then
    sync_held_error "identity mismatch: me is missing or not a slug"
    sync_log "push fail identity me"
    return 1
  fi
  err=$(sync_mktemp)
  set +e
  login=$("$HOST_SH" whoami 2>"$err")
  rc=$?
  set -e
  if [ "$rc" -eq 4 ]; then
    sync_held_error "sign in again"
    sync_log "push fail identity sign-in"
    printf '%s\n' "sign in again" >&2
    return 1
  fi
  if [ "$rc" -eq 5 ]; then
    sync_held_error "offline"
    sync_log "push fail identity offline"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    sync_held_error "identity check failed"
    sync_log "push fail identity"
    return 1
  fi
  login=$(printf '%s' "$login" | jq -r '.login // empty')
  github=$(sync_people_field "$me" github || true)
  if [ -z "$github" ] || [ "$login" != "$github" ]; then
    sync_held_error "identity mismatch: signed in as ${login:-unknown}, people page for ${me} says ${github:-nobody}"
    sync_log "push fail identity mismatch"
    return 1
  fi
  # shellcheck disable=SC2034
  SYNC_LOGIN=$login
  return 0
}

sync_file_diff() {
  local repo=$1
  local path=$2
  if git -C "$repo" ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
    git -C "$repo" diff --no-color HEAD -- "$path" || true
  else
    git -C "$repo" diff --no-color --no-index -- /dev/null "$path" || true
  fi
}

sync_engine_one() {
  local kind=$1
  local path=$2
  local diff=$3
  local cmd prompt out err pid elapsed limit rc line n
  cmd=$(sync_engine_cmd)
  [ -n "$cmd" ] || return 3
  prompt=$(sync_mktemp)
  out=$(sync_mktemp)
  err=$(sync_mktemp)
  {
    cat "$SYNC_DIR/push-check.md"
    printf '\nREPO: %s\nFILE: %s\nDIFF:\n' "$kind" "$path"
    cat "$diff"
  } > "$prompt"
  limit=${OS_ENGINE_TIMEOUT:-120}
  # shellcheck disable=SC2086
  $cmd < "$prompt" > "$out" 2>"$err" &
  pid=$!
  elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$limit" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  set +e
  wait "$pid"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || return "$rc"
  n=$(grep -c '^{' "$out" || true)
  [ "$n" = "1" ] || return 2
  line=$(grep '^{' "$out")
  printf '%s' "$line" | jq -e '(.decision == "commit" or .decision == "hold") and (.reason | type == "string")' >/dev/null
  printf '%s\n' "$line"
}

sync_scan_files() {
  local list=$1
  local hits=$2
  local scanner path
  scanner="$SYNC_DIR/secret-scan.sh"
  : > "$hits"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -f "$path" ] || continue
    set +e
    "$scanner" --files "$path" >> "$hits"
    rc=$?
    set -e
    if [ "$rc" -eq 2 ]; then
      return 2
    fi
  done < "$list"
  if [ -s "$hits" ]; then
    return 1
  fi
  return 0
}

sync_push_ref() {
  local dir=$1
  local ref=$2
  local force=$3
  local me
  me=$(sync_me)
  case "$ref" in
    "refs/heads/sync/${me}"|"refs/heads/rules/${me}/"*)
      ;;
    refs/heads/main)
      if [ "$force" = "1" ]; then
        sync_die 1 "refusing to force-push main"
      fi
      ;;
    *)
      sync_die 1 "refusing to push that branch"
      ;;
  esac
  if [ "$force" = "1" ]; then
    sync_git "$dir" push --force origin "HEAD:${ref}"
  else
    sync_git "$dir" push origin "HEAD:${ref}"
  fi
}

sync_open_pr() {
  local name=$1
  local head=$2
  local title=$3
  local tries=5 rc out err
  err=$(sync_mktemp)
  while [ "$tries" -gt 0 ]; do
    set +e
    out=$("$HOST_SH" open-pr "$name" --head "$head" --base main --title "$title" 2>"$err")
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      printf '%s\n' "$out"
      return 0
    fi
    if [ "$rc" -ne 2 ]; then
      return "$rc"
    fi
    tries=$((tries - 1))
    sleep 1
  done
  return 2
}

sync_commit_author() {
  local me name email
  me=$(sync_me)
  name=$(git -C "$SYNC_ROOT" config user.name || true)
  email=$(git -C "$SYNC_ROOT" config user.email || true)
  if [ -z "$name" ]; then
    name=$me
  fi
  if [ -z "$email" ]; then
    email=$(sync_people_field "$me" email || true)
  fi
  if [ -z "$email" ]; then
    email="${me}@invalid"
  fi
  printf '%s\n%s\n' "$name" "$email"
}

sync_apply_commit() {
  local repo=$1
  local id=$2
  local kind=$3
  local files=$4
  local message=$5
  local me ref tmp author name email path n
  me=$(sync_me)
  n=$(wc -l < "$files" | tr -d ' ')
  [ "$n" -gt 0 ] || return 0
  author=$(sync_commit_author)
  name=$(printf '%s\n' "$author" | head -n 1)
  email=$(printf '%s\n' "$author" | tail -n 1)
  if [ "$kind" = "workspace" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -f "$repo/$path" ]; then
        git -C "$repo" add -- "$path"
      else
        git -C "$repo" rm --cached -- "$path" >/dev/null 2>&1 || git -C "$repo" add -u -- "$path"
      fi
    done < "$files"
    git -C "$repo" -c user.name="$name" -c user.email="$email" -c commit.gpgsign=false \
      commit -F "$message" >/dev/null
    sync_push_ref "$repo" "refs/heads/main" 0
    return 0
  fi
  if ! sync_git "$repo" fetch origin >/dev/null 2>&1; then
    sync_log "push fail ${id} could not reach origin"
    return 1
  fi
  tmp=$(mktemp -d)
  chmod 700 "$tmp"
  git -C "$repo" worktree add --detach "$tmp" origin/main >/dev/null
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$repo/$path" ]; then
      mkdir -p "$tmp/$(dirname "$path")"
      cp "$repo/$path" "$tmp/$path"
    else
      rm -f "$tmp/$path"
    fi
  done < "$files"
  git -C "$tmp" add -A
  git -C "$tmp" -c user.name="$name" -c user.email="$email" -c commit.gpgsign=false \
    commit -F "$message" >/dev/null
  ref="refs/heads/sync/${me}"
  if ! sync_push_ref "$tmp" "$ref" 1; then
    git -C "$repo" worktree remove --force "$tmp" >/dev/null 2>&1 || true
    sync_log "push fail ${id} could not reach origin"
    return 1
  fi
  git -C "$repo" worktree remove --force "$tmp" >/dev/null 2>&1 || true
  local name_on_host number
  name_on_host=$(sync_remote_name "$repo") || return 1
  number=$(sync_open_pr "$name_on_host" "sync/${me}" "sync: ${me}" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    sync_log "push fail ${id} could not open a pull request"
    return 1
  fi
  if ! "$HOST_SH" auto-merge "$name_on_host" "$number" >/dev/null; then
    sync_log "push fail ${id} auto-merge"
    return 1
  fi
  return 0
}

sync_push_one() {
  local repo=$1
  local id=$2
  local kind
  local changed hits path rule reason added commit_files messages diff eng decision msg
  local scan_rc
  case "$id" in
    root) kind=root ;;
    area:*) kind=area ;;
    workspace) kind=workspace ;;
    *) kind=root ;;
  esac
  changed=$(sync_mktemp)
  (
    cd "$repo" && sync_changed_names "$repo"
  ) > "$changed" || true
  if [ ! -s "$changed" ]; then
    return 0
  fi
  # Paths from status are relative to the repo. Scan from the repo.
  hits=$(sync_mktemp)
  added=$(sync_mktemp)
  commit_files=$(sync_mktemp)
  messages=$(sync_mktemp)
  : > "$added"
  set +e
  (
    cd "$repo"
    sync_scan_files "$changed" "$hits"
  )
  scan_rc=$?
  set -e
  if [ "$scan_rc" -eq 2 ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      sync_hold_line "$id" "$path" "secret scan error" >> "$added"
    done < "$changed"
    sync_held_replace "$id" "$added"
    sync_held_error "secret scan error"
    sync_log "push fail ${id} secret scan error"
    return 1
  fi
  # Secret hits hold that file only.
  if [ -s "$hits" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      rule=$(awk -F: -v p="$path" 'index($0, p ":") == 1 { print $NF; exit }' "$hits")
      if [ -n "$rule" ]; then
        sync_hold_line "$id" "$path" "secret: ${rule}" >> "$added"
        sync_log "push hold ${id} ${path} secret"
      fi
    done < "$changed"
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if awk -F: -v p="$path" 'index($0, p ":") == 1 { found=1 } END { exit !found }' "$hits"; then
      continue
    fi
    if [ "$kind" != "workspace" ] && sync_is_rules "$path"; then
      sync_hold_line "$id" "$path" "$RULES_REASON" >> "$added"
      sync_log "push hold ${id} ${path} rules"
      continue
    fi
    diff=$(sync_mktemp)
    (cd "$repo" && sync_file_diff "$repo" "$path") > "$diff" || true
    set +e
    eng=$(sync_engine_one "$kind" "$path" "$diff")
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      : > "$added"
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        sync_hold_line "$id" "$path" "engine check failed" >> "$added"
      done < "$changed"
      sync_held_replace "$id" "$added"
      sync_held_error "engine check failed"
      sync_log "push fail ${id} engine check failed"
      return 1
    fi
    decision=$(printf '%s' "$eng" | jq -r '.decision')
    reason=$(printf '%s' "$eng" | jq -r '.reason')
    msg=$(printf '%s' "$eng" | jq -r '.message')
    if [ "$decision" = "hold" ]; then
      sync_hold_line "$id" "$path" "$reason" >> "$added"
      sync_log "push hold ${id} ${path} engine"
      continue
    fi
    printf '%s\n' "$path" >> "$commit_files"
    printf '%s\n' "$msg" >> "$messages"
  done < "$changed"
  sync_held_replace "$id" "$added"
  if [ ! -s "$commit_files" ]; then
    return 0
  fi
  msgfile=$(sync_mktemp)
  head -n 1 "$messages" | cut -c 1-72 > "$msgfile"
  if ! sync_apply_commit "$repo" "$id" "$kind" "$commit_files" "$msgfile"; then
    return 1
  fi
  sync_held_error ""
  sync_log "push ok ${id}"
  if [ "$kind" != "workspace" ]; then
    sync_pull_one "$repo" "$id" || true
  fi
  return 0
}

cmd_push() {
  sync_lock
  sync_identity || return 1
  [ -f "$HOST_SH" ] || sync_die 1 "host.sh is missing"
  local rc=0
  sync_each sync_push_one || rc=1
  return "$rc"
}

cmd_propose() {
  local topic=$1
  shift
  local me files path name number tmp author aname email msgfile
  sync_lock
  sync_identity || return 1
  sync_safe_slug "$topic" || sync_die 1 "topic is not a plain name"
  me=$(sync_me)
  [ $# -ge 1 ] || sync_die 1 "propose needs at least one file"
  files=$(sync_mktemp)
  for path in "$@"; do
    [ -f "$SYNC_ROOT/$path" ] || sync_die 1 "file not found: ${path}"
    printf '%s\n' "$path" >> "$files"
  done
  set +e
  set --
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    set -- "$@" "$path"
  done < "$files"
  (cd "$SYNC_ROOT" && "$SYNC_DIR/secret-scan.sh" --files "$@") >/dev/null
  rc=$?
  set -e
  if [ "$rc" -eq 1 ]; then
    sync_die 1 "propose refused: secret scan hit"
  fi
  if [ "$rc" -ne 0 ]; then
    sync_die 2 "propose refused: secret scan error"
  fi
  if ! sync_git "$SYNC_ROOT" fetch origin >/dev/null 2>&1; then
    sync_log "propose fail could not reach origin"
    return 2
  fi
  tmp=$(mktemp -d)
  chmod 700 "$tmp"
  git -C "$SYNC_ROOT" worktree add --detach "$tmp" origin/main >/dev/null
  while IFS= read -r path; do
    mkdir -p "$tmp/$(dirname "$path")"
    cp "$SYNC_ROOT/$path" "$tmp/$path"
  done < "$files"
  git -C "$tmp" add -A
  author=$(sync_commit_author)
  aname=$(printf '%s\n' "$author" | head -n 1)
  email=$(printf '%s\n' "$author" | tail -n 1)
  msgfile=$(sync_mktemp)
  printf '%s\n' "propose ${topic}" > "$msgfile"
  git -C "$tmp" -c user.name="$aname" -c user.email="$email" -c commit.gpgsign=false \
    commit -F "$msgfile" >/dev/null
  if ! sync_push_ref "$tmp" "refs/heads/rules/${me}/${topic}" 1; then
    git -C "$SYNC_ROOT" worktree remove --force "$tmp" >/dev/null 2>&1 || true
    sync_log "propose fail could not reach origin"
    return 2
  fi
  git -C "$SYNC_ROOT" worktree remove --force "$tmp" >/dev/null 2>&1 || true
  name=$(sync_remote_name "$SYNC_ROOT") || return 2
  number=$(sync_open_pr "$name" "rules/${me}/${topic}" "rules: ${topic}" | jq -r '.number // empty')
  [ -n "$number" ] || {
    sync_log "propose fail could not open a pull request"
    return 2
  }
  "$HOST_SH" auto-merge "$name" "$number" >/dev/null || true
  sync_log "propose ok ${topic} ${number}"
  printf '%s\n' "$number"
}
