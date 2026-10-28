#!/bin/bash
# Upgrade a v0 team company on a git host (GitHub path). A fake host.sh logs each verb.
# Checks: host set before the first host call, company_slug written, check tools on main
# before the pull requests, protect after, auto-merge failure is not fatal, area logs moved.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../team/common.sh"
root=$(team_root)
upgrade="$root/template/skills/upgrade/upgrade.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git filter-repo -h >/dev/null 2>&1 || { printf '%s\n' "BLOCKED: git filter-repo is not installed"; exit 0; }

commit_all() {
  local dir=$1 msg=$2
  git -C "$dir" add -A
  GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
    GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
    git -C "$dir" commit -q -m "$msg"
}

# v0 logs branch, checked out at memory/logs/ (skills/logs-folder in v0).
add_logs_branch() {
  local dir=$1 who=$2
  git -C "$dir" worktree add -q --detach memory/logs
  git -C "$dir/memory/logs" checkout -q --orphan logs
  git -C "$dir/memory/logs" rm -rfq .
  printf '%s\n' "worked on the shop" > "$dir/memory/logs/2026-10-01-${who}.md"
  commit_all "$dir/memory/logs" "log"
}

mkdir -p "$work/bin"
cat > "$work/bin/host.sh" << 'EOF'
#!/bin/bash
printf '%s %s host=%s org=%s\n' "$1" "${2:-}" "${OS_HOST:-unset}" "${OS_ORG:-unset}" >> "$FAKE_HOST_LOG"
case "$1" in
  get-token) printf '%s\n' local-token ;;
  whoami) printf '%s\n' '{"login":"acme-admin"}' ;;
  plan-check)
    if [ "${FAKE_PLAN:-team}" = "free" ]; then
      printf '%s\n' "This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again." >&2
      exit 3
    fi
    printf '{"plan":"%s"}\n' "${FAKE_PLAN:-team}"
    ;;
  secret-exists) printf '%s\n' '{"exists":true}' ;;
  open-pr) printf '%s\n' '{"number":5,"url":"http://example.test/5"}' ;;
  auto-merge) printf '%s\n' "Auto merge is not allowed for this repository" >&2; exit 3 ;;
  protect|unprotect) printf '%s\n' '{"ok":true}' ;;
  *) exit 1 ;;
esac
EOF
chmod 700 "$work/bin/host.sh"
export OS_HOST_SH="$work/bin/host.sh" FAKE_HOST_LOG="$work/host.log"
unset OS_HOST OS_ORG OS_HOST_URL OS_SLUG OS_PROFILE

# A v0 team company: classic setup, "* @admin" owners, logs branches, no host or slug in the profile.
make_v0() {
  local co=$1 origin_name=$2 area=$1/areas/marketing
  mkdir -p "$co"
  git -C "$root" archive c2034af template | tar -x -C "$work"
  cp -R "$work/template/." "$co/"
  rm -rf "$work/template"
  mkdir -p "$co/.github"
  printf '%s\n' '* @acme-admin' > "$co/.github/CODEOWNERS"
  git -C "$co" init -q
  git -C "$co" checkout -q -b main
  commit_all "$co" "v0 start"
  add_logs_branch "$co" ada
  mkdir -p "$area/.github"
  git -C "$root" archive c2034af template/skills/add-area/templates/_area | tar -x -C "$work"
  cp -R "$work/template/skills/add-area/templates/_area/." "$area/"
  rm -rf "$work/template"
  printf '%s\n' '* @acme-admin' > "$area/.github/CODEOWNERS"
  git -C "$area" init -q
  git -C "$area" checkout -q -b main
  commit_all "$area" "area start"
  add_logs_branch "$area" ada
  mkdir -p "$work/git"
  git init -q --bare "$work/git/${origin_name}.git"
  git init -q --bare "$work/git/${origin_name%-os}-marketing.git"
  git -C "$co" remote add origin "$work/git/${origin_name}.git"
  git -C "$co" push -q origin main logs
  git -C "$area" remote add origin "$work/git/${origin_name%-os}-marketing.git"
  git -C "$area" push -q origin main logs
}

co="$work/company"
make_v0 "$co" acme2-os
cat > "$work/answers" << 'EOF'
level=team
host=github
org=acme
review_vendor=xai
EOF

