#!/bin/bash
# Remove a leak from history. Never print the secret. Bash 3.2.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-teammate/lib.sh"

usage() {
  cat << 'EOF'
usage: remove-leak.sh --repo <name> (--path <p> | --pattern-rule <id>) [--root <dir>] [--pr <n>] [--head <branch>]

Rewrite history, force-push, ask the host to purge, and tag os-rewrite-*.
The secret is never printed.
EOF
}

REPO_NAME=""
LEAK_PATH=""
RULE=""
ROOT=""
PR_N=""
HEAD_BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --repo)
      [ $# -ge 2 ] || os_die 1 "missing repo"
      REPO_NAME=$2
      shift 2
      ;;
    --path)
      [ $# -ge 2 ] || os_die 1 "missing path"
      LEAK_PATH=$2
      shift 2
      ;;
    --pattern-rule)
      [ $# -ge 2 ] || os_die 1 "missing rule"
      RULE=$2
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || os_die 1 "missing root"
      ROOT=$2
      shift 2
      ;;
    --pr)
      [ $# -ge 2 ] || os_die 1 "missing pr"
      PR_N=$2
      shift 2
      ;;
    --head)
      [ $# -ge 2 ] || os_die 1 "missing head"
      HEAD_BRANCH=$2
      shift 2
      ;;
    *)
      os_die 1 "unknown argument: $1"
      ;;
  esac
done

[ -n "$REPO_NAME" ] || os_die 1 "pass --repo <name>"
if [ -z "$LEAK_PATH" ] && [ -z "$RULE" ]; then
  os_die 1 "pass --path or --pattern-rule"
fi
if [ -n "$LEAK_PATH" ] && [ -n "$RULE" ]; then
  os_die 1 "pass only one of --path or --pattern-rule"
fi
os_need git jq
if ! git filter-repo -h >/dev/null 2>&1; then
  os_die 3 "git filter-repo is not installed"
fi

[ -n "$ROOT" ] || ROOT=$(pwd)
ROOT=$(cd "$ROOT" && pwd)
[ -f "$ROOT/company-profile.md" ] || os_die 2 "company-profile.md is missing"

SLUG=$(os_fm_get "$ROOT/company-profile.md" company_slug)
HOST_KIND=$(os_fm_get "$ROOT/company-profile.md" host)
HOST_URL=$(os_fm_get "$ROOT/company-profile.md" host_url || true)
ORG=$(os_fm_get "$ROOT/company-profile.md" org)
if ! OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
  os_die 3 "host.sh is missing"
fi
export OS_HOST_BIN OS_ORG="$ORG" OS_HOST="$HOST_KIND" OS_HOST_URL="$HOST_URL" OS_SLUG="$SLUG"
export OS_PROFILE="$ROOT/company-profile.md"

rule_regex() {
  local id=$1 extra line eid
  extra="$ROOT/skills/sync/secret-patterns.txt"
  if [ -f "$extra" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      eid=${line%%	*}
      if [ "$eid" = "$id" ]; then
        printf '%s' "${line#*	}"
        return 0
      fi
    done < "$extra"
  fi
  case "$id" in
    aws-access-key) printf '%s[0-9A-Z]{16}' "$(printf '%s%s' 'AK' 'IA')" ;;
    generic-api-key) printf '%s' '(?i)(api[_-]?key|secret|token)[[:space:]]*[:=][[:space:]]*[^[:space:]]+' ;;
    private-key) printf '%s [A-Z ]*%s-----' "$(printf '%s%s' '-----BE' 'GIN')" "$(printf '%s%s' 'PRI' 'VATE KEY')" ;;
    *) return 1 ;;
  esac
}

LOCAL=""
if [ "$REPO_NAME" = "$(os_company_repo "$SLUG")" ]; then
  LOCAL=$ROOT
