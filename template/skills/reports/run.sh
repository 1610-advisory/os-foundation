#!/bin/bash
# Write the daily "to decide" file and the weekly report pages.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../nightly-review/lib.sh"

usage() {
  cat << 'EOF'
Usage: run.sh [--date YYYY-MM-DD] [--week YYYY-Www] [--daily] [--root DIR]

Write reports/YYYY-MM-DD-to-decide.md when it is not empty, and reports/YYYY-Www.md,
in each area. Write the company pages, reports/YYYY-MM-DD-to-decide-company.md and
reports/YYYY-Www-company.md, in the owners' area (report_area: in
company-profile.md, default admin). Nothing is written at the company root.
The file is the delivery. This script does not send mail or chat.
EOF
}

NR_DATE=""
NR_ROOT=""
WEEK=""
MODE_DAILY=0
MODE_WEEK=0

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
    --week)
      [ $# -ge 2 ] || nr_die "run.sh: missing week"
      WEEK=$2
      MODE_WEEK=1
      shift 2
      ;;
    --daily)
      MODE_DAILY=1
      shift
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
if [ -n "$WEEK" ] && ! nr_valid_week "$WEEK"; then
  nr_die "run.sh: week must be YYYY-Www"
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
nr_lock
trap 'nr_unlock; nr_tmp_cleanup' EXIT

if [ -z "$WEEK" ]; then
  # The job runs at 03:30. On a Monday the new week has no work yet, so the
  # weekly pages are for the week that just ended. Tuesday on, the current week.
  if [ "$(nr_dow "$NR_DATE")" = "1" ]; then
    WEEK=$(nr_iso_week "$(nr_date_add "$NR_DATE" -1)")
  else
    WEEK=$(nr_iso_week "$NR_DATE")
  fi
fi

DO_DAILY=1
DO_WEEKLY=1
if [ "$MODE_DAILY" = "1" ] && [ "$MODE_WEEK" = "0" ]; then
  DO_WEEKLY=0
fi

DIGEST="$NR_STATE_DIR/digests/${NR_DATE}.json"
if [ ! -f "$DIGEST" ]; then
  printf '%s\n' '{"date":"","review_ran":true,"failed_repos":[],"items":[]}' > "$DIGEST"
  chmod 600 "$DIGEST"
fi

rp_mdx() {
  nr_switch_on mdx-reports
}

rp_front() {
  local summary=$2 extra=$3
  local format="markdown"
  if rp_mdx; then
    format="mdx"
  fi
  printf '%s\n' "---"
  printf '%s\n' "type: report"
  printf 'summary: "%s"\n' "$summary"
  printf '%s\n' "$extra"
  printf 'format: %s\n' "$format"
  printf '%s\n' "---"
  printf '\n'
}

rp_counts_block() {
  local commits=$1 logs=$2 people=$3
  if rp_mdx; then
    local data
    data=$(jq -nc --argjson c "$commits" --argjson l "$logs" --argjson p "$people" \
      '[{"name":"Commits merged","value":$c},{"name":"Log files","value":$l},{"name":"People with actions","value":$p}]')
    printf '<Callout>Counts for this page.</Callout>\n\n'
    printf '<Chart title="Counts" data='\''%s'\'' />\n\n' "$data"
    printf '<Table>\n\n'
  fi
  printf '%s\n' "| What | Count |"
  printf '%s\n' "|---|---|"
  printf '| Commits merged | %s |\n' "$commits"
  printf '| Log files | %s |\n' "$logs"
  printf '| People with actions | %s |\n' "$people"
  if rp_mdx; then
    printf '\n</Table>\n'
  fi
}

rp_failed() {
  local rel=$1
  jq -e --arg r "$rel" '.failed_repos | index($r) != null' "$DIGEST" >/dev/null 2>&1
}

