#!/bin/bash
# Sweep before access (v1.0.4, B90): list what one person will be able to read, so an
# owner looks at it once before the invite. Local git only. Reads main in each repo.
# Changes nothing and calls no host.
set -euo pipefail

usage() {
  cat << 'EOF'
usage: skills/add-teammate/sweep.sh --areas a,b [--person slug]

Run from the company root. Prints what a person with these areas can read:
- every file on main in the company repo (everyone reads it),
- every file on main in each area named,
- files deleted from those repos that are still in their history,
- "look:" lines for files that mention access, billing, ownership or leadership.
Exit 0 always after a full list. Exit 1 on a usage error or a missing repo.
EOF
}

areas=""
person=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --areas) areas=${2:-}; shift 2 ;;
    --person) person=${2:-}; shift 2 ;;
    *) usage >&2; exit 1 ;;
  esac
done

ROOT=$(pwd)
if [ ! -f "$ROOT/company-profile.md" ] || ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  printf '%s\n' "sweep: run this from the company root" >&2
  exit 1
fi

# Words that often mark admin material. A hit is only a hint: the owner decides.
LOOK='(^|[^a-z])(admins?|access|logins?|passwords?|billing|subscription|plan:|ownership|owners? only|equity|salary|salaries|payroll|hiring|leadership|board meeting|private repo|github org|api key|tokens?)([^a-z]|$)'

ref_of() {
  local repo=$1
  if git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then
    printf '%s\n' origin/main
  else
    printf '%s\n' main
  fi
}

sweep_repo() {
  local repo=$1 label=$2 ref n gone path
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s\n' "sweep: ${label} is not a repo on this computer" >&2
    exit 1
  fi
  ref=$(ref_of "$repo")
  n=$(git -C "$repo" ls-tree -r --name-only "$ref" | wc -l | tr -d ' ')
  printf '\n%s: %s files on %s\n' "$label" "$n" "$ref"
  git -C "$repo" -c core.quotepath=false ls-tree -r --name-only "$ref" | sed 's/^/  /'
  git -C "$repo" -c core.quotepath=false ls-tree -r --name-only "$ref" | while IFS= read -r path; do
    case "$path" in
      skills/*|.github/*|.gitea/*|.forgejo/*|.claude/*|.agents/*) continue ;;
    esac
    if git -C "$repo" show "${ref}:${path}" 2>/dev/null | grep -Eiq "$LOOK"; then
      printf 'look: %s: %s mentions access, billing, ownership or leadership\n' "$label" "$path"
    fi
  done
  gone=$(git -C "$repo" -c core.quotepath=false log "$ref" --diff-filter=D --name-only --format= 2>/dev/null | sort -u | while IFS= read -r path; do
    [ -n "$path" ] || continue
    git -C "$repo" cat-file -e "${ref}:${path}" 2>/dev/null && continue
    printf '%s\n' "$path"
  done)
  if [ -n "$gone" ]; then
    printf 'history: %s: these files were deleted, but anyone who can read the repo can still read them in its history:\n' "$label"
    printf '%s\n' "$gone" | sed 's/^/  /'
  fi
}

printf 'sweep: what %s will be able to read\n' "${person:-this person}"
sweep_repo "$ROOT" "company repo (everyone)"
IFS=',' read -r -a area_list <<< "$areas"
for a in "${area_list[@]+"${area_list[@]}"}"; do
  a=$(printf '%s' "$a" | tr -d '[:space:]')
  [ -n "$a" ] || continue
  sweep_repo "$ROOT/areas/$a" "area $a"
done
printf '\n%s\n' "sweep: done. Show this to the owner. Ask: \"Is it fine for them to read all of this?\" Wait for a clear yes before the invite."
