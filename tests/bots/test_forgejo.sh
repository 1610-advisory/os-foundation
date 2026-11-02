#!/bin/bash
# Bot flow on the local Forgejo. Repos use a per-run prefix. Never wipe the volume.
# Cleanup deletes only this run's repos.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/lib.sh"
repo=$(bots_repo)
bots_need bash git jq curl openssl

url="${OSF_ACME_URL:-http://localhost:3300}"
if ! curl -fsS --max-time 5 "${url}/api/v1/version" >/dev/null 2>&1; then
  printf '%s\n' "BLOCKED: Forgejo is not ready at ${url}"
  exit 0
fi

if [ ! -f "$repo/template/skills/_host/host.sh" ]; then
  printf '%s\n' "BLOCKED: host.sh is not in this tree"
  exit 0
fi

real_home=${HOME}
admin_file="${real_home}/.cache/os-foundation/forgejo/tokens/acme-admin"
bot_file="${real_home}/.cache/os-foundation/forgejo/tokens/acme-bot"
if [ ! -f "$admin_file" ] || [ ! -f "$bot_file" ]; then
  printf '%s\n' "BLOCKED: Acme seat tokens are missing"
  exit 0
fi

tmp=$(mktemp -d)
slug="bots-t-$$"
repo_os="${slug}-os"
repo_area="${slug}-marketing"
repo_secret="${slug}-secret"
cleanup() {
  if [ -n "${company:-}" ] && [ -f "${company}/skills/_host/host.sh" ]; then
    export FORGEJO_TOKEN
    FORGEJO_TOKEN=$(tr -d '[:space:]' < "$admin_file")
    export OS_TEST_MODE=1
    export OS_PROFILE="${company}/company-profile.md"
    for name in "$repo_os" "$repo_area" "$repo_secret"; do
      bash "${company}/skills/_host/host.sh" delete-repo "$name" --yes-test-only \
        >"$tmp/del.out" 2>"$tmp/del.err" || true
    done
    FORGEJO_TOKEN=""
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export OS_JOBS_DIR="$tmp/jobs"
export OS_TEST_MODE=1
unset OS_SYNC_RECORD
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$OS_JOBS_DIR"
bots_git_env

company="$tmp/company"
mkdir -p "$company/notes" "$company/areas/marketing/notes" "$company/skills"
bots_profile "$company" forgejo "bots" "$slug"
bots_people "$company"
bots_copy_skills "$company"
printf '%s\n' "areas/" > "$company/.gitignore"
printf '%s\n' "Acme Co test company" > "$company/README.md"
mkdir -p "$company/.github/workflows" "$company/areas/marketing/.github/workflows"
cat > "$company/.github/workflows/checks.yml" << 'EOF'
name: checks
on:
  pull_request:
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
EOF
cp "$company/.github/workflows/checks.yml" "$company/areas/marketing/.github/workflows/checks.yml"
cp -R "$repo/template/skills/_host" "$company/skills/_host"
chmod 700 "$company/skills/_host/"*.sh
export OS_HOST_SH="$company/skills/_host/host.sh"

git -C "$company" init -q -b main
git -C "$company" add README.md .gitignore company-profile.md people skills .github
git -C "$company" commit -q -m "start"
git -C "$company/areas/marketing" init -q -b main
printf '%s\n' "Marketing" > "$company/areas/marketing/README.md"
git -C "$company/areas/marketing" add README.md .github
git -C "$company/areas/marketing" commit -q -m "start area"

export FORGEJO_TOKEN
FORGEJO_TOKEN=$(tr -d '[:space:]' < "$admin_file")
export OS_PROFILE="$company/company-profile.md"
host="$company/skills/_host/host.sh"
for name in "$repo_os" "$repo_area" "$repo_secret"; do
  bash "$host" delete-repo "$name" --yes-test-only >"$tmp/del.out" 2>"$tmp/del.err" || true
done
bash "$host" create-repo "$repo_os" --private --source "$company" --push >"$tmp/create-os.out"
bash "$host" create-repo "$repo_area" --private --source "$company/areas/marketing" --push >"$tmp/create-mkt.out"
bash "$host" create-repo "$repo_secret" --private >"$tmp/create-secret.out"

token_path="$tmp/secrets/bot-token"
mkdir -p "$tmp/secrets"
cp "$bot_file" "$token_path"
chmod 600 "$token_path"
engine="$repo/tests/bots/fixtures/engine.sh"
cat > "$tmp/answers" << EOF
kind=company
bot=helper
name=Acme helper
owner=ada
bot_user=acme-bot
repos=${repo_os},${repo_area}
scope.${repo_os}=company
scope.${repo_area}=marketing
email=acme.bot@acme.test
token_path=$token_path
box=yes
engine=$engine
inbox=none
EOF
bash "$company/skills/add-bot/add-bot.sh" --answers "$tmp/answers" --root "$company" >"$tmp/add.out"
grep -q "status: ready" "$tmp/add.out"
grep -q "jobs: installed" "$tmp/add.out"
[ -f "$OS_JOBS_DIR/installed" ]
if bots_secret_in_text "$token_path" "$tmp/add.out"; then
  bots_fail "add-bot printed the token"
fi
bots_pass "add-bot company bot on Forgejo"

# Bot can see granted repos and cannot see the other repo.
FORGEJO_TOKEN=$(tr -d '[:space:]' < "$token_path")
bash "$host" repo-access "$repo_os" >"$tmp/access-os.out"
grep -q '"access":"ok"' "$tmp/access-os.out" || bash "$host" repo-access "$repo_os" | grep -q 'ok'
set +e
bash "$host" repo-access "$repo_secret" >"$tmp/access-secret.out" 2>"$tmp/access-secret.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "outside repo access exit $code"
grep -q "no-access" "$tmp/access-secret.out"
ask="$tmp/ask"
cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
chmod 700 "$ask"
export OS_GIT_USER=acme-bot
export OS_GIT_TOKEN
OS_GIT_TOKEN=$(tr -d '[:space:]' < "$token_path")
set +e
GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
  git -c credential.helper= clone "${url}/acme/${repo_secret}.git" "$tmp/denied" >"$tmp/clone.out" 2>"$tmp/clone.err"
code=$?
set -e
[ "$code" -ne 0 ] || bots_fail "bot cloned a repo outside its grant"
if bots_secret_in_text "$token_path" "$tmp/clone.err"; then
  bots_fail "clone error printed the token"
fi
bots_pass "bot cannot clone outside its grant"

# Run as the bot. Two commits, then merge, then trailers on main.
cat > "$company/bots/helper/routines/daily.md" << 'EOF'
---
inbox: none
handoff: none
---

Write the daily note.
EOF
git -C "$company" add bots
git -C "$company" commit -q -m "bot page"
GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 \
  git -C "$company" -c credential.helper= push -q origin main
bash "$company/skills/add-bot/run.sh" helper daily --root "$company" >"$tmp/run.out"
run_id=$(sed -n 's/^run_id: //p' "$tmp/run.out")
[ -n "$run_id" ] || bots_fail "no run id"
GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 git -C "$company" -c credential.helper= fetch -q origin
GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 git -C "$company/areas/marketing" -c credential.helper= fetch -q origin
git -C "$company" log origin/main --format='%B' > "$tmp/company-bodies"
company_hits=$(awk -v id="$run_id" '
  /^Run-Id:/ { if ($0 ~ id) c++ }
  END { print c+0 }
' "$tmp/company-bodies")
[ "$company_hits" -ge 2 ] || bots_fail "company trailers $company_hits"
grep -q "Bot-Owner: ada" "$tmp/company-bodies"
git -C "$company/areas/marketing" log origin/main --format='%B' > "$tmp/area-bodies"
area_hits=$(awk -v id="$run_id" '
  /^Run-Id:/ { if ($0 ~ id) c++ }
  END { print c+0 }
' "$tmp/area-bodies")
[ "$area_hits" -ge 1 ] || bots_fail "area trailers $area_hits"
bots_pass "trailers present on main after merge"

# Token refresh across a real token life. No person step.
trace="$tmp/trace"
: > "$trace"
rm -f "$XDG_CONFIG_HOME/${slug}-os/bots/helper/token-cache"
printf 'protocol=http\nhost=localhost:3300\n\n' | \
  OS_BOT=helper OS_ROOT="$company" OS_BOT_TOKEN_TTL=1 OS_BOT_TOKEN_TRACE="$trace" \
  bash "$company/skills/add-bot/git-credential-os-bot" get >"$tmp/cred1.out"
sleep 2
printf 'protocol=http\nhost=localhost:3300\n\n' | \
  OS_BOT=helper OS_ROOT="$company" OS_BOT_TOKEN_TTL=1 OS_BOT_TOKEN_TRACE="$trace" \
  bash "$company/skills/add-bot/git-credential-os-bot" get >"$tmp/cred2.out"
[ "$(sed -n '1p' "$trace")" = "refresh" ] || bots_fail "first get did not refresh"
[ "$(sed -n '2p' "$trace")" = "refresh" ] || bots_fail "second get did not refresh after expiry"
if bots_secret_in_text "$token_path" "$trace"; then
  bots_fail "trace contains the token"
fi
bots_pass "token refresh with no person step"

# Undo the whole run. One revert commit per repo.
export OS_BOT=helper
bash "$company/skills/undo-run/undo-run.sh" "$run_id" --root "$company" >"$tmp/undo.out"
repo_name=""
while IFS= read -r line; do
  case "$line" in
    repo:*) repo_name=${line#repo: } ;;
    pr:*)
      number=${line#pr: }
      i=0
      merged=false
      while [ "$i" -lt 90 ]; do
        status=$(bash "$host" pr-status "$repo_name" "$number")
        merged=$(printf '%s' "$status" | jq -r '.merged')
        [ "$merged" = "true" ] && break
        i=$((i + 1))
        sleep 1
      done
      [ "$merged" = "true" ] || bots_fail "undo pull request ${repo_name}#${number} did not merge"
      ;;
  esac
done < "$tmp/undo.out"
GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 git -C "$company" -c credential.helper= fetch -q origin
GIT_ASKPASS=$ask GIT_TERMINAL_PROMPT=0 git -C "$company/areas/marketing" -c credential.helper= fetch -q origin
if git -C "$company" cat-file -e "origin/main:notes/run-note-1.md" 2>/dev/null; then
  bots_fail "company note still on main"
fi
if git -C "$company/areas/marketing" cat-file -e "origin/main:notes/run-note-3.md" 2>/dev/null; then
  bots_fail "area note still on main"
fi
reverts=$(git -C "$company" log origin/main --grep "^Revert run ${run_id}$" --format='%H' | wc -l | tr -d ' ')
[ "$reverts" = "1" ] || bots_fail "company revert count $reverts"
area_reverts=$(git -C "$company/areas/marketing" log origin/main --grep "^Revert run ${run_id}$" --format='%H' | wc -l | tr -d ' ')
[ "$area_reverts" = "1" ] || bots_fail "area revert count $area_reverts"
grep -q "repo: ${repo_os}" "$tmp/undo.out"
grep -q "repo: ${repo_area}" "$tmp/undo.out"
bots_pass "undo-run reverts the run in one commit per repo"

bots_pass "forgejo suite"