# True when the branch's changes are already on BASE. A squash or rebase merge leaves
# no ancestry, so compare content: the files the branch changed are the same on BASE,
# or BASE has a commit with the same patch.
rp_rules_merged() {
  local repo=$1 ref=$2 base=$3 mb pid c f
  local files=()
  if git -C "$repo" merge-base --is-ancestor "$ref" "$base" 2>/dev/null; then
    return 0
  fi
  mb=$(git -C "$repo" merge-base "$ref" "$base" 2>/dev/null) || return 1
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(git -C "$repo" diff --name-only "$mb" "$ref" 2>/dev/null)
  [ "${#files[@]}" -gt 0 ] || return 0
  if git -C "$repo" diff --quiet "$base" "$ref" -- "${files[@]}" 2>/dev/null; then
    return 0
  fi
  pid=$(git -C "$repo" diff "$mb" "$ref" | git patch-id --stable | awk '{ print $1 }')
  [ -n "$pid" ] || return 1
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ "$(git -C "$repo" show "$c" | git patch-id --stable | awk '{ print $1 }')" = "$pid" ]; then
      return 0
    fi
  done < <(git -C "$repo" log --no-merges --format=%H "$mb..$base" -- "${files[@]}")
  return 1
}

# One line per rules branch not yet on BASE, by branch name. A branch that is both
# local and on origin is one line; the origin copy is the one that counts.
rp_rules_waiting() {
  local repo=$1 base=$2 short name ref
  git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/rules refs/remotes/origin/rules \
    | while IFS= read -r short; do
        case "$short" in
          origin/rules/*) printf '%s\t%s\n' "${short#origin/}" "0" ;;
          rules/*) printf '%s\t%s\n' "$short" "1" ;;
        esac
      done | sort -t "$(printf '\t')" -k1,1 -k2,2n | awk -F '\t' '!seen[$1]++ { print $1 "\t" $2 }' \
    | while IFS="$(printf '\t')" read -r name local_only; do
        if [ "$local_only" = "0" ]; then
          ref="origin/$name"
        else
          ref="$name"
        fi
        if rp_rules_merged "$repo" "$ref" "$base"; then
          continue
        fi
        printf '%s\n' "$name"
      done
}

# rp_write_decide REPO REL BASE [OUTDIR] [SUFFIX]
# REPO is where the flags and rules branches come from. OUTDIR is the repo the file goes in.
rp_write_decide() {
  local repo=$1 rel=$2 base=$3 outdir=${4:-$1} suffix=${5:-} tmp cap area
  area=$(nr_area_of "$rel")
  tmp=$(mktemp)
  : > "$tmp"
  if rp_failed "$rel" || { [ "$rel" = "." ] && jq -e '.review_ran == false' "$DIGEST" >/dev/null; }; then
    printf '%s\n' "The review did not run." >> "$tmp"
  fi
  cap=$(nr_cap)
  jq -r --arg r "$rel" '
    [.items[] | select(.repo == $r and .leak != true and (.summary | startswith("Possible leak:") | not))]
    | sort_by(if .kind == "decision" then 0 else 1 end, .path)
    | .[] | [.path, .summary, .audience] | @tsv
  ' "$DIGEST" | awk -F '\t' -v cap="$cap" '
    BEGIN { n = 0 }
    {
      n++
      if (n > cap) next
      print "- " $1 " — " $2 " Waiting on " $3 "."
    }
    END { if (n > cap) print "and " (n - cap) " more" }
  ' >> "$tmp"
  rp_rules_waiting "$repo" "$base" | while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    printf -- '- Rules change waiting: %s\n' "$ref" >> "$tmp"
  done
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 0
  fi
  out="$outdir/reports/${NR_DATE}-to-decide${suffix}.md"
  mkdir -p "$outdir/reports"
  {
    rp_front "decide" "To decide, ${NR_DATE}" "$(printf 'date: %s\narea: %s' "$NR_DATE" "$area")"
    printf '# To decide\n\n'
    cat "$tmp"
  } > "$out"
  rm -f "$tmp"
}

rp_allowed_line() {
  local line=$1 file=$2
  [ -n "$line" ] || return 1
  grep -F -x -q "$line" "$file"
}

rp_week_facts() {
  local repo=$1 start=$2 end=$3 facts commits logs people sha subject path slug line
  facts=$4
  : > "$facts"
  commits=0
  logs=0
  people=$(mktemp)
  : > "$people"
  while IFS="$(printf '\t')" read -r sha subject || [ -n "${sha:-}" ]; do
    [ -n "${sha:-}" ] || continue
    if git -C "$repo" log -1 --format=%B "$sha" | grep -q '^Run-Id: review-'; then
      continue
    fi
    path=$(git -C "$repo" show --name-only --format= "$sha" | head -n 1 || true)
    case "$path" in
      users/*|profile/*|traces/*) continue ;;
    esac
    commits=$((commits + 1))
    slug=$(nr_file_author "$repo" "$path" || true)
    [ -n "$slug" ] || slug="unknown"
    printf 'commit\t%s\t%s\n' "$slug" "$subject" >> "$facts"
    printf '%s\n' "$slug" >> "$people"
  done < <(git -C "$repo" log --no-merges --format='%H%x09%s' \
    --since="${start} 00:00:00" --until="${end} 00:00:00" "$5")
  local f name day
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    name=$(basename "$f")
    case "$name" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
      *) continue ;;
    esac
    day=$(printf '%s' "$name" | cut -c1-10)
    if [ "$day" \< "$start" ] || [ ! "$day" \< "$end" ]; then
      continue
    fi
    logs=$((logs + 1))
    slug=$(printf '%s' "$name" | cut -c12- | sed 's/\.md$//')
    printf '%s\n' "$slug" >> "$people"
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      case "$line" in
        \#*) continue ;;
      esac
      if nr_private_line "$line" || nr_ranking_line "$line"; then
        continue
      fi
      case "$line" in
        Result:*) printf 'result\t%s\t%s\n' "$slug" "${line#Result: }" >> "$facts" ;;
        *) printf 'action\t%s\t%s\n' "$slug" "$line" >> "$facts" ;;
      esac
    done < <(git -C "$repo" show "$5:$f")
  done < <(git -C "$repo" ls-tree -r --name-only "$5" -- memory/logs)
  local pc
  pc=$(sort -u "$people" | grep -c . || true)
  rm -f "$people"
  printf '%s %s %s\n' "$commits" "$logs" "$pc"
}

rp_render_people() {
  local facts=$1 engine_json=$2 slug actions results line text mark slugs
  slugs=$(awk -F '\t' '$1=="action" || $1=="result" || $1=="commit" { print $2 }' "$facts" | sort -u)
  for slug in $slugs; do
    [ -n "$slug" ] || continue
    printf '\n## %s\n\n' "$(nr_person_name "$slug")"
    actions=$(mktemp)
    awk -F '\t' -v s="$slug" '$1=="action" && $2==s { print $3 }' "$facts" > "$actions"
    results=$(mktemp)
    awk -F '\t' -v s="$slug" '$1=="result" && $2==s { print $3 }' "$facts" > "$results"
    mark=$(mktemp)
    : > "$mark"
    if [ -n "${engine_json}" ] && [ -f "$engine_json" ]; then
      while IFS= read -r text || [ -n "$text" ]; do
        [ -n "$text" ] || continue
        if rp_allowed_line "$text" "$actions" && ! nr_ranking_line "$text"; then
          printf -- '- %s\n' "$text"
          printf '1\n' >> "$mark"
        fi
      done < <(jq -r --arg s "$slug" '.people[]? | select(.slug == $s) | .actions[]? // empty' "$engine_json")
      while IFS= read -r text || [ -n "$text" ]; do
        [ -n "$text" ] || continue
        if rp_allowed_line "$text" "$results" && ! nr_ranking_line "$text"; then
          printf -- '- Result: %s\n' "$text"
          printf '1\n' >> "$mark"
        fi
      done < <(jq -r --arg s "$slug" '.people[]? | select(.slug == $s) | .results[]? // empty' "$engine_json")
    fi
    if [ ! -s "$mark" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        printf -- '- %s\n' "$line"
      done < "$actions"
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        printf -- '- Result: %s\n' "$line"
      done < "$results"
    fi
    rm -f "$actions" "$results" "$mark"
  done
}

rp_week_sections() {
  local repo=$1 base=$2 start=$3 end=$4 rel=$5 path n
  printf '\n## New facts and skill changes\n\n'
  n=0
  while IFS= read -r path || [ -n "$path" ]; do
    [ -n "$path" ] || continue
    case "$path" in
      users/*|profile/*|traces/*|reports/*|memory/logs/*) continue ;;
      skills/*|*/skills/*|AGENTS.md|CLAUDE.md|*/AGENTS.md|*/CLAUDE.md|review-rules.md|company-rules.md|area-rules.md|*/company-rules.md|*/area-rules.md|CODEOWNERS|docs/CODEOWNERS|.github/*|*/.github/*|.gitea/*|*/.gitea/*|.forgejo/*|*/.forgejo/*|.claude/*|*/.claude/*)
        printf -- '- Skill or rules: [%s](%s)\n' "$path" "$path"
        n=$((n + 1))
        continue
        ;;
    esac
    printf -- '- New fact: [%s](%s)\n' "$path" "$path"
    n=$((n + 1))
  done < <(git -C "$repo" log --name-only --pretty=format: \
    --since="${start} 00:00:00" --until="${end} 00:00:00" "$base" | awk 'NF && !seen[$0]++')
  if [ "$n" = "0" ]; then
    printf '%s\n' "No new facts or skill changes."
  else
    printf '\nPaths: %s\n' "$n"
  fi
  printf '\n## Stuck work\n\n'
  n=0
  if [ -d "$repo/projects" ]; then
    while IFS= read -r path || [ -n "$path" ]; do
      [ -n "$path" ] || continue
      printf -- '- [%s](%s)\n' "${path#"$repo"/}" "$path"
      n=$((n + 1))
    done < <(grep -l -E 'status:[[:space:]]*fail|"status":[[:space:]]*"fail"' "$repo"/projects/* "$repo"/projects/*/* 2>/dev/null || true)
  fi
  if [ "$n" = "0" ]; then
    printf '%s\n' "No stuck work in the files."
  fi
  printf '\n## Contradictions\n\n'
  n=0
  if [ -f "$DIGEST" ]; then
    n=0
    while IFS="$(printf '\t')" read -r path summary || [ -n "${path:-}" ]; do
      [ -n "${path:-}" ] || continue
      if nr_ranking_line "$summary" || nr_private_line "$summary"; then
        continue
      fi
      case "$summary" in
        "Possible leak:"*) continue ;;
      esac
      printf -- '- [%s](%s) — %s\n' "$path" "$path" "$summary"
      n=$((n + 1))
    done < <(jq -r --arg r "$rel" '.items[]? | select(.repo == $r and .leak != true) | select(.summary | test("disagree|contradict|does not match"; "i")) | [.path, .summary] | @tsv' "$DIGEST")
  fi
  if [ "${n:-0}" = "0" ]; then
    printf '%s\n' "No contradiction was flagged."
  fi
}

