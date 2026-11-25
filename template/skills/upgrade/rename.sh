#!/bin/bash
# upgrade.sh --refresh: the bots -> automations rename (v1.0.8). Sourced by refresh.sh.
# Bash 3.2.
#
# Before v1.0.8 a company automation was called a bot. This step looks at main (it never
# reads a version number), the same way the root files step does, so a second run finds
# nothing to do. One repo at a time: the company repo, then each area repo.
#
# - bots/<name>/BOT.md becomes automations/<name>/AUTOMATION.md (git mv, with every other
#   file in the folder), and its frontmatter keys type: bot, bot: and bot_user: become
#   type: automation, automation: and host_user:.
# - bots in switches: (company-profile.md) becomes automations.
# - The stock CODEOWNERS lines for bots/*/BOT.md name automations/*/AUTOMATION.md.
# - The stock names in AGENTS.md, CLAUDE.md and review-rules.md change the same way (the
#   path names, `add-bot` and the [bots]: tag). No other text changes.
#
# A person's own bots (users/<person>/bots/, in their workspace repo) are never touched:
# this step works only on the company repo and the area repos.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf '%s\n' "Source this file from upgrade.sh." >&2
  exit 1
fi

# The rules-file text files whose stock path names change, in each repo.
RENAME_TEXT_FILES="AGENTS.md CLAUDE.md review-rules.md"
RENAME_OWNER_FILES=".github/CODEOWNERS .gitea/CODEOWNERS"

# company-profile.md: bots in switches: becomes automations. Inline list, block list or
# one bare value. Only inside the frontmatter. Reads stdin, writes stdout.
rename_switch_filter() {
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function bare(s) { s = trim(s); gsub(/^["\047]|["\047]$/, "", s); return s }
    BEGIN { n = 0; fm = 0; inlist = 0 }
    /^---[[:space:]]*$/ {
      n++
      fm = (n == 1)
      inlist = 0
      print
      next
    }
    !fm { print; next }
    inlist {
      if ($0 ~ /^[[:space:]]*-/) {
        v = $0
        sub(/^[[:space:]]*-/, "", v)
        sub(/[[:space:]]+#.*$/, "", v)
        if (bare(v) == "bots") { sub(/bots/, "automations") }
        print
        next
      }
      inlist = 0
    }
    /^switches:/ {
      # The stock comment names the allowed switches.
      i = index($0, "Allowed: bots,")
      if (i > 0) { $0 = substr($0, 1, i - 1) "Allowed: automations," substr($0, i + length("Allowed: bots,")) }
      rest = $0
      sub(/^switches:[[:space:]]*/, "", rest)
      if (rest == "" || rest ~ /^#/) { inlist = 1; print; next }
      lb = index($0, "[")
      rb = index($0, "]")
      if (lb > 0 && rb > lb) {
        inner = substr($0, lb + 1, rb - lb - 1)
        k = split(inner, items, ",")
        out = ""
        for (i = 1; i <= k; i++) {
          item = items[i]
          if (bare(item) == "bots") { sub(/bots/, "automations", item) }
          out = out (i > 1 ? "," : "") item
        }
        $0 = substr($0, 1, lb) out substr($0, rb)
        print
        next
      }
      v = rest
      sub(/[[:space:]]+#.*$/, "", v)
      if (bare(v) == "bots") { sub(/bots/, "automations") }
      print
      next
    }
    { print }
  '
}

# AUTOMATION.md frontmatter: type: bot, bot: and bot_user: get the new names.
rename_keys_filter() {
  awk '
    BEGIN { n = 0; fm = 0 }
    /^---[[:space:]]*$/ { n++; fm = (n == 1); print; next }
    fm && /^type:[[:space:]]*bot([[:space:]]|$)/ { sub(/bot/, "automation"); print; next }
    fm && /^bot:/ { sub(/^bot:/, "automation:"); print; next }
    fm && /^bot_user:/ { sub(/^bot_user:/, "host_user:"); print; next }
    { print }
  '
}

# CODEOWNERS (GitHub globs and Forgejo regular expressions): the stock bots line. The
# owners after the path stay as they are.
rename_owners_filter() {
  awk '
    BEGIN {
      og = "/bots/*/BOT.md"; ng = "/automations/*/AUTOMATION.md"
      of = "^bots/[^/]+/BOT\\.md$"; nf = "^automations/[^/]+/AUTOMATION\\.md$"
    }
    $1 == og { $0 = ng substr($0, length(og) + 1) }
    $1 == of { $0 = nf substr($0, length(of) + 1) }
    { print }
  '
}

# AGENTS.md, CLAUDE.md, review-rules.md: the stock names, exactly as shipped: the two path
# names, the skill name and the switch tag of the skills list.
rename_text_filter() {
  awk '
    function swap(s, old, new,   out, i) {
      out = ""
      while ((i = index(s, old)) > 0) {
        out = out substr(s, 1, i - 1) new
        s = substr(s, i + length(old))
      }
      return out s
    }
    {
      $0 = swap($0, "`bots/*/BOT.md`", "`automations/*/AUTOMATION.md`")
      $0 = swap($0, "`bots/<bot>/BOT.md`", "`automations/<automation>/AUTOMATION.md`")
      $0 = swap($0, "`add-bot`", "`add-automation`")
      $0 = swap($0, "[bots]:", "[automations]:")
      print
    }
  '
}

# Does main's copy of <path> change under <filter>? 0 yes, 1 no (or no such file).
rename_changes() {
  local dir=$1 path=$2 filter=$3
  git -C "$dir" cat-file -e "${REFRESH_BASE}:${path}" 2>/dev/null || return 1
  ! cmp -s <(git -C "$dir" show "${REFRESH_BASE}:${path}") \
    <(git -C "$dir" show "${REFRESH_BASE}:${path}" | "$filter")
}

# Plan the rename for one repo into $out/rename: one "<what> <path>" line each.
# Returns 2 when the repo has both bots/ and automations/: the caller stops that repo.
rename_plan() {
  local dir=$1 kind=$2 out=$3 path size
  : > "$out/rename"
  if git -C "$dir" cat-file -e "${REFRESH_BASE}:bots" 2>/dev/null; then
    if git -C "$dir" cat-file -e "${REFRESH_BASE}:automations" 2>/dev/null; then
      return 2
    fi
    printf 'folder bots\n' >> "$out/rename"
  fi
  if [ "$kind" = "root" ] && rename_changes "$dir" company-profile.md rename_switch_filter; then
    printf 'switch company-profile.md\n' >> "$out/rename"
  fi
  for path in $RENAME_OWNER_FILES; do
    if rename_changes "$dir" "$path" rename_owners_filter; then
      printf 'owners %s\n' "$path" >> "$out/rename"
    fi
  done
  for path in $RENAME_TEXT_FILES; do
    if rename_changes "$dir" "$path" rename_text_filter; then
      size=$(git -C "$dir" show "${REFRESH_BASE}:${path}" | rename_text_filter | wc -c | tr -d ' ')
      if [ "$path" != "review-rules.md" ] && [ "$size" -ge 10000 ]; then
        # A rules file must stay under 10000 bytes. The admin moves lines first.
        printf 'toolong %s\n' "$path" >> "$out/rename"
      else
        printf 'text %s\n' "$path" >> "$out/rename"
      fi
    fi
  done
  return 0
}

# One plain line per planned change.
rename_report() {
  local dir=$1 label=$2 plan=$3 what path n
  while read -r what path; do
    case "$what" in
      folder)
        n=$(git -C "$dir" ls-tree -d --name-only "${REFRESH_BASE}:bots" 2>/dev/null | grep -c . || true)
        printf 'rename: %s bots/ to automations/ (%s folders; each BOT.md becomes AUTOMATION.md)\n' "$label" "$n"
        ;;
      switch) printf 'rename: %s company-profile.md: bots becomes automations on the switches: line\n' "$label" ;;
      owners) printf 'rename: %s %s: the bots/*/BOT.md line names automations/*/AUTOMATION.md\n' "$label" "$path" ;;
      text) printf 'rename: %s %s: the stock names bots/*/BOT.md and add-bot become automations/*/AUTOMATION.md and add-automation\n' "$label" "$path" ;;
      toolong)
        printf 'todo: %s %s still names bots/*/BOT.md: the new name would make it 10000 bytes or more. Move some lines to a skill, then change the name by a rules change (sync.sh propose).\n' "$label" "$path"
        ;;
    esac
  done < "$plan/rename"
}

