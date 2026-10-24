#!/bin/bash
# Scan files for secrets. Print file:line:rule. Never print the value.
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: secret-scan.sh --staged
       secret-scan.sh --range <a>..<b>
       secret-scan.sh --files <file>...

Exit 0 is clean. Exit 1 is a hit. The line is file:line:rule.
Exit 2 is an error. The value is never printed.

Uses gitleaks when it is on PATH, unless OS_SECRET_SCAN=bundled.
OS_SECRET_SCAN=gitleaks forces gitleaks.
EOF
}

if [ $# -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  if [ $# -eq 0 ]; then
    exit 2
  fi
  exit 0
fi

mode=""
range=""
files=""

while [ $# -gt 0 ]; do
  case "$1" in
    --staged)
      mode=staged
      shift
      ;;
    --range)
      [ $# -ge 2 ] || { echo "secret-scan: missing range" >&2; exit 2; }
      mode=range
      range=$2
      shift 2
      ;;
    --files)
      mode=files
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --*) break ;;
        esac
        files="${files} ${1}"
        shift
      done
      ;;
    *)
      echo "secret-scan: unknown argument" >&2
      exit 2
      ;;
  esac
done

if [ -z "$mode" ]; then
  usage >&2
  exit 2
fi

scan_list=$(mktemp)
chmod 600 "$scan_list"
# shellcheck disable=SC2329
cleanup() {
  rm -f "$scan_list"
}
trap cleanup EXIT

add_file() {
  local f=$1
  [ -f "$f" ] || return 0
  printf '%s\n' "$f" >> "$scan_list"
}

case "$mode" in
  staged)
    git diff --cached --name-only -z | while IFS= read -r -d '' f; do
      add_file "$f"
    done
    ;;
  range)
    git diff --name-only -z "$range" | while IFS= read -r -d '' f; do
      add_file "$f"
    done
    ;;
  files)
    # shellcheck disable=SC2086
    for f in $files; do
      add_file "$f"
    done
    ;;
esac

if [ ! -s "$scan_list" ]; then
  exit 0
fi

want=${OS_SECRET_SCAN:-auto}
use_gitleaks=0
if [ "$want" = "gitleaks" ]; then
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "secret-scan: gitleaks is not installed" >&2
    exit 2
  fi
  use_gitleaks=1
elif [ "$want" = "bundled" ]; then
  use_gitleaks=0
elif command -v gitleaks >/dev/null 2>&1; then
  use_gitleaks=1
fi

hits=$(mktemp)
chmod 600 "$hits"
# shellcheck disable=SC2329
cleanup() {
  rm -f "$scan_list" "$hits"
}
trap cleanup EXIT

if [ "$use_gitleaks" -eq 1 ]; then
  src=$(mktemp -d)
  chmod 700 "$src"
  # shellcheck disable=SC2329
  cleanup() {
    rm -f "$scan_list" "$hits"
    rm -rf "$src"
  }
  trap cleanup EXIT
  i=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    i=$((i + 1))
    cp "$f" "$src/$i"
  done < "$scan_list"
  report=$(mktemp)
  chmod 600 "$report"
  set +e
  gitleaks detect --no-git --source "$src" --report-format json --report-path "$report" --exit-code 1 --no-banner >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    exit 0
  fi
  if [ "$rc" -ne 1 ]; then
    rm -f "$report"
    echo "secret-scan: gitleaks failed" >&2
    exit 2
  fi
  if [ ! -s "$report" ]; then
    rm -f "$report"
    echo "secret-scan: gitleaks failed" >&2
    exit 2
  fi
  # Print rule id and line only. Do not print the match.
  jq -r '.[] | "\(.File):\(.StartLine):\(.RuleID)"' "$report" > "$hits"
  rm -f "$report"
  map=$(mktemp)
  chmod 600 "$map"
  # The copy step writes id<TAB>original into map. Rebuild it from the list.
  i=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    i=$((i + 1))
    printf '%s\t%s\n' "$i" "$f" >> "$map"
  done < "$scan_list"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    base=$(basename "${line%%:*}")
    orig=$(awk -F '\t' -v b="$base" '$1 == b { print $2; exit }' "$map")
    rest=${line#*:}
    if [ -n "$orig" ]; then
      printf '%s:%s\n' "$orig" "$rest"
    fi
  done < "$hits"
  rm -f "$map"
  exit 1
fi

# Bundled patterns. Rule ids match gitleaks where the meaning is the same.
bundled_scan() {
  local f=$1
  awk -v file="$f" '
    function entropy(s,    i, n, c, e, p, seen) {
      n = length(s)
      if (n < 20) return 0
      e = 0
      delete seen
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        seen[c]++
      }
      for (c in seen) {
        p = seen[c] / n
        e -= p * log(p)
      }
      return e / log(2)
    }
    function hit(rule) {
      printf "%s:%d:%s\n", file, NR, rule
      found = 1
    }
    {
      line = $0
      if (line ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) hit("private-key")
      if (line ~ /ghp_[A-Za-z0-9]{36}/) hit("github-pat")
      if (line ~ /github_pat_[A-Za-z0-9_]{22,}/) hit("github-pat")
      if (line ~ /xox[baprs]-[A-Za-z0-9-]{10,}/) hit("slack-bot-token")
      if (line ~ /AKIA[0-9A-Z]{16}/) hit("aws-access-key")
      if (line ~ /(api[_-]?key|secret|password|token|passwd)[[:space:]]*[:=][[:space:]]*.{0,2}[A-Za-z0-9_=-]{16,}/) {
        if (line !~ /ghp_[A-Za-z0-9]{36}/) hit("generic-api-key")
      }
      if (line ~ /(api[_-]?key|secret|password|token|passwd)[[:space:]]*[:=]/ && match(line, /[A-Za-z0-9+\/=_-]{20,}/)) {
        tok = substr(line, RSTART, RLENGTH)
        if (entropy(tok) >= 4.2) hit("high-entropy")
      }
    }
    END { exit found ? 1 : 0 }
  ' "$f"
}

found=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  set +e
  bundled_scan "$f" >> "$hits"
  rc=$?
  set -e
  if [ "$rc" -eq 1 ]; then
    found=1
  elif [ "$rc" -ne 0 ]; then
    echo "secret-scan: scan failed" >&2
    exit 2
  fi
done < "$scan_list"

if [ "$found" -eq 1 ]; then
  cat "$hits"
  exit 1
fi
exit 0
