#!/usr/bin/env bash
# Public-repo guard. Prints counts and locations. Never prints a matched value.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pii-check.sh [--base REF] [--all] [--paths FILE...] [--allow-unconfigured] [--root DIR]

Checks added lines (default) or whole files for forbidden terms, home-folder
paths, token prefixes, and email addresses. Also checks path names in scope.
--base also checks commit messages. Prints a count per check and
file:line:check, path:name, or commit:sha:check. Never prints the matched text.

  --base REF   added lines in git diff REF...HEAD, plus added lines versus
               HEAD, plus untracked files that are not ignored. Also changed
               and renamed paths, and commit messages in REF..HEAD.
               Default REF is origin/next/v1.
  --all        every tracked file, and every tracked path name
  --paths FILE these files only, and their path names
  --allow-unconfigured
               do not exit 3 when the term lists are unset; run the generic checks
  --root DIR   git repo to scan (default: this repo)

Reads PII_SLUG_DIR, PII_TERMS_FILE, and PII_ALLOW from the environment.
Exit 0 clean, 1 hits, 2 usage, 3 not configured.
EOF
}

script_dir=$(cd "$(dirname "$0")" && pwd)
root=""
scope=""
base="origin/next/v1"
allow_unconfigured=0
paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --allow-unconfigured)
      allow_unconfigured=1
      shift
      ;;
    --all)
      [[ -z "$scope" ]] || { echo "pii-check: one scope only" >&2; exit 2; }
      scope=all
      shift
      ;;
    --base)
      [[ -z "$scope" ]] || { echo "pii-check: one scope only" >&2; exit 2; }
      [[ $# -ge 2 ]] || { echo "pii-check: missing ref" >&2; exit 2; }
      scope=base
      base=$2
      shift 2
      ;;
    --paths)
      [[ -z "$scope" ]] || { echo "pii-check: one scope only" >&2; exit 2; }
      scope=paths
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        paths+=("$1")
        shift
      done
      [[ ${#paths[@]} -gt 0 ]] || { echo "pii-check: missing paths" >&2; exit 2; }
      ;;
    --root)
      [[ $# -ge 2 ]] || { echo "pii-check: missing root" >&2; exit 2; }
      root=$2
      shift 2
      ;;
    *)
      echo "pii-check: unknown argument" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$scope" ]]; then
  scope=base
fi

if [[ -z "$root" ]]; then
  root=$(cd "$script_dir/../.." && pwd)
fi

configured=0
if [[ -n "${PII_SLUG_DIR:-}" && -n "${PII_TERMS_FILE:-}" ]]; then
  if [[ -d "$PII_SLUG_DIR" && -f "$PII_TERMS_FILE" ]]; then
    configured=1
  elif [[ "$allow_unconfigured" -eq 0 ]]; then
    echo "pii-check: NOT CONFIGURED"
    exit 3
  fi
elif [[ "$allow_unconfigured" -eq 0 ]]; then
  echo "pii-check: NOT CONFIGURED"
  exit 3
fi

terms_tmp=$(mktemp)
pat_tmp=$(mktemp)
hits_file=$(mktemp)
awk_file=$(mktemp)
diff_tmp=$(mktemp)
wt_tmp=$(mktemp)
names_tmp=$(mktemp)
msg_tmp=$(mktemp)
chmod 600 "$terms_tmp" "$pat_tmp" "$hits_file" "$awk_file" "$diff_tmp" "$wt_tmp" "$names_tmp" "$msg_tmp"

# Invoked by trap, not by a direct call.
# shellcheck disable=SC2329
cleanup() {
  rm -f "$terms_tmp" "$pat_tmp" "$hits_file" "$awk_file" "$diff_tmp" "$wt_tmp" "$names_tmp" "$msg_tmp"
}
trap cleanup EXIT

allow_lower=""
if [[ -n "${PII_ALLOW:-}" ]]; then
  IFS=',' read -r -a allow_items <<< "${PII_ALLOW}"
  for item in "${allow_items[@]}"; do
    item=${item#"${item%%[![:space:]]*}"}
    item=${item%"${item##*[![:space:]]}"}
    [[ -z "$item" ]] && continue
    low=$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')
    allow_lower="${allow_lower}${low}"$'\n'
  done
fi

add_term() {
  local term=$1
  local kind low
  [[ -n "$term" ]] || return 0
  low=$(printf '%s' "$term" | tr '[:upper:]' '[:lower:]')
  if [[ -n "$allow_lower" ]] && printf '%s' "$allow_lower" | grep -qxF -- "$low"; then
    return 0
  fi
  kind=w
  if [[ "$term" == *'/'* || "$term" == *'~'* ]]; then
    kind=s
  fi
  printf '%s\t%s\n' "$kind" "$term" >> "$terms_tmp"
}

if [[ "$configured" -eq 1 ]]; then
  # Only folder names, or links to folders. Skip hidden entries and plain files.
  while IFS= read -r -d '' entry; do
    [[ -n "$entry" ]] || continue
    name=$(basename "$entry")
    [[ "$name" == .* ]] && continue
    [[ -d "$entry" ]] || continue
    add_term "$name"
  done < <(find "$PII_SLUG_DIR" -mindepth 1 -maxdepth 1 -print0)

  while IFS= read -r term || [[ -n "$term" ]]; do
    term=${term%$'\r'}
    term=${term#"${term%%[![:space:]]*}"}
    term=${term%"${term##*[![:space:]]}"}
    [[ -z "$term" || "$term" == \#* ]] && continue
    add_term "$term"
  done < "$PII_TERMS_FILE"
fi

# Build prefixes at run time so this file does not contain them.
{
  printf 'p\t%s\n' "$(printf '%s%s' 'gh' 'p_')"
  printf 'p\t%s\n' "$(printf '%s%s' 'gh' 'o_')"
  printf 'p\t%s\n' "$(printf '%s%s' 'gh' 's_')"
  printf 'p\t%s\n' "$(printf '%s%s' 'github' '_pat_')"
  printf 'p\t%s\n' "$(printf '%s%s%s' 'sk' '-' 'ant-')"
  printf 'p\t%s\n' "$(printf '%s%s' 'sk' '-')"
  printf 'p\t%s\n' "$(printf '%s%s' 'xa' 'i-')"
  printf 'p\t%s\n' "$(printf '%s%s' 'AK' 'IA')"
  printf 'k\t%s\t%s\n' "$(printf '%s%s' '-----BE' 'GIN')" "$(printf '%s%s' 'PRIVATE' ' KEY')"
} > "$pat_tmp"

users_prefix=$(printf '%s%s' '/Use' 'rs/')
home_prefix=$(printf '%s%s' '/ho' 'me/')

cat > "$awk_file" <<'EOF'
function word_char(c) {
  if (c == "") return 0
  return c ~ /[A-Za-z0-9_]/
}

function has_term(line, lowterm, kind,    low, start, i, pos, n, before, after) {
  if (lowterm == "") return 0
  low = tolower(line)
  if (kind == "s") return index(low, lowterm) > 0
  n = length(lowterm)
  start = 1
  while (start <= length(low)) {
    i = index(substr(low, start), lowterm)
    if (i == 0) return 0
    pos = start + i - 1
    before = ""
    if (pos > 1) before = substr(low, pos - 1, 1)
    after = substr(low, pos + n, 1)
    if (!word_char(before) && !word_char(after)) return 1
    start = pos + 1
  }
  return 0
}

function ends_with(s, suf) {
  return length(s) >= length(suf) && substr(s, length(s) - length(suf) + 1) == suf
}

function allowed_domain(d,    low) {
  low = tolower(d)
  if (low == "example.com" || low == "example.org" || low == "example.net") return 1
  if (low == "acme.test") return 1
  if (low == "users.noreply.github.com") return 1
  if (ends_with(low, ".example")) return 1
  if (ends_with(low, ".example.com")) return 1
  if (ends_with(low, ".example.org")) return 1
  if (ends_with(low, ".example.net")) return 1
  if (ends_with(low, ".acme.test")) return 1
  return 0
}

function has_bad_email(line,    rest, m, at, dom) {
  rest = line
  while (match(rest, /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+/)) {
    m = substr(rest, RSTART, RLENGTH)
    at = index(m, "@")
    dom = substr(m, at + 1)
    if (!allowed_domain(dom)) return 1
    rest = substr(rest, RSTART + RLENGTH)
  }
  return 0
}

function has_home(line, re, prefix, ban_runner,    rest, m, name, prelen) {
  rest = line
  prelen = length(prefix)
  while (match(rest, re)) {
    m = substr(rest, RSTART, RLENGTH)
    name = substr(m, prelen + 1, length(m) - prelen - 1)
    if (!(ban_runner && name == "runner")) return 1
    rest = substr(rest, RSTART + RLENGTH)
  }
  return 0
}

function has_token(line,    i, n, kind, rest, a, b) {
  for (i = 1; i <= npat; i++) {
    n = index(pats[i], "\t")
    if (n == 0) continue
    kind = substr(pats[i], 1, n - 1)
    rest = substr(pats[i], n + 1)
    if (kind == "p") {
      if (index(line, rest) > 0) return 1
    } else if (kind == "k") {
      n = index(rest, "\t")
      if (n == 0) continue
      a = substr(rest, 1, n - 1)
      b = substr(rest, n + 1)
      if (a != "" && b != "" && index(line, a) > 0 && index(line, b) > 0) return 1
    }
  }
  return 0
}

function emit(file, lineno, check) {
  if (file == "" || lineno <= 0) return
  printf "%s:%d:%s\n", file, lineno, check
}

function note(kind) {
  if (kind == "term") c_term = 1
  else if (kind == "path") c_path = 1
  else if (kind == "token") c_token = 1
  else if (kind == "email") c_email = 1
}

function inspect(line,    i, hit) {
  gsub(/\r/, "", line)
  hit = 0
  for (i = 1; i <= nterms; i++) {
    if (has_term(line, lows[i], kinds[i])) { hit = 1; break }
  }
  if (hit) note("term")
  if (has_home(line, users_re, users_prefix, 0) || has_home(line, home_re, home_prefix, 1)) note("path")
  if (has_token(line)) note("token")
  if (has_bad_email(line)) note("email")
}

function has_any_term(line,    i) {
  for (i = 1; i <= nterms; i++) {
    if (has_term(line, lows[i], kinds[i])) return 1
  }
  return 0
}

function check(file, lineno, line,    i, hit) {
  if (file == "") return
  gsub(/\r/, "", line)
  hit = 0
  for (i = 1; i <= nterms; i++) {
    if (has_term(line, lows[i], kinds[i])) { hit = 1; break }
  }
  if (hit) emit(file, lineno, "term")
  if (has_home(line, users_re, users_prefix, 0) || has_home(line, home_re, home_prefix, 1)) {
    emit(file, lineno, "path")
  }
  if (has_token(line)) emit(file, lineno, "token")
  if (has_bad_email(line)) emit(file, lineno, "email")
}

function git_path(s,    tab) {
  tab = index(s, "\t")
  if (tab > 0) s = substr(s, 1, tab - 1)
  sub(/\r$/, "", s)
  if (substr(s, 1, 1) == "\"") {
    if (substr(s, length(s), 1) == "\"") s = substr(s, 2, length(s) - 2)
    gsub(/\\"/, "\"", s)
    gsub(/\\\\/, "\\", s)
  }
  if (s == "/dev/null") return ""
  if (substr(s, 1, 2) == "b/") return substr(s, 3)
  return s
}

BEGIN {
  nterms = 0
  if (terms_file != "") {
    while ((getline t < terms_file) > 0) {
      n = index(t, "\t")
      if (n == 0) continue
      nterms++
      kinds[nterms] = substr(t, 1, n - 1)
      lows[nterms] = tolower(substr(t, n + 1))
    }
    close(terms_file)
  }
  npat = 0
  if (pat_file != "") {
    while ((getline t < pat_file) > 0) {
      npat++
      pats[npat] = t
    }
    close(pat_file)
  }
  users_re = users_prefix "[A-Za-z0-9][A-Za-z0-9._-]*/"
  home_re = home_prefix "[A-Za-z0-9][A-Za-z0-9._-]*/"
  curfile = ""
  in_hunk = 0
  newln = 0
  c_term = 0
  c_path = 0
  c_token = 0
  c_email = 0
}

mode == "file" {
  check(FILENAME, FNR, $0)
  next
}

mode == "name" {
  if ($0 != "" && has_any_term($0)) printf "%s:name\n", $0
  next
}

mode == "commit" {
  inspect($0)
  next
}

mode == "diff" {
  if (substr($0, 1, 11) == "diff --git ") {
    curfile = ""
    in_hunk = 0
    next
  }
  if (substr($0, 1, 4) == "+++ ") {
    curfile = git_path(substr($0, 5))
    next
  }
  if (substr($0, 1, 3) == "@@ ") {
    if (match($0, /\+[0-9]+/)) {
      newln = substr($0, RSTART + 1, RLENGTH - 1) + 0
      in_hunk = 1
    }
    next
  }
  if (!in_hunk) next
  if (substr($0, 1, 1) == "\\") next
  if (substr($0, 1, 1) == "-") next
  if (substr($0, 1, 1) == "+" && substr($0, 1, 3) != "+++") {
    check(curfile, newln, substr($0, 2))
    newln++
    next
  }
  next
}

END {
  if (mode == "commit") {
    if (c_term) printf "%s:term\n", label
    if (c_path) printf "%s:path\n", label
    if (c_token) printf "%s:token\n", label
    if (c_email) printf "%s:email\n", label
  }
}
EOF

is_binary() {
  local bytes
  # Do not use grep for a NUL: an empty pattern matches every text file.
  bytes=$(dd if="$1" bs=8192 count=1 2>/dev/null | LC_ALL=C tr -cd '\0' | wc -c | tr -d '[:space:]')
  [[ "${bytes:-0}" -gt 0 ]]
}

run_awk_files() {
  [[ $# -gt 0 ]] || return 0
  awk -f "$awk_file" \
    -v mode=file \
    -v terms_file="$terms_tmp" \
    -v pat_file="$pat_tmp" \
    -v users_prefix="$users_prefix" \
    -v home_prefix="$home_prefix" \
    "$@" >> "$hits_file"
}

run_awk_diff() {
  local diff_file=$1
  [[ -s "$diff_file" ]] || return 0
  awk -f "$awk_file" \
    -v mode=diff \
    -v terms_file="$terms_tmp" \
    -v pat_file="$pat_tmp" \
    -v users_prefix="$users_prefix" \
    -v home_prefix="$home_prefix" \
    "$diff_file" >> "$hits_file"
}

scan_given_files() {
  local path
  local -a batch
  batch=()
  for path in "$@"; do
    [[ -n "$path" ]] || continue
    if [[ ! -f "$path" ]]; then
      echo "pii-check: not a file" >&2
      exit 2
    fi
    if is_binary "$path"; then
      continue
    fi
    batch+=("$path")
  done
  if [[ ${#batch[@]} -gt 0 ]]; then
    run_awk_files "${batch[@]}"
  fi
}

# Repo-relative names, so a hit does not print a machine path.
scan_repo_files() {
  local rel path
  local -a batch
  batch=()
  for rel in "$@"; do
    [[ -n "$rel" ]] || continue
    path="$root/$rel"
    [[ -f "$path" ]] || continue
    if is_binary "$path"; then
      continue
    fi
    batch+=("$rel")
  done
  if [[ ${#batch[@]} -eq 0 ]]; then
    return 0
  fi
  (
    cd "$root" || exit 2
    awk -f "$awk_file" \
      -v mode=file \
      -v terms_file="$terms_tmp" \
      -v pat_file="$pat_tmp" \
      -v users_prefix="$users_prefix" \
      -v home_prefix="$home_prefix" \
      "${batch[@]}"
  ) >> "$hits_file"
}

record_name() {
  [[ -n "$1" ]] || return 0
  printf '%s\n' "$1" >> "$names_tmp"
}

flush_names() {
  local sorted
  [[ -s "$names_tmp" ]] || return 0
  sorted=$(mktemp)
  chmod 600 "$sorted"
  sort -u "$names_tmp" > "$sorted"
  awk -f "$awk_file" \
    -v mode=name \
    -v terms_file="$terms_tmp" \
    -v pat_file="$pat_tmp" \
    -v users_prefix="$users_prefix" \
    -v home_prefix="$home_prefix" \
    "$sorted" >> "$hits_file"
  rm -f "$sorted"
}

append_status_paths() {
  local status old new path
  while IFS= read -r -d '' status; do
    [[ -n "$status" ]] || continue
    case "$status" in
      R*|C*)
        IFS= read -r -d '' old || break
        IFS= read -r -d '' new || break
        record_name "$old"
        record_name "$new"
        ;;
      *)
        IFS= read -r -d '' path || break
        record_name "$path"
        ;;
    esac
  done
  return 0
}

scan_commit_messages() {
  local full short
  while read -r full short; do
    [[ -n "$full" && -n "$short" ]] || continue
    git -C "$root" log -1 --format=%B "$full" > "$msg_tmp"
    awk -f "$awk_file" \
      -v mode=commit \
      -v label="commit:$short" \
      -v terms_file="$terms_tmp" \
      -v pat_file="$pat_tmp" \
      -v users_prefix="$users_prefix" \
      -v home_prefix="$home_prefix" \
      "$msg_tmp" >> "$hits_file"
  done < <(git -C "$root" log --format='%H %h' "${base}..HEAD")
  return 0
}

if [[ "$scope" == "paths" ]]; then
  scan_given_files "${paths[@]}"
  for path in "${paths[@]}"; do
    record_name "$path"
  done
  flush_names
elif [[ "$scope" == "all" ]]; then
  if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "pii-check: not a git repo" >&2
    exit 2
  fi
  rels=()
  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] || continue
    rels+=("$rel")
  done < <(git -C "$root" ls-files -z)
  if [[ ${#rels[@]} -gt 0 ]]; then
    scan_repo_files "${rels[@]}"
    for rel in "${rels[@]}"; do
      record_name "$rel"
    done
  fi
  flush_names
else
  if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "pii-check: not a git repo" >&2
    exit 2
  fi
  if ! git -C "$root" rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1; then
    echo "pii-check: bad base" >&2
    exit 2
  fi
  if ! git -C "$root" diff -U0 --no-color "${base}...HEAD" > "$diff_tmp"; then
    echo "pii-check: bad base" >&2
    exit 2
  fi
  run_awk_diff "$diff_tmp"
  if git -C "$root" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    git -C "$root" diff -U0 --no-color HEAD > "$wt_tmp"
    run_awk_diff "$wt_tmp"
  fi
  rels=()
  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] || continue
    rels+=("$rel")
  done < <(git -C "$root" ls-files --others --exclude-standard -z)
  if [[ ${#rels[@]} -gt 0 ]]; then
    scan_repo_files "${rels[@]}"
    for rel in "${rels[@]}"; do
      record_name "$rel"
    done
  fi
  git -C "$root" diff --name-status --find-renames -z "${base}...HEAD" | append_status_paths
  if git -C "$root" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    git -C "$root" diff --name-status --find-renames -z HEAD | append_status_paths
  fi
  flush_names
  scan_commit_messages
fi

term_n=$(grep -c ':term$' "$hits_file" || true)
name_n=$(grep -c ':name$' "$hits_file" || true)
path_n=$(grep -c ':path$' "$hits_file" || true)
token_n=$(grep -c ':token$' "$hits_file" || true)
email_n=$(grep -c ':email$' "$hits_file" || true)
term_n=${term_n:-0}
name_n=${name_n:-0}
path_n=${path_n:-0}
token_n=${token_n:-0}
email_n=${email_n:-0}
term_n=$((term_n + name_n))
total=$((term_n + path_n + token_n + email_n))

if [[ "$total" -eq 0 ]]; then
  echo "pii-check: OK"
  exit 0
fi

printf 'term %s\npath %s\ntoken %s\nemail %s\n' "$term_n" "$path_n" "$token_n" "$email_n"
cat "$hits_file"
exit 1
