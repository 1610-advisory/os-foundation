#!/bin/bash
# Run one bot routine. Every commit carries Run-Id and Bot-Owner.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap bot_cleanup EXIT

usage() {
  cat << 'EOF'
Usage: run.sh <bot> <routine> [--root <dir>]

Run a routine in the bot folder. The bots switch must be on.
Commits carry Run-Id and Bot-Owner. The push goes through sync.sh.
A hand-off is refused when cloud-handoff is off. This version does not
call a cloud agent.
EOF
}

BOT_ROOT_ARG=""
bot=""
routine=""

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
      if [ -z "$bot" ]; then
        bot=$1
      elif [ -z "$routine" ]; then
        routine=$1
      else
        bot_die 1 "too many arguments"
      fi
      shift
      ;;
  esac
done

[ -n "$bot" ] || bot_die 1 "bot is required"
[ -n "$routine" ] || bot_die 1 "routine is required"
bot_slug_ok "bot" "$bot"
bot_slug_ok "routine" "$routine"

BOT_ROOT=$(bot_find_root)
export BOT_ROOT
export OS_PROFILE
OS_PROFILE=$(bot_profile)
bot_require_switch bots

page="${BOT_ROOT}/bots/${bot}/BOT.md"
[ -f "$page" ] || bot_die 2 "bot page is missing"
owner=$(bot_field "$page" owner) || bot_die 2 "bot page has no owner"
owner=$(bot_trim "$owner")
bot_slug_ok "owner" "$owner"

routine_file="${BOT_ROOT}/bots/${bot}/routines/${routine}.md"
[ -f "$routine_file" ] || bot_die 2 "routine file is missing"

inbox=$(bot_field "$routine_file" inbox || true)
inbox=$(bot_trim "$inbox")
handoff=$(bot_field "$routine_file" handoff || true)
handoff=$(bot_trim "$handoff")

epoch=$(bot_now_epoch)
stamp=$(bot_now_utc "$epoch" "%Y%m%d-%H%M%S")
rand=$(openssl rand -hex 4)
run_id="${stamp}-${rand}"
day=$(bot_now_utc "$epoch" "%Y-%m-%d")
log_dir="${BOT_ROOT}/bots/${bot}/logs"
mkdir -p "$log_dir"
log_file="${log_dir}/${day}.md"

bot_log_line() {
  printf -- '- %s run %s %s\n' "$(bot_now_utc "$epoch" "%Y-%m-%dT%H:%M:%SZ")" "$run_id" "$1" >> "$log_file"
}

if [ -n "$handoff" ] && [ "$handoff" != "none" ]; then
  bot_slug_ok "handoff" "$handoff"
  if ! bot_has_switch "cloud-handoff"; then
    bot_die 2 "cloud-handoff switch is off"
  fi
  bot_die 3 "v1 does not call a cloud agent. $(bot_handoff_rule)"
fi

