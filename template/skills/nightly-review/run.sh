#!/bin/bash
# Review one day's merged changes. Fix clear errors. Flag the rest.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"

usage() {
  cat << 'EOF'
Usage: run.sh [--date YYYY-MM-DD] [--root DIR]

Review the day's merged changes on main for the company root and each area.
Fix a clear error by a pull request on review/<date>. Flag a judgment call.
Fold logs older than 30 days. Exit 2 when the review did not run.
EOF
}

NR_DATE=""
NR_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --date)
      [ $# -ge 2 ] || nr_die "run.sh: missing date"
      NR_DATE=$2
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || nr_die "run.sh: missing root"
      NR_ROOT=$2
      shift 2
      ;;
    *)
      nr_die "run.sh: unknown argument"
      ;;
  esac
done

if [ -n "$NR_DATE" ] && ! nr_valid_date "$NR_DATE"; then
  nr_die "run.sh: date must be YYYY-MM-DD"
fi

if [ -z "$NR_ROOT" ]; then
  if [ -f company-profile.md ]; then
    NR_ROOT=$(pwd)
  else
    nr_die "run.sh: company-profile.md not found. Pass --root."
  fi
fi
NR_ROOT=$(cd "$NR_ROOT" && pwd)
cd "$NR_ROOT"
umask 077
nr_prepare

nr_ours() {
  git -C "$1" log -1 --format=%B "$2" | grep -q '^Run-Id: review-'
}

nr_collect_commits() {
  local repo=$1 base=$2 last=$3 date=$4 next out sha subject
  next=$(nr_date_add "$date" 1)
  out=$(mktemp)
  if [ -n "$last" ] && git -C "$repo" cat-file -e "${last}^{commit}" 2>/dev/null; then
    git -C "$repo" log --no-merges --format='%H%x09%s' \
      --since="${date} 00:00:00" --until="${next} 00:00:00" \
      "${last}..${base}" > "$out" || true
  else
    git -C "$repo" log --no-merges --format='%H%x09%s' \
      --since="${date} 00:00:00" --until="${next} 00:00:00" \
      "$base" > "$out" || true
  fi
  while IFS="$(printf '\t')" read -r sha subject || [ -n "${sha:-}" ]; do
    [ -n "${sha:-}" ] || continue
    if nr_ours "$repo" "$sha"; then
      continue
    fi
    printf '%s\t%s\n' "$sha" "$subject"
  done < "$out"
  rm -f "$out"
}

nr_build_diff() {
  local repo=$1 commits=$2 diff sha
  diff=$(mktemp)
  : > "$diff"
  while IFS="$(printf '\t')" read -r sha _rest || [ -n "${sha:-}" ]; do
    [ -n "${sha:-}" ] || continue
    git -C "$repo" show --format= --patch "$sha" -- . \
      ':(exclude)reports' ':(exclude)users' ':(exclude)profile' ':(exclude)traces' \
      >> "$diff" || true
  done < "$commits"
  local size
  size=$(wc -c < "$diff" | tr -d ' ')
  if [ "$size" -gt 200000 ]; then
    head -c 200000 "$diff" > "${diff}.cut"
    printf '\ndiff truncated\n' >> "${diff}.cut"
    mv "${diff}.cut" "$diff"
  fi
  printf '%s\n' "$diff"
}

nr_apply_replace() {
  local file=$1 old=$2 new=$3
  [ -f "$file" ] || return 1
  case "$old" in
    *$'\n'*) return 1 ;;
  esac
  OLD="$old" NEW="$new" awk '
    BEGIN { old = ENVIRON["OLD"]; new = ENVIRON["NEW"]; n = 0 }
    {
      rest = $0
      while (index(rest, old) > 0) {
        n++
        rest = substr(rest, index(rest, old) + length(old))
      }
    }
    END { if (n != 1) exit 1 }
  ' "$file" || return 1
  OLD="$old" NEW="$new" awk '
    BEGIN { old = ENVIRON["OLD"]; new = ENVIRON["NEW"]; done = 0 }
    {
      if (!done) {
        s = index($0, old)
        if (s > 0) {
          $0 = substr($0, 1, s - 1) new substr($0, s + length(old))
          done = 1
        }
      }
      print
    }
  ' "$file" > "${file}.nr-tmp"
  mv "${file}.nr-tmp" "$file"
}

