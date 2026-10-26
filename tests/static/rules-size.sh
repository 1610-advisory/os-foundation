#!/usr/bin/env bash
# Every tracked AGENTS.md and CLAUDE.md must be under 10000 characters.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: rules-size.sh [--root DIR]

Check every tracked AGENTS.md, CLAUDE.md, company-rules.md, and area-rules.md.
A file fails when wc -m is 10000 or more.
Prints "OK <n> files", or each failing file with its size.
EOF
}

root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --root)
      [[ $# -ge 2 ]] || { echo "rules-size: missing root" >&2; exit 2; }
      root=$2
      shift 2
      ;;
    *)
      echo "rules-size: unknown argument" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$root" ]]; then
  script_dir=$(cd "$(dirname "$0")" && pwd)
  root=$(cd "$script_dir/../.." && pwd)
fi

if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "rules-size: not a git repo" >&2
  exit 2
fi

count=0
fail=0
while IFS= read -r -d '' rel; do
  [[ -n "$rel" ]] || continue
  base=$(basename "$rel")
  case "$base" in
    AGENTS.md|CLAUDE.md|company-rules.md|area-rules.md) ;;
    *) continue ;;
  esac
  count=$((count + 1))
  chars=$(wc -m < "$root/$rel" | tr -d '[:space:]')
  if [[ "$chars" -ge 10000 ]]; then
    printf '%s %s\n' "$rel" "$chars"
    fail=1
  fi
done < <(git -C "$root" ls-files -z)

if [[ "$fail" -eq 0 ]]; then
  printf 'OK %s files\n' "$count"
  exit 0
fi
exit 1
