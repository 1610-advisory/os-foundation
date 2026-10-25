#!/bin/bash
# Unit tests for add-bot, run, undo-run, and the credential helper. No host.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/lib.sh"
bots_need bash git jq openssl

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export OS_JOBS_DIR="$tmp/jobs"
export OS_SYNC_RECORD=1
export OS_SYNC_LOG="$tmp/sync.log"
export OS_HOST_LOG="$tmp/host.log"
export OS_TOKEN_COUNT="$tmp/token-count"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$OS_JOBS_DIR"
bots_git_env

root="$tmp/company"
mkdir -p "$root/notes" "$root/areas/marketing"
bots_profile "$root" forgejo "bots"
bots_people "$root"
bots_copy_skills "$root"
bots_stub_host "$root"
token="$tmp/bot-token"
printf '%s\n' "unit-secret-value" > "$token"
chmod 600 "$token"

add="$root/skills/add-bot/add-bot.sh"
run="$root/skills/add-bot/run.sh"
helper="$root/skills/add-bot/git-credential-os-bot"
undo="$root/skills/undo-run/undo-run.sh"

# Switch off.
off="$tmp/off"
mkdir -p "$off"
bots_profile "$off" forgejo ""
bots_people "$off"
bots_copy_skills "$off"
: > "$tmp/none"
set +e
bash "$off/skills/add-bot/add-bot.sh" --answers "$tmp/none" --root "$off" >"$tmp/off.out" 2>"$tmp/off.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "add-bot switch off exit $code"
grep -q "bots switch is off" "$tmp/off.err"
set +e
bash "$off/skills/add-bot/run.sh" helper daily --root "$off" >"$tmp/off-run.out" 2>"$tmp/off-run.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "run switch off exit $code"
grep -q "bots switch is off" "$tmp/off-run.err"
bots_pass "run refuses when bots is off"

# Company bot grants two repos and installs jobs.
cat > "$tmp/answers" << EOF
kind=company
bot=helper
name=Acme helper
owner=ada
bot_user=acme-bot
repos=acme-os,acme-marketing
scope.acme-os=company
scope.acme-marketing=marketing
email=acme.bot@acme.test
token_path=$token
box=yes
engine=$here/fixtures/engine.sh
inbox=none
EOF
: > "$OS_HOST_LOG"
bash "$add" --answers "$tmp/answers" --root "$root" >"$tmp/add.out" 2>"$tmp/add.err"
grep -q "status: ready" "$tmp/add.out"
grep -q "jobs: installed" "$tmp/add.out"
grep -q "propose: skills/sync/sync.sh propose add-bot-helper bots/helper/BOT.md bots/helper/routines/\*.md" "$tmp/add.out"
grep -c "grant " "$OS_HOST_LOG" | grep -q "^2$"
[ -f "$OS_JOBS_DIR/installed" ]
[ -f "$root/bots/helper/BOT.md" ]
[ -d "$root/bots/helper/skills" ]
[ -d "$root/bots/helper/logs" ]
grep -q "shared_inbox: none" "$root/bots/helper/BOT.md"
grep -q "owner: ada" "$root/bots/helper/BOT.md"
if bots_secret_in_text "$token" "$tmp/add.out" || bots_secret_in_text "$token" "$tmp/add.err"; then
  bots_fail "token value leaked from add-bot"
fi
bots_pass "add-bot grants two repos"

# Director cannot own the company bot.
cat > "$tmp/bad-owner" << EOF
kind=company
bot=other
owner=dana
bot_user=acme-bot
repos=acme-os
scope.acme-os=company
email=acme.bot@acme.test
token_path=$token
box=no
EOF
: > "$OS_HOST_LOG"
set +e
bash "$add" --answers "$tmp/bad-owner" --root "$root" >"$tmp/bad.out" 2>"$tmp/bad.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "director company bot exit $code"
[ ! -s "$OS_HOST_LOG" ]
bots_pass "grant does not exceed the owner"

# Area bot cannot take another area.
cat > "$tmp/bad-area" << EOF
kind=area
bot=area-bot
owner=dana
area=marketing
bot_user=acme-bot
repos=acme-finance
scope.acme-finance=finance
email=acme.bot@acme.test
token_path=$token
box=no
EOF
set +e
bash "$add" --answers "$tmp/bad-area" --root "$root" >"$tmp/area.out" 2>"$tmp/area.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "cross-area grant exit $code"
bots_pass "area bot stays in its area"