scope_file=$(bot_mktemp)
bot_field "$page" repo_scope > "$scope_file" || true
while IFS= read -r line; do
  [ -n "$line" ] || continue
  scope=${line#*=}
  path=$(bot_repo_path "$BOT_ROOT" "$scope")
  if ! bot_is_git "$path"; then
    continue
  fi
  if [ -n "$(git -C "$path" status --porcelain)" ]; then
    bot_die 2 "repo is dirty. Commit or stash before the bot run."
  fi
done < "$scope_file"

engine=$(bot_field "$page" engine || true)
engine=$(bot_trim "$engine")
if [ -z "$engine" ]; then
  engine=${OS_SYNC_ENGINE:-}
fi
if [ -z "$engine" ]; then
  engine=$(bot_field "$(bot_profile)" sync_engine || true)
  engine=$(bot_trim "$engine")
fi
[ -n "$engine" ] || bot_die 3 "no engine"

hooks=$(mktemp -d)
chmod 700 "$hooks"
BOT_TMP_FILES="${BOT_TMP_FILES} ${hooks}"
cat > "${hooks}/prepare-commit-msg" << EOF
#!/bin/bash
set -euo pipefail
msg=\$1
clean=\$(mktemp)
grep -v -e '^Run-Id:' -e '^Bot-Owner:' "\$msg" > "\$clean" || true
printf '\nRun-Id: %s\nBot-Owner: %s\n' "${run_id}" "${owner}" >> "\$clean"
cat "\$clean" > "\$msg"
rm -f "\$clean"
EOF
chmod 700 "${hooks}/prepare-commit-msg"

real_git=$(PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" command -v git)
[ -n "$real_git" ] || bot_die 3 "git is not installed"
wrap_dir=$(mktemp -d)
chmod 700 "$wrap_dir"
BOT_TMP_FILES="${BOT_TMP_FILES} ${wrap_dir}"
{
  printf '%s\n' "#!/bin/bash"
  printf '%s\n' "set -euo pipefail"
  printf 'export OS_REAL_GIT=%q\n' "$real_git"
  printf 'export OS_BOT_HOOKS=%q\n' "$hooks"
  printf 'export OS_BOT_LOG=%q\n' "$log_file"
  printf 'export OS_BOT=%q\n' "$bot"
  printf 'exec %q "$@"\n' "${DIR}/git-guard.sh"
} > "${wrap_dir}/git"
chmod 700 "${wrap_dir}/git"

bot_email=$(bot_field "$page" email || true)
bot_email=$(bot_trim "$bot_email")

scope_file=$(bot_mktemp)
bot_field "$page" repo_scope > "$scope_file" || true
while IFS= read -r line; do
  [ -n "$line" ] || continue
  scope=${line#*=}
  path=$(bot_repo_path "$BOT_ROOT" "$scope")
  if ! bot_is_git "$path"; then
    continue
  fi
  if git -C "$path" show-ref --verify --quiet "refs/remotes/origin/main"; then
    git -C "$path" checkout -B "sync/${bot}" "origin/main"
  elif git -C "$path" show-ref --verify --quiet refs/heads/main; then
    git -C "$path" checkout -B "sync/${bot}" main
  fi
done < "$scope_file"

if [ -n "$inbox" ] && [ "$inbox" != "none" ]; then
  bot_slug_ok "inbox" "$inbox"
  allowed=0
  while IFS= read -r line; do
    [ "$line" = "none" ] && continue
    [ "$line" = "$inbox" ] && allowed=1
  done << EOF
$(bot_field "$page" shared_inbox || true)
EOF
  if [ "$allowed" -ne 1 ]; then
    bot_log_line "refused inbox ${inbox}"
    bot_die 2 "inbox ${inbox} is not in shared_inbox"
  fi
  bot_log_line "read inbox ${inbox}"
fi

prompt=$(bot_mktemp)
awk '
  BEGIN { fm = 0; n = 0 }
  /^---[[:space:]]*$/ {
    n++
    if (n == 1) { fm = 1; next }
    if (n == 2) { fm = 0; next }
  }
  fm { next }
  { print }
' "$routine_file" > "$prompt"

# OS_BOT tells sync.sh push this is the bot's branch, not the person's.
export OS_BOT="$bot"
export OS_ROOT="$BOT_ROOT"
(
  cd "${BOT_ROOT}/bots/${bot}"
  export OS_RUN_ID="$run_id"
  export OS_BOT_OWNER="$owner"
  if [ -n "$bot_email" ]; then
    export GIT_AUTHOR_EMAIL="$bot_email"
    export GIT_COMMITTER_EMAIL="$bot_email"
  fi
  # The engine command is the admin's setting. It is not a secret.
  # shellcheck disable=SC2086
  PATH="${wrap_dir}:${PATH}" eval "$engine" < "$prompt"
)

sync_sh=$(bot_sync_sh)
(
  cd "$BOT_ROOT"
  bash "$sync_sh" push
)

printf 'run_id: %s\n' "$run_id"
printf 'bot: %s\n' "$bot"
printf 'owner: %s\n' "$owner"
