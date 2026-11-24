#!/bin/bash
# Run one automation routine. Every commit carries Run-Id and Automation-Owner.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap auto_cleanup EXIT

usage() {
  cat << 'EOF'
Usage: run.sh <automation> <routine> [--root <dir>]

Run a routine in the automation folder. The automations switch must be on.
Commits carry Run-Id and Automation-Owner. The push goes through sync.sh.
A hand-off is refused when cloud-handoff is off. This version does not
call a cloud agent.
EOF
}

AUTO_ROOT_ARG=""
automation=""
routine=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --root)
      [ $# -ge 2 ] || auto_die 1 "--root needs a directory"
      AUTO_ROOT_ARG=$2
      export AUTO_ROOT_ARG
      shift 2
      ;;
    --)
      shift
      break
      ;;
    --*)
      auto_die 1 "unknown argument: $1"
      ;;
    *)
      if [ -z "$automation" ]; then
        automation=$1
      elif [ -z "$routine" ]; then
        routine=$1
      else
        auto_die 1 "too many arguments"
      fi
      shift
      ;;
  esac
done

[ -n "$automation" ] || auto_die 1 "automation is required"
[ -n "$routine" ] || auto_die 1 "routine is required"
auto_slug_ok "automation" "$automation"
auto_slug_ok "routine" "$routine"

AUTO_ROOT=$(auto_find_root)
export AUTO_ROOT
export OS_PROFILE
OS_PROFILE=$(auto_profile)
auto_require_switch automations

page="${AUTO_ROOT}/automations/${automation}/AUTOMATION.md"
[ -f "$page" ] || auto_die 2 "automation page is missing"
owner=$(auto_field "$page" owner) || auto_die 2 "automation page has no owner"
owner=$(auto_trim "$owner")
auto_slug_ok "owner" "$owner"

routine_file="${AUTO_ROOT}/automations/${automation}/routines/${routine}.md"
[ -f "$routine_file" ] || auto_die 2 "routine file is missing"

inbox=$(auto_field "$routine_file" inbox || true)
inbox=$(auto_trim "$inbox")
handoff=$(auto_field "$routine_file" handoff || true)
handoff=$(auto_trim "$handoff")

epoch=$(auto_now_epoch)
stamp=$(auto_now_utc "$epoch" "%Y%m%d-%H%M%S")
rand=$(openssl rand -hex 4)
run_id="${stamp}-${rand}"
day=$(auto_now_utc "$epoch" "%Y-%m-%d")
log_dir="${AUTO_ROOT}/automations/${automation}/logs"
mkdir -p "$log_dir"
log_file="${log_dir}/${day}.md"

auto_log_line() {
  printf -- '- %s run %s %s\n' "$(auto_now_utc "$epoch" "%Y-%m-%dT%H:%M:%SZ")" "$run_id" "$1" >> "$log_file"
}

if [ -n "$handoff" ] && [ "$handoff" != "none" ]; then
  auto_slug_ok "handoff" "$handoff"
  if ! auto_has_switch "cloud-handoff"; then
    auto_die 2 "cloud-handoff switch is off"
  fi
  auto_die 3 "v1 does not call a cloud agent. $(auto_handoff_rule)"
fi