# Secret file inside the repo is refused.
inside="$root/inside-token"
printf '%s\n' "unit-secret-value" > "$inside"
chmod 600 "$inside"
cat > "$tmp/inside" << EOF
kind=company
bot=inside
owner=ada
repos=acme-os
scope.acme-os=company
email=acme.bot@acme.test
token_path=$inside
box=no
EOF
set +e
bash "$add" --answers "$tmp/inside" --root "$root" >"$tmp/inside.out" 2>"$tmp/inside.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "inside key exit $code"
grep -q "outside the repo" "$tmp/inside.err"
bots_pass "secret file must stay outside the repo"

# GitHub manifest and one-click URL. No App call.
ghroot="$tmp/gh"
mkdir -p "$ghroot"
bots_profile "$ghroot" github "bots"
bots_people "$ghroot"
bots_copy_skills "$ghroot"
cat > "$tmp/gh-answers" << 'EOF'
kind=company
bot=helper
name=Acme helper
owner=ada
repos=acme-os,acme-marketing
scope.acme-os=company
scope.acme-marketing=marketing
email=acme.bot@acme.test
box=no
EOF
bash "$ghroot/skills/add-bot/add-bot.sh" --answers "$tmp/gh-answers" --root "$ghroot" >"$tmp/gh.out"
grep -q "status: waiting-for-app" "$tmp/gh.out"
grep -q "contents=write" "$tmp/gh.out"
grep -q "pull_requests=write" "$tmp/gh.out"
grep -q "metadata=read" "$tmp/gh.out"
grep -q "public=false" "$tmp/gh.out"
grep -q "webhook_active=false" "$tmp/gh.out"
if grep -q "organization_administration" "$tmp/gh.out"; then
  bots_fail "create URL has org admin"
fi
manifest=$(sed -n 's/^manifest: //p' "$tmp/gh.out")
jq -e '.default_permissions.contents == "write" and .default_permissions.pull_requests == "write" and .default_permissions.metadata == "read" and .public == false' "$manifest" >/dev/null
if jq -e '.default_permissions | keys[] | select(. == "administration" or . == "members" or . == "organization_administration")' "$manifest" >/dev/null; then
  bots_fail "manifest has an admin permission"
fi
bots_pass "github manifest and create URL"

# Routine with two commits carries trailers. Push is recorded, not sent.
git -C "$root" init -q -b main
git -C "$root" add -A
git -C "$root" commit -q -m "start"
cat > "$root/bots/helper/routines/daily.md" << 'EOF'
---
inbox: none
handoff: none
---

Write the daily note.
EOF
cat > "$tmp/two.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
cat >/dev/null
mkdir -p "$OS_ROOT/notes"
printf 'one\n' > "$OS_ROOT/notes/one.md"
git -C "$OS_ROOT" add notes/one.md
git -C "$OS_ROOT" commit -q -m "one"
printf 'two\n' > "$OS_ROOT/notes/two.md"
git -C "$OS_ROOT" add notes/two.md
git -C "$OS_ROOT" commit -q -m "two"
EOF
chmod 700 "$tmp/two.sh"
# Point the bot at this engine.
python3 - "$root/bots/helper/BOT.md" "$tmp/two.sh" << 'PY'
import pathlib, sys
path, engine = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text()
text = text.replace("engine: ", "engine_unused: ", 1)
# The page may omit engine. Insert it before the closing marker.
lines = text.splitlines()
out = []
inserted = False
for line in lines:
    if line == "---" and not inserted and out:
        out.append('engine: "' + engine.replace("\\", "\\\\").replace('"', '\\"') + '"')
        inserted = True
    out.append(line)
pathlib.Path(path).write_text("\n".join(out) + "\n")
PY
git -C "$root" add -A
git -C "$root" commit -q -m "set engine"
bash "$run" helper daily --root "$root" >"$tmp/run.out"
run_id=$(sed -n 's/^run_id: //p' "$tmp/run.out")
[ -n "$run_id" ]
bodies=$(git -C "$root" log "sync/helper" --format='%B')
printf '%s\n' "$bodies" | grep -q "Run-Id: ${run_id}"
printf '%s\n' "$bodies" | grep -q "Bot-Owner: ada"
count=$(git -C "$root" log "sync/helper" --grep "Run-Id: ${run_id}" --format='%H' | wc -l | tr -d ' ')
[ "$count" = "2" ] || bots_fail "expected 2 trailer commits, got $count"
grep -q "^push$" "$OS_SYNC_LOG"
bots_pass "routine commits carry trailers"

# Inbox refusal and allow.
cat > "$root/bots/helper/routines/mail.md" << 'EOF'
---
inbox: finance
handoff: none
---

