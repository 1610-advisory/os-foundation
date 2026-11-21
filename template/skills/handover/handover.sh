#!/bin/bash
# Handover: move a company folder held in an advisor firm's org (the holder) to the
# company's own org. A fresh copy of each repo, with no history. Bash 3.2.
# Run by the holder's owner. A dry run by default.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/../add-teammate/lib.sh"

usage() {
  cat << 'EOF'
usage: handover.sh --to-org <org> --admin <slug> [--root <dir>] [--go | --archive | --undo]

Move a held company folder (host_mode: held) to the company's own org.
No flag: a dry run. It checks everything and prints each step. It changes nothing.
--go       Steps 1 to 7: a fresh copy of each repo (one commit, no history), pushed to
           <org>. CODEOWNERS and the people page name the company admin. host_mode is own.
           The holder copies stay as they are. It prints the team-on line for the admin.
--archive  Step 8, after the company admin ran team-on: archive the holder copies.
           Never deletes them.
--undo     Before --archive only: archive the copies that --go pushed to <org> (never
           delete), and forget the handover. The holder copies were not changed.

--admin is the company admin's slug: a people page with that slug and a github login,
not a holder person. Their login must be an owner of <org>.
Never moved: a holder person's workspace (users/<slug>) and people page (holder: true).
Exit 0 ok, 1 usage, 2 a check failed (nothing changed), 3 host error.
EOF
}

ROOT=""
TO_ORG=""
ADMIN=""
MODE=dry
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --root) [ $# -ge 2 ] || os_die 1 "--root needs a folder"; ROOT=$2; shift 2 ;;
    --to-org) [ $# -ge 2 ] || os_die 1 "--to-org needs an org"; TO_ORG=$2; shift 2 ;;
    --admin) [ $# -ge 2 ] || os_die 1 "--admin needs a slug"; ADMIN=$2; shift 2 ;;
    --go) [ "$MODE" = dry ] || os_die 1 "use one of --go, --archive, --undo"; MODE=go; shift ;;
    --archive) [ "$MODE" = dry ] || os_die 1 "use one of --go, --archive, --undo"; MODE=archive; shift ;;
    --undo) [ "$MODE" = dry ] || os_die 1 "use one of --go, --archive, --undo"; MODE=undo; shift ;;
    *) os_die 1 "unknown argument: $1" ;;
  esac
done

os_need git jq tar
[ -n "$ROOT" ] || ROOT=$(pwd)
[ -d "$ROOT" ] || os_die 1 "company folder is missing"
ROOT=$(cd "$ROOT" && pwd)
PROFILE="$ROOT/company-profile.md"
[ -f "$PROFILE" ] || os_die 1 "company-profile.md is missing"

SLUG=$(os_fm_get "$PROFILE" company_slug 2>/dev/null || true)
case "$SLUG" in ""|*'{{'*) os_die 2 "company_slug is not set" ;; esac
HOST_KIND=$(os_fm_get "$PROFILE" host 2>/dev/null || true)
HOST_URL=$(os_unquote "$(os_fm_get "$PROFILE" host_url 2>/dev/null || true)")
HOLDER=$(os_unquote "$(os_fm_get "$PROFILE" holder_org 2>/dev/null || true)")
HOST_MODE=$(os_fm_get "$PROFILE" host_mode 2>/dev/null || true)
case "$HOST_KIND" in github|forgejo) ;; *) os_die 2 "host is not github or forgejo: run team-on first" ;; esac

if ! OS_HOST_BIN=$(os_find_host "$ROOT" "$DIR"); then
  os_die 3 "host.sh is missing"
fi
export OS_HOST_BIN OS_HOST="$HOST_KIND" OS_HOST_URL="$HOST_URL" OS_SLUG="$SLUG"
export OS_PROFILE="$PROFILE"

CFG=$(os_config_dir "$SLUG")
RECORD="$CFG/handover.json"

step() {
  printf 'step %s: %s\n' "$1" "$2"
}

# Run host.sh against one org. own: the company's org. held: the holder org.
on_org() {
  local org=$1 mode=$2
  shift 2
  OS_ORG="$org" OS_HOST_MODE="$mode" os_host "$@"
}

# --archive and --undo work from the record that --go wrote.
if [ "$MODE" = "archive" ] || [ "$MODE" = "undo" ]; then
  [ -f "$RECORD" ] || os_die 2 "no handover to ${MODE}: ${RECORD} is missing (run --go first)"
  state=$(jq -r '.state // empty' "$RECORD")
  rec_to=$(jq -r '.to_org // empty' "$RECORD")
  rec_holder=$(jq -r '.holder_org // empty' "$RECORD")
  [ -z "$TO_ORG" ] || [ "$TO_ORG" = "$rec_to" ] || os_die 2 "the handover went to ${rec_to}, not ${TO_ORG}"
  [ "$state" = "pushed" ] || os_die 2 "the handover is ${state:-unknown}: ${MODE} works only after --go and before --archive"
  repos=$(jq -r '.repos[]' "$RECORD")
  if [ "$MODE" = "archive" ]; then
    step 8 "archive the holder copies in ${rec_holder} (never delete)"
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      on_org "$rec_holder" held archive-repo "$r" >/dev/null || os_die 3 "could not archive ${rec_holder}/${r}: run --archive again"
      printf 'archived: %s/%s\n' "$rec_holder" "$r"
    done << EOF