nr_flag_id() {
  printf '%s\n%s\n%s\n' "$1" "$2" "$3" | git hash-object --stdin
}

nr_add_item() {
  local rel=$1 path=$2 summary=$3 author=$4 approver=$5 audience=$6 kind=$7 escalated=$8
  local leak id item
  leak=${9:-false}
  id=$(nr_flag_id "$rel" "$path" "$summary")
  item=$(jq -nc \
    --arg repo "$rel" --arg path "$path" --arg summary "$summary" \
    --arg author "$author" --arg approver "$approver" --arg audience "$audience" \
    --arg kind "$kind" --argjson escalated "$escalated" --argjson leak "$leak" --arg id "$id" \
    --arg date "$NR_DATE" \
    '{repo:$repo,path:$path,summary:$summary,author:$author,approver:$approver,audience:$audience,kind:$kind,escalated:$escalated,leak:$leak,id:$id,date:$date}')
  jq --argjson item "$item" '. += [$item]' "$NR_ITEMS" > "${NR_ITEMS}.tmp"
  mv "${NR_ITEMS}.tmp" "$NR_ITEMS"
}

nr_audience() {
  local author=$1 approver=$2 rules=$3 id=$4
  if [ "$rules" = "1" ] || [ -z "$author" ]; then
    printf '%s\n' "$approver"
    return 0
  fi
  if nr_was_open "$id"; then
    printf '%s\n' "$approver"
    return 0
  fi
  printf '%s\n' "$author"
}

