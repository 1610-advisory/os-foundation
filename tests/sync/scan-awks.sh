#!/bin/bash
# Same known-bad fixtures under the awk on PATH.
# Outside a container, also runs bookworm mawk, stable mawk, and gawk.
# Prints rule ids and PASS/FAIL. Never prints a fixture value.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
scan=${SCAN_SH:-$root/template/skills/sync/secret-scan.sh}

write_fixtures() {
  local dir=$1
  printf '%s%s%s\n' 'gh' 'p_' "$(printf 'ab12%.0s' 1 2 3 4 5 6 7 8 9)" > "$dir/gh.txt"
  printf '%s%s%s\n' 'github' '_pat_' 'abcdefghij1234567890ab' > "$dir/fine.txt"
  printf '%s%s%s\n' 'xo' 'xb-' '1234567890abcdef' > "$dir/slack-b.txt"
  printf '%s%s%s\n' 'xo' 'xa-' '1234567890abcdef' > "$dir/slack-a.txt"
  printf '%s%s%s\n' 'xo' 'xp-' '1234567890abcdef' > "$dir/slack-p.txt"
  printf '%s%s%s\n' 'xo' 'xr-' '1234567890abcdef' > "$dir/slack-r.txt"
  printf '%s%s%s\n' 'xo' 'xs-' '1234567890abcdef' > "$dir/slack-s.txt"
  printf '%s%s%s\n' 'AK' 'IA' '0123456789ABCDEF' > "$dir/aws.txt"
  printf '%s\n' 'token = abcdefghijklmnop' > "$dir/generic.txt"
  printf '%s\n' 'api_key=abcdefghijklmnop' > "$dir/api-key.txt"
  printf '%s%s%s\n' 'token = "' "$(printf 'e%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)" '"' > "$dir/quoted.txt"
  printf '%s\n' 'password = aB3xQ9mZ2kL8pR4sT6uV1wY5nC7dE0fG2hJ4' > "$dir/entropy.txt"
  printf '%s%s\n' '-----BE' 'GIN OPENSSH PRIVATE KEY-----' > "$dir/pk1.txt"
  printf '%s%s\n' '-----BE' 'GIN RSA PRIVATE KEY-----' > "$dir/pk2.txt"
  printf '%s\n' 'notes: no secret here' > "$dir/clean.txt"
  printf '%s\n' 'password = short' > "$dir/short.txt"
  printf '%s%s\n' '-----BE' 'GIN OPENSSH' > "$dir/half.txt"
}

run_set() {
  local label=$1
  local dir name expect out rc fail
  dir=$(mktemp -d)
  chmod 700 "$dir"
  write_fixtures "$dir"
  fail=0
  for name in gh.txt fine.txt slack-b.txt slack-a.txt slack-p.txt slack-r.txt slack-s.txt aws.txt generic.txt api-key.txt quoted.txt entropy.txt pk1.txt pk2.txt; do
    case "$name" in
      gh.txt|fine.txt) expect=github-pat ;;
      slack-*) expect=slack-bot-token ;;
      aws.txt) expect=aws-access-key ;;
      generic.txt|api-key.txt|quoted.txt) expect=generic-api-key ;;
      entropy.txt) expect=high-entropy ;;
      pk1.txt|pk2.txt) expect=private-key ;;
      *) expect=missing ;;
    esac
    set +e
    out=$(OS_SECRET_SCAN=bundled bash "$scan" --files -- "$dir/$name" 2>"$dir/err")
    rc=$?
    set -e
    if [ "$rc" -ne 1 ] || ! printf '%s\n' "$out" | grep -q ":${expect}$"; then
      echo "FAIL $label $name rc=$rc"
      fail=1
    elif printf '%s\n' "$out" | grep -F -q -f "$dir/$name"; then
      echo "FAIL $label $name leaked"
      fail=1
    fi
  done
  for name in clean.txt short.txt half.txt; do
    set +e
    out=$(OS_SECRET_SCAN=bundled bash "$scan" --files -- "$dir/$name" 2>"$dir/err")
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      echo "FAIL $label $name rc=$rc"
      fail=1
    fi
  done
  rm -rf "$dir"
  if [ "$fail" -ne 0 ]; then
    echo "FAIL $label"
    return 1
  fi
  echo "PASS $label"
}

if [ "${1:-}" = "--in-container" ]; then
  run_set "${2:-container}"
  exit 0
fi

run_set "bsd"
if ! command -v docker >/dev/null 2>&1; then
  echo "BLOCKED: docker"
  exit 2
fi

script=$here/scan-awks.sh
docker run --rm \
  -e SCAN_SH=/scan.sh \
  -v "$scan":/scan.sh:ro \
  -v "$script":/scan-awks.sh:ro \
  debian:bookworm-slim \
  bash /scan-awks.sh --in-container bookworm-mawk

docker run --rm \
  -e SCAN_SH=/scan.sh \
  -e DEBIAN_FRONTEND=noninteractive \
  -v "$scan":/scan.sh:ro \
  -v "$script":/scan-awks.sh:ro \
  debian:stable-slim \
  bash -c 'apt-get update -qq && apt-get install -qq -y mawk gawk >/dev/null && update-alternatives --set awk /usr/bin/mawk >/dev/null && bash /scan-awks.sh --in-container stable-mawk && update-alternatives --set awk /usr/bin/gawk >/dev/null && bash /scan-awks.sh --in-container gawk'
