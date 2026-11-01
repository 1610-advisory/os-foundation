#!/bin/bash
# template/.github/scripts/stock-hashes.txt lists every stock file upgrade.sh --refresh may
# replace: the git blob id and path of each file under template/skills/ and
# template/.github/, in every commit of this repo's history that touched them, and in the
# working tree. A company copy that matches one of these is exactly as shipped. It ships
# with the check tools: the model review skips a file that is exactly a stock text.
#   --write  rebuild the list from history (run it before a release)
#   --check  fail when a stock file in the working tree is not in the list
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LIST="$ROOT/template/.github/scripts/stock-hashes.txt"

current() {
  (
    cd "$ROOT/template"
    find skills .github -type f | grep -v '/\.DS_Store$' | while IFS= read -r path; do
      case "$path" in .github/scripts/stock-hashes.txt|skills/upgrade/stock-hashes.txt) continue ;; esac
      printf '%s %s\n' "$(git hash-object -- "$path")" "$path"
    done
  )
}

case "${1:-}" in
  --write)
    tmp=$(mktemp)
    {
      git -C "$ROOT" log --format=%H HEAD -- template/skills template/.github | while IFS= read -r commit; do
        git -C "$ROOT" ls-tree -r "$commit" -- template/skills template/.github
      done | awk '$2 == "blob" { sub("^template/", "", $4); print $3, $4 }'
      current
    } | grep -v -e ' skills/upgrade/stock-hashes.txt$' -e ' .github/scripts/stock-hashes.txt$' | LC_ALL=C sort -u > "$tmp"
    {
      printf '%s\n' "# git blob id and path of every stock file the template has shipped"
      printf '%s\n' "# under skills/ and .github/. Written by tests/static/stock-hashes.sh --write."
      cat "$tmp"
    } > "$LIST"
    rm -f "$tmp"
    printf 'wrote %s lines\n' "$(grep -vc '^#' "$LIST")"
    ;;
  --check)
    missing=0
    while IFS= read -r line; do
      if ! grep -Fxq -- "$line" "$LIST"; then
        printf 'not in stock-hashes.txt: %s\n' "${line#* }" >&2
        missing=1
      fi
    done < <(current)
    if [ "$missing" -ne 0 ]; then
      printf '%s\n' "run tests/static/stock-hashes.sh --write" >&2
      exit 1
    fi
    printf '%s\n' "stock-hashes: ok"
    ;;
  *)
    printf '%s\n' "usage: stock-hashes.sh --write | --check" >&2
    exit 1
    ;;
esac
