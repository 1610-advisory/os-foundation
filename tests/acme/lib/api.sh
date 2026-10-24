#!/usr/bin/env bash
# Forgejo HTTP helpers. Source after common.sh.
# Writes status to OSF_HTTP_CODE and the body path to OSF_HTTP_BODY.
# The body file is mode 0600. The caller deletes it. Tokens are not printed.

# shellcheck disable=SC1091
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

osf_api() {
  local token_file="$1"
  local method="$2"
  local path="$3"
  local body_file="${4:-}"
  local cfg out token url
  if [ ! -f "$token_file" ]; then
    echo "FAIL: token file missing for API call" >&2
    return 1
  fi
  cfg=$(mktemp)
  out=$(mktemp)
  chmod 600 "$cfg" "$out"
  token=$(tr -d '[:space:]' < "$token_file")
  url="$(osf_acme_url)${path}"
  {
    printf 'silent\n'
    printf 'show-error\n'
    printf 'max-time = 60\n'
    printf 'url = "%s"\n' "$url"
    printf 'request = "%s"\n' "$method"
    printf 'header = "Authorization: token %s"\n' "$token"
    printf 'header = "Content-Type: application/json"\n'
    if [ -n "$body_file" ]; then
      printf 'data = "@%s"\n' "$body_file"
    fi
    printf 'output = "%s"\n' "$out"
    printf 'write-out = "%%{http_code}"\n'
  } > "$cfg"
  token=""
  OSF_HTTP_CODE=$(curl --config "$cfg" || true)
  rm -f "$cfg"
  OSF_HTTP_BODY=$out
}

osf_api_discard() {
  if [ -n "${OSF_HTTP_BODY:-}" ] && [ -f "$OSF_HTTP_BODY" ]; then
    rm -f "$OSF_HTTP_BODY"
  fi
  OSF_HTTP_BODY=""
  # Callers read this after the function returns.
  # shellcheck disable=SC2034
  OSF_HTTP_CODE=""
}
