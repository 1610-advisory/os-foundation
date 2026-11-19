#!/bin/bash
# upgrade --root-router (D163): facts and curated memory move from areas/everyone to the
# root; meetings and logs stay; dry run changes nothing; --yes needed; conflicts stop;
# a second run says "already done". Solo (no origin) and team without a host (bare origins).
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../team/common.sh"
root=$(team_root)
upgrade="$root/template/skills/upgrade/upgrade.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c init.defaultBranch=main "$@"; }

make_company() {
  local c=$1
  mkdir -p "$c/memory" "$c/areas"
  printf -- '---\nlevel: solo\ncompany_slug: acme\n---\n' > "$c/company-profile.md"
  printf '# Memory\n\n- [Old fact](old-fact.md) — kept\n' > "$c/memory/MEMORY.md"
  printf 'old fact\n' > "$c/memory/old-fact.md"
  printf 'areas/\n' > "$c/.gitignore"
  g -C "$c" init -q && g -C "$c" add -A && g -C "$c" commit -qm start
  local e="$c/areas/everyone"
  mkdir -p "$e/memory/logs" "$e/meetings" "$e/decisions"
  printf 'customers\n' > "$e/customers.md"
  printf 'offers\n' > "$e/offers.md"
  printf 'about us\n' > "$e/company.md"
  printf 'decision\n' > "$e/decisions/2026-11-17 Pricing.md"
  printf 'readme\n' > "$e/decisions/README.md"
  printf '# Memory\n\n- [How we work](how-we-work.md) — calls first\n- [Old fact](old-fact.md) — kept\n' > "$e/memory/MEMORY.md"
  printf 'calls first\n' > "$e/memory/how-we-work.md"
  printf 'old fact\n' > "$e/memory/old-fact.md"
  printf 'log\n' > "$e/memory/logs/2026-11-17-ada.md"
  printf 'all hands\n' > "$e/meetings/2026-11-17 All hands.md"
  g -C "$e" init -q && g -C "$e" add -A && g -C "$e" commit -qm start
}

check_moved() {
  local c=$1 e=$2
  for p in customers.md offers.md company.md memory/how-we-work.md; do
    [ -f "$c/$p" ] || team_fail "root lacks $p"
    [ ! -e "$e/$p" ] || team_fail "everyone still has $p"
  done
  [ ! -e "$c/decisions" ] || team_fail "decisions moved to the root"
  [ -f "$e/decisions/2026-11-17 Pricing.md" ] || team_fail "decisions left everyone"
  [ ! -e "$e/memory/old-fact.md" ] || team_fail "same file not removed from everyone"
  [ -f "$e/memory/logs/2026-11-17-ada.md" ] || team_fail "logs left everyone"
  [ -f "$e/meetings/2026-11-17 All hands.md" ] || team_fail "meetings left everyone"
  [ -f "$e/README.md" ] || team_fail "no pointer README in everyone"
  grep -qF '(how-we-work.md)' "$c/memory/MEMORY.md" || team_fail "index line missing"
  [ "$(grep -cF '(old-fact.md)' "$c/memory/MEMORY.md")" = 1 ] || team_fail "index line doubled"
}

# --- Solo.
c="$work/solo/acme-os"
make_company "$c"
e="$c/areas/everyone"
out=$(bash "$upgrade" --root-router --dry-run --root "$c")
printf '%s\n' "$out" | grep -q '^move: areas/everyone/customers.md -> customers.md$' || team_fail "dry run: no move line"
printf '%s\n' "$out" | grep -q '^same: memory/old-fact.md' || team_fail "dry run: no same line"
printf '%s\n' "$out" | grep -q '^index: memory/MEMORY.md gets 1 line' || team_fail "dry run: no index line"
printf '%s\n' "$out" | grep -q '^todo: company.md' || team_fail "dry run: no todo line"
[ ! -e "$c/customers.md" ] || team_fail "dry run wrote a file"
set +e
bash "$upgrade" --root-router --root "$c" > /dev/null 2>"$work/err"
rc=$?
set -e
[ "$rc" = 2 ] || team_fail "no --yes: expected exit 2, got $rc"
[ ! -e "$c/customers.md" ] || team_fail "no --yes wrote a file"
bash "$upgrade" --root-router --yes --root "$c" > "$work/out"
grep -q '^committed: acme-os (main)$' "$work/out" || team_fail "solo: no root commit line"
check_moved "$c" "$e"
[ -z "$(git -C "$c" status --porcelain)" ] || team_fail "root left dirty"
[ -z "$(git -C "$e" status --porcelain)" ] || team_fail "everyone left dirty"
git -C "$c" rev-parse -q --verify refs/tags/pre-root-router >/dev/null || team_fail "no tag"
out=$(bash "$upgrade" --root-router --yes --root "$c")
printf '%s\n' "$out" | grep -q 'already done' || team_fail "second run not idempotent"

# --- Conflict stops before any write.
c="$work/conflict/acme-os"
make_company "$c"
printf 'different\n' > "$c/customers.md"
g -C "$c" add customers.md && g -C "$c" commit -qm diff
out=$(bash "$upgrade" --root-router --dry-run --root "$c")
printf '%s\n' "$out" | grep -q '^conflict: customers.md' || team_fail "no conflict line"
set +e
bash "$upgrade" --root-router --yes --root "$c" > /dev/null 2>&1
rc=$?
set -e
[ "$rc" = 2 ] || team_fail "conflict: expected exit 2, got $rc"
[ ! -e "$c/offers.md" ] || team_fail "conflict run wrote a file"

# --- No everyone repo.
c="$work/none/acme-os"
mkdir -p "$c"
printf -- '---\nlevel: solo\n---\n' > "$c/company-profile.md"
g -C "$c" init -q && g -C "$c" add -A && g -C "$c" commit -qm start
out=$(bash "$upgrade" --root-router --root "$c")
printf '%s\n' "$out" | grep -q 'nothing to do' || team_fail "no everyone: wrong line"

# --- Team without a host: branches pushed to bare origins, main untouched.
c="$work/team/acme-os"
make_company "$c"
e="$c/areas/everyone"
g init -q --bare "$work/team/acme-os.git"
g init -q --bare "$work/team/acme-everyone.git"
g -C "$c" remote add origin "$work/team/acme-os.git" && g -C "$c" push -q origin main && g -C "$c" fetch -q origin
g -C "$e" remote add origin "$work/team/acme-everyone.git" && g -C "$e" push -q origin main && g -C "$e" fetch -q origin
bash "$upgrade" --root-router --yes --root "$c" > "$work/out"
grep -q '^pushed: acme-os upgrade/root-router$' "$work/out" || team_fail "team: root branch not pushed"
grep -q '^pushed: acme-everyone upgrade/root-router$' "$work/out" || team_fail "team: everyone branch not pushed"
[ ! -e "$c/customers.md" ] || team_fail "team: the folder changed (it must stay on main)"
[ "$(git -C "$c" worktree list | wc -l | tr -d ' ')" = 1 ] || team_fail "team: a worktree was left"
# Merge both branches as the host would, then pull: the result is the same as solo.
for d in "$c" "$e"; do
  g -C "$d" fetch -q origin
  g -C "$d" merge -q --ff-only origin/upgrade/root-router
  g -C "$d" push -q origin main
  g -C "$d" fetch -q origin
done
check_moved "$c" "$e"
out=$(bash "$upgrade" --root-router --yes --root "$c")
printf '%s\n' "$out" | grep -q 'already done' || team_fail "team: second run not idempotent"

printf 'PASS root-router\n'
