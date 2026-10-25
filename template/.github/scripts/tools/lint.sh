#!/bin/bash
# Lint the repo this check is running in.
# Company repo: company-profile.md is present. Run the full lint.
# That lint sources add-teammate/lib.sh from this tool set, not from skills/.
# Area repo: no company-profile.md. Check size only.
# An area has its own AGENTS.md and skills/. It does not use the company lint.
set -euo pipefail

usage() {
  cat << 'EOF'
usage: lint.sh [--ci] [--root DIR] [--base SHA]

Company or area comes from the base commit, not the pull request head.
Company repo: full lint. Area repo: size of AGENTS.md, CLAUDE.md, and review-rules.md.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

root="."
base=""
ci=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ci)
      ci=1
      shift
      ;;
    --root)
      root=${2:-}
      shift 2
      ;;
    --base)
      base=${2:-}
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

# The head can delete the profile, replace it with a directory, or leave a
# dangling link. That must not switch a company repo onto the size-only path.
# In --ci, a missing or unknown base fails closed. Size-only only when the
# base commit exists and has no company-profile.md.
if [ "$ci" -eq 1 ] && [ -z "$base" ]; then
  echo "lint failed: the base commit is missing" >&2
  exit 2
fi

company=0
if [ -n "$base" ]; then
  case "$base" in
    *[!0-9a-fA-F]*)
      echo "lint failed: the base commit is not a sha" >&2
      exit 2
      ;;
  esac
  if ! git -C "$root" cat-file -e "${base}^{commit}" 2>/dev/null; then
    echo "lint failed: the base commit is not in the repo" >&2
    exit 2
  fi
  if git -C "$root" cat-file -e "${base}:company-profile.md" 2>/dev/null; then
    company=1
  fi
elif [ -f "$root/company-profile.md" ] && [ ! -L "$root/company-profile.md" ]; then
  company=1
fi

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
if [ "$company" -eq 1 ]; then
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