# Dry run: the host is known before the first host call (B8).
: > "$FAKE_HOST_LOG"
"$upgrade" --dry-run --root "$co" --template "$root/template" --answers "$work/answers" > "$work/dry.out" 2>&1 \
  || { cat "$work/dry.out" >&2; team_fail "dry run failed"; }
grep -q 'host is not set' "$work/dry.out" && team_fail "dry run: host is not set"
grep -q 'could not fetch' "$work/dry.out" && team_fail "dry run could not fetch the area"
grep -q 'change: checks-on-main acme2-os' "$work/dry.out" || team_fail "dry run did not plan checks on main"
grep -q 'change: logs-history areas/marketing' "$work/dry.out" || team_fail "dry run did not plan area logs"
grep -q 'host=unset' "$FAKE_HOST_LOG" && team_fail "a host call ran before OS_HOST was set"
[ -z "$(git --git-dir "$work/git/acme2-os.git" ls-tree --name-only main .github/workflows 2>/dev/null)" ] \
  || team_fail "dry run changed main"

# Real run.
: > "$FAKE_HOST_LOG"
set +e
"$upgrade" --root "$co" --template "$root/template" --answers "$work/answers" > "$work/run.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/run.out" >&2; team_fail "upgrade exit $rc"; }
grep -q 'host=unset' "$FAKE_HOST_LOG" && team_fail "a host call ran before OS_HOST was set"

# B9: the slug (from the origin name here) is in the profile, and repos use it.
git -C "$co" show upgrade/v1:company-profile.md | grep -qx 'company_slug: acme2' || team_fail "company_slug not written"
git -C "$co" show upgrade/v1:company-profile.md | grep -qx 'host: github' || team_fail "host not written"
grep -q '^open-pr acme2-os ' "$FAKE_HOST_LOG" || team_fail "company pull request went to the wrong repo"

# B10: the check tools are on main before any pull request, then protect.
for repo in acme2-os acme2-marketing; do
  bare="$work/git/${repo}.git"
  for f in .github/workflows/checks.yml .github/scripts/checkout.sh .github/scripts/run-checks.sh \
    .github/scripts/tools/secret-scan.sh .github/review.conf .gitea/CODEOWNERS; do
    git --git-dir "$bare" cat-file -e "main:$f" 2>/dev/null || team_fail "$repo main lacks $f"
  done
  git --git-dir "$bare" show main:.github/review.conf | grep -qx 'vendor=xai' || team_fail "$repo review.conf vendor"
  # v1 owners: rules files only, so notes merge on green checks.
  git --git-dir "$bare" show main:.github/CODEOWNERS | grep -q '^\* ' && team_fail "$repo kept the v0 '*' owner line"
  git --git-dir "$bare" show main:.github/CODEOWNERS | grep -qx '/AGENTS.md @acme-admin' || team_fail "$repo v1 owners"
  # Only check files: no company content on main.
  changed=$(git --git-dir "$bare" diff --name-only main~1 main | grep -v '^\.github/' | grep -v '^\.gitea/' || true)
  [ -z "$changed" ] || team_fail "$repo check-tools commit touched $changed"
  order=$(grep -n -E "^(unprotect|protect|open-pr) ${repo} " "$FAKE_HOST_LOG" | cut -d' ' -f1 | tr -d '0-9:' | tr '\n' ' ')
  [ "$order" = "unprotect protect open-pr " ] || team_fail "$repo host order was: $order"
done
grep -qx 'checks-on-main: acme2-os' "$work/run.out" || team_fail "no checks-on-main line"
grep -qx 'protected: acme2-marketing' "$work/run.out" || team_fail "no protected line"
grep -q 'review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY' "$work/run.out" || team_fail "no review command"

# B7c: auto-merge failed, the run went on and says so in one line.
grep -q 'auto-merge is off on acme2-marketing: pull request 5 stays open' "$work/run.out" || team_fail "auto-merge line"
git --git-dir "$work/git/acme2-os.git" rev-parse --verify --quiet refs/heads/upgrade/v1 >/dev/null \
  || team_fail "company upgrade/v1 was not pushed after the auto-merge failure"

