#!/bin/bash
# One test for each P1 in the team fix list.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# P1.1 Forgejo unprotect deletes only rule_name main, and restores it if a later step fails.
cat > "$work/fj_server.py" << PY
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
log = Path("$work/fj.log")
log.write_text("")
rules = [
    {"rule_name": "main", "marker": "protect-made"},
    {"rule_name": "other", "marker": "leave-me"},
]

class H(BaseHTTPRequestHandler):
    def _send(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if body:
            self.wfile.write(body)
    def do_GET(self):
        with log.open("a") as fh:
            fh.write("GET " + self.path + "\n")
        if self.path.endswith("/branch_protections/main"):
            left = [r for r in rules if r["rule_name"] == "main"]
            self._send(200 if left else 404, json.dumps(left[:1] or {}).encode())
            return
        if "/branch_protections" in self.path:
            self._send(200, json.dumps(rules).encode())
            return
        self._send(404, b"{}")
    def do_DELETE(self):
        with log.open("a") as fh:
            fh.write("DELETE " + self.path + "\n")
        if self.path.endswith("/branch_protections/main"):
            rules[:] = [r for r in rules if r["rule_name"] != "main"]
            self._send(204)
            return
        self._send(404, b"{}")
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode()
        with log.open("a") as fh:
            fh.write("POST " + body + "\n")
        self._send(201, b"{}")
    def log_message(self, fmt, *args):
        return

srv = HTTPServer(("127.0.0.1", 0), H)
Path("$work/port").write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
python3 "$work/fj_server.py" >/dev/null 2>&1 &
pid1=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$work/port" ] && break
  sleep 0.1
done
port=$(cat "$work/port")
export OS_HOST=forgejo OS_HOST_URL="http://127.0.0.1:${port}" OS_ORG=acme OS_SLUG=acme
export FORGEJO_TOKEN=local-test
if ! "$root/template/skills/_host/host.sh" unprotect demo >"$work/u1.out"; then
  team_fail "unprotect of the protect rule failed"
fi
grep -q 'DELETE /api/v1/repos/acme/demo/branch_protections/main' "$work/fj.log" || team_fail "main rule was not deleted"
grep -q 'branch_protections/other' "$work/fj.log" && team_fail "unprotect deleted a rule it did not make"
kill "$pid1" 2>/dev/null || true
wait "$pid1" 2>/dev/null || true
cat > "$work/fj_restore.py" << PY
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
log = Path("$work/restore.log")
log.write_text("")

class H(BaseHTTPRequestHandler):
    def _send(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if body:
            self.wfile.write(body)
    def do_GET(self):
        with log.open("a") as fh:
            fh.write("GET " + self.path + "\n")
        if self.path.endswith("/branch_protections/main"):
            self._send(500, b"{}")
            return
        if "/branch_protections" in self.path:
            self._send(200, json.dumps([{"rule_name": "main", "marker": "protect-made"}]).encode())
            return
        self._send(404, b"{}")
    def do_DELETE(self):
        with log.open("a") as fh:
            fh.write("DELETE " + self.path + "\n")
        self._send(204)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode()
        with log.open("a") as fh:
            fh.write("POST " + body + "\n")
        self._send(201, b"{}")
    def log_message(self, fmt, *args):
        return

srv = HTTPServer(("127.0.0.1", 0), H)
Path("$work/port2").write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
python3 "$work/fj_restore.py" >/dev/null 2>&1 &
pid2=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$work/port2" ] && break
  sleep 0.1
done
port2=$(cat "$work/port2")
export OS_HOST_URL="http://127.0.0.1:${port2}"
set +e
"$root/template/skills/_host/host.sh" unprotect demo >"$work/u2.out" 2>"$work/u2.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "unprotect should fail when the confirm step fails"
grep -q 'protect-made' "$work/restore.log" || team_fail "saved rule was not restored"
grep -q 'PROTECTION IS OFF on demo' "$work/u2.err" || team_fail "failed forgejo restore was claimed"
kill "$pid2" 2>/dev/null || true
wait "$pid2" 2>/dev/null || true

# A rule that matches main by branch_name is deleted by its rule name, not /main.
cat > "$work/fj_named.py" << PY
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
log = Path("$work/named.log")
log.write_text("")
rules = [
    {"rule_name": "protect main", "branch_name": "main", "marker": "protect-made"},
    {"rule_name": "other", "branch_name": "other", "marker": "leave-me"},
]

class H(BaseHTTPRequestHandler):
    def _send(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if body:
            self.wfile.write(body)
    def do_GET(self):
        with log.open("a") as fh:
            fh.write("GET " + self.path + "\n")
        if self.path.endswith("/branch_protections/protect%20main"):
            left = [r for r in rules if r["rule_name"] == "protect main"]
            self._send(200 if left else 404, json.dumps(left[:1] or {}).encode())
            return
        if "/branch_protections" in self.path:
            self._send(200, json.dumps(rules).encode())
            return
        self._send(404, b"{}")
    def do_DELETE(self):
        with log.open("a") as fh:
            fh.write("DELETE " + self.path + "\n")
        if self.path.endswith("/branch_protections/protect%20main"):
            rules[:] = [r for r in rules if r["rule_name"] != "protect main"]
            self._send(204)
            return
        self._send(404, b"{}")
    def log_message(self, fmt, *args):
        return

srv = HTTPServer(("127.0.0.1", 0), H)
Path("$work/port3").write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
python3 "$work/fj_named.py" >/dev/null 2>&1 &
pid3=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$work/port3" ] && break
  sleep 0.1
done
port3=$(cat "$work/port3")
export OS_HOST_URL="http://127.0.0.1:${port3}"
if ! "$root/template/skills/_host/host.sh" unprotect demo >"$work/u3.out" 2>"$work/u3.err"; then
  team_fail "unprotect of a renamed main rule failed"
fi
grep -q 'DELETE /api/v1/repos/acme/demo/branch_protections/protect%20main' "$work/named.log" || team_fail "rule was not deleted by its name"
grep -q 'branch_protections/main' "$work/named.log" && team_fail "unprotect deleted branch_protections/main"
grep -q 'branch_protections/other' "$work/named.log" && team_fail "unprotect deleted a rule it did not make"
kill "$pid3" 2>/dev/null || true
wait "$pid3" 2>/dev/null || true

cat > "$work/fj_empty.py" << PY
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
log = Path("$work/empty.log")
log.write_text("")

class H(BaseHTTPRequestHandler):
    def _send(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if body:
            self.wfile.write(body)
    def do_GET(self):
        with log.open("a") as fh:
            fh.write("GET " + self.path + "\n")
        if "/branch_protections" in self.path:
            self._send(200, b"[]")
            return
        self._send(404, b"{}")
    def do_DELETE(self):
        with log.open("a") as fh:
            fh.write("DELETE " + self.path + "\n")
        self._send(404, b"{}")
    def log_message(self, fmt, *args):
        return

srv = HTTPServer(("127.0.0.1", 0), H)
Path("$work/port4").write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
python3 "$work/fj_empty.py" >/dev/null 2>&1 &
pid4=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$work/port4" ] && break
  sleep 0.1
done
port4=$(cat "$work/port4")
export OS_HOST_URL="http://127.0.0.1:${port4}"
if ! "$root/template/skills/_host/host.sh" unprotect demo >"$work/u4.out" 2>"$work/u4.err"; then
  team_fail "missing rule should already be unprotected"
fi
grep -q 'already unprotected: demo main' "$work/u4.err" || team_fail "did not say the branch was already unprotected"
grep -q 'DELETE ' "$work/empty.log" && team_fail "unprotect deleted a rule that was not there"
kill "$pid4" 2>/dev/null || true
wait "$pid4" 2>/dev/null || true

# P1.2 GitHub unprotect restores the main ruleset if the second delete fails.
mkdir -p "$work/bin"
cat > "$work/bin/gh" << 'EOF'
#!/bin/bash
method=GET
path=""
while [ $# -gt 0 ]; do
  case "$1" in
    --method) method=$2; shift 2 ;;
    --hostname) shift 2 ;;
    --input) shift; shift ;;
    *) path=$1; shift ;;
  esac
done
printf '%s %s\n' "$method" "$path" >> "$GH_LOG"
case "$method $path" in
  "GET /repos/acme/acme-os/rulesets"|"GET /repos/acme/acme-os/rulesets?per_page=100&page=1")
    printf '%s\n' '[{"name":"main","id":1},{"name":"rules-review","id":2}]'
    ;;
  "GET /repos/acme/acme-os/rulesets/1")
    printf '%s\n' '{"name":"main","id":1,"rules":[{"type":"deletion"}]}'
    ;;
  "GET /repos/acme/acme-os/rulesets/2")
    printf '%s\n' '{"name":"rules-review","id":2,"rules":[]}'
    ;;
  "DELETE /repos/acme/acme-os/rulesets/1")
    exit 0
    ;;
  "DELETE /repos/acme/acme-os/rulesets/2")
    printf '%s\n' "HTTP 500" >&2
    exit 1
    ;;
  "POST /repos/acme/acme-os/rulesets")
    exit 0
    ;;
  *)
    printf 'unexpected %s %s\n' "$method" "$path" >&2
    exit 1
    ;;
