#!/bin/bash
# Shared helpers for the check scripts. Source this file. Do not run it.
# The mktemp function below wraps the system one. Calls with no arguments are on purpose.
# shellcheck disable=SC2119,SC2120

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
# ci_mktemp runs in $( ), so the list above never reaches this shell. Every temp file goes
# in one folder made here instead, and ci_cleanup (the entry script's EXIT trap) removes it.
# A runner that is not thrown away after each job keeps a clean temp folder.
# A second source in the same shell keeps the first folder.
if [ -z "${ci_run_tmp:-}" ] || [ ! -d "$ci_run_tmp" ]; then
  ci_run_tmp=$(command mktemp -d "${TMPDIR:-/tmp}/os-check.XXXXXX") || ci_die 1 "could not make a temp folder"
  chmod 700 "$ci_run_tmp"
  export TMPDIR="$ci_run_tmp"
fi
# macOS mktemp ignores TMPDIR. With no template, make the file in TMPDIR (the run folder).
mktemp() {
  if [ $# -eq 0 ]; then
    command mktemp "${TMPDIR:-/tmp}/tmp.XXXXXXXX"
  elif [ $# -eq 1 ] && [ "$1" = "-d" ]; then
    command mktemp -d "${TMPDIR:-/tmp}/tmp.XXXXXXXX"
  else
    command mktemp "$@"
  fi
}

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
  rm -rf "$ci_run_tmp"
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

# Git over HTTP on GitHub takes only basic auth: x-access-token and the token.
# Forgejo takes the same form. printf is a shell builtin, so the token is never an argument.
ci_git_header() {
  local b64
  b64=$(printf '%s' "x-access-token:${JOB_TOKEN}" | base64 | tr -d '\r\n')
  printf '%s' "Authorization: basic ${b64}"
}

# Git reads the token from the environment, not from a command argument.
ci_git() {
  if [ -z "${JOB_TOKEN:-}" ]; then
    ci_die 1 "checkout failed: the job token is missing"
  fi
  GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=http.extraHeader \
    GIT_CONFIG_VALUE_0="$(ci_git_header)" \
    GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= "$@"
}

# kind is glob (GitHub CODEOWNERS) or regex (Forgejo CODEOWNERS).
# Exit 0 when the pattern matches the path. Anchored on path boundaries.
ci_path_match() {
  local kind=$1 pattern=$2 path=$3
  awk -v kind="$kind" -v pat="$pattern" -v path="$path" '
    function gm(p, s,   rest, n) {
      if (p == "" ) return s == ""
      if (substr(p, 1, 2) == "**") {
        rest = substr(p, 3)
        if (substr(rest, 1, 1) == "/") rest = substr(rest, 2)
        if (gm(rest, s)) return 1
        n = index(s, "/")
        if (n == 0) return gm(rest, "")
        return gm(p, substr(s, n + 1))
      }
      if (substr(p, 1, 1) == "*") {
        rest = substr(p, 2)
        if (gm(rest, s)) return 1
        if (s != "" && substr(s, 1, 1) != "/") return gm(p, substr(s, 2))
        return 0
      }
      if (s == "" || substr(p, 1, 1) != substr(s, 1, 1)) return 0
      return gm(substr(p, 2), substr(s, 2))
    }
    BEGIN {
      if (kind == "regex") {
        if (substr(pat, 1, 1) != "^") pat = "^(" pat ")$"
        if (path ~ pat) exit 0
        exit 1
      }
      anchored = 0
      if (substr(pat, 1, 1) == "/") {
        anchored = 1
        pat = substr(pat, 2)
      }
      if (pat != "" && substr(pat, length(pat), 1) == "/") {
        pat = substr(pat, 1, length(pat) - 1)
        if (index(path, pat) == 1 && (length(path) == length(pat) || substr(path, length(pat) + 1, 1) == "/")) exit 0
        exit 1
      }
      if (anchored || index(pat, "/") > 0) {
        if (gm(pat, path)) exit 0
        exit 1
      }
      if (gm(pat, path)) exit 0
      n = split(path, segs, "/")
      acc = ""
      for (i = n; i >= 1; i--) {
        if (acc == "") acc = segs[i]
        else acc = segs[i] "/" acc
        if (gm(pat, acc)) exit 0
      }
      exit 1
    }
  '
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