Read the shared inbox.
EOF
marker="$tmp/engine-ran"
cat > "$tmp/mark.sh" << EOF
#!/bin/bash
set -euo pipefail
cat >/dev/null
printf 'ran\n' > "$marker"
EOF
chmod 700 "$tmp/mark.sh"
python3 - "$root/bots/helper/BOT.md" "$tmp/mark.sh" << 'PY'
import pathlib, sys
path, engine = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text()
lines = []
for line in text.splitlines():
    if line.startswith("engine:"):
        lines.append('engine: "' + engine.replace('"', '\\"') + '"')
    else:
        lines.append(line)
pathlib.Path(path).write_text("\n".join(lines) + "\n")
PY
git -C "$root" add bots
git -C "$root" commit -q -m "mark engine"
git -C "$root" checkout -q main
git -C "$root" merge -q --ff-only sync/helper
rm -f "$marker"
set +e
bash "$run" helper mail --root "$root" >"$tmp/mail.out" 2>"$tmp/mail.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "inbox refuse exit $code"
[ ! -f "$marker" ]
grep -q "refused inbox finance" "$root/bots/helper/logs/"*.md
bots_pass "inbox outside shared_inbox is refused"

python3 - "$root/bots/helper/BOT.md" << 'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace("shared_inbox: none", "shared_inbox:\n  - finance", 1)
path.write_text(text)
PY
git -C "$root" add bots
git -C "$root" commit -q -m "allow finance inbox"
git -C "$root" checkout -q main
git -C "$root" merge -q --ff-only sync/helper || git -C "$root" merge -q sync/helper
bash "$run" helper mail --root "$root" >"$tmp/mail2.out"
[ -f "$marker" ]
grep -q "read inbox finance" "$root/bots/helper/logs/"*.md
if grep -q "Read the shared inbox" "$root/bots/helper/logs/"*.md; then
  bots_fail "inbox log includes message text"
fi
bots_pass "shared inbox read is logged"

# Hand-off off, then on with no cloud caller.
cat > "$root/bots/helper/routines/hand.md" << 'EOF'
---
inbox: none
handoff: cursor
---

Hand the task off.
EOF
set +e
bash "$run" helper hand --root "$root" >"$tmp/hand.out" 2>"$tmp/hand.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "handoff off exit $code"
grep -q "cloud-handoff switch is off" "$tmp/hand.err"
bots_pass "handoff refused when the switch is off"

bots_profile "$root" forgejo "bots, cloud-handoff"
set +e
bash "$run" helper hand --root "$root" >"$tmp/hand2.out" 2>"$tmp/hand2.err"
code=$?
set -e
[ "$code" -eq 3 ] || bots_fail "handoff on exit $code"
grep -q "never merge" "$tmp/hand2.err"
bots_pass "handoff has no cloud caller in v1"
bots_profile "$root" forgejo "bots"

# Credential cache and refresh. No person step. Faked clock.
trace="$tmp/trace"
: > "$trace"
printf '0\n' > "$OS_TOKEN_COUNT"
feed() {
  printf 'protocol=http\nhost=localhost:3300\n\n'
}
feed | OS_NOW=1000000 OS_BOT_TOKEN_TTL=60 OS_BOT=helper OS_ROOT="$root" \
  OS_BOT_TOKEN_TRACE="$trace" bash "$helper" get >"$tmp/cred1.out"
feed | OS_NOW=1000030 OS_BOT_TOKEN_TTL=60 OS_BOT=helper OS_ROOT="$root" \
  OS_BOT_TOKEN_TRACE="$trace" bash "$helper" get >"$tmp/cred2.out"
feed | OS_NOW=1000060 OS_BOT_TOKEN_TTL=60 OS_BOT=helper OS_ROOT="$root" \
  OS_BOT_TOKEN_TRACE="$trace" bash "$helper" get >"$tmp/cred3.out"
[ "$(tr -d '[:space:]' < "$OS_TOKEN_COUNT")" = "2" ] || bots_fail "token refresh count"
[ "$(sed -n '1p;3p' "$trace" | tr '\n' ' ')" = "refresh refresh " ] || true
line1=$(sed -n '1p' "$trace")
line2=$(sed -n '2p' "$trace")
line3=$(sed -n '3p' "$trace")
[ "$line1" = "refresh" ] && [ "$line2" = "cache" ] && [ "$line3" = "refresh" ] || bots_fail "trace $line1 $line2 $line3"
# One-hour token refreshes when under 5 minutes remain.
: > "$trace"
rm -f "$XDG_CONFIG_HOME/acme-os/bots/helper/token-cache"
feed | OS_NOW=2000000 OS_BOT_TOKEN_TTL=3600 OS_BOT=helper OS_ROOT="$root" \
  OS_BOT_TOKEN_TRACE="$trace" bash "$helper" get >/dev/null
