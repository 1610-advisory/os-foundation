#!/bin/bash
# Lint the repo this check is running in.
# Company repo: company-profile.md is present. Run the full lint.
# That lint sources add-teammate/lib.sh from this tool set, not from skills/.
# Area repo: no company-profile.md. Check size only.
# An area has its own AGENTS.md and skills/. It does not use the company lint.
set -euo pipefail

usage() {
  cat << 'EOF'
usage: lint.sh [--ci] [--root DIR]

Company repo: full lint. Area repo: size of AGENTS.md, CLAUDE.md, and review-rules.md.
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
root=$(cd "$root" && pwd)

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
if [ -f "$root/company-profile.md" ]; then
  exec bash "$here/lint/lint.sh" --ci --root "$root"
fi

fail=0
for name in AGENTS.md CLAUDE.md review-rules.md; do
  file="${root}/${name}"
  if [ ! -f "$file" ]; then
    continue
  fi
  size=$(wc -c < "$file" | tr -d ' ')
  if [ "$size" -ge 10000 ]; then
    printf '%s\n' "finding: size: ${name}"
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