# B11: area logs move like the company logs.
area="$co/areas/marketing"
git -C "$area" cat-file -e "upgrade/scripts:memory/logs/2026-10-01-ada.md" || team_fail "area logs not on upgrade/scripts"
git -C "$area" show upgrade/scripts:.gitignore | grep -qx '/memory/logs/' && team_fail "area .gitignore still hides logs"
git -C "$area" rev-parse --verify --quiet "refs/tags/logs-archive-$(date +%Y-%m-%d)" >/dev/null || team_fail "area logs tag"
git --git-dir "$work/git/acme2-marketing.git" cat-file -e "upgrade/scripts:memory/logs/2026-10-01-ada.md" \
  || team_fail "area logs not pushed"
git -C "$co" cat-file -e "upgrade/v1:memory/logs/2026-10-01-ada.md" || team_fail "company logs not moved"

# A second run after start-over keeps main as it is: the tools are already there.
before=$(git --git-dir "$work/git/acme2-os.git" rev-parse main)
git -C "$co" checkout -q main
git -C "$co" branch -D upgrade/v1 -q
: > "$FAKE_HOST_LOG"
"$upgrade" --root "$co" --template "$root/template" --answers "$work/answers" > "$work/run2.out" 2>&1 || true
[ "$(git --git-dir "$work/git/acme2-os.git" rev-parse main)" = "$before" ] || team_fail "second run wrote main again"

# B9: no slug anywhere. Stop with a plain line before any push or host change.
co2="$work/noslug"
make_v0 "$co2" company
before=$(git --git-dir "$work/git/company.git" rev-parse main)
: > "$FAKE_HOST_LOG"
set +e
"$upgrade" --root "$co2" --template "$root/template" --answers "$work/answers" > "$work/noslug.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || { cat "$work/noslug.out" >&2; team_fail "no-slug exit was $rc"; }
grep -q 'the company slug is not known. Add slug=<slug> to the answers file' "$work/noslug.out" || team_fail "no-slug line"
[ "$(git --git-dir "$work/git/company.git" rev-parse main)" = "$before" ] || team_fail "no-slug run pushed"
grep -q -E '^(unprotect|protect|open-pr) ' "$FAKE_HOST_LOG" && team_fail "no-slug run changed the host"
git -C "$co2" show-ref --verify --quiet refs/heads/upgrade/v1 && team_fail "no-slug run made upgrade/v1"

# A Free GitHub org: a team upgrade stops with one line before any write.
co3="$work/free"
make_v0 "$co3" acme3-os
before=$(git --git-dir "$work/git/acme3-os.git" rev-parse main)
: > "$FAKE_HOST_LOG"
set +e
FAKE_PLAN=free "$upgrade" --root "$co3" --template "$root/template" --answers "$work/answers" > "$work/free.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 3 ] || { cat "$work/free.out" >&2; team_fail "free plan exit was $rc"; }
grep -qx 'This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again.' \
  "$work/free.out" || team_fail "free plan line"
[ "$(git --git-dir "$work/git/acme3-os.git" rev-parse main)" = "$before" ] || team_fail "free plan run pushed"
grep -q -E '^(unprotect|protect|open-pr) ' "$FAKE_HOST_LOG" && team_fail "free plan run changed the host"
git -C "$co3" show-ref --verify --quiet refs/heads/upgrade/v1 && team_fail "free plan run made upgrade/v1"
[ "$(git -C "$co3" rev-parse --abbrev-ref HEAD)" = "main" ] || team_fail "free plan run moved the company off main"

# A solo upgrade on the same Free org still works: no plan check, no protect, no check tools on main.
sed 's/^level=team$/level=solo/' "$work/answers" > "$work/answers-solo"
: > "$FAKE_HOST_LOG"
set +e
FAKE_PLAN=free "$upgrade" --root "$co3" --template "$root/template" --answers "$work/answers-solo" > "$work/solo.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/solo.out" >&2; team_fail "solo upgrade on a Free org exit was $rc"; }
grep -q -E '^(plan-check|unprotect|protect) ' "$FAKE_HOST_LOG" && team_fail "solo upgrade used team features"
grep -q 'review-command' "$work/solo.out" && team_fail "solo upgrade printed the review command"
[ "$(git --git-dir "$work/git/acme3-os.git" rev-parse main)" = "$before" ] || team_fail "solo upgrade wrote main"
git -C "$co3" show upgrade/v1:company-profile.md | grep -qx 'level: solo' || team_fail "solo upgrade level"

printf '%s\n' "PASS host-upgrade"