# rp_write_weekly REPO REL BASE START END [OUTDIR]
rp_write_weekly() {
  local repo=$1 rel=$2 base=$3 start=$4 end=$5 outdir=${6:-$1} area facts counts c l p input line body
  area=$(nr_area_of "$rel")
  facts=$(mktemp)
  if [ "$rel" = "." ]; then
    # The company page holds only the per-area counts. It reads no company facts.
    counts="0 0 0"
  else
    counts=$(rp_week_facts "$repo" "$start" "$end" "$facts" "$base")
  fi
  c=$(printf '%s' "$counts" | awk '{ print $1 }')
  l=$(printf '%s' "$counts" | awk '{ print $2 }')
  p=$(printf '%s' "$counts" | awk '{ print $3 }')
  if [ "$rel" != "." ] && [ "$c" = "0" ] && [ "$l" = "0" ]; then
    # A quiet area gets no page, but it keeps its row on the company page.
    printf '| %s | 0 | 0 | 0 |\n' "$area" >> "$NR_AREA_COUNTS"
    rm -f "$facts"
    return 0
  fi
  body=$(mktemp)
  local engine_file="" summary_note=""
  if [ -f "$DIR/report-prompt.md" ] && [ "$rel" != "." ]; then
    input=$(mktemp)
    chmod 600 "$input"
    cat "$DIR/report-prompt.md" > "$input"
    printf '\n\n' >> "$input"
    {
      printf '%s\n' "---INPUT---"
      printf '%s\n' "kind: report"
      printf 'week: %s\n' "$WEEK"
      printf 'area: %s\n' "$area"
      awk -F '\t' '{ printf "%s: %s\n%s: %s\n", "person", $2, $1, $3 }' "$facts"
      printf '%s\n' "counts:"
      printf 'commits: %s\n' "$c"
      printf 'log_files: %s\n' "$l"
      printf 'people: %s\n' "$p"
      printf '%s\n' "---END---"
    } >> "$input"
    set +e
    line=$(nr_engine_json "$input")
    local rc=$?
    set -e
    rm -f "$input"
    if [ "$rc" -eq 0 ]; then
      engine_file=$(mktemp)
      printf '%s\n' "$line" > "$engine_file"
    else
      summary_note="The summary did not run."
    fi
  elif [ ! -f "$DIR/report-prompt.md" ] && [ "$rel" != "." ]; then
    summary_note="The summary did not run."
  fi
  # An area may have no reports/ folder yet (S7): make it before writing.
  mkdir -p "$outdir/reports"
  {
    rp_front "week" "What happened in ${area}, week ${WEEK}" \
      "$(printf 'week: %s\narea: %s' "$WEEK" "$area")"
    printf '# What happened\n\n'
    printf 'Week %s. %s.\n\n' "$WEEK" "$area"
    if [ -n "$summary_note" ]; then
      printf '%s\n' "$summary_note"
    fi
    if [ "$rel" = "." ]; then
      printf '%s\n\n' "Counts only. Area sentences stay in the area report."
      if ! awk -F '|' '{ c = $3; l = $4; gsub(/ /, "", c); gsub(/ /, "", l); if ((c ~ /^[0-9]+$/ && c > 0) || (l ~ /^[0-9]+$/ && l > 0)) found = 1 } END { exit !found }' "$NR_AREA_COUNTS"; then
        printf '%s\n\n' "No area work yet this week."
      fi
      if [ -s "$NR_AREA_COUNTS" ]; then
        if rp_mdx; then
          printf '<Table>\n\n'
        fi
        printf '%s\n' "| Area | Commits | Log files | People |"
        printf '%s\n' "|---|---|---|---|"
        cat "$NR_AREA_COUNTS"
        if rp_mdx; then
          printf '\n</Table>\n'
        fi
      fi
    else
      rp_render_people "$facts" "$engine_file"
      rp_week_sections "$repo" "$base" "$START" "$END" "$rel"
      printf '\n## Counts\n\n'
      rp_counts_block "$c" "$l" "$p"
      printf '| %s | %s | %s | %s |\n' "$area" "$c" "$l" "$p" >> "$NR_AREA_COUNTS"
    fi
    printf '\n%s\n' "$(rp_delivery_line)"
  } > "$outdir/reports/${WEEK}$([ "$rel" = "." ] && printf '%s' "-company").md"
  rm -f "$facts" "$body" "$engine_file"
}

