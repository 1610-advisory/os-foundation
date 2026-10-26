#!/bin/bash
# Merge one rules file. Keep company lines. Bash 3.2. No network.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat << 'EOF'
usage: rules-merge.sh --base <file> --real <file> --v1 <file> --scope <name> --out <file> [--values <file>] [--map <file>] [--plain <file>] [--spill <file>] [--score]

Prints company-lines and matched. Writes the merged file unless --score.
EOF
}

BASE=""
REAL=""
V1=""
SCOPE="company"
OUT=""
VALUES=""
MAP="$DIR/rules-map.txt"
PLAIN=""
SPILL=""
SCORE=0
ROLE="company"
LINK="company-rules.md"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --base)
      BASE=${2:-}
      shift 2
      ;;
    --real)
      REAL=${2:-}
      shift 2
      ;;
    --v1)
      V1=${2:-}
      shift 2
      ;;
    --scope)
      SCOPE=${2:-}
      shift 2
      ;;
    --out)
      OUT=${2:-}
      shift 2
      ;;
    --values)
      VALUES=${2:-}
      shift 2
      ;;
    --map)
      MAP=${2:-}
      shift 2
      ;;
    --plain)
      PLAIN=${2:-}
      shift 2
      ;;
    --spill)
      SPILL=${2:-}
      shift 2
      ;;
    --score)
      SCORE=1
      shift
      ;;
    --role)
      ROLE=${2:-}
      shift 2
      ;;
    --link)
      LINK=${2:-}
      shift 2
      ;;
    *)
      printf 'rules-merge: unknown argument\n' >&2
      exit 1
      ;;
  esac
done

[ -n "$BASE" ] && [ -f "$BASE" ] || { printf 'rules-merge: base missing\n' >&2; exit 1; }
[ -n "$REAL" ] && [ -f "$REAL" ] || { printf 'rules-merge: real missing\n' >&2; exit 1; }
if [ "$SCORE" -eq 0 ]; then
  [ -n "$V1" ] && [ -f "$V1" ] || { printf 'rules-merge: v1 missing\n' >&2; exit 1; }
  [ -n "$OUT" ] || { printf 'rules-merge: out missing\n' >&2; exit 1; }
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ -z "$OUT" ]; then
  OUT="$tmp/out.md"
fi
if [ -z "$PLAIN" ]; then
  PLAIN="$tmp/plain.md"
fi
spill_tmp="$tmp/spill.md"
if [ -z "$VALUES" ]; then
  VALUES="$tmp/empty.values"
  : > "$VALUES"
fi

score_flag=0
if [ "$SCORE" -eq 1 ]; then
  score_flag=1
fi

awk -f "$DIR/rules-merge.awk" \
  -v base_path="$BASE" \
  -v real_path="$REAL" \
  -v v1_path="$V1" \
  -v map_path="$MAP" \
  -v values_path="$VALUES" \
  -v out_path="$OUT" \
  -v plain_path="$PLAIN" \
  -v spill_path="$spill_tmp" \
  -v scope="$SCOPE" \
  -v score_only="$score_flag"

if [ "$SCORE" -eq 1 ]; then
  exit 0
fi

# Spill when the merged file would fail the 10000-byte rules cap.
chars=$(wc -c < "$OUT" | tr -d ' ')
spilled=0
if [ "$chars" -ge 10000 ] && [ -n "$SPILL" ]; then
  spilled=1
  cp "$spill_tmp" "$SPILL"
  # The plain v1 file plus one link line stays under the cap.
  awk -v role="$ROLE" -v link="$LINK" '
    BEGIN { done = 0 }
    {
      print
      if (done) next
      if (role == "area" && NR == 1) {
        print "Read " link " for rules this area added."
        done = 1
      }
      if (role != "area" && $0 == "## This company") {
        print "- Read " link " for rules this company added."
        done = 1
      }
    }
    END {
      if (!done) {
        if (role == "area") print "Read " link " for rules this area added."
        else print "- Read " link " for rules this company added."
      }
    }
  ' "$PLAIN" > "$OUT"
  chars=$(wc -c < "$OUT" | tr -d ' ')
fi
printf 'chars=%s\n' "$chars"
printf 'spill=%s\n' "$spilled"
