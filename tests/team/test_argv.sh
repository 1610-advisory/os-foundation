#!/bin/bash
# A fake git and a fake host.sh write their argv. A token must not appear there.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sentinel="argv-sentinel-$(team_sha <(printf '%s' "$$-$RANDOM") | cut -c 1-12)"
printf '%s\n' "$sentinel" > "$work/token"
chmod 600 "$work/token"

mkdir -p "$work/bin"
cat > "$work/bin/git" << 'EOF'
#!/bin/bash
printf '%s\n' "$#" >> "$OS_ARGV_LOG"
i=1
for arg in "$@"; do
  printf 'arg %s\n' "$i" >> "$OS_ARGV_LOG"
  printf '%s\n' "$arg" >> "$OS_ARGV_LOG"
  i=$((i + 1))
done
printf '%s\n' "---" >> "$OS_ARGV_LOG"
exit 0
EOF
cat > "$work/bin/host.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$#" >> "$OS_ARGV_LOG"
i=1
for arg in "$@"; do
  printf 'arg %s\n' "$i" >> "$OS_ARGV_LOG"
  printf '%s\n' "$arg" >> "$OS_ARGV_LOG"
  i=$((i + 1))
done
printf '%s\n' "---" >> "$OS_ARGV_LOG"
case "$1" in
  get-token)
    cat "$OS_TOKEN_FILE"
    ;;
  whoami)
    printf '%s\n' '{"login":"ada"}'
    ;;
  secret-exists)
    printf '%s\n' '{"exists":false}'
    ;;
  *)
    printf '%s\n' '{"ok":true}'
    ;;
esac
exit 0
EOF
chmod 700 "$work/bin/git" "$work/bin/host.sh"

export OS_ARGV_LOG="$work/argv.log"
export OS_TOKEN_FILE="$work/token"
export OS_HOST_BIN="$work/bin/host.sh"
: > "$OS_ARGV_LOG"

# shellcheck disable=SC1091
. "$root/template/skills/add-teammate/lib.sh"
PATH="$work/bin:$PATH" os_with_git_token git push origin main

if grep -F -q -f "$work/token" "$OS_ARGV_LOG"; then
  team_fail "token appeared in argv"
fi
grep -q 'push' "$OS_ARGV_LOG" || team_fail "spy git did not run"

# team-on must not read a key file and must not pass a key to host.sh.
company="$work/company"
mkdir -p "$company/skills" "$company/areas/marketing" "$company/people"
cat > "$company/company-profile.md" << 'EOF'
---
type: company-profile
company_slug: team
level: solo
switches: []
os_version: v1.0.0
host: forgejo
host_url: "http://127.0.0.1:9"
org: acme
---

# Acme Co
EOF
git -C "$company" init -q
git -C "$company" checkout -q -b main
printf '%s\n' "/areas/" > "$company/.gitignore"
printf '%s\n' "/users/" >> "$company/.gitignore"
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company" commit -q -m "start"
git -C "$company/areas/marketing" init -q
git -C "$company/areas/marketing" checkout -q -b main
printf '%s\n' "# Marketing" > "$company/areas/marketing/AGENTS.md"
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company/areas/marketing" add -A
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$company/areas/marketing" commit -q -m "start"

answers="$work/answers"
cat > "$answers" << EOF
root=$company
host=forgejo
host_url=http://127.0.0.1:9
org=acme
sync_engine=true
runner=ubuntu-latest
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.email=ada$(printf '%s' '@')example.test
person.ada.role=admin
person.ada.areas=marketing
EOF
: > "$OS_ARGV_LOG"
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
mkdir -p "$HOME"
export OS_HOST_SH="$work/bin/host.sh"
set +e
out=$(PATH="$work/bin:$PATH" "$root/template/skills/add-teammate/team-on.sh" --answers "$answers" 2>"$work/err")
rc=$?
set -e
printf '%s\n' "$out" | grep -q 'review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY' || team_fail "missing review command"
printf '%s\n' "$out" | grep -q 'no review key: every pull request fails the model review until you add one' || team_fail "missing no-key sentence"
if grep -F -q -f "$work/token" "$OS_ARGV_LOG"; then
  team_fail "token appeared in team-on argv"
fi
if grep -F -q 'set-secret' "$OS_ARGV_LOG"; then
  team_fail "team-on must not run set-secret"
fi
# The answers file must not be asked to hold a key. The script must not read one.
grep -q 'review_key' "$answers" && team_fail "answers file must not hold a review key"
[ "$rc" -eq 0 ] || {
  printf '%s\n' "$out" >&2
  cat "$work/err" >&2
  team_fail "team-on spy run failed ($rc)"
}

printf '%s\n' "PASS argv"