rp_delivery_line() {
  local arch="$NR_ROOT/architecture.md" found=""
  if [ -f "$arch" ]; then
    if grep -E -i -q 'slack' "$arch"; then
      found="Slack"
    fi
    if grep -E -i -q 'teams' "$arch"; then
      if [ -n "$found" ]; then
        found="${found}, Teams"
      else
        found="Teams"
      fi
    fi
    if grep -E -i -q 'email' "$arch"; then
      if [ -n "$found" ]; then
        found="${found}, email"
      else
        found="email"
      fi
    fi
  fi
  if [ -n "$found" ]; then
    printf 'Delivery: the file is the source. connect-tool already lists %s. This job does not send a copy.\n' "$found"
  else
    printf '%s\n' "Delivery: the file is the source. No email, Slack, or Teams connection is recorded."
  fi
}

rp_publish_repo() {
  local repo rel base wt branch rc
  repo=$1
  rel=$2
  base=$3
  if [ -z "$base" ]; then
    NR_FAILED=1
    return 0
  fi
  if [ -z "$(git -C "$repo" status --porcelain -- reports)" ]; then
    return 0
  fi
  branch="review/${NR_DATE}"
  set +e
  wt=$(nr_worktree_open "$repo" "$base" "$branch")
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ] || [ -z "$wt" ]; then
    NR_FAILED=1
    return 0
  fi
  mkdir -p "$wt/reports"
  cp -R "$repo/reports/." "$wt/reports/"
  nr_load_identity "$(nr_area_of "$rel")"
  if ! nr_publish "$wt" "$rel" "Reports ${NR_DATE}"; then
    NR_FAILED=1
  fi
  nr_worktree_close "$repo" "$wt"
  # Drop the working-tree copies so the company checkout stays clean.
  git -C "$repo" checkout -q -- reports 2>/dev/null || true
  git -C "$repo" clean -q -f -- reports 2>/dev/null || true
}

