#!/usr/bin/env bash
# Set the remote-setup defaults (defaults.txt, next to this file) in ~/.claude/settings.json.
# Keeps every other key. Makes the file when it is missing. Changes nothing when the file
# is not valid JSON. Prints the old and the new value of each setting.
# Exit 0 when done, 1 when the file is not valid JSON or no JSON tool is found.
set -u

DIR=$(cd "$(dirname "$0")" && pwd)
DEFAULTS="$DIR/defaults.txt"
SETTINGS="$HOME/.claude/settings.json"

# The JSON tool: jq (macOS 15 and later have it), else plutil on a Mac, else python3.
tool=${REMOTE_SETUP_JSON:-}
if [ -z "$tool" ]; then
  if command -v jq >/dev/null 2>&1; then tool=jq
  elif [ "$(uname -s)" = Darwin ] && command -v plutil >/dev/null 2>&1; then tool=plutil
  elif command -v python3 >/dev/null 2>&1; then tool=python3
  else echo "set-settings: no JSON tool found (jq or python3). Install jq, then run this again." >&2; exit 1
  fi
fi

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
cur="$work/settings.json"

if [ -s "$SETTINGS" ] && grep -q '[^[:space:]]' "$SETTINGS"; then
  cat "$SETTINGS" > "$cur"
else
  printf '{}\n' > "$cur"
fi

# Print the value of key $1 as JSON, or nothing when the key is not there.
get() {
  case "$tool" in
    jq) jq -c --arg k "$1" 'if has($k) then .[$k] else empty end' "$cur" ;;
    plutil) plutil -extract "$1" raw -o - "$cur" 2>/dev/null ;;
    python3) python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
if sys.argv[2] in d: print(json.dumps(d[sys.argv[2]]))' "$cur" "$1" ;;
  esac
}

# Set key $1 to the JSON value $2.
put() {
  case "$tool" in
    jq) jq --arg k "$1" --argjson v "$2" '.[$k] = $v' "$cur" > "$work/next" && mv "$work/next" "$cur" ;;
    plutil) plutil -replace "$1" -json "$2" "$cur" ;;
    python3) python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d[sys.argv[2]]=json.loads(sys.argv[3])
open(p,"w").write(json.dumps(d,indent=2)+"\n")' "$cur" "$1" "$2" ;;
  esac
}

# The file must be one JSON object.
case "$tool" in
  jq) jq -e 'type == "object"' "$cur" >/dev/null 2>&1 ;;
  plutil) plutil -convert json -o /dev/null "$cur" >/dev/null 2>&1 && [ "$(plutil -p "$cur" 2>/dev/null | head -c 1)" = '{' ] ;;
  python3) python3 -c 'import json,sys; sys.exit(0 if isinstance(json.load(open(sys.argv[1])),dict) else 1)' "$cur" 2>/dev/null ;;
esac || { echo "set-settings: $SETTINGS is not a valid JSON object. Nothing changed. Fix the file, then run this again." >&2; exit 1; }
# plutil reads "{}" as an old plist format and cannot write it back. Work in XML, then write JSON.
if [ "$tool" = plutil ]; then
  plutil -convert xml1 "$cur" || { echo "set-settings: plutil cannot read $SETTINGS. Install jq, then run this again." >&2; exit 1; }
fi

changed=0
while IFS='=' read -r key val; do
  key=${key%$'\r'}; val=${val%$'\r'}
  case "$key" in ''|'#'*) continue ;; esac
  old=$(get "$key")
  if [ "$old" = "$val" ]; then
    echo "$key: already $val."
    continue
  fi
  put "$key" "$val" || { echo "set-settings: could not set $key. Nothing changed." >&2; exit 1; }
  echo "$key: set to $val (was ${old:-not set})."
  changed=1
done < "$DEFAULTS"

if [ "$changed" = 1 ]; then
  if [ "$tool" = plutil ]; then plutil -convert json -r "$cur" || exit 1; fi
  mkdir -p "$(dirname "$SETTINGS")"
  # Write through the file, so a symlinked settings.json stays a symlink.
  cat "$cur" > "$SETTINGS"
fi
exit 0