${repos}
EOF
    tmp=$(mktemp)
    jq --arg at "$(os_stamp)" '.state = "archived" | .archived_at = $at' "$RECORD" > "$tmp" && mv "$tmp" "$RECORD"
    printf '%s\n' "handover: done. The company works in ${rec_to} now."
    exit 0
  fi
  step undo "archive the copies --go pushed to ${rec_to} (never delete). The holder copies were not changed."
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    on_org "$rec_to" own archive-repo "$r" >/dev/null || os_die 3 "could not archive ${rec_to}/${r}: run --undo again"
    printf 'archived: %s/%s\n' "$rec_to" "$r"
  done << EOF
${repos}
EOF
  mv "$RECORD" "$CFG/handover-undone-$(date -u +%Y%m%dT%H%M%SZ).json"
  printf '%s\n' "undo: done. ${rec_holder} still holds the company. An owner of ${rec_to} deletes the archived copies before the next handover. This script never runs these:"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if [ "$HOST_KIND" = "github" ]; then
      printf 'delete: gh repo delete %s/%s\n' "$rec_to" "$r"
    else
      printf 'delete: %s/%s/%s/settings (Danger Zone: Delete this repository)\n' "${HOST_URL%/}" "$rec_to" "$r"
    fi
  done << EOF
${repos}
EOF
  exit 0
fi

# Dry run and --go.
[ -n "$TO_ORG" ] || os_die 1 "pass --to-org <org>"
[ -n "$ADMIN" ] || os_die 1 "pass --admin <slug>"
host_require_plain() {
  case "$1" in ""|.*|*[!A-Za-z0-9._-]*) os_die 1 "$2 is not a plain name" ;; esac
}
host_require_plain "$TO_ORG" "--to-org"
host_require_plain "$ADMIN" "--admin"
[ "$HOST_MODE" = "held" ] || os_die 2 "host_mode is ${HOST_MODE:-own}, not held: there is nothing to hand over"
[ -n "$HOLDER" ] || os_die 2 "holder_org is empty in company-profile.md"
[ "$TO_ORG" != "$HOLDER" ] || os_die 2 "--to-org is the holder org: name the company's own org"
if [ -f "$RECORD" ] && [ "$(jq -r '.state // empty' "$RECORD")" = "pushed" ]; then
  os_die 2 "a handover to $(jq -r '.to_org' "$RECORD") is open: run --archive or --undo first"
fi

