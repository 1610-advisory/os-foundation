#!/usr/bin/env bash
# Named placeholders must be on the allow list. A built company has none left.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: placeholders.sh [--root DIR] [--allow FILE]
       placeholders.sh --built DIR

Default: every {{NAME}} in tracked files under template/, and in start*.md
and START.md, must be listed in placeholders.allow (one name per line).
Unknown names print file:line:{{NAME}}.

--built DIR: a company folder must have no {{...}} left outside skills/
and outside .git/.
EOF
}

script_dir=$(cd "$(dirname "$0")" && pwd)
root=""
allow_file="$script_dir/placeholders.allow"
built=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --root)
      [[ $# -ge 2 ]] || { echo "placeholders: missing root" >&2; exit 2; }
      root=$2
      shift 2
      ;;
    --allow)
      [[ $# -ge 2 ]] || { echo "placeholders: missing allow file" >&2; exit 2; }
      allow_file=$2
      shift 2
      ;;
    --built)
      [[ $# -ge 2 ]] || { echo "placeholders: missing folder" >&2; exit 2; }
      built=$2
      shift 2
      ;;
    *)
      echo "placeholders: unknown argument" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$built" ]]; then
  if [[ ! -d "$built" ]]; then
    echo "placeholders: folder not found" >&2
    exit 2
  fi
  fail=0
  while IFS= read -r -d '' file; do
    [[ -n "$file" ]] || continue
    rel=${file#"$built"/}
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      rest=$line
      while [[ "$rest" =~ \{\{([^}]+)\}\} ]]; do
        name=${BASH_REMATCH[1]}
        printf '%s:%s:{{%s}}\n' "$rel" "$n" "$name"
        fail=1
        rest=${rest#*"{{$name}}"}
      done
    done < "$file"
  done < <(find "$built" \( -name .git -o -name skills \) -prune -o -type f -print0)
  if [[ "$fail" -eq 0 ]]; then
    echo "OK"
    exit 0
  fi
  exit 1
fi

if [[ -z "$root" ]]; then
  root=$(cd "$script_dir/../.." && pwd)
fi

if [[ ! -f "$allow_file" ]]; then
  echo "placeholders: allow list missing" >&2
  exit 2
fi

if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "placeholders: not a git repo" >&2
  exit 2
fi

allowed_tmp=$(mktemp)
# Invoked by trap, not by a direct call.
# shellcheck disable=SC2329
cleanup() {
  rm -f "$allowed_tmp"
}
trap cleanup EXIT

while IFS= read -r name || [[ -n "$name" ]]; do
  name=${name%$'\r'}
  name=${name#"${name%%[![:space:]]*}"}
  name=${name%"${name##*[![:space:]]}"}
  [[ -z "$name" || "$name" == \#* ]] && continue
  printf '%s\n' "$name" >> "$allowed_tmp"
done < "$allow_file"

in_scope() {
  local rel=$1
  local base
  base=$(basename "$rel")
  case "$rel" in
    template|template/*) return 0 ;;
  esac
  case "$base" in
    START.md|start*.md) return 0 ;;
  esac
  return 1
}

is_allowed() {
  grep -qxF -- "$1" "$allowed_tmp"
}

fail=0
while IFS= read -r -d '' rel; do
  [[ -n "$rel" ]] || continue
  in_scope "$rel" || continue
  [[ -f "$root/$rel" ]] || continue
  n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    rest=$line
    while [[ "$rest" =~ \{\{([A-Z][A-Z0-9_]*)\}\} ]]; do
      name=${BASH_REMATCH[1]}
      if ! is_allowed "$name"; then
        printf '%s:%s:{{%s}}\n' "$rel" "$n" "$name"
        fail=1
      fi
      rest=${rest#*"{{$name}}"}
    done
  done < "$root/$rel"
done < <(git -C "$root" ls-files -z)

if [[ "$fail" -eq 0 ]]; then
  echo "OK"
  exit 0
fi
exit 1
