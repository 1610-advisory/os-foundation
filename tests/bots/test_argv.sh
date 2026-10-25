#!/bin/bash
# No token, key, or JWT in a child argument list.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/lib.sh"
bots_need bash git jq

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export OS_JOBS_DIR="$tmp/jobs"
export OS_SYNC_RECORD=1
export OS_SYNC_LOG="$tmp/sync.log"
export OS_HOST_LOG="$tmp/host.log"
export OS_TOKEN_COUNT="$tmp/token-count"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$OS_JOBS_DIR" "$tmp/bin"
bots_git_env

secret="$tmp/secret-value"
printf '%s\n' "argv-secret-marker" > "$secret"
chmod 600 "$secret"
export OS_ARGV_LOG="$tmp/argv.log"
export OS_ARGV_HITS="$tmp/argv.hits"
export OS_ARGV_SECRETS="$secret"
: > "$OS_ARGV_LOG"
: > "$OS_ARGV_HITS"

# The spy must notice a secret in argv. This is the control.
bash "$here/fixtures/argv-spy.sh" "argv-secret-marker" >/dev/null
[ -s "$OS_ARGV_HITS" ] || bots_fail "argv spy did not flag a secret"
: > "$OS_ARGV_LOG"
: > "$OS_ARGV_HITS"

real_git=$(PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" command -v git)
cp "$here/fixtures/argv-spy.sh" "$tmp/bin/curl"
cp "$here/fixtures/argv-spy.sh" "$tmp/bin/gh"
cat > "$tmp/bin/git" << EOF
#!/bin/bash
set -euo pipefail
export OS_ARGV_EXEC=1
export OS_ARGV_REAL="$real_git"
exec "$here/fixtures/argv-spy.sh" "\$@"
EOF
chmod 700 "$tmp/bin/curl" "$tmp/bin/gh" "$tmp/bin/git"
export PATH="$tmp/bin:$PATH"

root="$tmp/company"
mkdir -p "$root/notes"
bots_profile "$root" forgejo "bots"
bots_people "$root"
bots_copy_skills "$root"
bots_stub_host "$root"
token="$tmp/bot-token"
printf '%s\n' "argv-secret-marker" > "$token"
chmod 600 "$token"

# The stub host prints a different token so the helper has a secret to mishandle.
# The file secret is also in the answers path only as a path, not as a value.
cat > "$tmp/answers" << EOF
kind=company
bot=helper
name=Acme helper
owner=ada
bot_user=acme-bot
repos=acme-os
scope.acme-os=company
email=acme.bot@acme.test
token_path=$token
box=yes
engine=$here/fixtures/engine.sh
EOF
bash "$root/skills/add-bot/add-bot.sh" --answers "$tmp/answers" --root "$root" >"$tmp/add.out" 2>"$tmp/add.err"

git -C "$root" init -q -b main
git -C "$root" add company-profile.md people bots
git -C "$root" commit -q -m "start"
cat > "$root/bots/helper/routines/daily.md" << 'EOF'
---
inbox: none
handoff: none
---

Write a note.
EOF
cat > "$tmp/engine.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
cat >/dev/null
mkdir -p "$OS_ROOT/notes"
printf 'n\n' > "$OS_ROOT/notes/n.md"
git -C "$OS_ROOT" add notes/n.md
git -C "$OS_ROOT" commit -q -m "note"
EOF
chmod 700 "$tmp/engine.sh"
python3 - "$root/bots/helper/BOT.md" "$tmp/engine.sh" << 'PY'
import pathlib, sys
path, engine = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text()
lines = []
done = False
for line in text.splitlines():
    if line.startswith("engine:"):
        lines.append('engine: "' + engine.replace('"', '\\"') + '"')
        done = True
    else:
        lines.append(line)
if not done:
    lines.insert(1, 'engine: "' + engine.replace('"', '\\"') + '"')
pathlib.Path(path).write_text("\n".join(lines) + "\n")
PY
git -C "$root" add bots/helper/BOT.md
git -C "$root" commit -q -m "set engine"
bash "$root/skills/add-bot/run.sh" helper daily --root "$root" >"$tmp/run.out"

printf 'protocol=https\nhost=example.test\n\n' | \
  OS_BOT=helper OS_ROOT="$root" bash "$root/skills/add-bot/git-credential-os-bot" get \
  >"$tmp/cred.out"

if [ -s "$OS_ARGV_HITS" ]; then
  bots_fail "secret appeared in a child argv"
fi
if [ -s "$OS_ARGV_LOG" ] && grep -q "argv-secret-marker" "$OS_ARGV_LOG"; then
  bots_fail "secret marker appeared in argv log"
fi
if grep -q "unit-token-" "$OS_ARGV_LOG"; then
  bots_fail "token appeared in argv log"
fi
bots_pass "no secret in child argv"
