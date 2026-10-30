#!/bin/bash
# Company folder checks. Bash 3.2. Exit 0 ok, 1 findings.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-teammate/lib.sh"

usage() {
  cat << 'EOF'
usage: lint.sh [--ci] [--root <dir>]

Check links, copies, level, switches, rules size, placeholders, and profiles.
Exit 0 when clean. Exit 1 when there is a finding.
Without --ci, a newer-version notice and a one-time bot offer may print.
They do not change the exit code.
EOF
}

CI=0
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --ci)
      CI=1
      shift
      ;;
    --root)
      [ $# -ge 2 ] || os_die 2 "missing root"
      ROOT=$2
      shift 2
      ;;
    *)
      os_die 2 "unknown argument: $1"
      ;;
  esac
done

[ -n "$ROOT" ] || ROOT=$(pwd)
[ -d "$ROOT" ] || os_die 2 "company folder is missing"
ROOT=$(cd "$ROOT" && pwd)
FINDINGS=0

os_version_newer() {
  local remote=$1 localv=$2 r1 r2 r3 l1 l2 l3 r m
  remote=${remote#v}
  localv=${localv#v}
  case "$localv" in
    ""|*"{{"*) return 1 ;;
  esac
  case "$remote" in
    *-*) return 1 ;;
  esac
  r=$(printf '%s' "$remote" | awk -F. '{ printf "%d %d %d", $1+0, $2+0, $3+0 }')
  m=$(printf '%s' "${localv%%-*}" | awk -F. '{ printf "%d %d %d", $1+0, $2+0, $3+0 }')
  # shellcheck disable=SC2086
  set -- $r
  r1=$1
  r2=$2
  r3=$3
  # shellcheck disable=SC2086
  set -- $m
  l1=$1
  l2=$2
  l3=$3
  if [ "$r1" -gt "$l1" ]; then
    return 0
  fi
  if [ "$r1" -eq "$l1" ] && [ "$r2" -gt "$l2" ]; then
    return 0
  fi
  if [ "$r1" -eq "$l1" ] && [ "$r2" -eq "$l2" ] && [ "$r3" -gt "$l3" ]; then
    return 0
  fi
  if [ "$r1" -eq "$l1" ] && [ "$r2" -eq "$l2" ] && [ "$r3" -eq "$l3" ]; then
    case "$localv" in
      *-*) return 0 ;;
    esac
  fi
  return 1
}

os_days_at_least() {
  local a=$1 b=$2 n=$3 ea eb days
  ea=$(os_epoch "$a")
  eb=$(os_epoch "$b")
  days=$(( (eb - ea) / 86400 ))
  [ "$days" -ge "$n" ]
}

finding() {
  printf 'finding: %s\n' "$1"
  FINDINGS=1
}

check_link() {
  local path=$1 expected=$2 target skills
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    finding "link: $path is missing"
    return 0
  fi
  if [ -L "$path" ]; then
    target=$(readlink "$path")
    if [ "$target" != "$expected" ]; then
      finding "link: $path points to $target, not $expected"
      return 0
    fi
    if ! (cd "$(dirname "$path")" && cd "$target") >/dev/null 2>&1; then
      finding "link: $path target is missing"
    fi
    return 0
  fi
  if [ -d "$path" ]; then
    if ! (cd "$(dirname "$path")" && cd "$expected") >/dev/null 2>&1; then
      finding "skills copy drift: $path"
      return 0
    fi
    skills=$(cd "$(dirname "$path")" && cd "$expected" && pwd)
    if ! diff -rq "$path" "$skills" >/dev/null 2>&1; then
      finding "skills copy drift: $path"
    fi
    return 0
  fi
  finding "link: $path is not a link"
}

check_link "$ROOT/.agents/skills" "../skills"
check_link "$ROOT/.claude/skills" "../skills"

if [ -d "$ROOT/areas" ]; then
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    [ -f "$area/AGENTS.md" ] || continue
    base=$(basename "$area")
    check_link "$area/.agents/skills" "../skills"
    check_link "$area/.claude/skills" "../skills"
    if [ -d "$area/skills" ] && [ -d "$ROOT/skills" ]; then
      for skill in "$area"/skills/*; do
        [ -d "$skill" ] || continue
        name=$(basename "$skill")
        [ -d "$ROOT/skills/$name" ] || continue
        if ! diff -rq "$skill" "$ROOT/skills/$name" >/dev/null 2>&1; then
          finding "copy: areas/${base}/skills/${name} differs"
        fi
      done
    fi
  done
fi

PROFILE="$ROOT/company-profile.md"
if [ ! -f "$PROFILE" ]; then
  finding "level: company-profile.md is missing"
else
  LEVEL=$(os_fm_get "$PROFILE" level 2>/dev/null || true)
  case "$LEVEL" in
    solo|team|app) ;;
    "") finding "level: missing" ;;
    *) finding "level: $LEVEL" ;;
  esac

  HOST=$(os_fm_get "$PROFILE" host 2>/dev/null || true)
  case "$HOST" in
    none|github|forgejo) ;;
    "") finding "host: missing (add host: none to company-profile.md, or github or forgejo)" ;;
    *) finding "host: $HOST" ;;
  esac

  SWITCHES=$(os_fm_get "$PROFILE" switches 2>/dev/null || true)
  allowed=" bots traces cloud-handoff mdx-reports benchmarks "
  if [ -f "$ROOT/scale.md" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      allowed="${allowed}${name} "
    done << EOF
$(awk -F'`' '/^\| `[^`]+` \|/ { print $2 }' "$ROOT/scale.md")
EOF
  fi
  SWITCHES=$(printf '%s' "$SWITCHES" | tr -d '[]' | tr ',' ' ')
  for sw in $SWITCHES; do
    sw=$(os_trim "$sw")
    [ -n "$sw" ] || continue
    if [ "$sw" = "dream" ]; then
      finding "switch: dream"
      continue
    fi
    case "$allowed" in
      *" ${sw} "*) ;;
      *) finding "switch: $sw" ;;
    esac
  done
fi

size_file() {
  local f=$1 n
  [ -f "$f" ] || return 0
  n=$(wc -c < "$f" | tr -d ' ')
  if [ "$n" -ge 10000 ]; then
    finding "size: ${f#"$ROOT"/}"
  fi
}

size_file "$ROOT/AGENTS.md"
size_file "$ROOT/CLAUDE.md"
size_file "$ROOT/company-rules.md"
size_file "$ROOT/review-rules.md"
if [ -d "$ROOT/bots" ]; then
  for bot in "$ROOT"/bots/*/BOT.md; do
    size_file "$bot"
  done
