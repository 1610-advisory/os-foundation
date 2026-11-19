#!/bin/bash
# upgrade --root-router: move company facts and curated memory from areas/everyone back to
# the company root (D163). Meetings, logs and shared tools stay in everyone. Bash 3.2.
# Dry run first. The real run needs --yes: the files go to a wider audience (every git user).
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-teammate/lib.sh"

usage() {
  cat << 'EOF'
usage: upgrade.sh --root-router [--dry-run] [--yes] [--root <dir>]

Moves company facts (customers.md, offers.md, voice.md, company.md) and curated memory
(memory/*.md, not memory/logs/) from areas/everyone back to the company root.
Meetings, decisions, logs and everything else stay in everyone. Dry-run prints the list and changes
nothing. The real run needs --yes from the admin. Team level: one branch and one pull
request per repo (upgrade/root-router); merge the company one first. Run it again to check:
a second run says "already done".
EOF
}

DRY=0
YES=0
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --root-router) shift ;;
    --dry-run) DRY=1; shift ;;
    --yes) YES=1; shift ;;
    --root)
      [ $# -ge 2 ] || os_die 1 "missing root"
      ROOT=$2
      shift 2
      ;;
    *) os_die 1 "unknown argument: $1" ;;
  esac
done

os_need git
[ -n "$ROOT" ] || ROOT=$(pwd)
[ -d "$ROOT" ] || os_die 2 "company folder is missing"
ROOT=$(cd "$ROOT" && pwd)
[ -f "$ROOT/company-profile.md" ] || os_die 2 "company-profile.md is missing"
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || os_die 2 "not a git repo"
EV="$ROOT/areas/everyone"
BRANCH=upgrade/root-router

if [ ! -e "$EV/.git" ]; then
  printf 'root-router: nothing to do: there is no areas/everyone repo here.\n'
  exit 0
fi

# Team: read what the host has (origin/main). Solo (no origin): read main here.
ref_of() {
  if git -C "$1" rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
    printf 'refs/remotes/origin/main\n'
  else
    printf 'HEAD\n'
  fi
}
RREF=$(ref_of "$ROOT")
EREF=$(ref_of "$EV")
TEAM=0
if [ "$RREF" != HEAD ] && [ "$EREF" != HEAD ]; then
  TEAM=1
elif [ "$RREF" != "$EREF" ]; then
  os_die 2 "root-router: the company repo and areas/everyone disagree: one has a host copy (origin/main) and one does not. Fix the remotes, then run again."
fi

blob() { git -C "$1" rev-parse -q --verify "$2:$3" 2>/dev/null || true; }

# The paths that move: facts and curated memory. Never logs, meetings, decisions or anything
# else: the root never holds decisions at team level.
candidates() {
  git -C "$EV" ls-tree -r --name-only "$EREF" | while IFS= read -r p; do
    case "$p" in
      customers.md|offers.md|voice.md|company.md) printf '%s\n' "$p" ;;
      memory/MEMORY.md|memory/logs/*|memory/logs-archive/*) ;;
      memory/*.md) printf '%s\n' "$p" ;;
    esac
  done
}

MOVE=()
SAME=()
CONFLICT=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  eb=$(blob "$EV" "$EREF" "$p")
  rb=$(blob "$ROOT" "$RREF" "$p")
  if [ -z "$rb" ]; then
    MOVE+=("$p")
  elif [ "$rb" = "$eb" ]; then
    SAME+=("$p")
  else
    CONFLICT+=("$p")
  fi
done << EOF
$(candidates)
EOF

# Index lines in everyone's MEMORY.md for a moved file, which the root index lacks.
INDEX=$(mktemp)
: > "$INDEX"
if [ -n "$(blob "$EV" "$EREF" memory/MEMORY.md)" ]; then
  root_index=$(mktemp)
  git -C "$ROOT" show "$RREF:memory/MEMORY.md" > "$root_index" 2>/dev/null || : > "$root_index"
  git -C "$EV" show "$EREF:memory/MEMORY.md" | while IFS= read -r line; do
    case "$line" in
      "- ["*"]("*")"*)
        target=${line#*](}
        target=${target%%)*}
        target=${target#./}
        case "$target" in */*|"") continue ;; esac
        if [ -n "$(blob "$EV" "$EREF" "memory/$target")" ] && ! grep -qF -- "($target)" "$root_index"; then
          printf '%s\n' "$line"
        fi
        ;;
    esac
  done > "$INDEX"
fi
NINDEX=$(grep -c . "$INDEX" || true)

TOTAL=$(( ${#MOVE[@]} + ${#SAME[@]} + NINDEX ))
if [ "${#CONFLICT[@]}" -eq 0 ] && [ "$TOTAL" -eq 0 ]; then
  printf 'root-router: already done: no company facts or curated memory left in areas/everyone.\n'
  exit 0
fi

for p in ${MOVE[@]+"${MOVE[@]}"}; do printf 'move: areas/everyone/%s -> %s\n' "$p" "$p"; done
for p in ${SAME[@]+"${SAME[@]}"}; do printf 'same: %s is already at the root; it is removed from areas/everyone\n' "$p"; done
[ "$NINDEX" -eq 0 ] || printf 'index: memory/MEMORY.md gets %s line(s) from the everyone index\n' "$NINDEX"
for p in ${CONFLICT[@]+"${CONFLICT[@]}"}; do
  printf 'conflict: %s is different at the root and in areas/everyone. Keep one by hand (move the other text into it, delete the copy in everyone), then run again.\n' "$p"
done
for p in ${MOVE[@]+"${MOVE[@]}"}; do
  [ "$p" = company.md ] && printf 'todo: company.md comes back to the root as it is. Fold it into company-profile.md by hand later.\n'
done
printf 'keep: meetings, decisions, memory/logs and every other file stay in areas/everyone.\n'
printf 'audience: these files go from the everyone team to every person with the company repo. Check each one for leadership, access, billing or private-source material first.\n'

if [ "${#CONFLICT[@]}" -gt 0 ]; then
  [ "$DRY" -eq 1 ] && exit 0
  os_die 2 "root-router: stopped: fix each conflict line first. Nothing was changed."
fi
[ "$DRY" -eq 1 ] && exit 0
if [ "$YES" -ne 1 ]; then
  os_die 2 "root-router: the admin reads the list above and says yes. Then run again with --yes. Nothing was changed."
fi

# Host: the same setup as upgrade.sh (host.sh reads the profile or OS_HOST).
HOST_ON=0
UP_HOST=$(os_fm_get "$ROOT/company-profile.md" host 2>/dev/null || true)
SLUG=$(os_fm_get "$ROOT/company-profile.md" company_slug 2>/dev/null || true)
case "$UP_HOST" in
  github|forgejo)
    if [ "$TEAM" -eq 1 ] && [ -n "$SLUG" ] && OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
      HOST_ON=1
      OS_HOST_URL=$(os_fm_get "$ROOT/company-profile.md" host_url 2>/dev/null || true)
      OS_ORG=$(os_fm_get "$ROOT/company-profile.md" org 2>/dev/null || true)
      export OS_HOST_BIN OS_HOST="$UP_HOST" OS_HOST_URL OS_ORG OS_SLUG="$SLUG"
      export OS_PROFILE="$ROOT/company-profile.md"
    fi
    ;;
esac

# Where to write: a temporary worktree on origin/main (team), or the folder itself (solo).
prepare() {
  local dir=$1 tw
  if [ "$TEAM" -eq 1 ]; then
    tw=$(mktemp -d)
    git -C "$dir" worktree add -q --detach "$tw/b" refs/remotes/origin/main >/dev/null 2>&1 \
      || os_die 3 "root-router: could not prepare the change in ${dir}. Run again."
    printf '%s\n' "$tw/b"
  else
    [ -z "$(git -C "$dir" status --porcelain)" ] \
      || os_die 2 "root-router: ${dir} has uncommitted changes. Commit or stash them, then run again."
    printf '%s\n' "$dir"
  fi
}

finish() {
  local dir=$1 wt=$2 repo=$3 title=$4 body=$5 rc=0 pr number
  shift 5
  os_git_commit "$wt" "$title" "$@" >/dev/null
  if [ "$TEAM" -eq 0 ]; then
    printf 'committed: %s (main)\n' "$repo"
    return 0
  fi
  if git -C "$wt" diff --quiet refs/remotes/origin/main HEAD; then
    git -C "$dir" worktree remove --force "$wt" >/dev/null 2>&1 || true
    return 0
  fi
  if [ "$HOST_ON" -eq 1 ]; then
    os_with_git_token git -C "$wt" push -q --force origin "HEAD:refs/heads/${BRANCH}" || rc=$?
  else
    git -C "$wt" push -q --force origin "HEAD:refs/heads/${BRANCH}" || rc=$?
  fi
  git -C "$dir" worktree remove --force "$wt" >/dev/null 2>&1 || true
  [ "$rc" -eq 0 ] || os_die 3 "root-router: could not push ${BRANCH} for ${repo}. Check the sign-in, then run again."
  printf 'pushed: %s %s\n' "$repo" "$BRANCH"
  if [ "$HOST_ON" -eq 1 ]; then
    pr=$(os_host open-pr "$repo" --head "$BRANCH" --base main --title "$title" --body-file "$body")
    number=$(printf '%s' "$pr" | jq -r '.number // empty')
    [ -n "$number" ] || os_die 3 "root-router: could not open a pull request for ${repo}"
    printf 'pr: %s %s (the admin merges it by hand; no auto-merge)\n' "$repo" "$number"
  else
    printf 'pr: open a pull request in %s from %s to main\n' "$repo" "$BRANCH"
  fi
}

# Tag the starting point once, in both repos. No delete and no history rewrite here.
for d in "$ROOT" "$EV"; do
  git -C "$d" rev-parse -q --verify refs/tags/pre-root-router >/dev/null \
    || git -C "$d" tag pre-root-router "$(ref_of "$d")"
done

# 1. The company root: add the files and the index lines.
RW=$(prepare "$ROOT")
paths=()
for p in ${MOVE[@]+"${MOVE[@]}"}; do
  mkdir -p "$RW/$(dirname "$p")"
  git -C "$EV" show "$EREF:$p" > "$RW/$p"
  paths+=("$p")
done
if [ "$NINDEX" -gt 0 ]; then
  mkdir -p "$RW/memory"
  [ -f "$RW/memory/MEMORY.md" ] || printf '# Memory\n\n' > "$RW/memory/MEMORY.md"
  [ -z "$(tail -c 1 "$RW/memory/MEMORY.md")" ] || printf '\n' >> "$RW/memory/MEMORY.md"
  cat "$INDEX" >> "$RW/memory/MEMORY.md"
  paths+=(memory/MEMORY.md)
fi
rbody=$(mktemp)
{
  printf 'Root router (D163): company facts and curated memory come back to the company root from areas/everyone.\n\n'
  printf 'Every person with the company repo reads these files after the merge. The admin checked the list. Merge this one first, then the everyone pull request.\n\n'
  for p in ${paths[@]+"${paths[@]}"}; do printf -- '- %s\n' "$p"; done
} > "$rbody"
if [ "${#paths[@]}" -gt 0 ]; then
  finish "$ROOT" "$RW" "$(os_company_repo "${SLUG:-company}")" "Root router: company facts and memory back to the root" "$rbody" "${paths[@]}"
elif [ "$TEAM" -eq 1 ]; then
  git -C "$ROOT" worktree remove --force "$RW" >/dev/null 2>&1 || true
fi

# 2. areas/everyone: remove what is now at the root, add a pointer README.
EW=$(prepare "$EV")
epaths=()
for p in ${MOVE[@]+"${MOVE[@]}"} ${SAME[@]+"${SAME[@]}"}; do
  git -C "$EW" rm -q -- "$p" >/dev/null
  epaths+=("$p")
done
if [ ! -f "$EW/README.md" ]; then
  cat > "$EW/README.md" << 'EOF'
# Everyone

Company-wide meetings and decisions, and the tools every person has. Company facts
(customers, offers, voice) and company memory live at the company root (`../../`), not here.
EOF
  epaths+=(README.md)
fi
ebody=$(mktemp)
{
  printf 'Root router (D163): these files now live at the company root. Merge the company pull request first.\n\n'
  for p in ${epaths[@]+"${epaths[@]}"}; do printf -- '- %s\n' "$p"; done
} > "$ebody"
if [ "${#epaths[@]}" -gt 0 ]; then
  finish "$EV" "$EW" "$(os_area_repo "${SLUG:-company}" everyone)" "Root router: facts and memory moved to the company root" "$ebody" "${epaths[@]}"
elif [ "$TEAM" -eq 1 ]; then
  git -C "$EV" worktree remove --force "$EW" >/dev/null 2>&1 || true
fi

printf 'root-router: done. Run it again after both merges: it should say "already done".\n'
