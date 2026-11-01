#!/bin/bash
# Re-apply holds: a file changed here and on the host before either side merged. Sourced
# by sync.sh. The agent does the merge by intent (re-apply.md); this only lists the three
# texts, clears a hold, and records a question for a person.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh." >&2
  exit 1
fi

# The folder for a held repo id: root, area:<name> or workspace.
sync_repo_dir() {
  local id=$1 me
  case "$id" in
    root) printf '%s\n' "$SYNC_ROOT" ;;
    area:*) printf '%s\n' "$SYNC_ROOT/areas/${id#area:}" ;;
    workspace)
      me=$(sync_me)
      printf '%s\n' "$SYNC_ROOT/users/${me}"
      ;;
    *) return 1 ;;
  esac
}

# The one re-apply hold for repo and path, as JSON, or nothing.
sync_reapply_hold() {
  jq -c --arg repo "$1" --arg path "$2" \
    '[.files[]? | select(.kind == "re-apply" and .repo == $repo and .path == $path)][0] // empty' "$SYNC_HELD"
}

sync_reapply_list() {
  local line id path dir mine basefile asked n=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    id=$(printf '%s' "$line" | jq -r '.repo')
    path=$(printf '%s' "$line" | jq -r '.path')
    mine=$(printf '%s' "$line" | jq -r '.mine')
    basefile=$(printf '%s' "$line" | jq -r '.basefile // "none"')
    asked=$(printf '%s' "$line" | jq -r '.question // ""')
    dir=$(sync_repo_dir "$id") || continue
    printf -- '- %s %s\n' "$id" "$path"
    if [ -e "$dir/$path" ]; then
      printf '  now: %s\n' "$dir/$path"
    else
      printf '%s\n' "  now: deleted on the host"
    fi
    if [ "$basefile" = "none" ]; then
      printf '%s\n' "  base: none (a new file)"
    else
      printf '  base: %s\n' "$basefile"
    fi
    if [ "$mine" = "deleted" ]; then
      printf '%s\n' "  mine: deleted here"
    else
      printf '  mine: %s\n' "$mine"
    fi
    if [ -n "$asked" ]; then
      printf '  asked: %s\n' "$asked"
    fi
  done < <(jq -c '.files[]? | select(.kind == "re-apply")' "$SYNC_HELD")
  if [ "$n" -eq 0 ]; then
    printf '%s\n' "nothing to re-apply"
  fi
}

# The change is applied (or the person said to drop it): forget the set-aside copy.
sync_reapply_done() {
  local id=$1 path=$2 line mine basefile tmp
  line=$(sync_reapply_hold "$id" "$path")
  [ -n "$line" ] || sync_die 1 "no re-apply hold for ${id} ${path}"
  mine=$(printf '%s' "$line" | jq -r '.mine')
  basefile=$(printf '%s' "$line" | jq -r '.basefile // "none"')
  [ "$mine" = "deleted" ] || rm -f "$mine"
  [ "$basefile" = "none" ] || rm -f "$basefile"
  tmp=$(sync_mktemp)
  jq --argjson f "$line" '.files = [.files[] | select(. != $f)]' "$SYNC_HELD" > "$tmp"
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
  sync_log "re-apply done ${id} ${path}"
  printf '%s\n' "done: ${id} ${path}"
}