feed | OS_NOW=2003300 OS_BOT_TOKEN_TTL=3600 OS_BOT=helper OS_ROOT="$root" \
  OS_BOT_TOKEN_TRACE="$trace" bash "$helper" get >/dev/null
feed | OS_NOW=2003301 OS_BOT_TOKEN_TTL=3600 OS_BOT=helper OS_ROOT="$root" \
  OS_BOT_TOKEN_TRACE="$trace" bash "$helper" get >/dev/null
[ "$(sed -n '2p' "$trace")" = "cache" ] || bots_fail "hour token should stay cached at 5 minutes"
[ "$(sed -n '3p' "$trace")" = "refresh" ] || bots_fail "hour token should refresh under 5 minutes"
if bots_secret_in_text "$XDG_CONFIG_HOME/acme-os/bots/helper/token-cache" "$trace"; then
  bots_fail "trace contains the token"
fi
bots_pass "token refresh uses the faked clock"

# Local undo: two commits on main, one revert commit, no reused Run-Id.
bare="$tmp/bare.git"
git init -q --bare "$bare"
git -C "$root" checkout -q main
git -C "$root" remote remove origin 2>/dev/null || true
git -C "$root" remote add origin "$bare"
mkdir -p "$root/notes"
printf 'keep\n' > "$root/notes/keep.md"
git -C "$root" add notes/keep.md
git -C "$root" commit -q -m "keep"
printf 'a\n' > "$root/notes/a.md"
git -C "$root" add notes/a.md
git -C "$root" commit -q -m "add a

Run-Id: local-run
Bot-Owner: ada"
printf 'b\n' > "$root/notes/b.md"
git -C "$root" add notes/b.md
git -C "$root" commit -q -m "add b

Run-Id: local-run
Bot-Owner: ada"
git -C "$root" push -q origin main
bash "$undo" local-run --root "$root" >"$tmp/undo.out"
ahead=$(git -C "$root" rev-list --count main..undo/local-run | tr -d ' ')
[ "$ahead" = "1" ] || bots_fail "undo branch has $ahead commits"
if git -C "$root" log -1 --format='%B' undo/local-run | grep -q '^Run-Id:'; then
  bots_fail "revert commit reused Run-Id"
fi
git -C "$root" merge -q --no-ff undo/local-run -m "merge undo"
[ ! -f "$root/notes/a.md" ]
[ ! -f "$root/notes/b.md" ]
[ -f "$root/notes/keep.md" ]
grep -q "open-pr" "$OS_HOST_LOG"
bots_pass "undo-run makes one revert commit"

# A conflict in one repo does not stop the other repo.
conflict_root="$tmp/conflict"
mkdir -p "$conflict_root/areas/marketing" "$conflict_root/people"
bots_profile "$conflict_root" forgejo "bots"
bots_people "$conflict_root"
bots_copy_skills "$conflict_root"
bots_stub_host "$conflict_root"
mkdir -p "$conflict_root/bots/helper"
cat > "$conflict_root/bots/helper/BOT.md" << 'EOF'
---
type: bot
bot: helper
owner: ada
email: "acme.bot@acme.test"
repos:
  - acme-os
---
Helper.
EOF
git -C "$conflict_root" init -q -b main
printf 'base\n' > "$conflict_root/README.md"
git -C "$conflict_root" add README.md
git -C "$conflict_root" commit -q -m "base"
printf 'bot line\n' > "$conflict_root/notes.md"
git -C "$conflict_root" add notes.md
git -C "$conflict_root" commit -q -m "bot edit

Run-Id: conflict-run
Bot-Owner: ada"
printf 'later line\n' > "$conflict_root/notes.md"
git -C "$conflict_root" add notes.md
git -C "$conflict_root" commit -q -m "later edit"
git -C "$conflict_root/areas/marketing" init -q -b main
printf 'area\n' > "$conflict_root/areas/marketing/README.md"
git -C "$conflict_root/areas/marketing" add README.md
git -C "$conflict_root/areas/marketing" commit -q -m "area base"
printf 'area bot\n' > "$conflict_root/areas/marketing/note.md"
git -C "$conflict_root/areas/marketing" add note.md
git -C "$conflict_root/areas/marketing" commit -q -m "area bot

