#!/bin/bash
# upgrade.sh --refresh: bring a v1 company's stock skills and checks to this template.
# Sourced by upgrade.sh. Bash 3.2.
#
# A stock file is one the template ships under skills/ or .github/. The company's copy is
# replaced only when it is exactly a stock text of some release (stock-hashes.txt: git
# blob id and path of every such file the template ever had). A copy the company changed
# is kept and listed for the admin. Company skills of its own are never in the list, so
# they are never touched. One rules pull request per repo, from main: the company repo
# gets skills/ and .github/, each area repo gets .github/.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf '%s\n' "Source this file from upgrade.sh." >&2
  exit 1
fi

# Stock paths for one repo kind, from the template folder, one per line.
refresh_stock_paths() {
  local kind=$1
  (
    cd "$TEMPLATE" || exit 1
    if [ "$kind" = "root" ]; then
      find skills .github -type f
    else
      find .github -type f
    fi
  ) | grep -v '/\.DS_Store$' | LC_ALL=C sort
}

# Paths in the repo's main that a refresh may remove: the same folders as above.
# -z: a company skill named with an accent is never quoted.
refresh_repo_paths() {
  local dir=$1 kind=$2 path
  if [ "$kind" = "root" ]; then
    set -- skills .github
  else
    set -- .github
  fi
  while IFS= read -r -d '' path; do
    printf '%s\n' "$path"
  done < <(git -C "$dir" ls-tree -r -z --name-only "$REFRESH_BASE" -- "$@")
}

refresh_known() {
  grep -Fxq -- "$1 $2" "$REFRESH_HASHES"
}

# Sort one repo's stock files into add, replace, remove and kept (changed by the company).
# Writes four lists in $3.
refresh_plan() {
  local dir=$1 kind=$2 out=$3 path new old
  : > "$out/add"
  : > "$out/replace"
  : > "$out/remove"
  : > "$out/kept"
  refresh_stock_paths "$kind" > "$out/stock"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    new=$(git hash-object -- "$TEMPLATE/$path")
    old=$(git -C "$dir" rev-parse -q --verify "${REFRESH_BASE}:${path}" 2>/dev/null || true)
    if [ "$old" = "$new" ]; then
      continue
    elif [ -z "$old" ]; then
      printf '%s\n' "$path" >> "$out/add"
    elif refresh_known "$old" "$path"; then
      printf '%s\n' "$path" >> "$out/replace"
    else
      printf '%s\n' "$path" >> "$out/kept"
    fi
  done < "$out/stock"
  # A stock file this release dropped, still exactly as shipped: it goes too.
  refresh_repo_paths "$dir" "$kind" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    grep -Fxq -- "$path" "$out/stock" && continue
    old=$(git -C "$dir" rev-parse -q --verify "${REFRESH_BASE}:${path}" 2>/dev/null || true)
    if [ -n "$old" ] && refresh_known "$old" "$path"; then
      printf '%s\n' "$path" >> "$out/remove"
    fi
  done
}

# Write the plan into a work folder: copy each new text with its mode, remove the dropped.
refresh_apply() {
  local wt=$1 plan=$2 path
  cat "$plan/add" "$plan/replace" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    mkdir -p "$wt/$(dirname "$path")"
    cp "$TEMPLATE/$path" "$wt/$path"
    if [ -x "$TEMPLATE/$path" ]; then
      chmod 755 "$wt/$path"
    else
      chmod 644 "$wt/$path"
    fi
  done
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    git -C "$wt" rm -q -- "$path"
  done < "$plan/remove"
}

refresh_paths_args() {
  cat "$1/add" "$1/replace" "$1/remove"
}

# Why a fetch failed, in one plain line (B59). Only a network error is "could not reach".
refresh_fetch_fail() {
  local label=$1 err=$2 first
  first=$({ grep -m 1 -E '^(fatal|error):' "$err" || head -n 1 "$err"; } | sed 's#://[^/@]*@#://#g')
  if grep -qiE 'could not resolve host|failed to connect|couldn.t connect|connection (timed out|refused)|network is unreachable|operation timed out' "$err"; then
    printf 'refresh: could not reach the host for %s. Nothing was changed there.\n' "$label"
  elif grep -qiE 'authentication failed|permission denied|could not read username|returned error: 40[13]|repository not found|not found' "$err"; then
    printf 'refresh: the host refused the sign-in or the repo for %s (git: %s). Nothing was changed there.\n' "$label" "$first"
  else
    printf 'refresh: the host answered, but the fetch for %s failed (git: %s). Nothing was changed there.\n' "$label" "$first"
  fi
}

