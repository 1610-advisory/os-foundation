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
WORKSPACE_REASON="belongs in the workspace"

# Upgrade spill files are rules files. Held like AGENTS.md.
# Logs (root or area) and an area's drafts/ folder are area work, never "belongs in the
# workspace" (push-check.md rule 5, AGENTS.md section 6 Auto tier, start-core Phase E).
sync_not_workspace_only() {
  local kind=$1 path=$2
  case "$kind" in
    root|area) ;;
    *) return 1 ;;
  esac
  case "$path" in
    memory/logs/*) return 0 ;;
  esac
  if [ "$kind" = "area" ]; then
    case "$path" in
      drafts/*) return 0 ;;
    esac
  fi
  return 1
}

sync_hold_rules() {
  case "$(basename "$1")" in
    company-rules.md|area-rules.md) return 0 ;;
  esac
  sync_is_rules "$1"
}

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
  if [ ! -f "$repo/$path" ] || [ -L "$repo/$path" ]; then
    return 0
  fi
  if git -C "$repo" cat-file -e "origin/main:$path" >/dev/null 2>&1; then
    git -C "$repo" diff --no-color origin/main -- "$path" || true
    return 0
  fi
  git -C "$repo" diff --no-color --no-index -- /dev/null "$repo/$path" || true
}

sync_is_binary() {
  local path=$1
  local raw filtered
  [ -f "$path" ] || return 1
  [ -L "$path" ] && return 1
  raw=$(wc -c < "$path" | tr -d ' ')
  filtered=$(tr -d '\000' < "$path" | wc -c | tr -d ' ')
  [ "$raw" != "$filtered" ]
}

# Images under assets/ may go to the engine. Other binary files are held.
sync_binary_allowed() {
  local path=$1
  case "$path" in
    assets/*.png|assets/*.jpg|assets/*.jpeg|assets/*.gif|assets/*.webp) return 0 ;;
    */assets/*.png|*/assets/*.jpg|*/assets/*.jpeg|*/assets/*.gif|*/assets/*.webp) return 0 ;;
  esac
  return 1
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
  n=$(awk 'NF { c++ } END { print c + 0 }' "$out")
  [ "$n" = "1" ] || return 2
  line=$(awk 'NF { print; exit }' "$out")
  printf '%s' "$line" | jq -e '
    type == "object" and
    (.decision | type == "string") and
    (.decision == "commit" or .decision == "hold") and
    (.reason | type == "string") and
    (.message | type == "string")
  ' >/dev/null || return 2
  printf '%s\n' "$line"
}

sync_scan_files() {
  local list=$1
  local hits=$2
  local scanner path rc out err
  scanner="$SYNC_DIR/secret-scan.sh"
  : > "$hits"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -L "$path" ] || [ -d "$path" ]; then
      echo "symlink: add it by hand with a pull request" >&2
      return 2
    fi
    if [ ! -e "$path" ]; then
      continue
    fi
    if [ ! -f "$path" ]; then
      echo "symlink: add it by hand with a pull request" >&2
      return 2
    fi
    err=$(sync_mktemp)
    set +e
    out=$("$scanner" --files -- "$path" 2>"$err")
    rc=$?
    set -e
    case "$rc" in
      0) ;;
      1)
        if ! printf '%s\n' "$out" | grep -q ':[0-9][0-9]*:[A-Za-z0-9_-][A-Za-z0-9_-]*$'; then
          return 2
        fi
        printf '%s\n' "$out" >> "$hits"
        ;;
      *)
        return 2
        ;;
    esac
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

sync_apply_fail() {
  local repo=$1
  local tmp=$2
  local id=$3
  local why=$4
  if [ -n "$tmp" ]; then
    git -C "$repo" worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
  fi
  sync_log "push fail ${id} ${why}"
  return 1
}

# Called from 'if !', so set -e does not stop this function. Check every step.
sync_apply_commit() {
  local repo=$1
  local id=$2
  local kind=$3
  local files=$4
  local message=$5
  local me ref tmp author name email path n rc sha from to name_on_host number
  me=$(sync_me)
  n=$(wc -l < "$files" | tr -d ' ')
  [ "$n" -gt 0 ] || return 0
  author=$(sync_commit_author)
  name=$(printf '%s\n' "$author" | head -n 1)
  email=$(printf '%s\n' "$author" | tail -n 1)
  tmp=""
  sync_git "$repo" fetch origin >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_apply_fail "$repo" "" "$id" "could not reach origin"
    return 1
  fi
  tmp=$(mktemp -d)
  chmod 700 "$tmp"
  git -C "$repo" worktree add --detach "$tmp" origin/main >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_apply_fail "$repo" "$tmp" "$id" "worktree"
    return 1
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$repo/$path" ] && [ ! -L "$repo/$path" ]; then
      mkdir -p "$tmp/$(dirname "$path")"
      cp "$repo/$path" "$tmp/$path"
      rc=$?
      if [ "$rc" -ne 0 ]; then
        sync_apply_fail "$repo" "$tmp" "$id" "copy"
        return 1
      fi
    else
      rm -f "$tmp/$path"
    fi
  done < "$files"
  if [ -n "${SYNC_RENAMES:-}" ] && [ -f "$SYNC_RENAMES" ]; then
    while IFS=$(printf '\t') read -r from to; do
      [ -n "$to" ] || continue
      if grep -Fxq "$to" "$files"; then
        rm -f "$tmp/$from"
      fi
    done < "$SYNC_RENAMES"
  fi
  git -C "$tmp" add -A >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_apply_fail "$repo" "$tmp" "$id" "add"
    return 1
  fi
  sync_unstage_link_copies "$tmp"
  git -C "$tmp" -c user.name="$name" -c user.email="$email" -c commit.gpgsign=false \
    commit -F "$message" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_apply_fail "$repo" "$tmp" "$id" "commit"
    return 1
  fi
  if [ "$kind" = "workspace" ]; then
    sync_push_ref "$tmp" "refs/heads/main" 0 >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
      sync_apply_fail "$repo" "$tmp" "$id" "could not reach origin"
      return 1
    fi
    sha=$(git -C "$tmp" rev-parse HEAD)
    git -C "$repo" worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
    git -C "$repo" reset --mixed "$sha" >/dev/null 2>&1 || true
    return 0
  fi
  ref="refs/heads/sync/${me}"
  sync_push_ref "$tmp" "$ref" 1 >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_apply_fail "$repo" "$tmp" "$id" "could not reach origin"
    return 1
  fi
  git -C "$repo" worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
  tmp=""
  name_on_host=$(sync_remote_name "$repo") || {
    sync_log "push fail ${id} could not open a pull request"
    return 1
  }
  number=$(sync_open_pr "$name_on_host" "sync/${me}" "sync: ${me}" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    sync_log "push fail ${id} could not open a pull request"
    return 1
  fi
  "$HOST_SH" auto-merge "$name_on_host" "$number" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_held_error "auto-merge is off on ${name_on_host}: pull request ${number} is open but will not merge by itself. Ask the admin to run skills/_host/host.sh protect ${name_on_host} --code-owners --approvals 0"
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
  sync_materialize_repo "$repo"
  changed=$(sync_mktemp)
  SYNC_RENAMES=$(sync_mktemp)
  sync_changed_names "$repo" > "$changed" || true
  sync_rename_pairs "$repo" > "$SYNC_RENAMES" || true
  if git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    git -C "$repo" diff --name-only origin/main HEAD >> "$changed" || true
  fi
  sort -u "$changed" -o "$changed"
  sync_drop_link_copies "$repo" "$changed"
  if [ ! -s "$changed" ]; then
    return 0
  fi
  added=$(sync_mktemp)
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -L "$repo/$path" ] || [ -d "$repo/$path" ]; then
      : > "$added"
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        sync_hold_line "$id" "$path" "symlink: add it by hand with a pull request" >> "$added"
      done < "$changed"
      sync_held_replace "$id" "$added"
      sync_held_error "symlink: add it by hand with a pull request"
      sync_log "push fail ${id} symlink"
      return 1
    fi
  done < "$changed"
  # Paths from status are relative to the repo. Scan from the repo.
  hits=$(sync_mktemp)
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
    if [ "$kind" != "workspace" ] && sync_hold_rules "$path"; then
      sync_hold_line "$id" "$path" "$RULES_REASON" >> "$added"
      sync_log "push hold ${id} ${path} rules"
      continue
    fi
    if [ -f "$repo/$path" ] && sync_is_binary "$repo/$path" && ! sync_binary_allowed "$path"; then
      sync_hold_line "$id" "$path" "binary file: add it by hand with a pull request" >> "$added"
      sync_log "push hold ${id} ${path} binary"
      continue
    fi
    if [ -L "$repo/$path" ] || [ -d "$repo/$path" ]; then
      sync_hold_line "$id" "$path" "symlink: add it by hand with a pull request" >> "$added"
      sync_held_replace "$id" "$added"
      sync_held_error "symlink: add it by hand with a pull request"
      sync_log "push fail ${id} symlink"
      return 1
    fi
    if [ ! -e "$repo/$path" ]; then
      printf '%s\n' "$path" >> "$commit_files"
      printf '%s\n' "remove ${path}" >> "$messages"
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
    # push-check.md rule 5 is a path rule here: the model does not get to overrule it.
    if [ "$decision" = "hold" ] && [ "$reason" = "$WORKSPACE_REASON" ] && sync_not_workspace_only "$kind" "$path"; then
      decision=commit
      msg="Update ${path}"
      sync_log "push path-rule ${id} ${path} area work"
    fi
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
  # Keep an error an earlier repo set in this run.
  if [ -z "${SYNC_RUN_ERROR:-}" ]; then
    sync_held_error ""
  fi
  sync_log "push ok ${id}"
  if [ "$kind" != "workspace" ]; then
    sync_pull_one "$repo" "$id" || true
  fi
  return 0
}

# Bot runs already committed on sync/<bot>. Push those commits as they are.
# Do not commit again, and do not touch sync/<me>.
# The bot key is the boundary. This path does not check that me is the bot.
sync_bot_fail() {
  local id=$1 why=$2
  sync_log "push fail ${id} ${why}"
  printf '%s\n' "$why" >&2
  return 1
}

sync_bot_git() {
  local dir=$1 bot=$2 helper
  shift 2
  helper="${SYNC_ROOT}/skills/add-bot/git-credential-os-bot"
  if [ ! -x "$helper" ]; then
    return 1
  fi
  # Absolute helper path: git runs it directly. No token in an argument.
  env -u GIT_ASKPASS \
    OS_BOT="$bot" \
    OS_ROOT="${OS_ROOT:-$SYNC_ROOT}" \
    OS_PROFILE="${OS_PROFILE:-$SYNC_ROOT/company-profile.md}" \
    GIT_TERMINAL_PROMPT=0 \
    git -C "$dir" \
      -c credential.helper= \
      -c "credential.helper=${helper}" \
      -c commit.gpgsign=false \
      "$@"
}

# Slug is checked before this runs. The only refspec is sync/<bot>.
sync_bot_push_ref() {
  local dir=$1 bot=$2
  local ref="refs/heads/sync/${bot}"
  sync_bot_git "$dir" "$bot" push --force origin "${ref}:${ref}"
}

sync_bot_url_has_credential() {
  local url=$1
  case "$url" in
    *://*@*|*'token='*|*'password='*) return 0 ;;
  esac
  return 1
}

# Token stays in this function's output. The caller must not log it.
sync_bot_take_token() {
  local bot=$1 token err rc
  err=$(sync_mktemp)
  set +e
  token=$("$HOST_SH" get-token --bot "$bot" 2>"$err")
  rc=$?
  set -e
  rm -f "$err"
  if [ "$rc" -ne 0 ] || [ -z "$token" ]; then
    return 1
  fi
  token=$(printf '%s' "$token" | tr -d '\r\n')
  case "$token" in
    ""|*$'\n'*) return 1 ;;
  esac
  printf '%s' "$token"
}

# Set the host token only for this command. Not an argument, not a URL.
sync_bot_host() {
  local token=$1 host
  shift
  host=$(sync_profile host)
  case "$host" in
    github)
      GH_TOKEN="$token" "$@"
      ;;
    forgejo)
      FORGEJO_TOKEN="$token" "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

sync_bot_wait_merge() {
  local name=$1 number=$2 token=$3
  local limit i status merged rc
  limit=${OS_BOT_MERGE_WAIT:-180}
  case "$limit" in
    *[!0-9]*|"") return 1 ;;
  esac
  i=0
  while [ "$i" -lt "$limit" ]; do
    set +e
    status=$(sync_bot_host "$token" "$HOST_SH" pr-status "$name" "$number" 2>/dev/null)
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      merged=$(printf '%s' "$status" | jq -r '.merged // empty' 2>/dev/null || true)
      if [ "$merged" = "true" ]; then
        return 0
      fi
    fi
    i=$((i + 1))
    if [ "$i" -ge "$limit" ]; then
      break
    fi
    sleep 1
  done
  return 1
}

# origin/main..ref, or every commit on the branch when origin/main is missing.
sync_bot_range() {
  local repo=$1 ref=$2
  if git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    printf '%s\n' "origin/main..${ref}"
    return 0
  fi
  printf '%s\n' "$ref"
}

# Rules paths and secret blobs in the range. Return 1 before any push.
sync_bot_check_range() {
  local repo=$1 id=$2 ref=$3
  local range list line path sha kind dir n scanner rc blob
  range=$(sync_bot_range "$repo" "$ref")
  list=$(sync_mktemp)
  set +e
  git -C "$repo" log -z --name-only --no-renames --pretty=format: "$range" > "$list"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    sync_bot_fail "$id" "secret scan"
    return 1
  fi
  # -z keeps both sides of a rename and does not quote a path.
  while IFS= read -r -d '' path || [ -n "$path" ]; do
    [ -n "$path" ] || continue
    if sync_hold_rules "$path"; then
      sync_bot_fail "$id" "rules file: propose it with sync.sh propose"
      return 1
    fi
  done < "$list"
  scanner="$SYNC_DIR/secret-scan.sh"
  if [ ! -f "$scanner" ]; then
    sync_bot_fail "$id" "secret scan"
    return 1
  fi
  dir=$(mktemp -d)
  chmod 700 "$dir"
  n=0
  set +e
  git -C "$repo" rev-list --objects "$range" > "$list"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    rm -rf "$dir"
    sync_bot_fail "$id" "secret scan"
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *" "*)
        sha=${line%% *}
        ;;
      *)
        continue
        ;;
    esac
    kind=$(git -C "$repo" cat-file -t "$sha" 2>/dev/null || true)
    [ "$kind" = "blob" ] || continue
    n=$((n + 1))
    blob="$dir/blob-$n"
    if ! git -C "$repo" cat-file blob "$sha" > "$blob"; then
      rm -rf "$dir"
      sync_bot_fail "$id" "secret scan"
      return 1
    fi
    chmod 600 "$blob"
  done < "$list"
  if [ "$n" -eq 0 ]; then
    blob="$dir/blob-0"
    : > "$blob"
    chmod 600 "$blob"
  fi
  set +e
  # shellcheck disable=SC2086
  "$scanner" --files -- "$dir"/blob-* >/dev/null 2>"$dir/scan.err"
  rc=$?
  set -e
  rm -rf "$dir"
  if [ "$rc" -ne 0 ]; then
    sync_bot_fail "$id" "secret scan"
    return 1
  fi
  return 0
}

# Called from '||', so set -e does not stop this function. Check every step.
sync_bot_push_repo() {
  local repo=$1 id=$2 bot=$3 token=$4
  local ref rc name number out url
  ref="refs/heads/sync/${bot}"
  if ! git -C "$repo" show-ref --verify --quiet "$ref"; then
    return 0
  fi
  url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
  if [ -z "$url" ] || sync_bot_url_has_credential "$url"; then
    sync_log "push fail ${id} credential"
    printf '%s\n' "refusing a credential in the remote URL" >&2
    return 1
  fi
  sync_bot_git "$repo" "$bot" fetch origin >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_bot_fail "$id" "push"
    return 1
  fi
  if git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    if git -C "$repo" merge-base --is-ancestor "$ref" origin/main; then
      return 0
    fi
  fi
  if ! sync_bot_check_range "$repo" "$id" "$ref"; then
    return 1
  fi
  sync_bot_push_ref "$repo" "$bot" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_bot_fail "$id" "push"
    return 1
  fi
  name=$(sync_remote_name "$repo") || {
    sync_bot_fail "$id" "pull request"
    return 1
  }
  set +e
  out=$(sync_bot_host "$token" sync_open_pr "$name" "sync/${bot}" "sync: ${bot}")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    sync_bot_fail "$id" "pull request"
    return 1
  fi
  number=$(printf '%s' "$out" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    sync_bot_fail "$id" "pull request"
    return 1
  fi
  set +e
  sync_bot_host "$token" "$HOST_SH" auto-merge "$name" "$number" >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    sync_bot_fail "$id" "auto-merge"
    return 1
  fi
  if ! sync_bot_wait_merge "$name" "$number" "$token"; then
    sync_bot_fail "$id" "merge wait"
    return 1
  fi
  sync_log "push ok ${id}"
  return 0
}

sync_push_bot() {
  local bot rc=0 d id token host token_rc
  bot=${OS_BOT:-}
  if ! sync_safe_slug "$bot"; then
    sync_held_error "bot slug is not a plain name"
    sync_log "push fail bot slug"
    return 1
  fi
  if [ ! -f "$SYNC_ROOT/bots/${bot}/BOT.md" ]; then
    sync_held_error "bot page is missing"
    sync_log "push fail bot page"
    return 1
  fi
  [ -f "$HOST_SH" ] || sync_die 1 "host.sh is missing"
  if [ ! -x "${SYNC_ROOT}/skills/add-bot/git-credential-os-bot" ]; then
    sync_held_error "bot credential helper is missing"
    sync_log "push fail bot helper"
    return 1
  fi
  host=$(sync_profile host)
  case "$host" in
    github|forgejo) ;;
    *)
      sync_bot_fail "bot" "pull request"
      return 1
      ;;
  esac
  set +e
  token=$(sync_bot_take_token "$bot")
  token_rc=$?
  set -e
  if [ "$token_rc" -ne 0 ] || [ -z "$token" ]; then
    token=""
    sync_bot_fail "bot" "pull request"
    return 1
  fi
  if [ -e "$SYNC_ROOT/.git" ]; then
    sync_bot_push_repo "$SYNC_ROOT" "root" "$bot" "$token" || rc=1
  fi
  for d in "$SYNC_ROOT"/areas/*; do
    [ -d "$d" ] || continue
    [ -e "$d/.git" ] || continue
    id="area:$(basename "$d")"
    sync_bot_push_repo "$d" "$id" "$bot" "$token" || rc=1
  done
  token=""
  return "$rc"
}

cmd_push() {
  sync_lock
  if [ -n "${OS_BOT:-}" ]; then
    sync_push_bot || return 1
    return 0
  fi
  sync_identity || return 1
  [ -f "$HOST_SH" ] || sync_die 1 "host.sh is missing"
  local rc=0
  sync_each sync_push_one || rc=1
  return "$rc"
}

sync_propose_bad_path() {
  local path=$1
  local seg oldifs
  [ -n "$path" ] || return 0
  case "$path" in
    /*|..|../*|*/..|*/../*)
      return 0
      ;;
  esac
  case "$path" in
    *$'\n'*|*$'\t'*)
      return 0
      ;;
  esac
  oldifs=$IFS
  IFS=/
  # shellcheck disable=SC2086
  set -- $path
  IFS=$oldifs
  for seg in "$@"; do
    if [ -z "$seg" ] || [ "$seg" = ".." ]; then
      return 0
    fi
  done
  return 1
}

sync_propose_refuse_path() {
  local path=$1
  case "$path" in
    *$'\n'*|*$'\t'*)
      printf '%s\n' "propose refused: bad path" >&2
      ;;
    *)
      printf '%s\n' "propose refused: bad path: ${path}" >&2
      ;;
  esac
  exit 1
}

sync_under_dir() {
  local path=$1
  local root=$2
  local real rootreal
  real=$(sync_abs "$path")
  rootreal=$(sync_abs "$root")
  case "$real" in
    "$rootreal"|"$rootreal"/*) return 0 ;;
  esac
  return 1
}

sync_propose_main_symlink() {
  local root=$1
  local rel=$2
  local cur part oldifs
  cur=$root
  oldifs=$IFS
  set -f
  IFS=/
  # shellcheck disable=SC2086
  set -- $rel
  IFS=$oldifs
  set +f
  for part in "$@"; do
    [ -n "$part" ] || continue
    cur="$cur/$part"
    if [ -L "$cur" ]; then
      return 0
    fi
    if [ ! -e "$cur" ]; then
      return 1
    fi
  done
  return 1
}

sync_propose_symlink() {
  local root=$1
  local rel=$2
  local cur part oldifs
  if [ -L "$root/$rel" ]; then
    return 0
  fi
  cur=$root
  oldifs=$IFS
  set -f
  IFS=/
  # shellcheck disable=SC2086
  set -- $rel
  IFS=$oldifs
  set +f
  for part in "$@"; do
    [ -n "$part" ] || continue
    cur="$cur/$part"
    if [ -L "$cur" ]; then
      return 0
    fi
  done
  return 1
}

sync_propose_repo_ok() {
  local dir=$1
  local label=$2
  local top real
  if [ -L "$dir" ] || [ ! -d "$dir" ]; then
    sync_propose_fail "$label" "repo" 1
    return 1
  fi
  if [ -L "$dir/.git" ] || [ -f "$dir/.git" ] || [ ! -d "$dir/.git" ]; then
    sync_propose_fail "$label" "repo" 1
    return 1
  fi
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$top" ] || {
    sync_propose_fail "$label" "repo" 1
    return 1
  }
  real=$(sync_abs "$dir")
  top=$(sync_abs "$top")
  if [ "$top" != "$real" ]; then
    sync_propose_fail "$label" "repo" 1
    return 1
  fi
  return 0
}

sync_propose_note_tree() {
  local repo=$1
  local tmp=$2
  printf '%s\t%s\n' "$repo" "$tmp" >> "$SYNC_STATE/propose-trees"
}

sync_propose_drop_trees() {
  local line repo tmp
  [ -n "${SYNC_STATE:-}" ] || return 0
  [ -f "$SYNC_STATE/propose-trees" ] || return 0
  while IFS=$(printf '\t') read -r repo tmp; do
    [ -n "$tmp" ] || continue
    if [ -n "$repo" ] && [ -e "$repo/.git" ]; then
      git -C "$repo" worktree remove --force "$tmp" >/dev/null 2>&1 || true
    fi
    if [ -e "$tmp" ]; then
      rm -rf "$tmp"
    fi
  done < "$SYNC_STATE/propose-trees"
  rm -f "$SYNC_STATE/propose-trees"
}

sync_propose_print_opened() {
  local name number
  [ -n "${SYNC_STATE:-}" ] || return 0
  [ -f "$SYNC_STATE/propose-opened" ] || return 0
  while read -r name number; do
    [ -n "$name" ] || continue
    printf '%s\n' "opened: ${name} ${number}" >&2
  done < "$SYNC_STATE/propose-opened"
}

sync_propose_fail() {
  local repo=$1
  local step=$2
  local code=$3
  sync_log "propose fail ${repo}: ${step}"
  printf '%s\n' "propose fail ${repo}: ${step}" >&2
  sync_propose_print_opened
  return "$code"
}

# List lines are repo-relative path, tab, the path the person gave.
sync_propose_repo() {
  local repo=$1
  local topic=$2
  local me=$3
  local list=$4
  local rel userpath tmp name number rc author aname email msgfile dest
  name=$(sync_remote_name "$repo") || name=$repo
  tmp=$(mktemp -d)
  chmod 700 "$tmp"
  sync_propose_note_tree "$repo" "$tmp"
  if ! git -C "$repo" worktree add --detach "$tmp" origin/main >/dev/null 2>&1; then
    sync_propose_fail "$name" "worktree" 2
    return 2
  fi
  while IFS=$(printf '\t') read -r rel userpath; do
    [ -n "$rel" ] || continue
    dest="$tmp/$rel"
    if sync_propose_main_symlink "$tmp" "$rel"; then
      sync_propose_print_opened
      printf '%s\n' "propose refused: symlink on main: ${userpath}" >&2
      return 1
    fi
    mkdir -p "$(dirname "$dest")"
    if ! sync_under_dir "$(dirname "$dest")" "$tmp" && [ "$(dirname "$dest")" != "$tmp" ]; then
      sync_propose_fail "$name" "copy ${userpath}" 1
      return 1
    fi
    if ! cp "$SYNC_ROOT/$userpath" "$dest"; then
      sync_propose_fail "$name" "copy ${userpath}" 1
      return 1
    fi
    if ! sync_under_dir "$dest" "$tmp"; then
      sync_propose_fail "$name" "copy ${userpath}" 1
      return 1
    fi
    git -C "$tmp" add -- "$rel"
    if git -C "$tmp" diff --cached --quiet -- "$rel"; then
      sync_propose_print_opened
      sync_die 1 "nothing to propose: ${userpath}"
    fi
  done < "$list"
  author=$(sync_commit_author)
  aname=$(printf '%s\n' "$author" | head -n 1)
  email=$(printf '%s\n' "$author" | tail -n 1)
  msgfile=$(sync_mktemp)
  printf '%s\n' "propose ${topic}" > "$msgfile"
  if ! git -C "$tmp" -c user.name="$aname" -c user.email="$email" -c commit.gpgsign=false \
      commit -F "$msgfile" >/dev/null 2>&1; then
    sync_propose_fail "$name" "commit" 2
    return 2
  fi
  if ! sync_push_ref "$tmp" "refs/heads/rules/${me}/${topic}" 1; then
    sync_propose_fail "$name" "push" 2
    return 2
  fi
  number=$(sync_open_pr "$name" "rules/${me}/${topic}" "rules: ${topic}" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    sync_propose_fail "$name" "open-pr" 2
    return 2
  fi
  printf '%s %s\n' "$name" "$number" >> "$SYNC_STATE/propose-opened"
  if ! "$HOST_SH" auto-merge "$name" "$number" >/dev/null 2>&1; then
    sync_propose_fail "$name" "auto-merge" 2
    return 2
  fi
  sync_log "propose ok ${name} ${topic} ${number}"
  printf '%s\n' "$number"
}

sync_propose_check_file() {
  local repo=$1
  local rel=$2
  local userpath=$3
  local src
  src="$SYNC_ROOT/$userpath"
  if sync_propose_symlink "$repo" "$rel" || [ -L "$src" ]; then
    printf '%s\n' "propose refused: symlink: ${userpath}" >&2
    return 1
  fi
  if [ ! -f "$src" ]; then
    sync_die 1 "file not found: ${userpath}"
  fi
  if ! sync_under_dir "$src" "$repo"; then
    printf '%s\n' "propose refused: bad path: ${userpath}" >&2
    return 1
  fi
  return 0
}

cmd_propose() {
  local topic=$1
  shift
  local me path area rest company_list areas_list area_list scan_list args_file label rc
  sync_safe_slug "$topic" || sync_die 1 "topic is not a plain name"
  [ $# -ge 1 ] || sync_die 1 "propose needs at least one file"
  for path in "$@"; do
    path=${path#./}
    if sync_propose_bad_path "$path"; then
      sync_propose_refuse_path "$path"
    fi
  done
  sync_lock
  sync_identity || return 1
  me=$(sync_me)
  [ -f "$HOST_SH" ] || sync_die 1 "host.sh is missing"
  rm -f "$SYNC_STATE/propose-opened" "$SYNC_STATE/propose-trees"
  for path in "$@"; do
    path=${path#./}
    case "$path" in
      users|users/*)
        printf '%s\n' "propose refused: users paths stay in the workspace" >&2
        return 1
        ;;
    esac
  done
  company_list=$(sync_mktemp)
  areas_list=$(sync_mktemp)
  scan_list=$(sync_mktemp)
  args_file=$(sync_mktemp)
  : > "$company_list"
  : > "$areas_list"
  : > "$scan_list"
  : > "$args_file"
  for path in "$@"; do
    path=${path#./}
    printf '%s\n' "$path" >> "$args_file"
  done
  for path in "$@"; do
    path=${path#./}
    case "$path" in
      areas/*/*)
        area=${path#areas/}
        area=${area%%/*}
        printf '%s\n' "$area" >> "$areas_list"
        ;;
      areas|areas/*)
        sync_die 1 "nothing to propose: ${path}"
        ;;
      *)
        printf '%s\t%s\n' "$path" "$path" >> "$company_list"
        printf '%s\n' "$SYNC_ROOT/$path" >> "$scan_list"
        ;;
    esac
  done
  sort -u "$areas_list" -o "$areas_list"
  if [ -s "$company_list" ]; then
    label=$(sync_remote_name "$SYNC_ROOT" || true)
    [ -n "$label" ] || label=root
    sync_propose_repo_ok "$SYNC_ROOT" "$label" || return $?
    while IFS=$(printf '\t') read -r rest path; do
      sync_propose_check_file "$SYNC_ROOT" "$rest" "$path" || return 1
    done < "$company_list"
  fi
  while IFS= read -r area; do
    [ -n "$area" ] || continue
    label=$(sync_remote_name "$SYNC_ROOT/areas/$area" || true)
    [ -n "$label" ] || label=$area
    sync_propose_repo_ok "$SYNC_ROOT/areas/$area" "$label" || return $?
    for path in "$@"; do
      path=${path#./}
      case "$path" in
        areas/"$area"/*)
          rest=${path#areas/"$area"/}
          printf '%s\n' "$SYNC_ROOT/$path" >> "$scan_list"
          sync_propose_check_file "$SYNC_ROOT/areas/$area" "$rest" "$path" || return 1
          ;;
      esac
    done
  done < "$areas_list"
  set --
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    set -- "$@" "$path"
  done < "$scan_list"
  if [ $# -eq 0 ]; then
    sync_die 1 "propose needs at least one file"
  fi
  set +e
  "$SYNC_DIR/secret-scan.sh" --files -- "$@" >/dev/null
  rc=$?
  set -e
  if [ "$rc" -eq 1 ]; then
    sync_die 1 "propose refused: secret scan hit"
  fi
  if [ "$rc" -ne 0 ]; then
    sync_die 2 "propose refused: secret scan error"
  fi
  if [ -s "$company_list" ]; then
    label=$(sync_remote_name "$SYNC_ROOT" || true)
    [ -n "$label" ] || label=root
    if ! sync_git "$SYNC_ROOT" fetch origin >/dev/null 2>&1; then
      sync_propose_fail "$label" "fetch" 2
      return 2
    fi
  fi
  while IFS= read -r area; do
    [ -n "$area" ] || continue
    label=$(sync_remote_name "$SYNC_ROOT/areas/$area" || true)
    [ -n "$label" ] || label=$area
    if ! sync_git "$SYNC_ROOT/areas/$area" fetch origin >/dev/null 2>&1; then
      sync_propose_fail "$label" "fetch" 2
      return 2
    fi
  done < "$areas_list"
  if [ -s "$company_list" ]; then
    sync_propose_repo "$SYNC_ROOT" "$topic" "$me" "$company_list" || return $?
  fi
  while IFS= read -r area; do
    [ -n "$area" ] || continue
    area_list=$(sync_mktemp)
    : > "$area_list"
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      case "$path" in
        areas/"$area"/*)
          rest=${path#areas/"$area"/}
          printf '%s\t%s\n' "$rest" "$path" >> "$area_list"
          ;;
      esac
    done < "$args_file"
    sync_propose_repo "$SYNC_ROOT/areas/$area" "$topic" "$me" "$area_list" || return $?
  done < "$areas_list"
}
