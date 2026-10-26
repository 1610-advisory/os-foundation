#!/bin/bash
# Rules merge helpers for upgrade.sh. Bash 3.2. Sourced, not run.
# A v1 area file has no "## 1. Level first". "## Approval tiers [team]" is the marker.

rules_is_v1_file() {
  local f=$1
  [ -f "$f" ] || return 1
  if grep -q '^## 1\. Level first$' "$f"; then
    return 0
  fi
  if grep -q '^## Approval tiers \[team\]$' "$f"; then
    return 0
  fi
  return 1
}

rules_title_word() {
  local s=$1 first rest
  first=$(printf '%s' "$s" | cut -c1 | tr '[:lower:]' '[:upper:]')
  rest=$(printf '%s' "$s" | cut -c2-)
  printf '%s%s' "$first" "$rest"
}

rules_answer_into() {
  local dest=$1 key=$2 name=$3 val
  [ -n "${ANSWERS:-}" ] && [ -f "$ANSWERS" ] || return 0
  val=$(os_answer_or "$key" "$ANSWERS" "")
  [ -n "$val" ] || return 0
  case "$val" in
    *'{{'*) return 0 ;;
  esac
  printf '%s=%s\n' "$name" "$val" >> "$dest"
}

rules_profile_into() {
  local dest=$1 profile=$2 val line
  [ -f "$profile" ] || return 0
  val=$(os_fm_get "$profile" company_slug 2>/dev/null || true)
  case "$val" in
    ""|*'{{'*) ;;
    *) printf 'COMPANY_SLUG=%s\n' "$val" >> "$dest" ;;
  esac
  val=$(os_fm_get "$profile" summary 2>/dev/null || true)
  case "$val" in
    ""|*'{{'*) ;;
    *) printf 'ONE_LINER=%s\n' "$val" >> "$dest" ;;
  esac
  val=$(os_fm_get "$profile" updated 2>/dev/null || true)
  case "$val" in
    ""|*'{{'*) ;;
    *) printf 'DATE=%s\n' "$val" >> "$dest" ;;
  esac
  val=$(os_fm_get "$profile" os_version 2>/dev/null || true)
  case "$val" in
    ""|*'{{'*) ;;
    *) printf 'OS_VERSION=%s\n' "$val" >> "$dest" ;;
  esac
  line=$(grep -m 1 '^# ' "$profile" 2>/dev/null || true)
  line=${line#\# }
  line=$(os_trim "$line")
  case "$line" in
    ""|*'{{'*) ;;
    *) printf 'COMPANY_NAME=%s\n' "$line" >> "$dest" ;;
  esac
}

rules_slug_ok() {
  local s=$1
  case "$s" in
    ""|*[!a-z0-9-]*|-*|*-|*/*) return 1 ;;
  esac
  return 0
}

# ~/acme-os/ in a v0 area rules file. The slug is the text between ~/ and -os/.
rules_slug_from_file() {
  local f=$1 slug
  [ -f "$f" ] || return 1
  slug=$(awk '
    {
      s = $0
      while (match(s, /~\/[a-z0-9]+(-[a-z0-9]+)*-os\//)) {
        hit = substr(s, RSTART + 2, RLENGTH - 6)
        if (hit !~ /\{\{/ && hit != "") {
          print hit
          exit
        }
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$f")
  rules_slug_ok "$slug" || return 1
  printf '%s' "$slug"
}

rules_slug_from_rules() {
  local f area slug
  for f in "$ROOT/AGENTS.md" "$ROOT/CLAUDE.md"; do
    if slug=$(rules_slug_from_file "$f"); then
      printf '%s' "$slug"
      return 0
    fi
  done
  [ -d "$ROOT/areas" ] || return 1
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    for f in "$area/AGENTS.md" "$area/CLAUDE.md"; do
      if slug=$(rules_slug_from_file "$f"); then
        printf '%s' "$slug"
        return 0
      fi
    done
  done
  return 1
}

rules_slug_from_origin() {
  local url name slug
  url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
  [ -n "$url" ] || return 1
  name=${url%/}
  name=${name%.git}
  name=${name##*/}
  name=${name##*:}
  case "$name" in
    *-os) slug=${name%-os} ;;
    *) return 1 ;;
  esac
  rules_slug_ok "$slug" || return 1
  printf '%s' "$slug"
}

# First hit wins: answers, profile, a rules file, the origin repo name, the folder name.
rules_resolve_slug() {
  local slug folder
  if [ -n "${ANSWERS:-}" ] && [ -f "$ANSWERS" ]; then
    slug=$(os_answer_or slug "$ANSWERS" "")
    if ! rules_slug_ok "$slug"; then
      slug=$(os_answer_or company_slug "$ANSWERS" "")
    fi
    if rules_slug_ok "$slug"; then
      printf '%s' "$slug"
      return 0
    fi
  fi
  if [ -f "$ROOT/company-profile.md" ]; then
    slug=$(os_fm_get "$ROOT/company-profile.md" company_slug 2>/dev/null || true)
    if rules_slug_ok "$slug"; then
      printf '%s' "$slug"
      return 0
    fi
  fi
  if slug=$(rules_slug_from_rules); then
    printf '%s' "$slug"
    return 0
  fi
  if slug=$(rules_slug_from_origin); then
    printf '%s' "$slug"
    return 0
  fi
  folder=$(basename "$ROOT")
  case "$folder" in
    *-os)
      slug=${folder%-os}
      if rules_slug_ok "$slug"; then
        printf '%s' "$slug"
        return 0
      fi
      ;;
  esac
  return 1
}