# The change no longer makes sense on the new text. A person decides: one line in the
# person's own inbox, a comment on this computer's open pull request for that repo, and
# the line in the pull request body, which the nightly digest lists. The hold stays.
sync_reapply_ask() {
  local id=$1 path=$2 question=$3 line me seat inbox tmp dir name listing number body
  case "$question" in
    ''|*$'\n'*) sync_die 1 "the question is one line" ;;
  esac
  line=$(sync_reapply_hold "$id" "$path")
  [ -n "$line" ] || sync_die 1 "no re-apply hold for ${id} ${path}"
  me=$(sync_me)
  [ -n "$me" ] || sync_die 1 "identity mismatch: me is missing or not a slug"
  seat=$(sync_seat)
  tmp=$(sync_mktemp)
  jq --argjson f "$line" --arg q "$question" \
    '.files = [.files[] | if . == $f then .question = $q else . end]' "$SYNC_HELD" > "$tmp"
  mv "$tmp" "$SYNC_HELD"
  chmod 600 "$SYNC_HELD"
  if [ -d "$SYNC_ROOT/users/${me}" ]; then
    inbox="$SYNC_ROOT/users/${me}/inbox/re-apply.md"
    mkdir -p "$(dirname "$inbox")"
    printf -- '- %s %s %s: %s\n' "$(sync_today)" "$id" "$path" "$question" >> "$inbox"
  fi
  sync_log "re-apply ask ${id} ${path}"
  printf 'asked: %s %s\n' "$id" "$path"
  [ "$id" != "workspace" ] || return 0
  dir=$(sync_repo_dir "$id") || return 0
  name=$(sync_remote_name "$dir" 2>/dev/null) || return 0
  listing=$(sync_mktemp)
  "$HOST_SH" open-prs "$name" > "$listing" 2>/dev/null || return 0
  number=$(jq -r --arg head "sync/${me}/${seat}" '[.prs[]? | select(.head == $head) | .number][0] // empty' "$listing")
  [ -n "$number" ] || return 0
  body=$(sync_mktemp)
  printf 're-apply question: %s: %s\n' "$path" "$question" > "$body"
  if "$HOST_SH" pr-comment "$name" "$number" --body-file "$body" >/dev/null 2>&1; then
    printf 'commented: %s %s\n' "$name" "$number"
  fi
}

# The questions still open for one repo, as pull request body lines.
sync_reapply_questions() {
  jq -r --arg repo "$1" \
    '.files[]? | select(.kind == "re-apply" and .repo == $repo and (.question // "") != "") | "- re-apply question: \(.path): \(.question)"' \
    "$SYNC_HELD"
}

# join (B69): the person's version of one file from their old (v0) folder, and the text
# it was edited from (- for none, a new file; mine - for deleted). The agent re-applies it
# on the host's current text, as for any re-apply hold. Each version set aside is noted
# in state/join-brought, so a later join does not bring it again: "already" while its hold
# is open, "done" once the agent has re-applied it.
cmd_set_aside() {
  local id dir path mine basef base=none key ledger
  [ $# -eq 4 ] || sync_die 1 "usage: sync.sh set-aside <repo> <path> <mine-file|-> <base-file|->"
  id=$1 path=$2 mine=$3 basef=$4
  dir=$(sync_repo_dir "$id") || sync_die 1 "no repo ${id} here"
  [ -d "$dir/.git" ] || [ -f "$dir/.git" ] || sync_die 1 "no repo ${id} here"
  sync_lock
  key=deleted
  [ "$mine" = "-" ] || key=$(git hash-object -- "$mine") || sync_die 1 "could not read ${mine}"
  ledger="$SYNC_STATE/join-brought"
  if [ -f "$ledger" ] && grep -Fxq -- "${id}	${path}	${key}" "$ledger"; then
    if [ -n "$(sync_reapply_hold "$id" "$path")" ]; then
      printf '%s\n' "already"
    else
      printf '%s\n' "done"
    fi
    return 0
  fi
  if [ "$basef" != "-" ]; then
    base=$(git -C "$dir" hash-object -w -- "$basef") || sync_die 1 "could not keep the base text of ${path}"
  fi
  [ "$mine" != "-" ] || mine="${SYNC_RUN_TMP}/deleted"
  sync_set_aside "$dir" "$id" "$path" "$base" "held:${mine}" "re-apply: brought from the old folder by join" \
    || sync_die 1 "could not set ${path} aside"
  printf '%s\t%s\t%s\n' "$id" "$path" "$key" >> "$ledger"
  chmod 600 "$ledger"
  printf '%s\n' "set-aside"
}

cmd_reapply() {
  local sub=${1:-}
  [ $# -eq 0 ] || shift
  sync_held_prune
  case "$sub" in
    ''|list)
      [ $# -eq 0 ] || sync_die 1 "usage: sync.sh re-apply [list]"
      sync_reapply_list
      ;;
    done)
      [ $# -eq 2 ] || sync_die 1 "usage: sync.sh re-apply done <repo> <path>"
      sync_reapply_done "$1" "$2"
      ;;
    ask)
      [ $# -eq 3 ] || sync_die 1 "usage: sync.sh re-apply ask <repo> <path> <question>"
      sync_reapply_ask "$1" "$2" "$3"
      ;;
    *)
      sync_die 1 "usage: sync.sh re-apply [list|done|ask]"
      ;;
  esac
}
