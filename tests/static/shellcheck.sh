#!/usr/bin/env bash
# Run shellcheck on tracked shell scripts. Passes when there are none.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: shellcheck.sh [--root DIR]

Run shellcheck on every tracked *.sh file, and on extensionless scripts
with a bash shebang under template/ and tests/.
Prints "OK 0 files" when there are none.
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
      [[ $# -ge 2 ]] || { echo "shellcheck: missing root" >&2; exit 2; }
      root=$2
      shift 2
      ;;
    *)
      echo "shellcheck: unknown argument" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$root" ]]; then
  script_dir=$(cd "$(dirname "$0")" && pwd)
  root=$(cd "$script_dir/../.." && pwd)
fi

if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "shellcheck: not a git repo" >&2
  exit 2
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck: not found" >&2
  exit 127
fi

is_bash_shebang() {
  local line
  IFS= read -r line < "$1" || return 1
  case "$line" in
    '#!'*bash*) return 0 ;;
    *) return 1 ;;
  esac
}

files=()
while IFS= read -r -d '' rel; do
  [[ -n "$rel" ]] || continue
  case "$rel" in
    *.sh)
      files+=("$rel")
      continue
      ;;
  esac
  case "$rel" in
    template/*|tests/*) ;;
    *) continue ;;
  esac
  base=$(basename "$rel")
  case "$base" in
    *.*) continue ;;
  esac
  if is_bash_shebang "$root/$rel"; then
    files+=("$rel")
  fi
done < <(git -C "$root" ls-files -z)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "OK 0 files"
  exit 0
fi

if (cd "$root" && shellcheck "${files[@]}"); then
  printf 'OK %s files\n' "${#files[@]}"
  exit 0
fi
exit 1
