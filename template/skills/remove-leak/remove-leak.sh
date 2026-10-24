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
    aws-access-key) printf '%s' 'AKIA[0-9A-Z]{16}' ;;
    generic-api-key) printf '%s' '(?i)(api[_-]?key|secret|token)[[:space:]]*[:=][[:space:]]*[^[:space:]]+' ;;
    private-key) printf '%s' '-----BEGIN [A-Z ]*PRIVATE KEY-----' ;;
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
      os_git_commit "$LOCAL" "Revert leak on open pull request"
      os_with_git_token git -C "$LOCAL" push origin "$HEAD_BRANCH"
    fi
    if [ -n "$LEAK_PATH" ]; then
      if ! git -C "$LOCAL" cat-file -e "origin/main:$LEAK_PATH" 2>/dev/null; then
        printf '%s\n' "remove-leak: ok"
        printf '%s\n' "rule: path"
        printf '%s\n' "pr: $PR_N"
        exit 0
      fi
    fi
  fi
fi

URL=$(os_clone_url "$HOST_KIND" "$HOST_URL" "$ORG" "$REPO_NAME")
WORK=$(mktemp -d)
chmod 700 "$WORK"
os_with_git_token git clone --quiet "$URL" "$WORK/repo"
git -C "$WORK/repo" fetch --quiet origin '+refs/heads/*:refs/heads/*' || true

if [ -n "$LEAK_PATH" ]; then
  git -C "$WORK/repo" filter-repo --invert-paths --path "$LEAK_PATH" --force
  RULE_LABEL="path"
  TAG_MSG="path: $LEAK_PATH"
else
  regex=$(rule_regex "$RULE" || true)
  [ -n "$regex" ] || os_die 2 "unknown pattern rule"
  expr=$(mktemp)
  chmod 600 "$expr"
  printf 'regex:%s==>[removed]\n' "$regex" > "$expr"
  git -C "$WORK/repo" filter-repo --replace-text "$expr" --force
  rm -f "$expr"
  RULE_LABEL="$RULE"
  TAG_MSG="rule: $RULE"
fi

ME=""
cfg=$(os_config_dir "$SLUG")
if [ -f "$cfg/me" ]; then
  ME=$(tr -d '\r\n' < "$cfg/me")
fi
[ -n "$ME" ] || ME="admin"
mkdir -p "$WORK/repo/memory/logs"
printf '%s\n' "- remove-leak: repo ${REPO_NAME} rule ${RULE_LABEL}" >> "$WORK/repo/memory/logs/$(os_today)-${ME}.md"
os_git_commit "$WORK/repo" "Audit: remove leak"

git -C "$WORK/repo" remote add origin "$URL"

set +e
os_host unprotect "$REPO_NAME" >/dev/null
unprotect_rc=$?
set -e
if [ "$unprotect_rc" -ne 0 ] && [ "$unprotect_rc" -ne 2 ]; then
  printf '%s\n' "unprotect: host.sh has no unprotect verb yet" >&2
fi

set +e
os_with_git_token git -C "$WORK/repo" push --force --all origin
push_rc=$?
set -e
if [ "$push_rc" -ne 0 ]; then
  printf '%s\n' "force-push failed. main is still protected. host.sh needs unprotect." >&2
  rm -rf "$WORK"
  exit 3
fi
os_with_git_token git -C "$WORK/repo" push --force --tags origin

STAMP=$(os_stamp)
TAG="os-rewrite-${STAMP}"
git -C "$WORK/repo" tag -a "$TAG" -m "$TAG_MSG"
os_with_git_token git -C "$WORK/repo" push origin "$TAG"

os_host protect "$REPO_NAME" --code-owners --approvals 0 >/dev/null || true
os_host purge-request "$REPO_NAME" >/dev/null || true

printf '%s\n' "remove-leak: ok"
printf 'tag: %s\n' "$TAG"
printf 'rule: %s\n' "$RULE_LABEL"
rm -rf "$WORK"
