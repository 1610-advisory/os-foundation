#!/bin/bash
# Git wrapper for a bot run. A push may only write sync/<bot> or undo/*.
set -euo pipefail

real=${OS_REAL_GIT:-}
if [ -z "$real" ]; then
  real=$(PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" command -v git || true)
fi
[ -n "$real" ] || {
  printf '%s\n' "git is not installed" >&2
  exit 3
}

guard_log() {
  printf '%s\n' "$*" >&2
  if [ -n "${OS_BOT_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$OS_BOT_LOG"
  fi
}

guard_refuse() {
  guard_log "refused: $*"
  exit 1
}

guard_branch() {
  extra=()
  if [ -n "${GIT_DIR_OPT:-}" ]; then
    extra+=(--git-dir "$GIT_DIR_OPT")
  fi
  if [ -n "${GIT_WORK_OPT:-}" ]; then
    extra+=(--work-tree "$GIT_WORK_OPT")
  fi
  if [ -n "${GIT_C:-}" ]; then
    extra+=(-C "$GIT_C")
  fi
  "$real" "${extra[@]}" rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

guard_is_main() {
  case "$1" in
    main|master) return 0 ;;
    *) return 1 ;;
  esac
}

# Allow only refs/heads/sync/<bot> and refs/heads/undo/*. Wildcards are not allowed.
guard_allowed() {
  local short=$1 bot=${OS_BOT:-}
  short=${short#refs/heads/}
  case "$short" in
    *'*'*|*'?'*|*'['*) return 1 ;;
    undo/*) return 0 ;;
  esac
  if [ -n "$bot" ] && [ "$short" = "sync/${bot}" ]; then
    return 0
  fi
  return 1
}

guard_dest() {
  local spec=$1 dest
  spec=${spec#+}
  case "$spec" in
    :*)
      guard_refuse "push delete is not allowed"
      ;;
  esac
  case "$spec" in
    *:*) dest=${spec#*:} ;;
    *) dest=$spec ;;
  esac
  if [ "$dest" = "HEAD" ]; then
    dest=$(guard_branch)
  fi
  printf '%s\n' "$dest"
}

args=("$@")
n=${#args[@]}
i=0
GIT_C=""
GIT_DIR_OPT=""
GIT_WORK_OPT=""
sub=""
while [ "$i" -lt "$n" ]; do
  arg=${args[$i]}
  case "$arg" in
    -C)
      i=$((i + 1))
      GIT_C=${args[$i]:-}
      [ -n "$GIT_C" ] || guard_refuse "git -C needs a directory"
      ;;
    --git-dir)
      i=$((i + 1))
      GIT_DIR_OPT=${args[$i]:-}
      [ -n "$GIT_DIR_OPT" ] || guard_refuse "git --git-dir needs a directory"
      ;;
    --git-dir=*)
      GIT_DIR_OPT=${arg#--git-dir=}
      ;;
    --work-tree)
      i=$((i + 1))
      GIT_WORK_OPT=${args[$i]:-}
      [ -n "$GIT_WORK_OPT" ] || guard_refuse "git --work-tree needs a directory"
      ;;
    --work-tree=*)
      GIT_WORK_OPT=${arg#--work-tree=}
      ;;
    -c|--namespace)
      i=$((i + 1))
      ;;
    --namespace=*)
      ;;
    -*)
      ;;
    *)
      sub=$arg
      i=$((i + 1))
      break
      ;;
  esac
  i=$((i + 1))
done

case "$sub" in
  merge|pull|rebase)
    branch=$(guard_branch)
    if guard_is_main "$branch"; then
      guard_refuse "${sub} into ${branch}"
    fi
    ;;
esac

if [ "$sub" = "push" ]; then
  blocked=0
  specs=""
  seen_remote=0
  while [ "$i" -lt "$n" ]; do
    arg=${args[$i]}
    case "$arg" in
      --all|--mirror|--tags|--delete)
        blocked=1
        ;;
      --)
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          specs="${specs}
${args[$i]}"
          i=$((i + 1))
        done
        break
        ;;
      --repo|--exec|--receive-pack|-o)
        i=$((i + 1))
        ;;
      -*)
        ;;
      *)
        if [ "$seen_remote" -eq 0 ]; then
          case "$arg" in
            *:*|+*|main|master|HEAD|refs/heads/*|refs/tags/*)
              specs="${specs}
${arg}"
              ;;
            *)
              seen_remote=1
              ;;
          esac
        else
          specs="${specs}
${arg}"
        fi
        ;;
    esac
    i=$((i + 1))
  done
  if [ "$blocked" -eq 1 ]; then
    guard_refuse "push of every ref is not allowed"
  fi
  if [ -z "$specs" ]; then
    branch=$(guard_branch)
    if ! guard_allowed "$branch"; then
      guard_refuse "push of ${branch:-unknown}"
    fi
  fi
  spec=""
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    dest=$(guard_dest "$spec")
    if ! guard_allowed "$dest"; then
      guard_refuse "push destination ${dest}"
    fi
  done << EOF
$specs
EOF
fi

if [ -n "${OS_BOT_HOOKS:-}" ]; then
  exec "$real" -c "core.hooksPath=${OS_BOT_HOOKS}" "${args[@]}"
fi
exec "$real" "${args[@]}"