esac
EOF
chmod 700 "$work/bin/gh"
export GH_LOG="$work/gh.log"
export PATH="$work/bin:$PATH"
export OS_HOST=github OS_ORG=acme OS_SLUG=acme OS_HOST_URL=""
set +e
"$root/template/skills/_host/host.sh" unprotect acme-os >"$work/gh.out" 2>"$work/gh.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "github unprotect should fail when the second delete fails"
grep -q 'POST /repos/acme/acme-os/rulesets' "$GH_LOG" || team_fail "deleted main ruleset was not restored"
grep -q 'PROTECTION IS OFF on acme-os' "$work/gh.err" || team_fail "failed github restore was claimed"

# P1.3 A 404 revoke is not success when we cannot confirm the person is gone.
mkdir -p "$work/co/people"
cat > "$work/co/company-profile.md" << 'EOF'
---
company_slug: acme
host: forgejo
host_url: "http://127.0.0.1:9"
org: acme
level: team
---
# Acme Co
EOF
cat > "$work/co/people/Ada Admin.md" << 'EOF'
---
slug: ada
github: acme-admin
role: admin
left: ""
---
# Ada Admin
EOF
cat > "$work/co/people/Sam Member.md" << 'EOF'
---
slug: sam
github: acme-member-d
role: writer
left: ""
manager: ada
---
# Sam Member
EOF
cat > "$work/bin/host.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HOST_LOG"
case "$1" in
  team-remove|revoke) exit 2 ;;
  user-access) printf '%s\n' '{"access":"write"}'; exit 0 ;;
  org-remove) exit 0 ;;
  archive-repo) printf 'should-not-run %s\n' "$1" >> "$HOST_LOG"; exit 0 ;;
  *) printf '%s\n' '{"ok":true}'; exit 0 ;;
