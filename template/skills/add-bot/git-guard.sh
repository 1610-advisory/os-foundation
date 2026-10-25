#!/bin/bash
# Git wrapper for a bot run. Refuse a push or merge that writes main.
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
  if [ -n "${GIT_C:-}" ]; then
    "$real" -C "$GIT_C" rev-parse --abbrev-ref HEAD 2>/dev/null || true
  else
    "$real" rev-parse --abbrev-ref HEAD 2>/dev/null || true
  fi
}

guard_dest() {
  local spec=$1 dest
  spec=${spec#+}
  case "$spec" in
    *:*) dest=${spec#*:} ;;
    *) dest=$spec ;;
  esac
  dest=${dest#refs/heads/}
  if [ "$dest" = "HEAD" ]; then
    dest=$(guard_branch)
  fi
  printf '%s\n' "$dest"
}

guard_is_main() {
  case "$1" in
    main|master) return 0 ;;
    *) return 1 ;;
  esac
}

args=("$@")
n=${#args[@]}
i=0
GIT_C=""
sub=""
while [ "$i" -lt "$n" ]; do
  arg=${args[$i]}
  case "$arg" in
    -C)
      i=$((i + 1))
      GIT_C=${args[$i]:-}
      [ -n "$GIT_C" ] || guard_refuse "git -C needs a directory"
      ;;
    -c|--git-dir|--work-tree|--namespace)
      i=$((i + 1))
      ;;
    --git-dir=*|--work-tree=*|--namespace=*)
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

if [ "$sub" = "merge" ]; then
  branch=$(guard_branch)
  if guard_is_main "$branch"; then
    guard_refuse "merge into ${branch}"
  fi
fi

if [ "$sub" = "push" ]; then
  all=0
  specs=""
  seen_remote=0
  while [ "$i" -lt "$n" ]; do
    arg=${args[$i]}
    case "$arg" in
      --all|--mirror)
        all=1
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
            *:*|+*|main|master|HEAD|refs/heads/main|refs/heads/master)
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
  if [ "$all" -eq 1 ]; then
    guard_refuse "push of every branch can write main"
  fi
  if [ -z "$specs" ]; then
    branch=$(guard_branch)
    if guard_is_main "$branch"; then
      guard_refuse "push of ${branch}"
    fi
  fi
  spec=""
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    dest=$(guard_dest "$spec")
    if guard_is_main "$dest"; then
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
