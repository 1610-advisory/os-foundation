#!/bin/bash
# Write privacy.md from places.md and company-profile.md.
# Uses skills/_host/profile.sh when that file is present.
# Bash 3.2. Same input writes the same bytes. No date is added.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: privacy.sh [--root <dir>] [--stdout] [--check]

Write privacy.md from places.md and company-profile.md.
--root DIR   company folder (default: the current folder)
--stdout     print privacy.md and do not write it
--check      write nothing; exit 0 if privacy.md is current, 1 if it differs
EOF
}

die() {
  printf 'privacy: %s\n' "$1" >&2
  exit "${2:-1}"
}

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

strip_inline_comment() {
  local s=$1
  s=${s%%" #"*}
  printf '%s' "$s"
}

strip_yaml_scalar() {
  local s=$1
  if [[ ${#s} -ge 2 && "$s" == \"*\" ]]; then
    s=${s#\"}
    s=${s%\"}
  elif [[ ${#s} -ge 2 && "$s" == \'*\' ]]; then
    s=${s#\'}
    s=${s%\'}
  fi
  printf '%s' "$s"
}

append_switch() {
  local name=$1
  if [[ -z "$SWITCHES" ]]; then
    SWITCHES=$name
  else
    SWITCHES="${SWITCHES}"$'\n'"${name}"
  fi
}

parse_flow_list() {
  local s=$1
  local inner item
  inner=${s#\[}
  inner=${inner%\]}
  inner="${inner},"
  while [[ "$inner" == *,* ]]; do
    item=${inner%%,*}
    inner=${inner#*,}
    item=$(strip_inline_comment "$item")
    item=$(trim "$item")
    item=$(strip_yaml_scalar "$item")
    if [[ -n "$item" && "$item" != "[]" ]]; then
      append_switch "$item"
    fi
  done
}

# list_key is global so a nested call can set it. Bash 3.2 has no nameref.
parse_switches_value() {
  local raw=$1
  if [[ -z "$raw" ]]; then
    list_key=switches
    return 0
  fi
  if [[ "$raw" == "[]" ]]; then
    return 0
  fi
  if [[ "$raw" == \[*\] ]]; then
    parse_flow_list "$raw"
    return 0
  fi
  raw=$(strip_yaml_scalar "$raw")
  if [[ -z "$raw" ]]; then
    return 0
  fi
  die "cannot read switches in company-profile.md"
}

read_frontmatter() {
  local file=$1
  local line key raw started=0
  list_key=""
  LEVEL=""
  SWITCHES=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ "$started" -eq 0 ]]; then
      if [[ "$line" == "---" ]]; then
        started=1
      fi
      continue
    fi
    if [[ "$line" == "---" ]]; then
      return 0
    fi
    if [[ "$list_key" == "switches" && "$line" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
      raw=${BASH_REMATCH[1]}
      raw=$(strip_inline_comment "$raw")
      raw=$(trim "$raw")
      raw=$(strip_yaml_scalar "$raw")
      if [[ -n "$raw" ]]; then
        append_switch "$raw"
      fi
      continue
    fi
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]]; then
      key=${BASH_REMATCH[1]}
      raw=${BASH_REMATCH[2]}
      list_key=""
      raw=$(strip_inline_comment "$raw")
      raw=$(trim "$raw")
      if [[ "$key" == "level" ]]; then
        LEVEL=$(strip_yaml_scalar "$raw")
      elif [[ "$key" == "switches" ]]; then
        parse_switches_value "$raw"
      fi
      continue
    fi
  done < "$file"
}

take_switch_line() {
  local line=$1
  line=$(trim "$line")
  line=${line%$'\r'}
  line=$(strip_yaml_scalar "$line")
  if [[ -z "$line" || "$line" == "[]" ]]; then
    return 0
  fi
  if [[ "$line" == \[*\] ]]; then
    parse_flow_list "$line"
    return 0
  fi
  append_switch "$line"
}

load_from_profile_sh() {
  local profile_sh=$1
  local out rc line
  local profile_file="$ROOT/company-profile.md"

  rc=0
  out=$(
    cd "$ROOT" || exit 1
    OS_PROFILE="$profile_file" bash "$profile_sh" level
  ) || rc=$?
  if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
    die "profile.sh could not read level"
  fi
  LEVEL=${out%%$'\n'*}
  LEVEL=$(trim "$LEVEL")
  LEVEL=$(strip_yaml_scalar "$LEVEL")

  rc=0
  out=$(
    cd "$ROOT" || exit 1
    OS_PROFILE="$profile_file" bash "$profile_sh" switches
  ) || rc=$?
  if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
    die "profile.sh could not read switches"
  fi
  SWITCHES=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    take_switch_line "$line"
  done < <(printf '%s\n' "$out")
}

load_profile() {
  local profile_sh="$ROOT/skills/_host/profile.sh"
  LEVEL=""
  SWITCHES=""
  if [[ -f "$profile_sh" ]]; then
    load_from_profile_sh "$profile_sh"
  else
    read_frontmatter "$ROOT/company-profile.md"
  fi
  LEVEL=$(trim "$LEVEL")
  if [[ -z "$LEVEL" ]]; then
    LEVEL=solo
  fi
  LEVEL=$(printf '%s' "$LEVEL" | tr '[:upper:]' '[:lower:]')
}

switch_on() {
  local name=$1
  local rest=$SWITCHES
  local item
  [[ -n "$rest" ]] || return 1
  rest="${rest}"$'\n'
  while [[ -n "$rest" ]]; do
    item=${rest%%$'\n'*}
    rest=${rest#*$'\n'}
    if [[ "$item" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

# 0 true, 1 false, 2 unknown. Never guess.
eval_cond() {
  local cond=$1
  local left right ls rs name
  cond=$(trim "$cond")
  if [[ "$cond" == *" and "* ]]; then
    left=${cond%%" and "*}
    right=${cond#*" and "}
    left=$(trim "$left")
    right=$(trim "$right")
    if [[ "$right" == *" and "* || -z "$left" || -z "$right" ]]; then
      return 2
    fi
    if eval_cond "$left"; then
      ls=0
    else
      ls=$?
    fi
    if [[ "$ls" -eq 2 ]]; then
      return 2
    fi
    if eval_cond "$right"; then
      rs=0
    else
      rs=$?
    fi
    if [[ "$rs" -eq 2 ]]; then
      return 2
    fi
    if [[ "$ls" -eq 0 && "$rs" -eq 0 ]]; then
      return 0
    fi
    return 1
  fi
  case "$cond" in
    always)
      return 0
      ;;
    "level: team")
      if [[ "$LEVEL" == "team" || "$LEVEL" == "app" ]]; then
        return 0
      fi
      return 1
      ;;
    "level: app")
      if [[ "$LEVEL" == "app" ]]; then
        return 0
      fi
      return 1
      ;;
    "switch:"*)
      name=${cond#switch:}
      name=$(trim "$name")
      if [[ -z "$name" || "$name" == *" "* ]]; then
        return 2
      fi
      if switch_on "$name"; then
        return 0
      fi
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}

include_place() {
  local pid=$1
  local pcond=$2
  local psent=$3
  local st=0
  if eval_cond "$pcond"; then
    st=0
  else
    st=$?
  fi
  if [[ "$st" -eq 2 ]]; then
    die "unknown condition for ${pid}: ${pcond}"
  fi
  if [[ "$st" -ne 0 ]]; then
    return 0
  fi
  count=$((count + 1))
  if [[ "$pid" == "t2" ]]; then
    if [[ -n "$t2_sentence" ]]; then
      die "t2 appears twice"
    fi
    t2_sentence=$psent
    return 0
  fi
  printf -- '- %s\n' "$psent" >> "$bullets"
}

flush_place() {
  [[ -n "$id" ]] || return 0
  [[ -n "$cond" ]] || die "${id} has no when line"
  [[ -n "$sentence" ]] || die "${id} has no sentence"
  include_place "$id" "$cond" "$sentence"
  id=""
  cond=""
  sentence=""
  phase=""
}

parse_places() {
  local line
  id=""
  cond=""
  sentence=""
  phase=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ "$line" == "## "* ]]; then
      flush_place
      id=$(trim "${line#"## "}")
      if [[ ! "$id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        die "bad place id in places.md"
      fi
      phase=when
      continue
    fi
    [[ -n "$phase" ]] || continue
    if [[ "$phase" == "when" ]]; then
      [[ -z "$line" ]] && continue
      if [[ "$line" == when:* ]]; then
        cond=$(trim "${line#when:}")
        [[ -n "$cond" ]] || die "${id} has no when condition"
        phase=sentence
        continue
      fi
      die "${id} has no when line"
    fi
    if [[ "$phase" == "sentence" ]]; then
      if [[ -z "$line" ]]; then
        continue
      fi
      sentence=$line
      phase=gap
      continue
    fi
    if [[ -z "$line" ]]; then
      continue
    fi
    die "${id} has more than one sentence"
  done < "$places_file"
  flush_place
}

compose() {
  {
    printf '%s\n' "# Privacy"
    printf '\n'
    printf '%s\n' "Made by \`skills/privacy/privacy.sh\` from the level and switches in \`company-profile.md\`. Do not edit by hand."
    printf '\n'
    if [[ -n "$t2_sentence" ]]; then
      printf '%s\n' "$t2_sentence"
      printf '\n'
    fi
    printf '%s\n' "## Where copies of your data sit"
    printf '\n'
    if [[ -s "$bullets" ]]; then
      cat "$bullets"
    fi
  } > "$out"
}

# Invoked by trap, not by a direct call.
# shellcheck disable=SC2329
cleanup() {
  if [[ -n "${work:-}" ]]; then
    rm -rf "$work"
  fi
  if [[ -n "${stage:-}" ]]; then
    rm -f "$stage"
  fi
}

deliver() {
  local dest="$ROOT/privacy.md"
  local word=places
  if [[ "$count" -eq 1 ]]; then
    word=place
  fi
  if [[ "$stdout_mode" -eq 1 ]]; then
    cat "$out"
    return 0
  fi
  if [[ "$check_mode" -eq 1 ]]; then
    if [[ -f "$dest" ]] && cmp -s "$out" "$dest"; then
      printf '%s\n' "privacy.md: current"
      return 0
    fi
    die "privacy.md is not current"
  fi
  if [[ ! -f "$dest" ]] || ! cmp -s "$out" "$dest"; then
    stage=$(mktemp "$ROOT/privacy.md.XXXXXX")
    cp "$out" "$stage"
    chmod 644 "$stage"
    mv "$stage" "$dest"
    stage=""
  fi
  printf 'privacy.md: %s %s\n' "$count" "$word"
}

ROOT="."
stdout_mode=0
check_mode=0
LEVEL=""
SWITCHES=""
list_key=""
count=0
t2_sentence=""
id=""
cond=""
sentence=""
phase=""
work=""
stage=""
bullets=""
out=""
places_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --root)
      [[ $# -ge 2 ]] || die "missing folder for --root"
      [[ "$2" == --* ]] && die "missing folder for --root"
      ROOT=$2
      shift 2
      ;;
    --stdout)
      stdout_mode=1
      shift
      ;;
    --check)
      check_mode=1
      shift
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ "$stdout_mode" -eq 1 && "$check_mode" -eq 1 ]]; then
  die "--stdout and --check cannot be used together"
fi

if [[ ! -d "$ROOT" ]]; then
  die "no company-profile.md" 2
fi
ROOT=$(cd "$ROOT" && pwd -P)
[[ -f "$ROOT/company-profile.md" ]] || die "no company-profile.md" 2

script_dir=$(cd "$(dirname "$0")" && pwd)
places_file="$script_dir/places.md"
[[ -f "$places_file" ]] || die "no places.md next to this script"

trap cleanup EXIT
work=$(mktemp -d "${TMPDIR:-/tmp}/privacy.XXXXXX")
bullets="$work/bullets"
out="$work/privacy.md"
: > "$bullets"

load_profile
parse_places
compose
deliver
