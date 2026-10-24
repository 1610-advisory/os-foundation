#!/bin/bash
# Shared helpers for the check scripts. Source this file. Do not run it.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf '%s\n' "Source this file from the check scripts. Do not run it."
    exit 0
  fi
  printf '%s\n' "Source this file from the check scripts. Do not run it." >&2
  exit 1
fi

ci_die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

ci_tmp_files=""

ci_mktemp() {
  local f
  f=$(mktemp)
  chmod 600 "$f"
  ci_tmp_files="${ci_tmp_files} ${f}"
  printf '%s\n' "$f"
}

ci_cleanup() {
  local f
  # shellcheck disable=SC2086
  for f in $ci_tmp_files; do
    rm -f "$f"
  done
  ci_tmp_files=""
}

ci_scrub_file() {
  local file=$1 secret=$2
  if [ ! -f "$file" ]; then
    return 0
  fi
  if [ -z "$secret" ]; then
    cat "$file"
    return 0
  fi
  awk -v secret="$secret" '
    {
      line = $0
      out = ""
      while (index(line, secret) > 0) {
        i = index(line, secret)
        out = out substr(line, 1, i - 1) "<redacted>"
        line = substr(line, i + length(secret))
      }
      print out line
    }
  ' "$file"
}

ci_state_dir() {
  local dir
  dir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
  dir="${dir}/os-ci"
  mkdir -p "$dir"
  chmod 700 "$dir"
  printf '%s\n' "$dir"
}

ci_write_state() {
  local key=$1 value=$2 dir
  dir=$(ci_state_dir)
  printf '%s\n' "$value" > "${dir}/${key}"
  chmod 600 "${dir}/${key}"
}

ci_read_state() {
  local key=$1 dir file
  dir=$(ci_state_dir)
  file="${dir}/${key}"
  if [ ! -f "$file" ]; then
    return 1
  fi
  tr -d '\r\n' < "$file"
}

ci_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

ci_trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Git reads the token from the environment, not from a command argument.
ci_git() {
  if [ -z "${JOB_TOKEN:-}" ]; then
    ci_die 1 "checkout failed: the job token is missing"
  fi
  GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=http.extraHeader \
    GIT_CONFIG_VALUE_0="Authorization: token ${JOB_TOKEN}" \
    GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= "$@"
}

ci_is_github() {
  case "${GITHUB_SERVER_URL:-}" in
    *://github.com|*://www.github.com|*://github.com/*) return 0 ;;
  esac
  return 1
}

ci_api_base() {
  local api
  api=${GITHUB_API_URL:-}
  case "$api" in
    */api/v1|https://api.github.com|https://api.github.com/)
      printf '%s\n' "${api%/}"
      return 0
      ;;
  esac
  if ci_is_github; then
    printf '%s\n' "https://api.github.com"
    return 0
  fi
  printf '%s\n' "${GITHUB_SERVER_URL%/}/api/v1"
}

ci_auth_header() {
  local token=$1
  if ci_is_github; then
    printf '%s\n' "Authorization: Bearer ${token}"
  else
    printf '%s\n' "Authorization: token ${token}"
  fi
}

ci_summary_add() {
  local text=$1
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "$text" >> "$GITHUB_STEP_SUMMARY"
  fi
  printf '%s\n' "$text"
}
