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
  auto-merge)
    [ "${FAKE_AUTOMERGE:-fail}" = "ok" ] && { printf '%s\n' '{"ok":true}'; exit 0; }
    printf '%s\n' "Auto merge is not allowed for this repository" >&2; exit 3 ;;
  protect)
    [ "${FAKE_PROTECT:-ok}" = "ok" ] || { printf '%s\n' "host error" >&2; exit 3; }
    printf '%s\n' '{"ok":true}' ;;
  unprotect)
    # A host error part way, after the classic rule went (item 40).
    [ "${FAKE_UNPROTECT:-ok}" = "ok" ] || { printf '%s\n' "host error" >&2; exit 3; }
    printf '%s\n' '{"ok":true}' ;;
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
  # A line the company added after setup. The upgrade must keep it (item 26).
  printf '%s\n' '* @acme-admin' '/docs/legal/ @acme-counsel' > "$co/.github/CODEOWNERS"
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
  # Item 26: the company's own line stays, after the rules lines, so it still wins.
  if [ "$repo" = "acme2-os" ]; then
    owners_main=$(git --git-dir "$bare" show main:.github/CODEOWNERS)
    printf '%s\n' "$owners_main" | grep -qx '/docs/legal/ @acme-counsel' || team_fail "upgrade dropped a company CODEOWNERS line"
    [ "$(printf '%s\n' "$owners_main" | grep -n '^/docs/legal/' | cut -d: -f1)" -gt \
      "$(printf '%s\n' "$owners_main" | grep -n '^/AGENTS.md ' | cut -d: -f1)" ] || team_fail "company line is not after the rules lines"
  fi
  # Only check files: no company content on main.
  changed=$(git --git-dir "$bare" diff --name-only main~1 main | grep -v '^\.github/' | grep -v '^\.gitea/' || true)
  [ -z "$changed" ] || team_fail "$repo check-tools commit touched $changed"
  order=$(grep -n -E "^(unprotect|protect|open-pr) ${repo} " "$FAKE_HOST_LOG" | cut -d' ' -f1 | tr -d '0-9:' | tr '\n' ' ')
  [ "$order" = "unprotect protect open-pr " ] || team_fail "$repo host order was: $order"
done
grep -qx 'checks-on-main: acme2-os' "$work/run.out" || team_fail "no checks-on-main line"
grep -qx 'protected: acme2-marketing' "$work/run.out" || team_fail "no protected line"
grep -q 'review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY' "$work/run.out" || team_fail "no review command"

# Round 3 (39): on GitHub the upgrade pull requests merge by the admin's bypass click, so
# they never get auto-merge (that hides the bypass box). Never "upgrade: ok" with one open.
grep -q '^auto-merge ' "$FAKE_HOST_LOG" && team_fail "GitHub upgrade pull request got auto-merge"
grep -qx 'merge-by-hand: acme2-os 5' "$work/run.out" || team_fail "no merge-by-hand line for the company"
grep -qx 'merge-by-hand: acme2-marketing 5' "$work/run.out" || team_fail "no merge-by-hand line for the area"
grep -q 'pr-plan: [^ ]*marketing branch upgrade/scripts files .* merge-by-hand$' "$work/dry.out" \
  || team_fail "dry run did not plan merge-by-hand"
git --git-dir "$work/git/acme2-os.git" rev-parse --verify --quiet refs/heads/upgrade/v1 >/dev/null \
  || team_fail "company upgrade/v1 was not pushed"
grep -q '^upgrade: ok' "$work/run.out" && team_fail "upgrade: ok with pull requests left open"
grep -qx 'upgrade: open pull requests: acme2-marketing 5, acme2-os 5. Merge each one when its checks pass.' "$work/run.out" \
  || team_fail "last line does not name the open pull requests"

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

# Item 24: auto-merge is on, but on GitHub the admin's own rules pull request needs the bypass click.
co5="$work/automerge"
make_v0 "$co5" acme5-os
: > "$FAKE_HOST_LOG"
FAKE_AUTOMERGE=ok "$upgrade" --root "$co5" --template "$root/template" --answers "$work/answers" > "$work/am.out" 2>&1 \
  || { cat "$work/am.out" >&2; team_fail "auto-merge run failed"; }
grep -qx 'merge-by-hand: acme5-os 5' "$work/am.out" || team_fail "no merge-by-hand line for the company"
grep -qx 'merge-by-hand: acme5-marketing 5' "$work/am.out" || team_fail "no merge-by-hand line for the area"
grep -q 'Tick "Merge without waiting for requirements to be met (bypass rules)". Click "Bypass rules and merge".' "$work/am.out" \
  || team_fail "no bypass click path"
grep -q '^upgrade: ok' "$work/am.out" && team_fail "upgrade: ok while the admin must merge by hand"
grep -q '^auto-merge ' "$FAKE_HOST_LOG" && team_fail "GitHub upgrade pull request got auto-merge"
grep -q 'If it shows "Disable auto-merge", click that first.' "$work/am.out" || team_fail "no disable-auto-merge step"

# Forgejo: the pull requests get auto-merge. A refusal (B7c, item 23) is one line, the run
# goes on, and the last line names the open pull requests.
co6="$work/forgejo"
make_v0 "$co6" acme6-os
printf '%s\n' 'level=team' 'host=forgejo' 'host_url=http://localhost:3300' 'org=acme' 'review_vendor=xai' > "$work/fj.answers"
: > "$FAKE_HOST_LOG"
"$upgrade" --root "$co6" --template "$root/template" --answers "$work/fj.answers" > "$work/fj.out" 2>&1 \
  || { cat "$work/fj.out" >&2; team_fail "forgejo upgrade failed"; }