esac
EOF
chmod 700 "$work/bin/host.sh"
export HOST_LOG="$work/host.log"
export OS_HOST_SH="$work/bin/host.sh"
: > "$HOST_LOG"
set +e
OS_HOST_SH="$work/bin/host.sh" "$root/template/skills/remove-teammate/remove.sh" --root "$work/co" --person sam >"$work/rm.out" 2>"$work/rm.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "failed team-remove was treated as success"
grep -q '^revoked:' "$work/rm.out" && team_fail "revoked was printed after a failed revoke"
grep -q 'Still has access' "$work/rm.err" || team_fail "missing list of what is left"
grep -q 'acme-os' "$work/rm.err" || team_fail "remaining repo was not listed"

# P1.4 A failed push after unprotect still restores protection, and does not print ok.
origin="$work/origin/acme/team-leak.git"
mkdir -p "$work/origin/acme" "$work/seed"
git init -q --bare "$origin"
git -C "$work/seed" init -q
git -C "$work/seed" checkout -q -b main
printf '%s\n' "note" > "$work/seed/note.md"
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$work/seed" add note.md
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$work/seed" commit -q -m plant
git -C "$work/seed" remote add origin "$origin"
git -C "$work/seed" push -q origin main
cat > "$work/leak-profile.md" << EOF
---
company_slug: acme
host: forgejo
host_url: "$work/origin"
org: acme
level: team
---
# Acme Co
EOF
cp "$work/leak-profile.md" "$work/seed/company-profile.md"
git -C "$work/seed" add company-profile.md
GIT_AUTHOR_NAME="Company OS" GIT_AUTHOR_EMAIL="os@localhost" \
  GIT_COMMITTER_NAME="Company OS" GIT_COMMITTER_EMAIL="os@localhost" \
  git -C "$work/seed" commit -q -m profile