refresh_one() {
  local dir=$1 kind=$2 label=$3 plan n kept wt name branch pr number path size err
  plan=$(mktemp -d)
  REFRESH_BASE=main
  if [ "$HOST_ON" -eq 1 ]; then
    # --prune: a branch the host deleted (an old sync/<me> beside sync/<me>/<seat>) would
    # otherwise stop the fetch (B59).
    err=$(mktemp)
    if ! os_with_git_token up_git_err "$err" -C "$dir" fetch -q --prune origin; then
      refresh_fetch_fail "$label" "$err"
      rm -f "$err"
      REFRESH_FAILED=1
      rm -rf "$plan"
      return 0
    fi
    rm -f "$err"
    REFRESH_BASE=origin/main
  fi
  # Team: the checks job runs main's tools, so this release's tools and stock list go on
  # main first, by the upgrade's own path (protection lifted for that one push, then back
  # on). The pull request is then judged by them, and only skills/ is left in it.
  if [ "$REFRESH_TEAM" -eq 1 ]; then
    if [ "$DRY" -eq 1 ]; then
      printf 'change: checks-on-main %s\n' "$label"
    else
      checks_on_main "$dir" "$(basename "$(git -C "$dir" remote get-url origin)" .git)"
    fi
  fi
  refresh_plan "$dir" "$kind" "$plan"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf 'kept: %s %s (changed by the company; compare it with the template by hand)\n' "$label" "$path"
  done < "$plan/kept"
  n=$(refresh_paths_args "$plan" | grep -c . || true)
  kept=$(grep -c . "$plan/kept" || true)
  if [ "$n" -eq 0 ]; then
    printf 'refresh: %s is current (%s kept)\n' "$label" "$kept"
    rm -rf "$plan"
    return 0
  fi
  printf 'refresh: %s: %s new, %s replaced, %s removed, %s kept\n' "$label" \
    "$(grep -c . "$plan/add" || true)" "$(grep -c . "$plan/replace" || true)" \
    "$(grep -c . "$plan/remove" || true)" "$kept"
  if [ "$DRY" -eq 1 ]; then
    rm -rf "$plan"
    return 0
  fi
  if [ "$HOST_ON" -eq 0 ]; then
    # Solo: commit on main, as everything at solo is. Only these paths.
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -n "$(git -C "$dir" status --porcelain -- "$path")" ]; then
        printf 'refresh: stopped in %s: %s has a change not committed. Commit or undo it, then run again.\n' "$label" "$path"
        REFRESH_FAILED=1
        rm -rf "$plan"
        return 0
      fi
    done < <(refresh_paths_args "$plan")
    refresh_apply "$dir" "$plan"
    # shellcheck disable=SC2046
    os_git_commit "$dir" "Upgrade: refresh stock skills and checks (${REFRESH_RELEASE})" $(refresh_paths_args "$plan") >/dev/null
    printf 'committed: %s\n' "$label"
    rm -rf "$plan"
    return 0
  fi
  name=$(basename "$(git -C "$dir" remote get-url origin)" .git)
  branch="rules/${REFRESH_ME}/refresh-${REFRESH_RELEASE}"
  wt=$(os_branch_start "$dir") || { REFRESH_FAILED=1; rm -rf "$plan"; return 0; }
  refresh_apply "$wt" "$plan"
  # shellcheck disable=SC2046
  os_git_commit "$wt" "Upgrade: refresh stock skills and checks (${REFRESH_RELEASE})" $(refresh_paths_args "$plan") >/dev/null
  os_branch_push "$dir" "$wt" "$branch"
  refresh_body > "$plan/body"
  pr=$(os_host_try open-pr "$name" --head "$branch" --base main \
    --title "Refresh stock skills and checks (${REFRESH_RELEASE})" --body-file "$plan/body" || true)
  number=$(printf '%s' "$pr" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    printf 'refresh: could not open a pull request for %s (branch %s is on the host). Run again.\n' "$name" "$branch"
    REFRESH_FAILED=1
    rm -rf "$plan"
    return 0
  fi
  printf 'opened: %s %s\n' "$name" "$number"
  refresh_close_older "$name" "$number" "$branch"
  if [ "$REFRESH_TEAM" -eq 1 ]; then
    size=$(review_size "$dir" "$(git -C "$dir" merge-base origin/main "origin/${branch}")..origin/${branch}")
    if [ "$size" -gt 100000 ]; then
      printf 'override: %s %s is too large for the model review (%s bytes, limit 100000). After lint and the secret scan pass, the admin comments on it: /override refresh: stock skills, too large for the model review\n' \
        "$name" "$number" "$size"
    else
      os_override_line "$name" "$number" "refresh: the release's stock skills and checks"
    fi
  fi
  os_auto_merge_line "$name" "$number"
  rm -rf "$plan"
}

