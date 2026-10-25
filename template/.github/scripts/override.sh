#!/bin/bash
# Decide whether an /override comment is allowed.
# Prints one line: valid <reason> | ignored empty | ignored not-owner
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"

usage() {
  cat << 'EOF'
usage: override.sh --user LOGIN --comment-file FILE --base SHA

Decide if this person may override a failed review.
Reads CODEOWNERS and people pages from the base commit, not the pull request head.
A person may override when they are an org owner in the event file, a person
with role admin, or a company-root code owner.
Prints one line and exits 0.
EOF
}

user=""
comment_file=""
base=""
event_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --user)
      user=${2:-}
      shift 2
      ;;
    --comment-file)
      comment_file=${2:-}
      shift 2
      ;;
    --base)
      base=${2:-}
      shift 2
      ;;
    --event-file)
      event_file=${2:-}
      shift 2
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$user" ] || [ -z "$comment_file" ] || [ -z "$base" ]; then
  usage >&2
  exit 1
fi
if [ ! -f "$comment_file" ]; then
  ci_die 1 "override failed: the comment file is missing"
fi

body=$(tr -d '\r' < "$comment_file")
first=$(printf '%s\n' "$body" | head -n 1)
first=$(ci_trim "$first")
case "$first" in
  /override*) ;;
  *)
    printf '%s\n' "ignored not-owner"
    exit 0
    ;;
esac
reason=$(printf '%s' "$first" | sed 's/^\/override[[:space:]]*//')
reason=$(ci_trim "$reason")
if [ -z "$reason" ]; then
  printf '%s\n' "ignored empty"
  exit 0
fi

want=$(ci_lower "$user")
owners_file=$(ci_mktemp)
trap ci_cleanup EXIT

add_owner() {
  local name
  name=$(printf '%s' "$1" | sed 's/^@//')
  name=$(ci_trim "$name")
  if [ -z "$name" ]; then
    return 0
  fi
  printf '%s\n' "$(ci_lower "$name")" >> "$owners_file"
}

# Company-root rules paths. A CODEOWNERS line that matches one of these
# names its owner as a company-root code owner.
rules_paths="AGENTS.md
CLAUDE.md
review-rules.md
skills/example/SKILL.md
.github/workflows/checks.yml
.github/CODEOWNERS
bots/example/BOT.md"

pattern_hits_rules() {
  local kind=$1 pattern=$2 path
  pattern=$(ci_trim "$pattern")
  [ -n "$pattern" ] || return 1
  case "$pattern" in
    \!*) return 1 ;;
  esac
  printf '%s\n' "$rules_paths" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ci_path_match "$kind" "$pattern" "$path"; then
      echo hit
      break
    fi
  done | head -n 1 | grep -q hit
}

load_codeowners() {
  local spec=$1 kind=$2 text line pattern rest owner
  if ! git cat-file -e "$spec" 2>/dev/null; then
    return 0
  fi
  text=$(git show "$spec")
  printf '%s\n' "$text" | while IFS= read -r line; do
    line=$(ci_trim "$line")
    case "$line" in
      ""|\#*) continue ;;
    esac
    pattern=${line%%[[:space:]]*}
    rest=${line#"$pattern"}
    rest=$(ci_trim "$rest")
    if ! pattern_hits_rules "$kind" "$pattern"; then
      continue
    fi
    for owner in $rest; do
      case "$owner" in
        \#*) break ;;
      esac
      add_owner "$owner"
    done
  done
}

load_codeowners "${base}:CODEOWNERS" regex
load_codeowners "${base}:.github/CODEOWNERS" glob
load_codeowners "${base}:.forgejo/CODEOWNERS" regex
load_codeowners "${base}:docs/CODEOWNERS" regex

if git cat-file -e "${base}:people" 2>/dev/null || git ls-tree -d --name-only "$base" people >/dev/null 2>&1; then
  git ls-tree -r --name-only "$base" -- people 2>/dev/null | while IFS= read -r page; do
    [ -n "$page" ] || continue
    case "$page" in
      *.md) ;;
      *) continue ;;
    esac
    text=$(git show "${base}:${page}" 2>/dev/null || true)
    role=$(printf '%s\n' "$text" | sed -n 's/^role:[[:space:]]*//p' | head -n 1)
    role=$(ci_trim "$role")
    role=$(printf '%s' "$role" | tr -d '"' | tr -d "'")
    login=$(printf '%s\n' "$text" | sed -n 's/^github:[[:space:]]*//p' | head -n 1)
    login=$(ci_trim "$login")
    login=$(printf '%s' "$login" | tr -d '"' | tr -d "'")
    left=$(printf '%s\n' "$text" | sed -n 's/^left:[[:space:]]*//p' | head -n 1)
    left=$(ci_trim "$left")
    if [ "$(ci_lower "$role")" = "admin" ] && [ -n "$login" ] && [ -z "$left" ]; then
      add_owner "$login"
    fi
  done
fi

if [ -n "$event_file" ] && [ -f "$event_file" ]; then
  assoc=$(jq -r '.comment.author_association // .review.author_association // empty' "$event_file")
  if [ "$(ci_lower "$assoc")" = "owner" ]; then
    add_owner "$user"
  fi
fi

if grep -q -x -F "$want" "$owners_file" 2>/dev/null; then
  printf 'valid %s\n' "$reason"
  exit 0
fi
printf '%s\n' "ignored not-owner"