nr_review_diff() {
  local repo=$1 rel=$2 commits=$3 prompt=$4 diff input line
  local area approver base_ref files_all files_n
  area=$(nr_area_of "$rel")
  approver=$(nr_director_slug "$area")
  base_ref=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if git -C "$repo" show-ref --verify --quiet refs/remotes/origin/main && [ "${OS_SKIP_FETCH:-}" != "1" ]; then
    base_ref="origin/main"
  else
    base_ref="main"
  fi
  diff=$(nr_build_diff "$repo" "$commits")
  input=$(mktemp)
  chmod 600 "$input"
  if [ -f "$prompt" ]; then
    cat "$prompt" > "$input"
    printf '\n\n' >> "$input"
  fi
  {
    printf '%s\n' "---INPUT---"
    printf '%s\n' "kind: review"
    printf 'repo: %s\n' "$rel"
    printf 'date: %s\n' "$NR_DATE"
    printf '%s\n' "commits:"
    while IFS="$(printf '\t')" read -r sha subject || [ -n "${sha:-}" ]; do
      [ -n "${sha:-}" ] || continue
      printf '%s %s %s\n' "$sha" "$(nr_commit_slug "$repo" "$sha")" "$subject"
    done < "$commits"
    printf '%s\n' "files:"
    files_all=$(mktemp)
    git -C "$repo" ls-tree -r --name-only "$base_ref" | awk '
      $0 ~ /^(users|profile|traces)\// { next }
      { print }
    ' > "$files_all"
    files_n=$(wc -l < "$files_all" | tr -d ' ')
    awk 'NR<=400' "$files_all"
    if [ "$files_n" -gt 400 ]; then
      printf 'and %s more files\n' $((files_n - 400))
    fi
    rm -f "$files_all"
    printf '%s\n' "diff:"
    cat "$diff"
    printf '%s\n' "---END---"
  } >> "$input"
  rm -f "$diff"
  set +e
  line=$(nr_engine_json "$input")
  local rc=$?
  set -e
  rm -f "$input"
  if [ "$rc" -ne 0 ]; then
    return 1
  fi
  printf '%s\n' "$line" > "$NR_ENGINE_OUT"
  local n i kind path summary author action old new rules escalated audience id
  n=$(printf '%s' "$line" | jq '.findings // [] | length')
  i=0
  while [ "$i" -lt "$n" ]; do
    kind=$(printf '%s' "$line" | jq -r ".findings[$i].kind // \"\"")
    path=$(printf '%s' "$line" | jq -r ".findings[$i].path // \"\"")
    summary=$(printf '%s' "$line" | jq -r ".findings[$i].summary // \"\"")
    author=$(printf '%s' "$line" | jq -r ".findings[$i].author // \"\"")
    action=$(printf '%s' "$line" | jq -r ".findings[$i].fix.action // \"\"")
    if ! nr_slug_known "$author"; then
      author=$(nr_file_author "$repo" "$path" || true)
    fi
    rules=0
    if nr_is_rules_path "$path"; then
      rules=1
    fi
    if ! nr_safe_rel "$path" >/dev/null; then
      i=$((i + 1))
      continue
    fi
    id=$(nr_flag_id "$rel" "$path" "$summary")
    escalated=false
    if nr_was_open "$id"; then
      escalated=true
    fi
    audience=$(nr_audience "$author" "$approver" "$rules" "$id")
    case "$summary" in
      "Possible leak:"*)
        audience=$(nr_admin_slug)
        nr_add_item "$rel" "$path" "$summary" "$author" "$audience" "$audience" "judgment" false true
        i=$((i + 1))
        continue
        ;;
    esac
    if [ "$kind" = "clear-error" ] && [ "$rules" = "0" ]; then
      printf '%s\n' "$line" | jq -c ".findings[$i]" >> "$NR_FIXES"
    else
      if [ "$rules" = "1" ] && [ "$kind" = "clear-error" ]; then
        summary="Rules file: ${summary}"
      fi
      nr_add_item "$rel" "$path" "$summary" "$author" "$approver" "$audience" "judgment" "$escalated"
    fi
    i=$((i + 1))
  done
  # Decision lines in the diff, listed first by kind.
  while IFS="$(printf '\t')" read -r sha _rest || [ -n "${sha:-}" ]; do
    [ -n "${sha:-}" ] || continue
    git -C "$repo" show --format= --patch "$sha" -- . \
      ':(exclude)reports' ':(exclude)users' ':(exclude)profile' ':(exclude)traces' \
      | grep '^+Decision:' | sed 's/^+//' > "$NR_DECISIONS" || true
    while IFS= read -r dline || [ -n "$dline" ]; do
      [ -n "$dline" ] || continue
      nr_add_item "$rel" "log" "$dline" "" "$approver" "$approver" "decision" false
    done < "$NR_DECISIONS"
  done < "$commits"
  return 0
}

nr_fold_plan() {
  local repo=$1 rel=$2 tree=$3 cutoff month f name day input line summary months month_list
  cutoff=$(nr_date_add "$NR_DATE" -30)
  : > "$NR_FOLD_RM"
  : > "$NR_FOLD_SUM"
  git -C "$repo" ls-tree -r --name-only "$tree" -- memory/logs > "$NR_FOLD_RM.list" || true
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    name=$(basename "$f")
    case "$name" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
      *) continue ;;
    esac
    day=$(printf '%s' "$name" | cut -c1-10)
    if [ "$day" \< "$cutoff" ]; then
      printf '%s\n' "$f" >> "$NR_FOLD_RM"
    fi
  done < "$NR_FOLD_RM.list"
  rm -f "$NR_FOLD_RM.list"
  if [ ! -s "$NR_FOLD_RM" ]; then
    return 0
  fi
  # One engine call per month.
  local months
  months=$(mktemp)
  while IFS= read -r f; do
    printf '%s\n' "$(basename "$f" | cut -c1-7)"
  done < "$NR_FOLD_RM" | sort -u > "$months"
  month_list=$(cat "$months")
  rm -f "$months"
  while IFS= read -r month; do
    [ -n "$month" ] || continue
    input=$(mktemp)
    chmod 600 "$input"
    {
      printf '%s\n' "---INPUT---"
      printf '%s\n' "kind: fold"
      printf 'month: %s\n' "$month"
      printf 'repo: %s\n' "$rel"
      printf '%s\n' "instruction: Summarize these logs in plain sentences. No scores. No ranking. No private quotes."
      while IFS= read -r f; do
        case "$(basename "$f")" in
          "$month"-*) ;;
          *) continue ;;
        esac
        printf 'file: %s\n' "$f"
        printf '%s\n' "---"
        git -C "$repo" show "$tree:$f"
        printf '\n%s\n' "---"
      done < "$NR_FOLD_RM"
      if git -C "$repo" cat-file -e "$tree:memory/logs/${month}-summary.md" 2>/dev/null; then
        printf '%s\n' "current summary:"
        git -C "$repo" show "$tree:memory/logs/${month}-summary.md"
        printf '\n'
      fi
      printf '%s\n' "---END---"
    } > "$input"
    set +e
    line=$(nr_engine_json "$input")
    local rc=$?
    set -e
    rm -f "$input"
    if [ "$rc" -ne 0 ]; then
      return 1
    fi
    summary=$(printf '%s' "$line" | jq -r '.summary // ""')
    printf '%s\n' "$summary" | nr_drop_ranked > "${input}.sum" || true
    if [ ! -s "${input}.sum" ]; then
      printf 'Folded log files for %s.\n' "$month" > "${input}.sum"
    fi
    printf '%s\t%s\n' "$month" "${input}.sum" >> "$NR_FOLD_SUM"
  done << EOF