# This person's refresh pull request for an older release, still open, is replaced by the
# new one: close it, with a comment that names the new one. Another person's is left.
refresh_close_older() {
  local name=$1 number=$2 branch=$3 prs n head rel body prefix
  prefix=${branch%refresh-*}refresh-
  prs=$(os_host_try open-prs "$name" 2>/dev/null) || return 0
  printf '%s' "$prs" | jq -r '(.prs // [])[] | "\(.number) \(.head)"' | while read -r n head; do
    case "$head" in
      "$prefix"*) ;;
      *) continue ;;
    esac
    [ "$head" != "$branch" ] && [ "$n" != "$number" ] || continue
    rel=${head#"$prefix"}
    case "$rel" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$rel" -lt "$REFRESH_RELEASE" ] || continue
    body=$(mktemp)
    printf 'Replaced by #%s (release %s). Closed by upgrade.sh --refresh.\n' "$number" "$REFRESH_RELEASE" > "$body"
    os_host_try pr-comment "$name" "$n" --body-file "$body" >/dev/null 2>&1 || true
    rm -f "$body"
    if os_host_try close-pr "$name" "$n" >/dev/null 2>&1; then
      printf 'closed: %s %s (refresh for release %s; replaced by %s)\n' "$name" "$n" "$rel" "$number"
    else
      printf 'could not close %s %s (an older refresh): close it by hand\n' "$name" "$n"
    fi
  done
}

# The body says what changed, in one line, for the review.
refresh_body() {
  printf 'Refresh of the stock skills and checks to template release %s. Only files that were exactly as shipped are replaced; files the company changed are kept.\n' "$REFRESH_RELEASE"
}

upgrade_refresh() {
  local area cfg
  REFRESH_HASHES="$TEMPLATE/.github/scripts/stock-hashes.txt"
  [ -f "$REFRESH_HASHES" ] || os_die 1 "this template has no .github/scripts/stock-hashes.txt: use a newer os-foundation"
  REFRESH_RELEASE=$(tr -d '[:space:]' < "$TEMPLATE/.github/scripts/tools-release" 2>/dev/null || true)
  [ -n "$REFRESH_RELEASE" ] || os_die 1 "this template has no .github/scripts/tools-release"
  cfg=$(os_config_dir "$SLUG")
  REFRESH_ME=$(tr -d '[:space:]' < "$cfg/me" 2>/dev/null || true)
  [ -n "$REFRESH_ME" ] || REFRESH_ME=$(os_admin_slug_from_pages "$ROOT" || true)
  case "$REFRESH_ME" in
    ''|*[!a-z0-9-]*) os_die 2 "refresh: who runs this? Write your slug in ${cfg}/me" ;;
  esac
  REFRESH_TEAM=0
  if [ "$HOST_ON" -eq 1 ]; then
    case "$(os_fm_get "$ROOT/company-profile.md" level 2>/dev/null || true)" in
      team|app) REFRESH_TEAM=1 ;;
    esac
  fi
  REFRESH_FAILED=0
  refresh_one "$ROOT" root "the company folder"
  for area in "$ROOT"/areas/*; do
    [ -e "$area/.git" ] || continue
    refresh_one "$area" area "areas/$(basename "$area")"
  done
  if [ "$REFRESH_FAILED" -ne 0 ]; then
    return 3
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '%s\n' "refresh: dry run, nothing changed"
  else
    printf '%s\n' "refresh: ok. Teammates get the new files with their next pull, once each pull request merges."
  fi
}