fi
if [ -d "$ROOT/areas" ]; then
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    size_file "$area/AGENTS.md"
    size_file "$area/CLAUDE.md"
    size_file "$area/area-rules.md"
    size_file "$area/review-rules.md"
  done
fi

# Placeholders outside skills/. Skip .github/: workflow files use the actions form.
# Skip library/: the admin's private repo of copies, never edited.
# Skip memory/logs-archive/: it is history from v0 and nobody edits it.
ph=$(mktemp)
find "$ROOT" -type f \
  -not -path "$ROOT/skills/*" \
  -not -path "$ROOT/library/*" \
  -not -path "$ROOT/.github/*" \
  -not -path "$ROOT/memory/logs-archive/*" \
  -not -path "$ROOT/areas/*/memory/logs-archive/*" \
  -not -path "$ROOT/.git/*" \
  -not -path "$ROOT/areas/*/.git/*" \
  -not -path "$ROOT/users/*/.git/*" \
  | while IFS= read -r f; do
    # Bracket classes, so this line is not itself a placeholder.
    if grep -q '[{][{][^}]*[}][}]' "$f" 2>/dev/null; then
      printf 'finding: placeholder: %s\n' "${f#"$ROOT"/}"
    fi
  done > "$ph" || true
if [ -s "$ph" ]; then
  cat "$ph"
  FINDINGS=1
fi
rm -f "$ph"

if [ -f "$PROFILE" ]; then
  SLUG=$(os_fm_get "$PROFILE" company_slug 2>/dev/null || true)
  CNAME=$(os_company_name "$PROFILE")
  if [ -d "$ROOT/users" ]; then
    for prof in "$ROOT"/users/*/profile/PROFILE.md; do
      [ -f "$prof" ] || continue
      hit=0
      if [ -n "$SLUG" ] && grep -q -F "$SLUG" "$prof"; then
        hit=1
      fi
      case "$CNAME" in
        ""|*'{{'*) ;;
        *)
          if grep -q -F "$CNAME" "$prof"; then
            hit=1
          fi
          ;;
      esac
      if [ "$hit" -eq 1 ]; then
        finding "profile: ${prof#"$ROOT"/}"
      fi
    done
  fi
fi

if [ "$CI" -eq 0 ] && [ -f "$PROFILE" ]; then
  OS_VER=$(os_fm_get "$PROFILE" os_version 2>/dev/null || true)
  URL=${OS_VERSION_URL:-https://1610.sh/os/version}
  remote=""
  if remote=$(curl -fsS --max-time 5 "$URL" 2>/dev/null); then
    remote=$(printf '%s' "$remote" | tr -d '\r' | head -n 1)
    case "$remote" in
      unreleased|"") ;;
      *)
        if os_version_newer "$remote" "$OS_VER"; then
          printf 'notice: a newer os-foundation version exists: %s\n' "$remote"
        fi
        ;;
    esac
  fi

  LEVEL=$(os_fm_get "$PROFILE" level 2>/dev/null || true)
  SWITCHES=$(os_fm_get "$PROFILE" switches 2>/dev/null || true)
  SWITCHES=$(printf '%s' "$SWITCHES" | tr -d '[]' | tr ',' ' ')
  bots_on=0
  for sw in $SWITCHES; do
    if [ "$(os_trim "$sw")" = "bots" ]; then
      bots_on=1
    fi
  done
  if [ "$bots_on" -eq 0 ] && [ -n "$SLUG" ]; then
    state="$(os_config_dir "$SLUG")/state"
    mkdir -p "$state"
    today=$(os_today)
    if [ ! -f "$state/lint-first-use" ]; then
      printf '%s\n' "$today" > "$state/lint-first-use"
    fi
    if [ ! -f "$state/lint-bot-offer" ]; then
      first=$(tr -d '\r\n' < "$state/lint-first-use")
      if os_days_at_least "$first" "$today" 14; then
        printf '%s\n' "offer: You have used this OS for two weeks. A bot can run jobs for you. Ask to add one."
        printf '%s\n' "$today" > "$state/lint-bot-offer"
      fi
    fi
  fi
fi

if [ "$FINDINGS" -ne 0 ]; then
  exit 1
fi
exit 0