# The holder's people: their pages and workspaces never move.
HOLDER_SLUGS=""
HOLDER_LOGINS=""
for page in "$ROOT"/people/*.md; do
  [ -f "$page" ] || continue
  [ "$(os_fm_get "$page" holder 2>/dev/null || true)" = "true" ] || continue
  HOLDER_SLUGS="${HOLDER_SLUGS} $(os_fm_get "$page" slug 2>/dev/null || true)"
  HOLDER_LOGINS="${HOLDER_LOGINS} $(os_fm_get "$page" github 2>/dev/null || true)"
done
[ -n "$(os_trim "$HOLDER_LOGINS")" ] || os_die 2 "no holder person: a people page with holder: true names the owner on record"
is_holder_slug() {
  case " ${HOLDER_SLUGS} " in *" $1 "*) return 0 ;; esac
  return 1
}

ADMIN_PAGE=$(os_person_file "$ROOT" "$ADMIN") || os_die 2 "no people page with slug: ${ADMIN}"
! is_holder_slug "$ADMIN" || os_die 2 "${ADMIN} is a holder person: name the company's own admin"
ADMIN_GH=$(os_fm_get "$ADMIN_PAGE" github 2>/dev/null || true)
[ -n "$ADMIN_GH" ] || os_die 2 "${ADMIN} has no github login on their people page"

# Step 1: every repo is clean and pushed, with no open pull request.
step 1 "check every repo is clean and pushed"
REPO_DIRS=()
REPO_NAMES=()
check_repo() {
  local d=$1 rel=$2 url name ahead
  url=$(git -C "$d" remote get-url origin 2>/dev/null || true)
  [ -n "$url" ] || os_die 2 "${rel}: no origin: push it to ${HOLDER} first"
  name=$(basename "$url" .git)
  case "$name" in "${SLUG}"-*) ;; *) os_die 2 "${rel}: repo ${name} does not start with ${SLUG}-" ;; esac
  [ -z "$(git -C "$d" status --porcelain)" ] || os_die 2 "${rel}: uncommitted changes: commit and push them first"
  os_with_git_token git -C "$d" fetch -q origin || os_die 3 "${rel}: could not fetch from ${HOLDER}"
  git -C "$d" rev-parse -q --verify refs/remotes/origin/main >/dev/null || os_die 2 "${rel}: origin has no main"
  ahead=$(git -C "$d" log --oneline --branches --not --remotes | wc -l | tr -d ' ')
  [ "$ahead" = "0" ] || os_die 2 "${rel}: ${ahead} commits are not pushed: push them first"
  if git -C "$d" rev-parse -q --verify refs/heads/main >/dev/null \
    && [ "$(git -C "$d" rev-parse main)" != "$(git -C "$d" rev-parse origin/main)" ]; then
    os_die 2 "${rel}: main is not the same as ${HOLDER}/${name} main: pull or push first"
  fi
  prs=$(on_org "$HOLDER" held open-prs "$name" 2>/dev/null) || os_die 3 "${rel}: could not list the open pull requests"
  n=$(printf '%s' "$prs" | jq '.prs | length')
  [ "$n" = "0" ] || os_die 2 "${rel}: ${n} open pull requests in ${HOLDER}/${name}: merge or close them first (notes on a branch would not move)"
  REPO_DIRS+=("$d")
  REPO_NAMES+=("$name")
  printf 'ok: %s (%s/%s)\n' "$rel" "$HOLDER" "$name"
}
check_repo "$ROOT" "company root"
for d in "$ROOT"/areas/* "$ROOT"/library "$ROOT"/users/*; do
  [ -e "$d/.git" ] || continue
  rel=${d#"$ROOT"/}
  case "$rel" in
    users/*)
      if is_holder_slug "${rel#users/}"; then
        printf 'skip: %s (a holder person'"'"'s workspace: it never moves)\n' "$rel"
        continue
      fi
      ;;
  esac
  check_repo "$d" "$rel"
done

# The admin page moves from main, so it must be there now (not only on this computer).
ADMIN_REL=${ADMIN_PAGE#"$ROOT"/}
git -C "$ROOT" cat-file -e "refs/remotes/origin/main:${ADMIN_REL}" 2>/dev/null \
  || os_die 2 "${ADMIN_REL} is not on main in ${HOLDER}/${REPO_NAMES[0]}: merge it first, then run this again"

# Step 2: the company's own org is there, on a paid plan, and the admin is an owner.
step 2 "check ${TO_ORG}: it exists, its plan, ${ADMIN_GH} is an owner, no repo of the same name"
if [ "$HOST_KIND" = "github" ]; then
  on_org "$TO_ORG" own plan-check >/dev/null || os_die 2 "${TO_ORG}: the plan check failed (it must exist, on GitHub Team, and you must be an owner)"
fi
mem=$(on_org "$TO_ORG" own org-membership "$ADMIN_GH" 2>/dev/null) || os_die 2 "${TO_ORG}: could not read the membership of ${ADMIN_GH}"
[ "$(printf '%s' "$mem" | jq -r '.state // empty')" = "active" ] && [ "$(printf '%s' "$mem" | jq -r '.role // empty')" = "admin" ] \
  || os_die 2 "${TO_ORG}: ${ADMIN_GH} is not an owner. Make them an owner, then run this again"
for name in "${REPO_NAMES[@]}"; do
  set +e
  on_org "$TO_ORG" own repo-access "$name" >/dev/null 2>&1
  rc=$?
  set -e
  case "$rc" in
    2) ;;
    0) os_die 2 "${TO_ORG}/${name} is already there: an owner of ${TO_ORG} removes it first" ;;
    *) os_die 3 "${TO_ORG}: could not check ${name}" ;;
  esac
done

if [ "$MODE" = "dry" ]; then
  step 3 "would make a fresh copy of ${#REPO_NAMES[@]} repos: ${REPO_NAMES[*]} (one commit: Handover from ${HOLDER})"
  step 4 "would rewrite CODEOWNERS to @${ADMIN_GH} and set role: admin on ${ADMIN_PAGE#"$ROOT"/}; holder pages stay out"
  step 5 "would set host_mode: own, holder_org: \"\", org: ${TO_ORG}"
  step 6 "would push each copy to ${TO_ORG}"
  step 7 "would print the team-on line for the company admin"
  step 8 "later, with --archive: archive the holder copies in ${HOLDER} (never delete)"
  printf '%s\n' "dry run: nothing was changed. Run again with --go."
  exit 0
fi

# Steps 3 to 6: a fresh copy of each repo, with no history.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
HOLDER_RE=$(printf '%s' "$HOLDER_LOGINS" | tr -s ' ' '\n' | grep -v '^$' | sed 's/[.]/\\./g' | paste -sd'|' -)

# Every holder login in a CODEOWNERS file becomes the admin. One name once per line.
rewrite_owners() {
  local f=$1 tmp
  [ -f "$f" ] || return 0
  tmp=$(mktemp)
  awk -v re="^@(${HOLDER_RE})\$" -v admin="@${ADMIN_GH}" '
    /^#/ || NF < 2 { print; next }
    {
      out = $1; delete seen
      for (i = 2; i <= NF; i++) {
        w = $i
        if (tolower(w) ~ tolower(re)) w = admin
        if (!(tolower(w) in seen)) { seen[tolower(w)] = 1; out = out " " w }
      }
      print out
    }' "$f" > "$tmp"
  mv "$tmp" "$f"
}

step 3 "make a fresh copy of each repo (one commit: Handover from ${HOLDER})"
i=0
for d in "${REPO_DIRS[@]}"; do
  name=${REPO_NAMES[$i]}
  copy="$WORK/$name"
  mkdir -p "$copy"
  git -C "$d" archive --format=tar refs/remotes/origin/main | tar -x -C "$copy"
  if [ "$d" = "$ROOT" ]; then
    # Holder pages are the holder's: they never move.
    for page in "$copy"/people/*.md; do
      [ -f "$page" ] || continue
      if [ "$(os_fm_get "$page" holder 2>/dev/null || true)" = "true" ]; then
        rm -f "$page"
        printf 'left out: %s (holder page)\n' "${page#"$copy"/}"
      fi
    done
  fi
  i=$((i + 1))
done

step 4 "name the company admin @${ADMIN_GH} in CODEOWNERS and on the people page"
for name in "${REPO_NAMES[@]}"; do
  rewrite_owners "$WORK/$name/.github/CODEOWNERS"
  rewrite_owners "$WORK/$name/.gitea/CODEOWNERS"
done
ROOT_COPY="$WORK/${REPO_NAMES[0]}"
copy_page="$ROOT_COPY/${ADMIN_PAGE#"$ROOT"/}"
[ -f "$copy_page" ] || os_die 2 "${ADMIN_PAGE#"$ROOT"/} is not on main in ${HOLDER}: merge it first"
os_fm_set "$copy_page" role admin

step 5 "switch host_mode to own, org to ${TO_ORG}"
os_fm_set "$ROOT_COPY/company-profile.md" host_mode own
os_fm_set "$ROOT_COPY/company-profile.md" holder_org '""'
os_fm_set "$ROOT_COPY/company-profile.md" org "$TO_ORG"

for name in "${REPO_NAMES[@]}"; do
  copy="$WORK/$name"
  git -C "$copy" init -q
  git -C "$copy" checkout -q -b main 2>/dev/null || git -C "$copy" symbolic-ref HEAD refs/heads/main
  os_git_commit "$copy" "Handover from ${HOLDER}" . >/dev/null
done

step 6 "push each copy to ${TO_ORG}"
mkdir -p "$CFG"
pushed=()
write_record() {
  local list
  list=$(printf '%s\n' "${pushed[@]+"${pushed[@]}"}" | jq -Rsc 'split("\n") | map(select(length > 0))')
  jq -nc --arg to "$TO_ORG" --arg holder "$HOLDER" --arg admin "$ADMIN" --arg at "$(os_stamp)" \
    --argjson repos "$list" --arg state "$1" \
    '{state:$state, to_org:$to, holder_org:$holder, admin:$admin, repos:$repos, at:$at}' > "$RECORD"
  chmod 600 "$RECORD"
}
for name in "${REPO_NAMES[@]}"; do
  if ! on_org "$TO_ORG" own create-repo "$name" --private --source "$WORK/$name" --push >/dev/null; then
    write_record pushed
    os_die 3 "push to ${TO_ORG}/${name} failed. The holder copies are not changed. Run --undo to archive what was pushed, then try again"
  fi
  pushed+=("$name")
  printf 'pushed: %s/%s\n' "$TO_ORG" "$name"
done
write_record pushed

step 7 "the company admin turns on the team in ${TO_ORG}"
printf 'team-on: %s clones %s/%s, then runs skills/add-teammate/team-on.sh --answers <file> with host=%s, org=%s, host_mode=own (no holder_org, no holder=true)\n' \
  "$ADMIN_GH" "$TO_ORG" "${REPO_NAMES[0]}" "$HOST_KIND" "$TO_ORG"
printf '%s\n' "manual: point the kernel's GitHub team link at ${TO_ORG}"
printf '%s\n' "this folder still points at ${HOLDER}. The holder copies are not changed."
printf '%s\n' "next: after team-on in ${TO_ORG}, run handover.sh --archive. Until then, handover.sh --undo takes it back."