# The paths to stage for the rename, one per line. The folder rename is staged by git mv.
rename_paths() {
  local what path
  while read -r what path; do
    case "$what" in
      folder) printf '%s\n' automations ;;
      switch|owners|text) printf '%s\n' "$path" ;;
    esac
  done < "$1/rename"
}

# The paths a solo run must find clean before it writes.
rename_dirty_paths() {
  local what path
  while read -r what path; do
    case "$what" in
      folder) printf '%s\n' bots automations ;;
      switch|owners|text) printf '%s\n' "$path" ;;
    esac
  done < "$1/rename"
}

# Apply the plan in a work folder (a worktree on origin/main, or the solo folder).
rename_apply() {
  local wt=$1 plan=$2 what path f rel tmp filter
  while read -r what path; do
    case "$what" in
      folder)
        git -C "$wt" mv bots automations
        for f in "$wt"/automations/*/BOT.md; do
          [ -f "$f" ] || continue
          rel=${f#"$wt"/}
          git -C "$wt" mv "$rel" "$(dirname "$rel")/AUTOMATION.md"
          tmp=$(mktemp)
          rename_keys_filter < "$wt/$(dirname "$rel")/AUTOMATION.md" > "$tmp"
          cat "$tmp" > "$wt/$(dirname "$rel")/AUTOMATION.md"
          rm -f "$tmp"
        done
        continue
        ;;
      switch) filter=rename_switch_filter ;;
      owners) filter=rename_owners_filter ;;
      text) filter=rename_text_filter ;;
      *) continue ;;
    esac
    tmp=$(mktemp)
    "$filter" < "$wt/$path" > "$tmp"
    cat "$tmp" > "$wt/$path"
    rm -f "$tmp"
  done < "$plan/rename"
}

# Count of rename lines that change a file.
rename_count() {
  grep -c -E '^(folder|switch|owners|text) ' "$1/rename" || true
}
