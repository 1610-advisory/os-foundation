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
refresh_repo_paths() {
  local dir=$1 kind=$2
  if [ "$kind" = "root" ]; then
    git -C "$dir" ls-tree -r --name-only "$REFRESH_BASE" -- skills .github
  else
    git -C "$dir" ls-tree -r --name-only "$REFRESH_BASE" -- .github
  fi
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

refresh_one() {
  local dir=$1 kind=$2 label=$3 plan n kept wt name branch pr number path
  plan=$(mktemp -d)
  REFRESH_BASE=main
  if [ "$HOST_ON" -eq 1 ]; then
    if ! os_with_git_token up_git_quiet -C "$dir" fetch -q origin; then
      printf 'refresh: could not reach the host for %s. Nothing was changed there.\n' "$label"
      REFRESH_FAILED=1
      rm -rf "$plan"
      return 0
    fi
    REFRESH_BASE=origin/main
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
  os_auto_merge_line "$name" "$number"
  rm -rf "$plan"
}

# The body says what changed, in one line, for the review.
refresh_body() {
  printf 'Refresh of the stock skills and checks to template release %s. Only files that were exactly as shipped are replaced; files the company changed are kept.\n' "$REFRESH_RELEASE"
}

upgrade_refresh() {
  local area cfg
  REFRESH_HASHES="$TEMPLATE/skills/upgrade/stock-hashes.txt"
  [ -f "$REFRESH_HASHES" ] || os_die 1 "this template has no skills/upgrade/stock-hashes.txt: use a newer os-foundation"
  REFRESH_RELEASE=$(tr -d '[:space:]' < "$TEMPLATE/.github/scripts/tools-release" 2>/dev/null || true)
  [ -n "$REFRESH_RELEASE" ] || os_die 1 "this template has no .github/scripts/tools-release"
  cfg=$(os_config_dir "$SLUG")
  REFRESH_ME=$(tr -d '[:space:]' < "$cfg/me" 2>/dev/null || true)
  [ -n "$REFRESH_ME" ] || REFRESH_ME=$(os_admin_slug_from_pages "$ROOT" || true)
  case "$REFRESH_ME" in
    ''|*[!a-z0-9-]*) os_die 2 "refresh: who runs this? Write your slug in ${cfg}/me" ;;
  esac
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