span=$(nr_week_span "$WEEK")
START=${span%% *}
END=${span#* }
NR_AREA_COUNTS=$(mktemp)
: > "$NR_AREA_COUNTS"

# Company pages go to the owners' area: the company root is the shared root, and
# everyone reads it. report_area: in company-profile.md names the area (default admin).
REPORT_AREA=$(nr_profile report_area | head -n 1 || true)
[ -n "$REPORT_AREA" ] || REPORT_AREA="admin"
case "$REPORT_AREA" in
  *[!a-z0-9-]*|-*) nr_die "run.sh: report_area must be an area name, such as admin" ;;
esac
REPORT_DIR="$NR_ROOT/areas/$REPORT_AREA"
REPORT_BASE=""
PUBLISH=$(mktemp)
: > "$PUBLISH"

rp_one() {
  local repo=$1 rel=$2 base
  set +e
  base=$(nr_sync_base "$repo")
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    NR_FAILED=1
    if [ "$DO_WEEKLY" = "1" ]; then
      printf '| %s | not read | not read | not read |\n' "$(nr_area_of "$rel")" >> "$NR_AREA_COUNTS"
    fi
    return 0
  fi
  if [ "$DO_DAILY" = "1" ]; then
    rp_write_decide "$repo" "$rel" "$base"
  fi
  if [ "$DO_WEEKLY" = "1" ]; then
    rp_write_weekly "$repo" "$rel" "$base" "$START" "$END"
  fi
  if [ "$repo" = "$REPORT_DIR" ]; then
    REPORT_BASE=$base
  fi
  # Publish after the company pages, so the owners' area gets one commit.
  printf '%s\t%s\t%s\n' "$repo" "$rel" "$base" >> "$PUBLISH"
}