else
  area=${REPO_NAME#"${SLUG}-"}
  if [ -e "$ROOT/areas/$area/.git" ]; then
    LOCAL="$ROOT/areas/$area"
  fi
fi

if [ -n "$PR_N" ]; then
  status=$(os_host pr-status "$REPO_NAME" "$PR_N")
  state=$(printf '%s' "$status" | jq -r '.state // empty')
  merged=$(printf '%s' "$status" | jq -r '.merged // false')
  if [ "$state" = "open" ] && [ "$merged" != "true" ]; then
    [ -n "$HEAD_BRANCH" ] || os_die 1 "--head is required when the pull request is open"
    [ -n "$LOCAL" ] || os_die 2 "no local checkout for $REPO_NAME"
    os_with_git_token git -C "$LOCAL" fetch origin
    git -C "$LOCAL" checkout -q -B "$HEAD_BRANCH" "origin/$HEAD_BRANCH"
    if [ -n "$LEAK_PATH" ] && [ -e "$LOCAL/$LEAK_PATH" ]; then
      rm -f "$LOCAL/$LEAK_PATH"
      os_git_commit "$LOCAL" "Revert leak on open pull request" "$LEAK_PATH"
      os_with_git_token git -C "$LOCAL" push origin "$HEAD_BRANCH"
    fi
    if [ -n "$LEAK_PATH" ]; then
      if ! git -C "$LOCAL" cat-file -e "origin/main:$LEAK_PATH" 2>/dev/null; then
        printf '%s\n' "remove-leak: ok"
        printf 'path: %s\n' "$LEAK_PATH"
        printf '%s\n' "pr: $PR_N"
        exit 0
      fi
    fi
  fi
fi

URL=$(os_clone_url "$HOST_KIND" "$HOST_URL" "$ORG" "$REPO_NAME")
WORK=$(mktemp -d)
EXPR=""
LEAK_PROTECT=0
chmod 700 "$WORK"
leak_cleanup() {
  local status=$?
  if [ "$LEAK_PROTECT" = "1" ]; then
    if ! os_host protect "$REPO_NAME" --code-owners --approvals 0 >/dev/null; then
      printf 'PROTECTION IS OFF on %s: run skills/_host/host.sh protect %s --code-owners --approvals 0\n' "$REPO_NAME" "$REPO_NAME" >&2
      status=3
    fi
    LEAK_PROTECT=0
  fi
  rm -rf "$WORK"
  if [ -n "$EXPR" ]; then
    rm -f "$EXPR"
  fi
  exit "$status"
}
trap leak_cleanup EXIT
os_with_git_token git clone --quiet "$URL" "$WORK/repo"
if ! os_with_git_token git -C "$WORK/repo" fetch --quiet origin '+refs/heads/*:refs/remotes/origin/*'; then
  printf '%s\n' "fetch failed. History was not rewritten." >&2
  exit 3
fi
git -C "$WORK/repo" for-each-ref --format '%(refname:strip=3)' refs/remotes/origin | while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  [ "$branch" = "HEAD" ] && continue
  if ! git -C "$WORK/repo" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "$WORK/repo" branch "$branch" "origin/${branch}"
  fi
done

if [ -n "$LEAK_PATH" ]; then
  git -C "$WORK/repo" filter-repo --invert-paths --path "$LEAK_PATH" --force
  TAG_MSG="path: $LEAK_PATH"
else
  regex=$(rule_regex "$RULE" || true)
  [ -n "$regex" ] || os_die 2 "unknown pattern rule"
  EXPR=$(mktemp)
  chmod 600 "$EXPR"
  printf 'regex:%s==>[removed]\n' "$regex" > "$EXPR"
  git -C "$WORK/repo" filter-repo --replace-text "$EXPR" --force
  rm -f "$EXPR"
  EXPR=""
  TAG_MSG="rule: $RULE"
fi

ME=""
cfg=$(os_config_dir "$SLUG")
if [ -f "$cfg/me" ]; then
  ME=$(tr -d '\r\n' < "$cfg/me")
fi
[ -n "$ME" ] || ME="admin"
mkdir -p "$WORK/repo/memory/logs"
if [ -n "$LEAK_PATH" ]; then
  printf '%s\n' "- remove-leak: repo ${REPO_NAME} path: ${LEAK_PATH}" >> "$WORK/repo/memory/logs/$(os_today)-${ME}.md"
else
  printf '%s\n' "- remove-leak: repo ${REPO_NAME} rule: ${RULE}" >> "$WORK/repo/memory/logs/$(os_today)-${ME}.md"
fi
os_git_commit "$WORK/repo" "Audit: remove leak" "memory/logs/$(os_today)-${ME}.md"

git -C "$WORK/repo" remote add origin "$URL"

os_host unprotect "$REPO_NAME" >/dev/null
LEAK_PROTECT=1

os_with_git_token git -C "$WORK/repo" push --force --all origin
os_with_git_token git -C "$WORK/repo" push --force --tags origin

STAMP=$(os_stamp)
TAG="os-rewrite-${STAMP}"
git -C "$WORK/repo" tag -a "$TAG" -m "$TAG_MSG"
os_with_git_token git -C "$WORK/repo" push origin "$TAG"

if ! os_host protect "$REPO_NAME" --code-owners --approvals 0 >/dev/null; then
  printf 'PROTECTION IS OFF on %s: run skills/_host/host.sh protect %s --code-owners --approvals 0\n' "$REPO_NAME" "$REPO_NAME" >&2
  LEAK_PROTECT=0
  exit 3
fi
LEAK_PROTECT=0
os_host purge-request "$REPO_NAME" >/dev/null || true

printf '%s\n' "remove-leak: ok"
printf 'tag: %s\n' "$TAG"
if [ -n "$LEAK_PATH" ]; then
  printf 'rule: path\n'
  printf 'path: %s\n' "$LEAK_PATH"
else
  printf 'rule: %s\n' "$RULE"
fi
