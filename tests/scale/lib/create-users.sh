#!/bin/sh
# Create Forgejo users from stdin, one username per line.
# The password is generated inside Forgejo (--random-password) and discarded.
# No token, password, or other secret is placed on a command line.
set -eu

admin=0
if [ "${1:-}" = "--admin" ]; then
  admin=1
  shift
fi
if [ "$#" -ne 0 ]; then
  echo "FAIL: usage" >&2
  exit 1
fi

while IFS= read -r username; do
  [ -n "$username" ] || continue
  case "$username" in
    *[!a-z0-9-]*)
      echo "FAIL: bad username" >&2
      exit 1
      ;;
  esac
  email="${username}@scale.example"
  err=$(mktemp)
  set -- forgejo admin user create \
    --username "$username" \
    --email "$email" \
    --random-password
  if [ "$admin" -eq 1 ]; then
    set -- "$@" --admin
  fi
  if [ "${OSF_MUST_CHANGE:-}" = "0" ]; then
    set -- "$@" --must-change-password=false
  fi
  if ! "$@" </dev/null >"$err" 2>&1; then
    if grep -Eiq 'already exists|name is reserved|user already' "$err"; then
      rm -f "$err"
      echo "exists ${username}"
      continue
    fi
    # The temp file may hold a generated password. Do not print it.
    rm -f "$err"
    echo "FAIL: create ${username}" >&2
    exit 1
  fi
  rm -f "$err"
  echo "created ${username}"
done
