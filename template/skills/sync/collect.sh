#!/bin/bash
# Traces collector. Sourced by sync.sh.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from sync.sh."
    exit 0
  fi
  printf '%s\n' "Source this file from sync.sh." >&2
  exit 1
fi

sync_switches_have() {
  local want=$1
  local item
  while IFS= read -r item; do
    [ "$item" = "$want" ] && return 0
  done < <(sync_profile switches)
  return 1
}

sync_is_subagent() {
  local f=$1
  local dir base parent
  dir=$(dirname "$f")
  while [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    base=$(basename "$dir")
    parent=$(dirname "$dir")
    if [ -f "$parent/${base}.jsonl" ]; then
      return 0
    fi
    dir=$parent
  done
  return 1
}

sync_session_files() {
  local primary=$1
  local dir base
  printf '%s\n' "$primary"
  dir=$(dirname "$primary")
  base=$(basename "$primary" .jsonl)
  if [ -d "$dir/$base" ]; then
    find "$dir/$base" -name '*.jsonl' -type f
  fi
}

sync_extract() {
  local file=$1
  local kind=$2
  jq -r --arg kind "$kind" '
    def cwd:
      .cwd // empty,
      (select(.type == "session") | .cwd // empty);
    def toolpath:
      (.message.content[]? | .input.file_path // empty),
      (.message.content[]? | .input.path // empty),
      (.message.content[]? | select(.type == "toolCall") | .arguments.path // empty),
      (.message.content[]? | select(.type == "toolCall") | .arguments.file_path // empty);
    def command:
      (.message.content[]? | select(.type == "tool_use" or .type == "toolCall") | .input.command // .arguments.command // empty);
    if $kind == "cwd" then cwd
    elif $kind == "path" then toolpath
    else command
    end
  ' "$file" 2>/dev/null || true
}

sync_abs_path() {
  local path=$1
  local cwd=$2
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *)
      if [ -n "$cwd" ]; then
        printf '%s\n' "${cwd%/}/$path"
      fi
      ;;
  esac
}

sync_scrub_file() {
  local in=$1
  local out=$2
  local a b c d e
  # Prefixes are split so the source file does not contain a live prefix.
  a=$(printf '%s%s_' gh p)
  b=$(printf '%s%s_' github_ pat)
  c=$(printf '%s%s' xo x)
  d=$(printf '%s%s' AK IA)
  e=$(printf '%s%s' '-----BE' 'GIN')
  sed -E \
    -e "s/${a}[A-Za-z0-9]{36}/[redacted]/g" \
    -e "s/${b}[A-Za-z0-9_]{22,}/[redacted]/g" \
    -e "s/${c}[baprs]-[A-Za-z0-9-]{10,}/[redacted]/g" \
    -e "s/${d}[0-9A-Z]{16}/[redacted]/g" \
    -e "s/${e} [A-Z ]*PRIVATE KEY-----/[redacted]/g" \
    "$in" > "$out"
}

sync_post_trace() {
  local file=$1
  local url cfg tok
  url=${OS_TRACES_UPLOAD_URL:-}
  [ -n "$url" ] || return 0
  case "$url" in
    *$'\n'*) return 1 ;;
  esac
  cfg=$(sync_mktemp)
  {
    printf '%s\n' 'silent' 'show-error' 'max-time = 60'
    printf 'url = "%s"\n' "$url"
    printf '%s\n' 'request = "POST"' 'header = "Content-Type: application/x-ndjson"'
    printf 'upload-file = "%s"\n' "$file"
    if [ -n "${OS_TRACES_UPLOAD_TOKEN_FILE:-}" ] && [ -f "$OS_TRACES_UPLOAD_TOKEN_FILE" ]; then
      tok=$(tr -d '\r\n' < "$OS_TRACES_UPLOAD_TOKEN_FILE")
      printf 'header = "Authorization: Bearer %s"\n' "$tok"
      tok=""
    fi
  } > "$cfg"
  curl --config "$cfg"
}

cmd_collect() {
  local level root target
  sync_lock
  level=$(sync_level)
  if [ "$level" != "app" ] || ! sync_switches_have traces; then
    sync_log "collect off"
    return 0
  fi
  target=${OS_TRACES_TARGET:-}
  [ -n "$target" ] || sync_die 1 "OS_TRACES_TARGET is not set"
  mkdir -p "$target"
  root=$(sync_abs "$SYNC_ROOT")
  local base f id cwd path cmd other above hold file bundle comp inside scrub hits
  for base in "$HOME/.claude/projects" "$HOME/.pi/agent/sessions" "$HOME/.cursor/projects" "$HOME/.codex/sessions"; do
    [ -d "$base" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if sync_is_subagent "$f"; then
        continue
      fi
      id=$(basename "$f" .jsonl)
      case "$id" in
        *[!A-Za-z0-9._-]*) id=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '-') ;;
      esac
      bundle=$(sync_mktemp)
      sync_session_files "$f" > "$bundle"
      cwd=""
      other=0
      above=0
      hold=0
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        while IFS= read -r path; do
          [ -n "$path" ] || continue
          if [ -d "$path" ]; then
            path=$(sync_abs "$path")
          fi
          cwd=$path
          if sync_is_above "$path" "$root"; then
            above=1
          fi
          comp=$(sync_company_of "$path" || true)
          if [ -n "$comp" ] && [ "$comp" != "$root" ]; then
            other=1
          fi
          if [ -z "$comp" ]; then
            hold=1
          fi
        done < <(sync_extract "$file" cwd)
        while IFS= read -r path; do
          [ -n "$path" ] || continue
          path=$(sync_abs_path "$path" "$cwd")
          [ -n "$path" ] || continue
          if sync_on_shared "$path"; then
            continue
          fi
          comp=$(sync_company_of "$path" || true)
          if [ -n "$comp" ] && [ "$comp" != "$root" ]; then
            other=1
          fi
        done < <(sync_extract "$file" path)
      done < "$bundle"
      if grep -q . "$bundle"; then
        while IFS= read -r file; do
          while IFS= read -r cmd; do
            [ -n "$cmd" ] || continue
            hits=$(printf '%s\n' "$cmd" | grep -oE '/[^ "]+' || true)
            while IFS= read -r path; do
              [ -n "$path" ] || continue
              if sync_on_shared "$path"; then
                continue
              fi
              comp=$(sync_company_of "$path" || true)
              if [ -n "$comp" ] && [ "$comp" != "$root" ]; then
                other=1
              fi
            done << EOF
$hits
EOF
          done < <(sync_extract "$file" command)
        done < "$bundle"
      fi
      if [ "$above" -eq 1 ] || [ -z "$cwd" ]; then
        sync_log "collect skip ${id} started above a company folder"
        continue
      fi
      if [ "$other" -eq 1 ] || [ "$hold" -eq 1 ]; then
        sync_log "collect hold ${id} touched another company"
        continue
      fi
      # Every cwd must be inside this company.
      inside=1
      while IFS= read -r file; do
        while IFS= read -r path; do
          [ -n "$path" ] || continue
          comp=$(sync_company_of "$path" || true)
          if [ "$comp" != "$root" ]; then
            inside=0
          fi
        done < <(sync_extract "$file" cwd)
      done < "$bundle"
      if [ "$inside" -eq 0 ]; then
        sync_log "collect hold ${id} touched another company"
        continue
      fi
      scrub=$(sync_mktemp)
      : > "$scrub"
      while IFS= read -r file; do
        sync_scrub_file "$file" "$scrub.one"
        cat "$scrub.one" >> "$scrub"
      done < "$bundle"
      mv "$scrub" "$target/${id}.jsonl"
      chmod 600 "$target/${id}.jsonl"
      if [ -n "${OS_TRACES_UPLOAD_URL:-}" ]; then
        if ! sync_post_trace "$target/${id}.jsonl"; then
          rm -f "$target/${id}.jsonl"
          sync_log "collect hold ${id} upload failed"
          continue
        fi
      fi
      sync_log "collect upload ${id}"
    done < <(find "$base" -name '*.jsonl' -type f)
  done
}

sync_is_above() {
  local cwd=$1
  local company=$2
  case "$company" in
    "$cwd"/*) return 0 ;;
  esac
  return 1
}