Run-Id: conflict-run
Bot-Owner: ada"
bare_a="$tmp/conflict-a.git"
bare_b="$tmp/conflict-b.git"
git init -q --bare "$bare_a"
git init -q --bare "$bare_b"
git -C "$conflict_root" remote add origin "$bare_a"
git -C "$conflict_root" push -q origin main
git -C "$conflict_root/areas/marketing" remote add origin "$bare_b"
git -C "$conflict_root/areas/marketing" push -q origin main
set +e
bash "$conflict_root/skills/undo-run/undo-run.sh" conflict-run --root "$conflict_root" >"$tmp/conflict.out" 2>"$tmp/conflict.err"
code=$?
set -e
[ "$code" -eq 3 ] || bots_fail "conflict exit $code"
grep -q "conflict:" "$tmp/conflict.out"
grep -q "repo: conflict-b" "$tmp/conflict.out" || grep -q "pr:" "$tmp/conflict.out"
if git -C "$conflict_root" diff --quiet && git -C "$conflict_root" diff --cached --quiet; then
  :
else
  bots_fail "conflict repo was left dirty"
fi
bots_pass "conflict in one repo does not stop the others"

# P1: a scope line cannot relabel the company repo as an area.
cat > "$tmp/bad-scope" << EOF
kind=company
bot=relabel
name=Relabel
owner=ada
email=acme.bot@acme.test
repos=acme-os
scope.acme-os=marketing
token_path=$token
box=no
EOF
: > "$OS_HOST_LOG"
set +e
bash "$add" --answers "$tmp/bad-scope" --root "$root" >"$tmp/scope.out" 2>"$tmp/scope.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "bad scope exit $code"
grep -q "does not match the repo name" "$tmp/scope.err"
if grep -q "^grant " "$OS_HOST_LOG"; then
  bots_fail "bad scope granted a repo"
fi
bots_pass "scope comes from the repo name"

# P1: helper answers only for this host, and only when bots is on.
helper_out="$tmp/helper-miss.out"
printf 'protocol=https\nhost=evil.example\n\n' | \
  OS_BOT=helper OS_ROOT="$root" bash "$helper" get >"$helper_out"
[ ! -s "$helper_out" ] || bots_fail "helper answered a foreign host"
printf 'protocol=http\nhost=localhost:3300\npath=acme/acme-secret.git\n\n' | \
  OS_BOT=helper OS_ROOT="$root" bash "$helper" get >"$helper_out"
[ ! -s "$helper_out" ] || bots_fail "helper answered a path outside the grant"
off_cfg="$XDG_CONFIG_HOME/acme-os/bots/helper/token-cache"
before=$(wc -c < "$off_cfg" | tr -d ' ')
printf 'protocol=http\nhost=localhost:3300\n\n' | \
  OS_BOT=helper OS_ROOT="$off" bash "$off/skills/add-bot/git-credential-os-bot" get >"$helper_out"
[ ! -s "$helper_out" ] || bots_fail "helper answered with bots off"
after=$(wc -c < "$off_cfg" | tr -d ' ')
[ "$before" = "$after" ] || bots_fail "helper wrote a cache with bots off"
printf 'protocol=http\nhost=localhost:3300\n\n' | \
  OS_ROOT="$root" bash "$helper" get >"$helper_out"
[ ! -s "$helper_out" ] || bots_fail "helper guessed a bot"
bots_pass "credential helper answers only for this host"

# P1: undo does not touch a dirty live checkout.
printf 'dirty\n' > "$root/notes/dirty.md"
dirty_before=$(cat "$root/notes/dirty.md")
set +e
bash "$undo" local-run --root "$root" >"$tmp/dirty-undo.out" 2>"$tmp/dirty-undo.err"
set -e
[ "$(cat "$root/notes/dirty.md")" = "$dirty_before" ] || bots_fail "undo changed the live checkout"
git -C "$root" status --porcelain | grep -q "notes/dirty.md" || bots_fail "dirty file was committed or lost"
bots_pass "undo uses a worktree and leaves the live checkout"

# P2: a copied Run-Id on another author is not reverted.
GIT_AUTHOR_EMAIL="other@acme.test" GIT_COMMITTER_EMAIL="other@acme.test" \
  git -C "$root" commit -q --allow-empty -m "copied

Run-Id: copied-run
Bot-Owner: ada"
git -C "$root" push -q origin main
set +e
bash "$undo" copied-run --root "$root" >"$tmp/copied.out" 2>"$tmp/copied.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "copied trailer exit $code"
grep -q "no commits" "$tmp/copied.err"
bots_pass "copied Run-Id is not reverted"

