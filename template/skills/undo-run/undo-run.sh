#!/bin/bash
# Revert every commit of one bot run. One revert commit per repo.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-bot/lib.sh"
trap bot_cleanup EXIT

usage() {
  cat << 'EOF'
Usage: undo-run.sh <run-id> [--root <dir>]

Find every commit on main with that Run-Id trailer. Make one revert
commit per repo, open a pull request, and ask for auto-merge.
The bots switch must be on.
EOF
}

BOT_ROOT_ARG=""
run_id=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --root)
      [ $# -ge 2 ] || bot_die 1 "--root needs a directory"
      BOT_ROOT_ARG=$2
      export BOT_ROOT_ARG
      shift 2
      ;;
    --)
      shift
      break
      ;;
    --*)
      bot_die 1 "unknown argument: $1"
      ;;
    *)
      if [ -n "$run_id" ]; then
        bot_die 1 "too many arguments"
      fi
      run_id=$1
      shift
      ;;
  esac
done

[ -n "$run_id" ] || bot_die 1 "run-id is required"
bot_slug_ok "run-id" "$run_id"

BOT_ROOT=$(bot_find_root)
export BOT_ROOT
export OS_PROFILE
OS_PROFILE=$(bot_profile)
bot_require_switch bots
bot_need jq
bot_need git

host_sh=$(bot_host_sh)
err=$(bot_mktemp)
set +e
if [ -n "${OS_BOT:-}" ]; then
  token=$(bash "$host_sh" get-token --bot "$OS_BOT" 2>"$err")
else
  token=$(bash "$host_sh" get-token 2>"$err")
fi
rc=$?
set -e
if [ "$rc" -ne 0 ] || [ -z "$token" ]; then
  scrub=$(bot_mktemp)
  OS_SCRUB=$token bot_scrub_file "$err" "$scrub"
  if [ -s "$scrub" ]; then
    cat "$scrub" >&2
  else
    printf '%s\n' "get-token failed" >&2
  fi
  exit "${rc:-4}"
fi
export OS_GIT_TOKEN=$token
token=""

login=$(bash "$host_sh" whoami | jq -r '.login // empty')
[ -n "$login" ] || bot_die 4 "whoami returned no login"
export OS_GIT_USER=$login

ask=$(bot_mktemp)
cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
chmod 700 "$ask"

repo_list=$(bot_mktemp)
if bot_is_git "$BOT_ROOT"; then
  printf '%s\n' "$BOT_ROOT" >> "$repo_list"
fi
if [ -d "${BOT_ROOT}/areas" ]; then
  for dir in "${BOT_ROOT}/areas"/*; do
    if bot_is_git "$dir"; then
      printf '%s\n' "$dir" >> "$repo_list"
    fi
  done
fi

found_any=0
any_conflict=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -C "$path" -c credential.helper= fetch origin
  hits=$(bot_mktemp)
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    body=$(git -C "$path" log -1 --format='%B' "$sha")
    if printf '%s\n' "$body" | awk -v id="$run_id" '
      BEGIN { hit = 0 }
      {
        line = $0
        sub(/\r/, "", line)
        if (line ~ /^Run-Id:[ \t]/) {
          val = line
          sub(/^Run-Id:[ \t]*/, "", val)
          sub(/[ \t]*$/, "", val)
          if (val == id) { hit = 1 }
        }
      }
      END { exit (hit ? 0 : 1) }
    '; then
      printf '%s\n' "$sha" >> "$hits"
    fi
  done << EOF
$(git -C "$path" log origin/main --format='%H')
EOF
  if [ ! -s "$hits" ]; then
    continue
  fi
  found_any=1
  name=$(bot_origin_name "$path") || bot_die 3 "repo has no origin"
  branch="undo/${run_id}"
  git -C "$path" checkout -B "$branch" origin/main
  conflict=0
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    if ! git -C "$path" revert --no-commit "$sha"; then
      conflict=1
      break
    fi
  done < "$hits"
  if [ "$conflict" -eq 1 ]; then
    git -C "$path" revert --abort >/dev/null 2>&1 || true
    git -C "$path" reset --hard origin/main >/dev/null 2>&1 || true
    git -C "$path" checkout -q --detach origin/main >/dev/null 2>&1 || true
    git -C "$path" branch -D "$branch" >/dev/null 2>&1 || true
    any_conflict=1
    printf 'repo: %s\n' "$name"
    printf '%s\n' "conflict: revert stopped; this repo was left unchanged"
    continue
  fi
  if git -C "$path" diff --cached --quiet; then
    printf 'repo: %s\n' "$name"
    printf '%s\n' "revert: empty"
    continue
  fi
  msg=$(bot_mktemp)
  {
    printf 'Revert run %s\n\n' "$run_id"
    printf 'Reverts: %s\n' "$run_id"
  } > "$msg"
  git -C "$path" commit -F "$msg"
  revert_sha=$(git -C "$path" rev-parse HEAD)
  GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
    git -C "$path" -c credential.helper= push -u origin "$branch"
  body=$(bot_mktemp)
  {
    printf 'Revert run %s\n\n' "$run_id"
    printf '%s\n' "Commits:"
    while IFS= read -r sha; do
      printf '%s\n' "$sha"
    done < "$hits"
  } > "$body"
  pr=$(bash "$host_sh" open-pr "$name" --head "$branch" --base main \
    --title "Revert run ${run_id}" --body-file "$body")
  number=$(printf '%s' "$pr" | jq -r '.number')
  url=$(printf '%s' "$pr" | jq -r '.url // empty')
  bash "$host_sh" auto-merge "$name" "$number" >/dev/null
  printf 'repo: %s\n' "$name"
  printf 'reverted:'
  while IFS= read -r sha; do
    printf ' %s' "$sha"
  done < "$hits"
  printf '\n'
  printf 'revert_commit: %s\n' "$revert_sha"
  printf 'pr: %s\n' "$number"
  if [ -n "$url" ]; then
    printf 'url: %s\n' "$url"
  fi
done < "$repo_list"

if [ "$found_any" -ne 1 ]; then
  bot_die 2 "no commits for that run"
fi
if [ "$any_conflict" -eq 1 ]; then
  exit 3
fi
