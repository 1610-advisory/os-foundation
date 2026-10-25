#!/usr/bin/env bash
# Run Acme scenarios. Print each script's result lines, then a summary line.
# S13 prints one line per engine and a summary line. The last line is the tally.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/lib/common.sh"

# Phase A scenario ids, in order. Tier B is blocked until gates G1-G8.
PHASE_A="S0 S1 S2 S3 S4 S5 S6 S7 S8 S9 S10 S11 S12 S13 S14"
# The en dash in G1–G8 is the character the brief requires.
TIER_B_REASON="BLOCKED: gates G1–G8"

usage() {
  cat << 'EOF'
usage: run.sh --tier a|b [--only S1,S3]

Tier A runs scenario scripts and prints one line each.
Tier B prints BLOCKED for every selected Phase A scenario.
BLOCKED never counts as PASS.
EOF
}

tier=""
only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --tier)
      tier="${2:-}"
      shift 2
      ;;
    --only)
      only="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ "$tier" != "a" ] && [ "$tier" != "b" ]; then
  usage >&2
  exit 1
fi

selected="$PHASE_A"
if [ -n "$only" ]; then
  selected=$(printf '%s\n' "$only" | tr ',' ' ')
fi

for id in $selected; do
  case "$id" in
    S[0-9]|S[0-9][0-9]) ;;
    *)
      echo "unknown scenario: $id" >&2
      exit 1
      ;;
  esac
done

if [ "$tier" = "b" ]; then
  blocked_ids=""
  for id in $selected; do
    echo "$id $TIER_B_REASON"
    blocked_ids="$blocked_ids $id"
  done
  echo "ACME: FAIL"
  echo "BLOCKED:${blocked_ids}"
  exit 1
fi

root=$(osf_acme_root)
mkdir -p "$root/tests/acme/.out"
pass=0
ran=0
fail_ids=""
blocked_ids=""
for id in $selected; do
  ran=$((ran + 1))
  script="$root/tests/acme/scenarios/${id}.sh"
  if [ ! -f "$script" ]; then
    echo "$id FAIL missing script"
    fail_ids="$fail_ids $id"
    continue
  fi
  set +e
  out=$(bash "$script" 2>>"$root/tests/acme/.out/run.err")
  set -e
  if [ -z "$out" ]; then
    line="$id FAIL no result line"
    printf '%s\n' "$line"
  else
    printf '%s\n' "$out"
    line=$(printf '%s\n' "$out" | tail -n 1)
  fi
  case "$line" in
    "$id PASS"*)
      pass=$((pass + 1))
      ;;
    "$id BLOCKED"*)
      blocked_ids="$blocked_ids $id"
      ;;
    "$id FAIL"*)
      fail_ids="$fail_ids $id"
      ;;
    *)
      fail_ids="$fail_ids $id"
      ;;
  esac
done

if [ -z "$fail_ids" ] && [ -z "$blocked_ids" ] && [ "$pass" -eq "$ran" ]; then
  echo "ACME: PASS $pass/$ran"
  exit 0
fi
echo "ACME: FAIL${fail_ids}"
if [ -n "$blocked_ids" ]; then
  echo "BLOCKED:${blocked_ids}"
fi
exit 1