# P2: a dirty tree is refused. A push to main is refused.
printf 'more\n' >> "$root/README.md"
set +e
bash "$run" helper daily --root "$root" >"$tmp/dirty-run.out" 2>"$tmp/dirty-run.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "dirty run exit $code"
grep -q "dirty" "$tmp/dirty-run.err"
rm -f "$root/notes/dirty.md"
export OS_REAL_GIT OS_BOT_LOG="$tmp/guard.log"
OS_REAL_GIT=$(PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" command -v git)
set +e
bash "$root/skills/add-bot/git-guard.sh" -C "$root" push origin main >"$tmp/guard.out" 2>"$tmp/guard.err"
code=$?
set -e
[ "$code" -eq 1 ] || bots_fail "push main exit $code"
grep -q "refused:" "$tmp/guard.err"
grep -q "refused:" "$OS_BOT_LOG"
set +e
bash "$root/skills/add-bot/git-guard.sh" -C "$root" push origin "HEAD:refs/heads/main" >"$tmp/guard2.out" 2>"$tmp/guard2.err"
code=$?
set -e
[ "$code" -eq 1 ] || bots_fail "HEAD push exit $code"
rm -f "$root/README.md"
printf 'loose\n' > "$root/notes/untracked.md"
set +e
bash "$run" helper daily --root "$root" >"$tmp/untracked.out" 2>"$tmp/untracked.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "untracked dirty exit $code"
grep -q "dirty" "$tmp/untracked.err"
rm -f "$root/notes/untracked.md"
bots_pass "dirty tree and push to main are refused"

# A: allowlist. Wildcards, --all, --mirror, --tags, and --delete are refused.
# An allowed sync/<bot> refspec reaches git.
fake="$tmp/fake-git"
cat > "$fake" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${OS_FAKE_GIT_LOG:?}"
for a in "$@"; do
  if [ "$a" = "rev-parse" ]; then
    printf '%s\n' "${OS_FAKE_BRANCH:-main}"
    exit 0
  fi
done
exit 0
EOF
chmod 700 "$fake"
export OS_FAKE_GIT_LOG="$tmp/fake-git.log" OS_BOT=helper
: > "$OS_FAKE_GIT_LOG"
for bad in --all --mirror --tags --delete; do
  set +e
  OS_REAL_GIT="$fake" bash "$root/skills/add-bot/git-guard.sh" push origin "$bad" >"$tmp/bad.out" 2>"$tmp/bad.err"
  code=$?
  set -e
  [ "$code" -eq 1 ] || bots_fail "push $bad exit $code"
done
set +e
OS_REAL_GIT="$fake" bash "$root/skills/add-bot/git-guard.sh" push origin 'refs/heads/*:refs/heads/*' >"$tmp/wild.out" 2>"$tmp/wild.err"
code=$?
set -e
[ "$code" -eq 1 ] || bots_fail "wildcard push exit $code"
set +e
OS_FAKE_BRANCH=main OS_REAL_GIT="$fake" bash "$root/skills/add-bot/git-guard.sh" --git-dir "$root/.git" push >"$tmp/gitdir.out" 2>"$tmp/gitdir.err"
code=$?
set -e
[ "$code" -eq 1 ] || bots_fail "git-dir push exit $code"
grep -q "refused:" "$tmp/gitdir.err"
: > "$OS_FAKE_GIT_LOG"
OS_FAKE_BRANCH=sync/helper OS_REAL_GIT="$fake" bash "$root/skills/add-bot/git-guard.sh" push origin refs/heads/sync/helper >"$tmp/allow.out" 2>"$tmp/allow.err"
grep -q "push origin refs/heads/sync/helper" "$OS_FAKE_GIT_LOG" || bots_fail "allowed push did not reach git"
bots_pass "push allowlist"

# D: an existing undo branch is refused and not reset.
tip=$(git -C "$root" rev-parse undo/local-run)
set +e
bash "$undo" local-run --root "$root" >"$tmp/exists.out" 2>"$tmp/exists.err"
code=$?
set -e
[ "$code" -eq 2 ] || bots_fail "existing undo exit $code"
grep -q "already exists" "$tmp/exists.out"
[ "$(git -C "$root" rev-parse undo/local-run)" = "$tip" ] || bots_fail "existing undo branch was reset"
bots_pass "existing undo branch is not reset"

# P2: a second run revokes a dropped repo.
cat > "$tmp/drop" << EOF
kind=company
bot=helper
name=Acme helper
owner=ada
email=acme.bot@acme.test
repos=acme-os
scope.acme-os=company
token_path=$token
box=no
engine=$here/fixtures/engine.sh
EOF
: > "$OS_HOST_LOG"
bash "$add" --answers "$tmp/drop" --root "$root" >"$tmp/drop.out"
grep -q "revoked: acme-marketing" "$tmp/drop.out"
grep -q "revoke acme-marketing" "$OS_HOST_LOG"
bots_pass "second run revokes a dropped grant"

# B: useHttpPath is set, and a path outside the grant gets no answer.
cat > "$tmp/http-path" << EOF
kind=company
bot=helper
name=Acme helper
owner=ada
email=acme.bot@acme.test
repos=acme-os
scope.acme-os=company
token_path=$token
box=yes
engine=$here/fixtures/engine.sh
EOF
bash "$add" --answers "$tmp/http-path" --root "$root" >"$tmp/http.out"
use=$(git -C "$root" config --local --get credential.http://localhost:3300.useHttpPath)
[ "$use" = "true" ] || bots_fail "useHttpPath is not set"
printf 'protocol=http\nhost=localhost:3300\npath=acme/acme-secret.git\n\n' | \
  OS_BOT=helper OS_ROOT="$root" bash "$helper" get >"$tmp/outside.out"
[ ! -s "$tmp/outside.out" ] || bots_fail "helper answered a repo outside the grant"
bots_pass "useHttpPath grant check"

# A repo the token cannot see is skipped. A hard fetch error still fails.
skip_root="$tmp/skip"
mkdir -p "$skip_root/areas/marketing" "$skip_root/bots/helper"
bots_profile "$skip_root" forgejo "bots"
bots_people "$skip_root"
bots_copy_skills "$skip_root"
bots_stub_host "$skip_root"
cat > "$skip_root/bots/helper/BOT.md" << 'EOF'
---
type: bot
bot: helper
owner: ada
email: "acme.bot@acme.test"
repos:
  - skip-os
---
Helper.
EOF
git -C "$skip_root" init -q -b main
printf 'base\n' > "$skip_root/README.md"
git -C "$skip_root" add README.md
git -C "$skip_root" commit -q -m "base"
printf 'bot note\n' > "$skip_root/notes.md"
git -C "$skip_root" add notes.md
git -C "$skip_root" commit -q -m "bot note

Run-Id: skip-run
Bot-Owner: ada"
skip_bare="$tmp/skip-bare.git"
git init -q --bare "$skip_bare"
git -C "$skip_root" remote add origin "$skip_bare"
git -C "$skip_root" push -q origin main
git -C "$skip_root/areas/marketing" init -q -b main
printf 'area\n' > "$skip_root/areas/marketing/README.md"
git -C "$skip_root/areas/marketing" add README.md
git -C "$skip_root/areas/marketing" commit -q -m "area"
git -C "$skip_root/areas/marketing" update-ref refs/remotes/origin/main HEAD
python3 - "$tmp/skip-port" << 'PY' &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(404)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"not found")
    def do_POST(self):
        self.send_response(404)
        self.end_headers()
    def log_message(self, fmt, *args):
        return
srv = HTTPServer(("127.0.0.1", 0), H)
Path(sys.argv[1]).write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
skip_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$tmp/skip-port" ] && break
  sleep 0.1
done
skip_port=$(cat "$tmp/skip-port")
git -C "$skip_root/areas/marketing" remote add origin "http://127.0.0.1:${skip_port}/hidden.git"
set +e
bash "$skip_root/skills/undo-run/undo-run.sh" skip-run --root "$skip_root" >"$tmp/skip.out" 2>"$tmp/skip.err"
skip_rc=$?
set -e
kill "$skip_pid" 2>/dev/null || true
wait "$skip_pid" 2>/dev/null || true
[ "$skip_rc" -eq 0 ] || bots_fail "skip exit $skip_rc $(tr '\n' ' ' < "$tmp/skip.err")"
grep -q 'undo-run skip hidden: not visible to this token' "$tmp/skip.err" || bots_fail "missing skip line"
grep -q 'repo: skip-bare' "$tmp/skip.out" || bots_fail "visible repo was not reverted"
if git -C "$skip_root" diff --quiet && git -C "$skip_root" diff --cached --quiet; then
  :
else
  bots_fail "skip left the company checkout dirty"
fi
bots_pass "undo-run skips a repo the token cannot see"

# A fetch error that is not "not found" still fails, and no repo visible fails.
dark_root="$tmp/dark"
mkdir -p "$dark_root/bots/helper"
bots_profile "$dark_root" forgejo "bots"
bots_people "$dark_root"
bots_copy_skills "$dark_root"
bots_stub_host "$dark_root"
cat > "$dark_root/bots/helper/BOT.md" << 'EOF'
---
type: bot
bot: helper
owner: ada
email: "acme.bot@acme.test"
---
Helper.
EOF
git -C "$dark_root" init -q -b main
printf 'x\n' > "$dark_root/README.md"
git -C "$dark_root" add README.md
git -C "$dark_root" commit -q -m "base"
git -C "$dark_root" remote add origin "http://127.0.0.1:9/missing.git"
set +e
bash "$dark_root/skills/undo-run/undo-run.sh" dark-run --root "$dark_root" >"$tmp/dark.out" 2>"$tmp/dark.err"
dark_rc=$?
set -e
[ "$dark_rc" -eq 3 ] || bots_fail "hard fetch error exit $dark_rc"
grep -q 'undo-run skip' "$tmp/dark.err" && bots_fail "a connect error was treated as not visible"
bots_pass "undo-run still fails on a fetch error that is not access"

none_root="$tmp/none-visible"
mkdir -p "$none_root/bots/helper"
bots_profile "$none_root" forgejo "bots"
bots_people "$none_root"
bots_copy_skills "$none_root"
bots_stub_host "$none_root"
cat > "$none_root/bots/helper/BOT.md" << 'EOF'
---
type: bot
bot: helper
owner: ada
email: "acme.bot@acme.test"
---
Helper.
EOF
python3 - "$tmp/none-port" << 'PY' &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"not found")
    def log_message(self, fmt, *args):
        return