# Later lines win in the values file. Captures win over these, except COMPANY_SLUG.
rules_write_values() {
  local dest=$1 folder=$2 area_slug=$3 slug
  : > "$dest"
  if [ -n "$area_slug" ]; then
    {
      printf 'AREA_SLUG=%s\n' "$area_slug"
      printf 'AREA_NAME=%s\n' "$(rules_title_word "$area_slug")"
    } >> "$dest"
  fi
  rules_answer_into "$dest" company_name COMPANY_NAME
  rules_answer_into "$dest" owner_name OWNER_NAME
  rules_answer_into "$dest" owner_role OWNER_ROLE
  rules_answer_into "$dest" one_liner ONE_LINER
  rules_answer_into "$dest" areas AREAS
  rules_answer_into "$dest" date DATE
  rules_answer_into "$dest" os_version OS_VERSION
  rules_answer_into "$dest" area_name AREA_NAME
  rules_answer_into "$dest" area_slug AREA_SLUG
  rules_profile_into "$dest" "$ROOT/company-profile.md"
  if slug=$(rules_resolve_slug); then
    printf 'COMPANY_SLUG=%s\n' "$slug" >> "$dest"
  fi
}

rules_todos() {
  local f=$1
  [ -f "$f" ] || return 0
  # Only the keys a fresh setup fills. {{APP}} and other skill markers stay.
  awk '
    function fill_key(name) {
      return name == "COMPANY_NAME" || name == "COMPANY_SLUG" || name == "OWNER_NAME" \
        || name == "OWNER_ROLE" || name == "DATE" || name == "ONE_LINER" \
        || name == "AREAS" || name == "OS_VERSION" || name == "AREA_NAME" \
        || name == "AREA_SLUG"
    }
    {
      s = $0
      while (match(s, /\{\{[A-Z][A-Z0-9_]*\}\}/)) {
        name = substr(s, RSTART + 2, RLENGTH - 4)
        if (fill_key(name) && !(name in seen)) {
          seen[name] = 1
          printf "todo: fill {{%s}}\n", name
        }
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$f"
}

rules_best_kind() {
  local real=$1 kind best score best_score stats
  best="_area"
  best_score=-1
  for kind in _area apps finance marketing; do
    [ -f "$DIR/v0/areas/$kind/AGENTS.md" ] || continue
    stats=$(bash "$DIR/rules-merge.sh" --score \
      --base "$DIR/v0/areas/$kind/AGENTS.md" \
      --real "$real" --scope area)
    score=$(printf '%s\n' "$stats" | awk -F= '$1=="matched"{print $2; exit}')
    [ -n "$score" ] || score=0
    if [ "$score" -gt "$best_score" ]; then
      best_score=$score
      best=$kind
    fi
  done
  printf '%s\n' "$best"
}

# write=1 copies the result onto the real file. Dry-run passes 0.
rules_merge_one() {
  local rel=$1 real=$2 base=$3 v1=$4 scope=$5 role=$6 area_slug=$7 write=$8
  local tmp lines chars spill link stats
  [ -f "$real" ] || return 0
  [ -f "$base" ] || return 0
  [ -f "$v1" ] || return 0
  if rules_is_v1_file "$real"; then
    return 0
  fi
  tmp=$(mktemp -d)
  rules_write_values "$tmp/values" "$ROOT" "$area_slug"
  if [ "$role" = "area" ]; then
    link="area-rules.md"
  else
    link="company-rules.md"
  fi
  stats=$(bash "$DIR/rules-merge.sh" \
    --base "$base" --real "$real" --v1 "$v1" --scope "$scope" \
    --values "$tmp/values" --out "$tmp/out.md" --plain "$tmp/plain.md" \
    --spill "$tmp/spill.md" --role "$role" --link "$link")
  lines=$(printf '%s\n' "$stats" | awk -F= '$1=="company-lines"{print $2; exit}')
  chars=$(printf '%s\n' "$stats" | awk -F= '$1=="chars"{print $2; exit}')
  spill=$(printf '%s\n' "$stats" | awk -F= '$1=="spill"{print $2; exit}')
  [ -n "$lines" ] || lines=0
  [ -n "$chars" ] || chars=0
  printf 'change: rules-merge %s company-lines=%s chars=%s\n' "$rel" "$lines" "$chars"
  if [ "$spill" = "1" ]; then
    printf 'change: rules-spill %s -> %s\n' "$rel" "$link"
  fi
  rules_todos "$tmp/out.md"
  if [ "$write" = "1" ]; then
    cp "$tmp/out.md" "$real"
    if [ "$spill" = "1" ]; then
      cp "$tmp/spill.md" "$(dirname "$real")/$link"
    fi
  fi
  rm -rf "$tmp"
}

rules_plan_company() {
  local write=$1
  if [ -f "$ROOT/AGENTS.md" ] && rules_is_v1_file "$ROOT/AGENTS.md"; then
    return 0
  fi
  rules_merge_one "AGENTS.md" "$ROOT/AGENTS.md" "$DIR/v0/AGENTS.md" \
    "$TEMPLATE/AGENTS.md" company company "" "$write"
  rules_merge_one "CLAUDE.md" "$ROOT/CLAUDE.md" "$DIR/v0/CLAUDE.md" \
    "$TEMPLATE/CLAUDE.md" claude company "" "$write"
}

rules_area_v1() {
  local kind=$1 name=$2
  local path="$TEMPLATE/skills/add-area/templates/$kind/$name"
  if [ -f "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi
  if [ "$name" = "CLAUDE.md" ] && [ -f "$TEMPLATE/skills/add-area/templates/_area/CLAUDE.md" ]; then
    printf '%s\n' "$TEMPLATE/skills/add-area/templates/_area/CLAUDE.md"
    return 0
  fi
  return 1
}

rules_one_area() {
  local area=$1 write=$2 name kind base v1 rel
  name=$(basename "$area")
  [ -f "$area/AGENTS.md" ] || return 0
  if rules_is_v1_file "$area/AGENTS.md"; then
    return 0
  fi
  kind=$(rules_best_kind "$area/AGENTS.md")
  base="$DIR/v0/areas/$kind/AGENTS.md"
  v1=$(rules_area_v1 "$kind" AGENTS.md) || return 0
  rel="areas/${name}/AGENTS.md"
  rules_merge_one "$rel" "$area/AGENTS.md" "$base" "$v1" area area "$name" "$write"
  if [ -f "$area/CLAUDE.md" ]; then
    base="$DIR/v0/areas/_area/CLAUDE.md"
    if v1=$(rules_area_v1 "$kind" CLAUDE.md); then
      rules_merge_one "areas/${name}/CLAUDE.md" "$area/CLAUDE.md" "$base" "$v1" \
        claude area "$name" "$write"
    fi
  fi
  rules_maybe_attrs "$area" "$kind" "$write" "areas/${name}"
}

rules_maybe_attrs() {
  local dest_dir=$1 kind=$2 write=$3 rel=$4 src
  src=""
  if [ -n "$kind" ]; then
    if [ -f "$TEMPLATE/skills/add-area/templates/$kind/.gitattributes" ]; then
      src="$TEMPLATE/skills/add-area/templates/$kind/.gitattributes"
    fi
  elif [ -f "$TEMPLATE/.gitattributes" ]; then
    src="$TEMPLATE/.gitattributes"
  fi
  [ -n "$src" ] || return 0
  [ -e "$dest_dir/.gitattributes" ] && return 0
  if [ -n "$rel" ]; then
    printf 'change: .gitattributes %s\n' "$rel"
  else
    printf '%s\n' "change: .gitattributes"
  fi
  if [ "$write" = "1" ]; then
    cp "$src" "$dest_dir/.gitattributes"
  fi
}

rules_plan_areas() {
  local area
  [ -d "$ROOT/areas" ] || return 0
  for area in "$ROOT"/areas/*; do
    [ -d "$area" ] || continue
    rules_one_area "$area" 0
  done
}

rules_commit_msg() {
  local dir=$1 msg=$2
  GIT_AUTHOR_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_AUTHOR_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    GIT_COMMITTER_NAME="${OS_GIT_NAME:-Company OS}" \
    GIT_COMMITTER_EMAIL="${OS_GIT_EMAIL:-os@localhost}" \
    git -C "$dir" commit -q -m "$msg"
}

rules_stage_rules() {
  local dir=$1 f
  for f in AGENTS.md CLAUDE.md company-rules.md area-rules.md .gitattributes; do
    if [ -e "$dir/$f" ]; then
      git -C "$dir" add -- "$f"
    fi
  done
}

rules_pr_body() {
  local repo=$1 base=$2 dest=$3 subject
  {
    printf '%s\n' "Rules merge (code owner reviews this first):"
    if git -C "$repo" log --format='%s' "${base}..HEAD" | grep -qx 'Upgrade: rules merge'; then
      printf '%s\n' "- Upgrade: rules merge"
    fi
    printf '\n%s\n' "Other changes:"
    git -C "$repo" log --format='%s' "${base}..HEAD" | while IFS= read -r subject; do
      [ "$subject" = "Upgrade: rules merge" ] && continue
      printf -- '- %s\n' "$subject"
    done
  } > "$dest"
}