scope_file=$(auto_mktemp)
auto_field "$page" repo_scope > "$scope_file" || true
while IFS= read -r line; do
  [ -n "$line" ] || continue
  scope=${line#*=}
  path=$(auto_repo_path "$AUTO_ROOT" "$scope")
  if ! auto_is_git "$path"; then
    continue
  fi
  if [ -n "$(git -C "$path" status --porcelain)" ]; then
    auto_die 2 "repo is dirty. Commit or stash before the automation run."
  fi
done < "$scope_file"

engine=$(auto_field "$page" engine || true)
engine=$(auto_trim "$engine")
if [ -z "$engine" ]; then
  engine=${OS_SYNC_ENGINE:-}
fi
if [ -z "$engine" ]; then
  engine=$(auto_field "$(auto_profile)" sync_engine || true)
  engine=$(auto_trim "$engine")
fi
[ -n "$engine" ] || auto_die 3 "no engine"

if [ -n "$inbox" ] && [ "$inbox" != "none" ]; then
  auto_slug_ok "inbox" "$inbox"
  allowed=0
  while IFS= read -r line; do
    [ "$line" = "none" ] && continue
    [ "$line" = "$inbox" ] && allowed=1
  done << EOF
$(auto_field "$page" shared_inbox || true)
EOF
  if [ "$allowed" -ne 1 ]; then
    auto_log_line "refused inbox ${inbox}"
    auto_die 2 "inbox ${inbox} is not in shared_inbox"
  fi
fi

# An automation may run in any folder --root names, a person's live folder too: nothing checks
# who `me` is. So it never works in the folder itself. Each repo in scope gets a temporary
# worktree on sync/<automation>, laid out as the folder is (the company repo, then
# areas/<area>). The company repo is always there for the automation page and the profile,
# detached when it is not in scope. The folder stays on main, as it was.
work=$(mktemp -d)
chmod 700 "$work"
AUTO_WORKTREES=""
auto_run_cleanup() {
  local entry
  for entry in $AUTO_WORKTREES; do
    git -C "${entry%%=*}" worktree remove --force "${entry#*=}" >/dev/null 2>&1 || true
    git -C "${entry%%=*}" worktree prune >/dev/null 2>&1 || true
  done
  rm -rf "$work"
  auto_cleanup
}
trap auto_run_cleanup EXIT

# Where sync/<automation> starts. A run that never reached the host (offline, a failed push)
# left commits only here: build on them, never reset them. Else the host's branch while
# its pull request has not merged. Else main.
auto_branch_start() {
  local path=$1 mine="refs/heads/sync/${automation}" theirs="refs/remotes/origin/sync/${automation}" known=""
  if git -C "$path" show-ref --verify --quiet refs/heads/main; then
    known=refs/heads/main
  fi
  # shellcheck disable=SC2086
  if git -C "$path" show-ref --verify --quiet "$mine" \
    && [ -n "$(git -C "$path" rev-list -n 1 "$mine" --not --remotes=origin $known 2>/dev/null)" ]; then
    printf '%s\n' "$mine"
  elif git -C "$path" show-ref --verify --quiet "$theirs" \
    && ! git -C "$path" merge-base --is-ancestor "$theirs" origin/main 2>/dev/null; then
    printf '%s\n' "$theirs"
  elif git -C "$path" show-ref --verify --quiet refs/remotes/origin/main; then
    printf '%s\n' origin/main
  elif git -C "$path" show-ref --verify --quiet refs/heads/main; then
    printf '%s\n' main
  else
    printf '%s\n' HEAD
  fi
}

auto_worktree() {
  local path=$1 dest=$2 start
  git -C "$path" worktree prune >/dev/null 2>&1 || true
  # An older run.sh left the folder on sync/<automation>. It is clean (checked above): back to main.
  if [ "$(git -C "$path" symbolic-ref --short -q HEAD 2>/dev/null || true)" = "sync/${automation}" ]; then
    git -C "$path" checkout -q main >/dev/null 2>&1 \
      || auto_die 2 "$(basename "$path") is on sync/${automation} and could not go back to main"
  fi
  start=$(auto_branch_start "$path")
  git -C "$path" worktree add -q -B "sync/${automation}" "$dest" "$start" >/dev/null 2>&1 \
    || auto_die 3 "could not open a worktree for $(basename "$path")"
  AUTO_WORKTREES="${AUTO_WORKTREES} ${path}=${dest}"
}

auto_is_git "$AUTO_ROOT" || auto_die 2 "the company folder is not a git repo"
scope_file=$(auto_mktemp)
auto_field "$page" repo_scope > "$scope_file" || true
company_in_scope=0
grep -q '=company$' "$scope_file" && company_in_scope=1
if [ "$company_in_scope" -eq 1 ]; then
  auto_worktree "$AUTO_ROOT" "$work"
else
  git -C "$AUTO_ROOT" worktree add -q --detach "$work" HEAD >/dev/null 2>&1 \
    || auto_die 3 "could not open a worktree for the company folder"
  AUTO_WORKTREES="${AUTO_WORKTREES} ${AUTO_ROOT}=${work}"
fi
while IFS= read -r line; do
  [ -n "$line" ] || continue
  scope=${line#*=}
  [ "$scope" != "company" ] || continue
  path=$(auto_repo_path "$AUTO_ROOT" "$scope")
  auto_is_git "$path" || continue
  auto_worktree "$path" "$(auto_repo_path "$work" "$scope")"
done < "$scope_file"

# The run's log is part of its work: it goes up on sync/<automation> with the run.
mkdir -p "${work}/automations/${automation}/logs"
log_file="${work}/automations/${automation}/logs/${day}.md"
if [ -n "$inbox" ] && [ "$inbox" != "none" ]; then
  auto_log_line "read inbox ${inbox}"
fi

hooks=$(mktemp -d)
chmod 700 "$hooks"
AUTO_TMP_FILES="${AUTO_TMP_FILES} ${hooks}"
cat > "${hooks}/prepare-commit-msg" << EOF
#!/bin/bash
set -euo pipefail
msg=\$1
clean=\$(mktemp)
grep -v -e '^Run-Id:' -e '^Automation-Owner:' -e '^Bot-Owner:' "\$msg" > "\$clean" || true
printf '\nRun-Id: %s\nAutomation-Owner: %s\n' "${run_id}" "${owner}" >> "\$clean"
cat "\$clean" > "\$msg"
rm -f "\$clean"
EOF
chmod 700 "${hooks}/prepare-commit-msg"

real_git=$(PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" command -v git)
[ -n "$real_git" ] || auto_die 3 "git is not installed"
wrap_dir=$(mktemp -d)
chmod 700 "$wrap_dir"
AUTO_TMP_FILES="${AUTO_TMP_FILES} ${wrap_dir}"
{
  printf '%s\n' "#!/bin/bash"
  printf '%s\n' "set -euo pipefail"
  printf 'export OS_REAL_GIT=%q\n' "$real_git"
  printf 'export OS_AUTOMATION_HOOKS=%q\n' "$hooks"
  printf 'export OS_AUTOMATION_LOG=%q\n' "$log_file"
  printf 'export OS_AUTOMATION=%q\n' "$automation"
  printf 'exec %q "$@"\n' "${DIR}/git-guard.sh"
} > "${wrap_dir}/git"
chmod 700 "${wrap_dir}/git"

auto_email=$(auto_field "$page" email || true)
auto_email=$(auto_trim "$auto_email")

prompt=$(auto_mktemp)
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

# OS_AUTOMATION tells sync.sh push this is the automation's branch, not the person's. The engine sees
# the worktrees as its company folder; the push runs from the folder.
export OS_AUTOMATION="$automation"
(
  cd "${work}/automations/${automation}"
  # shellcheck disable=SC2030
  export OS_ROOT="$work"
  export OS_RUN_ID="$run_id"
  export OS_AUTOMATION_OWNER="$owner"
  if [ -n "$auto_email" ]; then
    export GIT_AUTHOR_EMAIL="$auto_email"
    export GIT_COMMITTER_EMAIL="$auto_email"
  fi
  # The engine command is the admin's setting. It is not a secret.
  # shellcheck disable=SC2086
  PATH="${wrap_dir}:${PATH}" eval "$engine" < "$prompt"
  if [ "$company_in_scope" -eq 1 ] && [ -n "$(git -C "$work" status --porcelain -- "automations/${automation}/logs")" ]; then
    PATH="${wrap_dir}:${PATH}" git -C "$work" add -- "automations/${automation}/logs"
    PATH="${wrap_dir}:${PATH}" git -C "$work" commit -q -m "Log: ${automation} run ${run_id}"
  fi
)

# A change the run did not commit goes with the worktree. Say so.
for entry in $AUTO_WORKTREES; do
  left=$(git -C "${entry#*=}" status --porcelain -- . ":(exclude)automations/${automation}/logs" 2>/dev/null | grep -c . || true)
  if [ "$left" -gt 0 ]; then
    printf 'not committed: %s files in %s were left by the run and dropped\n' "$left" "$(basename "${entry%%=*}")" >&2
  fi
done

sync_sh=$(auto_sync_sh)
(
  cd "$AUTO_ROOT"
  OS_ROOT="$AUTO_ROOT" bash "$sync_sh" push
)

printf 'run_id: %s\n' "$run_id"
printf 'automation: %s\n' "$automation"
printf 'owner: %s\n' "$owner"