srv = HTTPServer(("127.0.0.1", 0), H)
Path(sys.argv[1]).write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
none_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$tmp/none-port" ] && break
  sleep 0.1
done
none_port=$(cat "$tmp/none-port")
git -C "$none_root" init -q -b main
printf 'x\n' > "$none_root/README.md"
git -C "$none_root" add README.md
git -C "$none_root" commit -q -m "base"
git -C "$none_root" remote add origin "http://127.0.0.1:${none_port}/gone.git"
git -C "$none_root" update-ref refs/remotes/origin/main HEAD
set +e
bash "$none_root/skills/undo-run/undo-run.sh" none-run --root "$none_root" >"$tmp/none.out" 2>"$tmp/none.err"
none_rc=$?
set -e
kill "$none_pid" 2>/dev/null || true
wait "$none_pid" 2>/dev/null || true
[ "$none_rc" -eq 2 ] || bots_fail "no visible repo exit $none_rc"
grep -q 'no repo visible to this token' "$tmp/none.err" || bots_fail "missing no-visible line"
bots_pass "undo-run fails when no repo is visible"

# A skipped repo that already has this run is a partial undo.
part_root="$tmp/part"
mkdir -p "$part_root/areas/marketing" "$part_root/bots/helper"
bots_profile "$part_root" forgejo "bots"
bots_people "$part_root"
bots_copy_skills "$part_root"
bots_stub_host "$part_root"
cat > "$part_root/bots/helper/BOT.md" << 'EOF'
---
type: bot
bot: helper
owner: ada
email: "acme.bot@acme.test"
---
Helper.
EOF
git -C "$part_root" init -q -b main
printf 'base\n' > "$part_root/README.md"
git -C "$part_root" add README.md
git -C "$part_root" commit -q -m "base"
printf 'bot note\n' > "$part_root/notes.md"
git -C "$part_root" add notes.md
git -C "$part_root" commit -q -m "bot note