grep -q '^auto-merge acme6-os ' "$FAKE_HOST_LOG" || team_fail "forgejo company pull request got no auto-merge"
grep -q 'auto-merge is off on acme6-marketing: pull request 5 stays open' "$work/fj.out" || team_fail "forgejo area auto-merge line"
grep -q 'auto-merge is off on acme6-os: pull request 5 stays open until the admin merges it' "$work/fj.out" \
  || team_fail "forgejo company auto-merge line"
grep -q 'merge-by-hand' "$work/fj.out" && team_fail "forgejo printed merge-by-hand"
grep -q 'bypass rules' "$work/fj.out" && team_fail "forgejo printed the GitHub bypass steps"
grep -qx 'upgrade: open pull requests: acme6-marketing 5, acme6-os 5. Merge each one when its checks pass.' "$work/fj.out" \
  || team_fail "forgejo last line does not name the open pull requests"

# Item 25: a refused push to main never leaves main open. Protect runs again before the stop.
co4="$work/refused"
make_v0 "$co4" acme4-os
printf '%s\n' '#!/bin/sh' 'echo "refused by the test host" >&2' 'exit 1' > "$work/git/acme4-os.git/hooks/pre-receive"
chmod +x "$work/git/acme4-os.git/hooks/pre-receive"
: > "$FAKE_HOST_LOG"
set +e
"$upgrade" --root "$co4" --template "$root/template" --answers "$work/answers" > "$work/refused.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 3 ] || { cat "$work/refused.out" >&2; team_fail "refused push exit was $rc"; }
grep -q 'could not put the check tools on main of acme4-os. Protection on acme4-os is back on.' "$work/refused.out" \
  || team_fail "refused push line"
order=$(grep -E "^(unprotect|protect|open-pr) acme4-os " "$FAKE_HOST_LOG" | cut -d' ' -f1 | tr '\n' ' ')
[ "$order" = "unprotect protect " ] || team_fail "refused push host order was: $order"
# And if protect fails then, the line says main is open, in words the admin can act on.
: > "$FAKE_HOST_LOG"
set +e
FAKE_PROTECT=fail "$upgrade" --root "$co4" --template "$root/template" --answers "$work/answers" > "$work/refused2.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 3 ] || { cat "$work/refused2.out" >&2; team_fail "refused push, failed protect exit was $rc"; }
grep -qx 'PROTECTION IS OFF on acme4-os: run skills/_host/host.sh protect acme4-os --code-owners --approvals 0' "$work/refused2.out" \
  || team_fail "no PROTECTION IS OFF line"
[ "$(grep -c 'PROTECTION IS OFF' "$work/refused2.out")" -eq 1 ] || team_fail "PROTECTION IS OFF printed more than once"

# Round 3 (40): unprotect itself stops part way (set -e). The exit trap protects again.
: > "$FAKE_HOST_LOG"
set +e
FAKE_UNPROTECT=fail "$upgrade" --root "$co4" --template "$root/template" --answers "$work/answers" > "$work/unprot.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "a failed unprotect exited 0"
order=$(grep -E "^(unprotect|protect|open-pr) acme4-os " "$FAKE_HOST_LOG" | cut -d' ' -f1 | tr '\n' ' ')
[ "$order" = "unprotect protect " ] || team_fail "failed unprotect host order was: $order"
grep -qx 'upgrade stopped. Protection on acme4-os is back on.' "$work/unprot.out" || team_fail "no back-on line after a failed unprotect"
# And when protect fails too, the line says main is open.
: > "$FAKE_HOST_LOG"
set +e
FAKE_UNPROTECT=fail FAKE_PROTECT=fail "$upgrade" --root "$co4" --template "$root/template" --answers "$work/answers" > "$work/unprot2.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "failed unprotect and protect exited 0"
grep -qx 'PROTECTION IS OFF on acme4-os: run skills/_host/host.sh protect acme4-os --code-owners --approvals 0' "$work/unprot2.out" \
  || team_fail "no PROTECTION IS OFF line after a failed unprotect"

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

# Round 3 (31): a dry run on a Free org reports the plan as a finding and prints the full report.
: > "$FAKE_HOST_LOG"
set +e
FAKE_PLAN=free "$upgrade" --dry-run --root "$co3" --template "$root/template" --answers "$work/answers" > "$work/free-dry.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$work/free-dry.out" >&2; team_fail "free plan dry run exit was $rc"; }
grep -qx 'finding: plan: This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again.' \
  "$work/free-dry.out" || team_fail "dry run did not report the plan"
grep -q '^finding: plan blocks: check tools on main, protect, and the upgrade pull requests' "$work/free-dry.out" \
  || team_fail "dry run did not say what the plan blocks"
grep -q '^change: rules-merge AGENTS.md' "$work/free-dry.out" || team_fail "dry run stopped before the report"
grep -q '^change: checks-on-main acme3-os' "$work/free-dry.out" || team_fail "dry run left out the host steps"
[ "$(git --git-dir "$work/git/acme3-os.git" rev-parse main)" = "$before" ] || team_fail "free plan dry run pushed"

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
grep -q '^auto-merge ' "$FAKE_HOST_LOG" && team_fail "solo upgrade asked for auto-merge"
grep -q '^upgrade: open pull requests: acme3-marketing 5, acme3-os 5\.' "$work/solo.out" || team_fail "solo last line"

printf '%s\n' "PASS host-upgrade"
