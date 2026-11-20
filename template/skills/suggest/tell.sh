#!/bin/bash
# "Tell 1610": send one short note about the OS (what was confusing or broken, which step,
# the OS version) to the people who make os-foundation. The agent runs it only after the
# person read the note and said yes. No company data, names or file contents in the note.
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: tell.sh --file <note.txt> --yes

Sends the note as plain text to https://1610.sh/os/feedback (at most 2,000 characters).
--yes means the person read this exact note and said yes. Without it, nothing is sent.
The note goes through the secret scan first. A hit sends nothing.
If the address does not answer, the note and a place to paste it are printed instead.
Exit 0: sent. Exit 1: usage, empty or too long. Exit 2: secret scan hit or error.
Exit 3: not sent (no network, or the address is not there); paste it by hand.
EOF
}

FILE=""
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --file) [ $# -ge 2 ] || { usage >&2; exit 1; }; FILE=$2; shift 2 ;;
    --yes) YES=1; shift ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$FILE" ] || { usage >&2; exit 1; }
[ -f "$FILE" ] || { printf 'tell: the note file is missing\n' >&2; exit 1; }
grep -q '[^[:space:]]' "$FILE" || { printf 'tell: the note is empty\n' >&2; exit 1; }
chars=$(LC_ALL=en_US.UTF-8 wc -m < "$FILE" | tr -d ' ')
if [ "$chars" -gt 2000 ]; then
  printf 'tell: the note has %s characters; make it 2,000 or fewer\n' "$chars" >&2
  exit 1
fi
if [ "$YES" -ne 1 ]; then
  printf 'tell: not sent. Show the person the note, wait for a clear yes, then run again with --yes\n' >&2
  exit 1
fi

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCAN="$DIR/../sync/secret-scan.sh"
if [ -f "$SCAN" ]; then
  set +e
  bash "$SCAN" --files -- "$FILE" >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    printf 'tell: not sent: the secret scan flagged the note (or could not run). Remove the secret and show the note again.\n' >&2
    exit 2
  fi
fi

URL=${OS_FEEDBACK_URL:-https://1610.sh/os/feedback}
PASTE="https://github.com/1610-advisory/os-foundation/issues/new"
code=""
if command -v curl >/dev/null 2>&1; then
  set +e
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -X POST \
    -H 'content-type: text/plain; charset=utf-8' --data-binary "@$FILE" "$URL" 2>/dev/null)
  set -e
fi
case "$code" in
  2??)
    printf 'tell: sent. Thank you.\n'
    exit 0
    ;;
esac
printf 'tell: not sent: %s did not take it. Paste the note below at %s\n\n' "$URL" "$PASTE"
cat "$FILE"
printf '\n'
exit 3
