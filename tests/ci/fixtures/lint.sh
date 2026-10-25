#!/bin/bash
# Test double for skills/lint/lint.sh.
set -euo pipefail

usage() {
  cat << 'EOF'
usage: lint.sh [--ci] [--root DIR]

Exit 1 when a file contains the lint failure marker. Otherwise exit 0.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

root="."
while [ $# -gt 0 ]; do
  case "$1" in
    --ci)
      shift
      ;;
    --root)
      root=${2:-}
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$root" ] || [ ! -d "$root" ]; then
  echo "lint failed: the root is missing" >&2
  exit 2
fi

marker="OSF_LINT_FAIL"
if grep -R -l -F --exclude-dir=.git --exclude=lint.sh "$marker" "$root" >/dev/null 2>&1; then
  echo "lint failed" >&2
  exit 1
fi
exit 0
