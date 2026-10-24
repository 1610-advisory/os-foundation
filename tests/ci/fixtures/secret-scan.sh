#!/bin/bash
# Test double for skills/sync/secret-scan.sh.
# Prints file:line:rule and never prints the matched value.
set -euo pipefail

usage() {
  cat << 'EOF'
usage: secret-scan.sh --range BASE..HEAD

Exit 0 when the range is clean, 1 when a planted marker is in the diff.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

range=""
while [ $# -gt 0 ]; do
  case "$1" in
    --range)
      range=${2:-}
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$range" ]; then
  usage >&2
  exit 2
fi

marker=OSF_PLANTED_SECRET
hit=0
file=""
line_no=0
while IFS= read -r row; do
  case "$row" in
    "diff --git "*)
      file=${row#diff --git a/}
      file=${file%% b/*}
      ;;
    "@@ "*)
      plus=${row#*+}
      line_no=${plus%%,*}
      line_no=${line_no%% *}
      ;;
    "+"*)
      case "$row" in
        "+++"*) ;;
        *)
          if printf '%s' "$row" | grep -q -F "$marker"; then
            printf '%s:%s:planted\n' "$file" "$line_no"
            hit=1
          fi
          line_no=$((line_no + 1))
          ;;
      esac
      ;;
  esac
done << EOF
$(git diff --unified=0 "$range")
EOF

if [ "$hit" -ne 0 ]; then
  exit 1
fi
exit 0
