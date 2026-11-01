#!/bin/bash
# Print the diff the model review reads for one range. Run inside the repo.
#
# A file whose text at the head is exactly the stock text this release ships at that path
# is left out: the line at the top says how many. The list is stock-current.txt from the
# base tools (main), never from the head, so a pull request cannot add to it. An older
# release's text is not in it: putting a file back to old text is a change, and is
# reviewed. A match is a git blob id and its path. upgrade.sh measures a pull request with
# this same script.
set -euo pipefail

usage() {
  cat << 'EOF'
usage: review-diff.sh <base>..<head> <stock-current file>

Print the diff for the model review. Files exactly as this release ships them are left out.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi
if [ $# -ne 2 ]; then
  usage >&2
  exit 1
fi

range=$1
hashes=$2
head=${range#*..}
skip=()
if [ -f "$hashes" ]; then
  while IFS= read -r -d '' path; do
    id=$(git rev-parse -q --verify "${head}:${path}" 2>/dev/null) || continue
    if grep -Fxq -- "$id $path" "$hashes"; then
      skip+=(":(exclude,literal)${path}")
    fi
  done < <(git -c core.quotepath=false diff -z --name-only --no-renames --diff-filter=AM "$range")
fi
if [ "${#skip[@]}" -eq 1 ]; then
  printf '%s\n' "# 1 file is left out: it is exactly as this release of the company OS ships it."
elif [ "${#skip[@]}" -gt 1 ]; then
  printf '# %s files are left out: each is exactly as this release of the company OS ships it.\n' "${#skip[@]}"
fi
git diff --no-color --no-renames "$range" -- . ${skip[@]+"${skip[@]}"}