git -C "$work/seed" push -q origin main
cat > "$work/bin/host-leak.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HOST_LOG"
case "$1" in
  get-token) printf '%s\n' "local-test" ;;
  whoami) printf '%s\n' '{"login":"ada"}' ;;
  unprotect) printf '%s\n' '{"ok":true}' ;;
  protect) exit 1 ;;
  purge-request) printf '%s\n' '{"ok":true}' ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
EOF
chmod 700 "$work/bin/host-leak.sh"
export HOST_LOG="$work/leak-host.log"
: > "$HOST_LOG"
set +e
OS_HOST_SH="$work/bin/host-leak.sh" "$root/template/skills/remove-leak/remove-leak.sh" \
  --root "$work/seed" --repo team-leak --path note.md >"$work/leak.out" 2>"$work/leak.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "remove-leak printed success after a failed restore"
grep -q 'remove-leak: ok' "$work/leak.out" && team_fail "ok was printed while protection is off"
grep -q 'PROTECTION IS OFF on team-leak' "$work/leak.err" || team_fail "missing protection-off message"

# P1.5 A failing filter-repo still removes the temp clone.
cat > "$work/bin/git-filter-repo" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod 700 "$work/bin/git-filter-repo"
cat > "$work/bin/mktemp" << 'EOF'
#!/bin/bash
out=$(/usr/bin/mktemp "$@")
printf '%s\n' "$out" >> "$OS_TMP_LOG"
printf '%s\n' "$out"
EOF
chmod 700 "$work/bin/mktemp"
export OS_TMP_LOG="$work/tmps"
: > "$OS_TMP_LOG"
export HOST_LOG="$work/leak2.log"
: > "$HOST_LOG"
set +e
PATH="$work/bin:$PATH" OS_HOST_SH="$work/bin/host-leak.sh" \
  "$root/template/skills/remove-leak/remove-leak.sh" \
  --root "$work/seed" --repo team-leak --path note.md >"$work/leak2.out" 2>"$work/leak2.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "failing filter-repo should fail the run"
while IFS= read -r tmp; do
  [ -n "$tmp" ] || continue
  if [ -e "$tmp" ]; then
    team_fail "temp file survived a failed rewrite"
  fi
done < "$OS_TMP_LOG"

# E. A GitHub 403 on user-access is not access gone.
mkdir -p "$work/ghco/people" "$work/ghbin"
cat > "$work/ghco/company-profile.md" << 'EOF'
---
company_slug: acme
host: github
org: acme
level: team
---
# Acme Co
EOF
cat > "$work/ghco/people/Ada Admin.md" << 'EOF'
---
slug: ada
github: acme-admin
role: admin
left: ""
---
# Ada Admin
EOF
cat > "$work/ghco/people/Sam Member.md" << 'EOF'
---
slug: sam
github: acme-member-d
role: writer
left: ""
manager: ada
---
# Sam Member
EOF
cat > "$work/ghbin/gh" << 'EOF'
#!/bin/bash
path=""
prev=""
for arg in "$@"; do
  case "$prev" in
    --method) ;;
    *) path=$arg ;;
  esac
  prev=$arg
done
case "$path" in
  */collaborators/*/permission)
    printf '%s\n' "HTTP 403" >&2
    exit 1
    ;;
esac
printf '%s\n' '{}'
exit 0
EOF
chmod 700 "$work/ghbin/gh"
unset OS_HOST_SH
set +e
PATH="$work/ghbin:$PATH" "$root/template/skills/remove-teammate/remove.sh" --root "$work/ghco" --person sam >"$work/ghrm.out" 2>"$work/ghrm.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || team_fail "403 was treated as access gone"
grep -q '^revoked:' "$work/ghrm.out" && team_fail "revoked was printed after a 403"
grep -q 'acme-os' "$work/ghrm.err" || team_fail "403 repo was not listed as still reachable"

printf '%s\n' "PASS p1"