for dir in "$NR_ROOT"/areas/*; do
  [ -d "$dir" ] || continue
  if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
    rp_one "$dir" "areas/$(basename "$dir")"
  fi
done

if [ -d "$NR_ROOT/.git" ] || [ -f "$NR_ROOT/.git" ]; then
  if [ ! -d "$REPORT_DIR/.git" ] && [ ! -f "$REPORT_DIR/.git" ]; then
    printf 'reports: company pages not written: areas/%s is not checked out here. Check out that area, or set report_area: in company-profile.md to the owners'"'"' area.\n' "$REPORT_AREA" >&2
    NR_FAILED=1
  elif [ -z "$REPORT_BASE" ]; then
    printf 'reports: company pages not written: areas/%s could not be read.\n' "$REPORT_AREA" >&2
    NR_FAILED=1
  else
    set +e
    base=$(nr_sync_base "$NR_ROOT")
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      NR_FAILED=1
    else
      if [ "$DO_DAILY" = "1" ]; then
        rp_write_decide "$NR_ROOT" "." "$base" "$REPORT_DIR" "-company"
      fi
      if [ "$DO_WEEKLY" = "1" ]; then
        rp_write_weekly "$NR_ROOT" "." "$base" "$START" "$END" "$REPORT_DIR"
      fi
    fi
  fi
fi

while IFS="$(printf '\t')" read -r repo rel base || [ -n "${repo:-}" ]; do
  [ -n "${repo:-}" ] || continue
  rp_publish_repo "$repo" "$rel" "$base"
done < "$PUBLISH"

rm -f "$NR_AREA_COUNTS" "$PUBLISH"
if [ "$NR_FAILED" = "1" ]; then
  exit 2
fi
exit 0
