#!/bin/bash
# Decide whether a pull request waits for an owner's yes (v1.0.4, B89).
# Two kinds of change wait:
# - a rules file, in any repo;
# - a file added or changed in the company repo (the shared root that everyone reads).
#   A deleted file does not wait: taking content off the root is always allowed.
# Prints one line per reason: "rules <path>" or "root <path>".
# Exit 0: nothing waits. Exit 10: an owner must say yes. Exit 1: error.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: owner-gate.sh --range BASE..HEAD --tools SHA

List the changes in the range that wait for an owner's yes.
A repo is the company repo when company-profile.md is on SHA (main).
Prints "rules <path>" or "root <path>", one per line.
Exit 0 when nothing waits, 10 when an owner must say yes, 1 on error.
EOF
}

range=""
tools_sha=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --range) range=${2:-}; shift 2 ;;
    --tools) tools_sha=${2:-}; shift 2 ;;
    *) usage >&2; exit 1 ;;
  esac
done
if [ -z "$range" ] || [ -z "$tools_sha" ]; then
  usage >&2
  exit 1
fi

# The same list as sync_is_rules in skills/sync/lib.sh.
is_rules() {
  local path=$1 base
  base=${path##*/}
  case "$base" in
    AGENTS.md|CLAUDE.md|review-rules.md|CODEOWNERS|company-rules.md|area-rules.md) return 0 ;;
  esac
  case "$path" in
    skills/*|*/skills/*|.github/*|*/.github/*|.gitea/*|*/.gitea/*|.forgejo/*|*/.forgejo/*|.claude/*|*/.claude/*|docs/CODEOWNERS|*/docs/CODEOWNERS|automations/*/AUTOMATION.md) return 0 ;;
  esac
  return 1
}

company=no
if git cat-file -e "${tools_sha}:company-profile.md" 2>/dev/null; then
  company=yes
fi

list=$(ci_mktemp)
if ! git diff --name-status -z --no-renames "$range" > "$list" 2>/dev/null; then
  ci_die 1 "owner check failed: could not read the changes"
fi

out=$(ci_mktemp)
: > "$out"
# -z output: status, then path, each ending in NUL.
while IFS= read -r -d '' status; do
  IFS= read -r -d '' path || break
  if is_rules "$path"; then
    printf 'rules %s\n' "$path" >> "$out"
    continue
  fi
  [ "$company" = yes ] || continue
  case "$status" in
    D*) continue ;;
  esac
  printf 'root %s\n' "$path" >> "$out"
done < "$list"

if [ -s "$out" ]; then
  cat "$out"
  exit 10
fi
exit 0