${month_list}
EOF
  return 0
}

nr_apply_in_wt() {
  local wt=$1 line path action old new content
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    path=$(printf '%s' "$line" | jq -r '.path')
    action=$(printf '%s' "$line" | jq -r '.fix.action // ""')
    if ! nr_safe_rel "$path" >/dev/null; then
      continue
    fi
    if nr_is_rules_path "$path"; then
      continue
    fi
    case "$path" in
      reports/*|users/*|profile/*|traces/*) continue ;;
    esac
    if [ "$action" = "replace" ]; then
      old=$(printf '%s' "$line" | jq -r '.fix.old // ""')
      new=$(printf '%s' "$line" | jq -r '.fix.new // ""')
      if ! nr_apply_replace "$wt/$path" "$old" "$new"; then
        if [ -f "$wt/$path" ] && grep -F -q "$new" "$wt/$path"; then
          continue
        fi
        nr_add_item "$NR_REL" "$path" "Could not apply the fix." "" \
          "$(nr_director_slug "$(nr_area_of "$NR_REL")")" \
          "$(nr_director_slug "$(nr_area_of "$NR_REL")")" "judgment" false
      fi
    elif [ "$action" = "write" ]; then
      content=$(mktemp)
      printf '%s' "$line" | jq -r '.fix.content // ""' > "$content"
      parent=$(dirname "$wt/$path")
      if [ -d "$parent" ]; then
        mv "$content" "$wt/$path"
      else
        rm -f "$content"
      fi
    fi
  done < "$NR_FIXES"
  local month sum f line missing name
  mkdir -p "$wt/memory/logs"
  while IFS="$(printf '\t')" read -r month sum || [ -n "${month:-}" ]; do
    [ -n "${month:-}" ] || continue
    if [ -f "$wt/memory/logs/${month}-summary.md" ]; then
      {
        printf '\nFolded on %s. The originals stay in git history.\n\n' "$NR_DATE"
        cat "$sum"
      } >> "$wt/memory/logs/${month}-summary.md"
    else
      {
        printf '# %s summary\n\n' "$month"
        printf 'Folded on %s. The originals stay in git history.\n\n' "$NR_DATE"
        cat "$sum"
      } > "$wt/memory/logs/${month}-summary.md"
    fi
    rm -f "$sum"
  done < "$NR_FOLD_SUM"
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    [ -f "$wt/$f" ] || continue
    name=$(basename "$f")
    month=$(printf '%s' "$name" | cut -c1-7)
    missing=0
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        Decision:*)
          if ! grep -F -q "$line" "$wt/memory/logs/${month}-summary.md" 2>/dev/null; then
            missing=1
          fi
          ;;
      esac
    done < "$wt/$f"
    if [ "$missing" = "1" ]; then
      printf '%s kept %s: a Decision line is not in the summary.\n' "$NR_DATE" "$f" >> "$NR_LOG"
      continue
    fi
    git -C "$wt" rm -q -f -- "$f"
  done < "$NR_FOLD_RM"
}

nr_plan_repo() {
  local repo=$1 rel=$2 id=$3 base last commits n
  NR_REL=$rel
  : > "$NR_FIXES"
  : > "$NR_FOLD_RM"
  : > "$NR_FOLD_SUM"
  printf '%s\n' '[]' > "$NR_ITEMS"
  set +e
  base=$(nr_sync_base "$repo")
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$rel" >> "$NR_FAILED_REPOS"
    return 1
  fi
  last=$(nr_saved_sha "$rel" || true)
  commits=$(mktemp)
  nr_collect_commits "$repo" "$base" "$last" "$NR_DATE" > "$commits" || true
  n=$(grep -c . "$commits" || true)
  if [ "$n" -gt 0 ]; then
    if ! nr_review_diff "$repo" "$rel" "$commits" "$DIR/review-prompt.md"; then
      printf '%s\n' "$rel" >> "$NR_FAILED_REPOS"
      rm -f "$commits"
      return 1
    fi
  fi
  if ! nr_fold_plan "$repo" "$rel" "$base"; then
    printf '%s\n' "$rel" >> "$NR_FAILED_REPOS"
    rm -f "$commits"
    return 1
  fi
  printf '%s\n' "$repo" > "$NR_PLAN/$id.repo"
  printf '%s\n' "$rel" > "$NR_PLAN/$id.rel"
  printf '%s\n' "$base" > "$NR_PLAN/$id.base"
  printf '%s\n' "$n" > "$NR_PLAN/$id.ncommits"
  cp "$NR_FIXES" "$NR_PLAN/$id.fixes"
  cp "$NR_ITEMS" "$NR_PLAN/$id.items"
  cp "$NR_FOLD_RM" "$NR_PLAN/$id.foldrm"
  cp "$NR_FOLD_SUM" "$NR_PLAN/$id.foldsum"
  : > "$NR_PLAN/$id.ready"
  rm -f "$commits"
  return 0
}

nr_apply_plan() {
  local id=$1 repo rel base ncommits wt branch sha
  repo=$(cat "$NR_PLAN/$id.repo")
  rel=$(cat "$NR_PLAN/$id.rel")
  base=$(cat "$NR_PLAN/$id.base")
  ncommits=$(cat "$NR_PLAN/$id.ncommits")
  NR_REL=$rel
  cp "$NR_PLAN/$id.fixes" "$NR_FIXES"
  cp "$NR_PLAN/$id.items" "$NR_ITEMS"
  cp "$NR_PLAN/$id.foldrm" "$NR_FOLD_RM"
  cp "$NR_PLAN/$id.foldsum" "$NR_FOLD_SUM"
  if [ -s "$NR_FIXES" ] || [ -s "$NR_FOLD_RM" ]; then
    branch="review/${NR_DATE}"
    set +e
    wt=$(nr_worktree_open "$repo" "$base" "$branch")
    local rc=$?
    set -e
    if [ "$rc" -ne 0 ] || [ -z "$wt" ]; then
      nr_fail_line
      printf '%s\n' "$rel" >> "$NR_FAILED_REPOS"
      return 0
    fi
    nr_load_identity "$(nr_area_of "$rel")"
    nr_apply_in_wt "$wt"
    if ! nr_publish "$wt" "$rel" "Review ${NR_DATE}"; then
      nr_worktree_close "$repo" "$wt"
      nr_fail_line
      printf '%s\n' "$rel" >> "$NR_FAILED_REPOS"
      return 0
    fi
    nr_worktree_close "$repo" "$wt"
  fi
  sha=$(git -C "$repo" rev-parse "$base")
  nr_save_sha "$rel" "$sha"
  if [ "$ncommits" -gt 0 ]; then
    nr_replace_repo_flags "$rel" "$NR_ITEMS"
  fi
}

nr_write_digests() {
  local cap json md
  cap=$(nr_cap)
  json="$NR_STATE_DIR/digests/${NR_DATE}.json"
  jq -n \
    --arg date "$NR_DATE" \
    --argjson ran "$([ "$NR_FAILED" = "1" ] && printf 'false' || printf 'true')" \
    --slurpfile flags "$NR_STATE" \
    --rawfile failed "$NR_FAILED_REPOS" \
    '{
      date: $date,
      review_ran: $ran,
      failed_repos: ($failed | split("\n") | map(select(length > 0)) | unique),
      items: ($flags[0].flags // [])
    }' > "$json"
  chmod 600 "$json"
  # One markdown digest per audience.
  local audiences
  audiences=$(jq -r '.items[].audience // empty' "$json" | sort -u)
  if [ "$NR_FAILED" = "1" ]; then
    audiences=$(printf '%s\n%s\n' "$audiences" "$(nr_admin_slug)" | sort -u)
  fi
  local person
  for person in $audiences; do
    [ -n "$person" ] || continue
    md="$NR_STATE_DIR/digests/${NR_DATE}-${person}.md"
    {
      printf '# Digest %s\n\n' "$NR_DATE"
      if [ "$NR_FAILED" = "1" ]; then
        printf '%s\n\n' "The review did not run."
      fi
      jq -r --arg p "$person" '
        [.items[] | select(.audience == $p)]
        | sort_by(if .kind == "decision" then 0 else 1 end, .repo, .path)
        | .[] | [.repo, .path, .summary] | @tsv
      ' "$json" | awk -F '\t' -v cap="$cap" '
        BEGIN { n = 0; area = "" }
        {
          n++
          if (n > cap) { next }
          repo = $1
          if (repo == ".") a = "company"
          else if (index(repo, "areas/") == 1) a = substr(repo, 7)
          else a = repo
          if (a != area) {
            if (area != "") print ""
            print "## " a
            print ""
            area = a
          }
          print "- " $2 " — " $3
        }
        END {
          if (n > cap) print "and " (n - cap) " more"
        }
      '
    } > "$md"
    chmod 600 "$md"
  done
}

nr_lock
NR_PLAN=$(mktemp -d)
trap 'nr_unlock; rm -rf "$NR_PLAN"' EXIT
NR_FAILED_REPOS=$(mktemp)
: > "$NR_FAILED_REPOS"
if [ ! -f "$DIR/review-prompt.md" ] || ! nr_load_engine; then
  nr_fail_line
  nr_write_digests
  exit 2
fi
if [ ! -x "${NR_ENGINE[0]}" ] && ! command -v "${NR_ENGINE[0]}" >/dev/null 2>&1; then
  nr_fail_line
  nr_write_digests
  exit 2
fi

NR_ITEMS=$(mktemp)
NR_FIXES=$(mktemp)
NR_FOLD_RM=$(mktemp)
NR_FOLD_SUM=$(mktemp)
NR_ENGINE_OUT=$(mktemp)
NR_DECISIONS=$(mktemp)
printf '%s\n' '[]' > "$NR_ITEMS"
plan_id=0
plan_fail=0
if [ -d "$NR_ROOT/.git" ] || [ -f "$NR_ROOT/.git" ]; then
  if ! nr_plan_repo "$NR_ROOT" "." "$plan_id"; then
    plan_fail=1
  fi
  plan_id=$((plan_id + 1))
fi
for dir in "$NR_ROOT"/areas/*; do
  [ -d "$dir" ] || continue
  if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
    if ! nr_plan_repo "$dir" "areas/$(basename "$dir")" "$plan_id"; then
      plan_fail=1
    fi
    plan_id=$((plan_id + 1))
  fi
done
if [ "$plan_fail" = "1" ]; then
  nr_fail_line
  NR_FAILED=1
  nr_write_digests
  exit 2
fi
for ready in "$NR_PLAN"/*.ready; do
  [ -f "$ready" ] || continue
  nr_apply_plan "$(basename "$ready" .ready)"
done

nr_write_digests
rm -f "$NR_ITEMS" "$NR_FIXES" "$NR_FOLD_RM" "$NR_FOLD_SUM" "$NR_ENGINE_OUT" "$NR_FAILED_REPOS" "$NR_DECISIONS"

if [ "$NR_FAILED" = "1" ]; then
  exit 2
fi
exit 0
