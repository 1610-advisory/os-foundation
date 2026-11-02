#!/bin/bash
# Scan files for secrets. Print file:line:rule. Never print the value.
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: secret-scan.sh --staged
       secret-scan.sh --range <a>..<b>
       secret-scan.sh --files -- <file>...

Exit 0 is clean. Exit 1 is a hit. The line is file:line:rule.
Exit 2 is an error. The value is never printed.
--files with no paths is an error. A missing path is an error.
The bundled scan checks a known-bad sample first. If that sample is not
flagged, it exits 2 and prints: secret scan error: self-test failed

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
file_count=0

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
      if [ "${1:-}" = "--" ]; then
        shift
      fi
      break
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
  case "$f" in
    *$'\n'*)
      echo "secret-scan: path has a newline" >&2
      exit 2
      ;;
  esac
  if [ ! -e "$f" ] || [ -L "$f" ] || [ ! -f "$f" ]; then
    return 1
  fi
  printf '%s\n' "$f" >> "$scan_list"
  return 0
}

case "$mode" in
  staged)
    while IFS= read -r -d '' f; do
      [ -n "$f" ] || continue
      add_file "$f" || true
    done < <(git diff --cached --name-only -z)
    ;;
  range)
    while IFS= read -r -d '' f; do
      [ -n "$f" ] || continue
      add_file "$f" || true
    done < <(git diff --name-only -z "$range")
    ;;
  files)
    if [ $# -eq 0 ]; then
      echo "secret-scan: no files" >&2
      exit 2
    fi
    for f in "$@"; do
      file_count=$((file_count + 1))
      if ! add_file "$f"; then
        echo "secret-scan: not a regular file" >&2
        exit 2
      fi
    done
    ;;
esac

if [ "$mode" = "files" ] && [ "$file_count" -eq 0 ]; then
  echo "secret-scan: no files" >&2
  exit 2
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
  if [ ! -s "$scan_list" ]; then
    exit 0
  fi
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

# Bundled patterns. No interval expressions: old mawk treats {n} as text.
# Rule ids match gitleaks where the meaning is the same.
bundled_awk() {
  local mode=$1
  local target=${2:-/dev/null}
  awk -v mode="$mode" -v file="$target" '
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
    function is_space(c) {
      return c == " " || c == "\t" || c == "\r" || c == "\f" || c == "\v"
    }
    function class_ok(c, kind) {
      if (kind == "pat") return c ~ /[A-Za-z0-9]/
      if (kind == "fine") return c ~ /[A-Za-z0-9_]/
      if (kind == "slack") return (c ~ /[A-Za-z0-9]/) || c == "-"
      if (kind == "aws") return c ~ /[0-9A-Z]/
      if (kind == "gen") return (c ~ /[A-Za-z0-9_=]/) || c == "-"
      if (kind == "ent") return (c ~ /[A-Za-z0-9+=_]/) || c == "-" || c == "/"
      return 0
    }
    function run_end(s, i, kind,    n) {
      n = length(s)
      while (i <= n && class_ok(substr(s, i, 1), kind)) i++
      return i
    }
    function has_prefixed(s, prefix, kind, need,    from, rest, p, start, end) {
      from = 1
      while (from <= length(s)) {
        rest = substr(s, from)
        p = index(rest, prefix)
        if (p < 1) return 0
        start = from + p - 1 + length(prefix)
        end = run_end(s, start, kind)
        if (end - start >= need) return 1
        from = from + p
      }
      return 0
    }
    function has_slack(s) {
      if (has_prefixed(s, "xo" "xb-", "slack", 10)) return 1
      if (has_prefixed(s, "xo" "xa-", "slack", 10)) return 1
      if (has_prefixed(s, "xo" "xp-", "slack", 10)) return 1
      if (has_prefixed(s, "xo" "xr-", "slack", 10)) return 1
      if (has_prefixed(s, "xo" "xs-", "slack", 10)) return 1
      return 0
    }
    function keyword_hit(s, kw,    from, rest, p, pos, c) {
      from = 1
      while (from <= length(s)) {
        rest = substr(s, from)
        p = index(rest, kw)
        if (p < 1) return 0
        pos = from + p - 1 + length(kw)
        while (pos <= length(s) && is_space(substr(s, pos, 1))) pos++
        c = substr(s, pos, 1)
        if (c == ":" || c == "=") return pos + 1
        from = from + p
      }
      return 0
    }
    function assign_at(s,    at) {
      at = keyword_hit(s, "apikey")
      if (at) return at
      at = keyword_hit(s, "api_key")
      if (at) return at
      at = keyword_hit(s, "api-key")
      if (at) return at
      at = keyword_hit(s, "secret")
      if (at) return at
      at = keyword_hit(s, "password")
      if (at) return at
      at = keyword_hit(s, "token")
      if (at) return at
      at = keyword_hit(s, "passwd")
      if (at) return at
      return 0
    }
    # A $ or backtick before the run makes it a variable or a command, not a literal:
    # token=$(host_token), token="${TOKEN_FILE_PATH}".
    function site_has_run(s, at,    off, start, end, c) {
      while (at <= length(s) && is_space(substr(s, at, 1))) at++
      for (off = 0; off <= 2; off++) {
        c = substr(s, at + off - 1, 1)
        if (off > 0 && (c == "$" || c == "`")) return 0
        start = at + off
        end = run_end(s, start, "gen")
        if (end - start >= 16) return 1
      }
      return 0
    }
    function keyword_sites(s, kw,    from, rest, p, pos, c) {
      from = 1
      while (from <= length(s)) {
        rest = substr(s, from)
        p = index(rest, kw)
        if (p < 1) return 0
        pos = from + p - 1 + length(kw)
        while (pos <= length(s) && is_space(substr(s, pos, 1))) pos++
        c = substr(s, pos, 1)
        if ((c == ":" || c == "=") && site_has_run(s, pos + 1)) return 1
        from = from + p
      }
      return 0
    }
    function has_generic(s) {
      if (keyword_sites(s, "apikey")) return 1
      if (keyword_sites(s, "api_key")) return 1
      if (keyword_sites(s, "api-key")) return 1
      if (keyword_sites(s, "secret")) return 1
      if (keyword_sites(s, "password")) return 1
      if (keyword_sites(s, "token")) return 1
      if (keyword_sites(s, "passwd")) return 1
      return 0
    }
    function take_run(s, kind, need,    i, n, start, end) {
      tok = ""
      n = length(s)
      i = 1
      while (i <= n) {
        if (class_ok(substr(s, i, 1), kind)) {
          start = i
          end = run_end(s, start, kind)
          if (end - start >= need) {
            tok = substr(s, start, end - start)
            return 1
          }
          i = end
        } else {
          i++
        }
      }
      return 0
    }
    function note(rule) {
      found = 1
      line_got = line_got " " rule " "
      if (mode == "file") printf "%s:%d:%s\n", file, NR, rule
    }
    function scan_line(line) {
      line_got = ""
      if (index(line, "-----BE" "GIN") && index(line, "PRIVATE" " KEY")) note("private-key")
      if (has_prefixed(line, "gh" "p_", "pat", 36) || has_prefixed(line, "github_" "pat_", "fine", 22)) note("github-pat")
      if (has_slack(line)) note("slack-bot-token")
      if (has_prefixed(line, "AK" "IA", "aws", 16)) note("aws-access-key")
      if (has_generic(line) && !has_prefixed(line, "gh" "p_", "pat", 36)) note("generic-api-key")
      if (assign_at(line) && take_run(line, "ent", 20) && entropy(tok) >= 4.2) note("high-entropy")
    }
    function repeat(ch, n,    i, s) {
      s = ""
      for (i = 1; i <= n; i++) s = s ch
      return s
    }
    function expect(line, rule) {
      scan_line(line)
      if (index(line_got, " " rule " ") < 1) self_ok = 0
    }
    function expect_clean(line) {
      scan_line(line)
      if (line_got != "") self_ok = 0
    }
    function run_self(    mixed) {
      self_ok = 1
      expect("gh" "p_" repeat("a", 36), "github-pat")
      expect("github_" "pat_" repeat("b", 22), "github-pat")
      expect("xo" "xb-" repeat("c", 10), "slack-bot-token")
      expect("AK" "IA" "0123456789ABCDEF", "aws-access-key")
      expect("token = " repeat("d", 16), "generic-api-key")
      expect("token = \"" repeat("e", 16), "generic-api-key")
      expect("token = " repeat("d", 16) " secret = x", "generic-api-key")
      expect("token = no token = " repeat("d", 16), "generic-api-key")
      mixed = "aB3xQ9mZ2kL8pR4sT6uV1wY5nC7dE0fG2hJ4"
      expect("password = " mixed, "high-entropy")
      expect("-----BE" "GIN OPENSSH PRIVATE" " KEY-----", "private-key")
      expect_clean("notes only")
      expect_clean("password = short")
      expect_clean("-----BE" "GIN OPENSSH")
      expect_clean("PRIVATE" " KEY")
      expect_clean("token=$(host_forgejo_token)")
      expect_clean("  token=\"$(sync_bot_take_token \"$bot\")\"")
      expect_clean("token=${OS_REVIEW_TOKEN_FILE}")
      if (self_ok) print "self-test ok"
    }
    BEGIN {
      found = 0
      if (mode == "self") {
        run_self()
        exit self_ok ? 0 : 1
      }
    }
    mode == "file" {
      scan_line($0)
    }
    END {
      if (mode == "file") exit found ? 1 : 0
    }
  ' "$target"
}

bundled_scan() {
  bundled_awk file "$1"
}

scan_self_test() {
  local out rc
  set +e
  out=$(bundled_awk self 2>/dev/null)
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || return 1
  printf '%s\n' "$out" | grep -q 'self-test ok'
}

if ! scan_self_test; then
  echo "secret scan error: self-test failed" >&2
  exit 2
fi

if [ ! -s "$scan_list" ]; then
  exit 0
fi

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