Run-Id: part-run
Bot-Owner: ada"
part_bare="$tmp/part-bare.git"
git init -q --bare "$part_bare"
git -C "$part_root" remote add origin "$part_bare"
git -C "$part_root" push -q origin main
git -C "$part_root/areas/marketing" init -q -b main
printf 'area bot\n' > "$part_root/areas/marketing/note.md"
git -C "$part_root/areas/marketing" add note.md
git -C "$part_root/areas/marketing" commit -q -m "area bot

Run-Id: part-run
Bot-Owner: ada"
git -C "$part_root/areas/marketing" update-ref refs/remotes/origin/main HEAD
python3 - "$tmp/part-port" << 'PY' &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"not found")
    def log_message(self, fmt, *args):
        return
srv = HTTPServer(("127.0.0.1", 0), H)
Path(sys.argv[1]).write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
part_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$tmp/part-port" ] && break
  sleep 0.1
done
part_port=$(cat "$tmp/part-port")
git -C "$part_root/areas/marketing" remote add origin "http://127.0.0.1:${part_port}/hidden.git"
set +e
bash "$part_root/skills/undo-run/undo-run.sh" part-run --root "$part_root" >"$tmp/part.out" 2>"$tmp/part.err"
part_rc=$?
set -e
kill "$part_pid" 2>/dev/null || true
wait "$part_pid" 2>/dev/null || true
[ "$part_rc" -eq 4 ] || bots_fail "partial exit $part_rc $(tr '\n' ' ' < "$tmp/part.err")"
grep -q 'undo-run partial: hidden not visible; revert it there by hand or rerun' "$tmp/part.err" || bots_fail "missing partial line"
grep -q 'repo: part-bare' "$tmp/part.out" || bots_fail "visible repo was not reverted on a partial undo"
grep -q 'undo-run skip hidden' "$tmp/part.err" && bots_fail "a local match was skipped"
bots_pass "undo-run exits 4 when a skipped repo still has the run"

bots_pass "unit suite"
