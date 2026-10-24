#!/bin/bash
# Shared helpers for bots tests. Source this file. Do not run it.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf '%s\n' "Source this file. Do not run it." >&2
  exit 1
fi

bots_repo() {
  local here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  cd "$here/../.." && pwd
}

bots_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bots_pass() {
  printf 'PASS %s\n' "$*"
}

bots_need() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || bots_fail "missing command: $cmd"
  done
}

bots_git_env() {
  export GIT_AUTHOR_NAME="Acme Bot"
  export GIT_AUTHOR_EMAIL="acme.bot@acme.test"
  export GIT_COMMITTER_NAME="Acme Bot"
  export GIT_COMMITTER_EMAIL="acme.bot@acme.test"
  git config --global user.name "Acme Bot"
  git config --global user.email "acme.bot@acme.test"
  git config --global commit.gpgsign false
  git config --global init.defaultBranch main
}

bots_copy_skills() {
  local root=$1 repo
  repo=$(bots_repo)
  mkdir -p "$root/skills/add-bot" "$root/skills/undo-run" "$root/skills/sync"
  cp "$repo/template/skills/add-bot/add-bot.sh" "$root/skills/add-bot/"
  cp "$repo/template/skills/add-bot/lib.sh" "$root/skills/add-bot/"
  cp "$repo/template/skills/add-bot/run.sh" "$root/skills/add-bot/"
  cp "$repo/template/skills/add-bot/git-credential-os-bot" "$root/skills/add-bot/"
  cp "$repo/template/skills/undo-run/undo-run.sh" "$root/skills/undo-run/"
  cp "$repo/tests/bots/fixtures/sync.sh" "$root/skills/sync/sync.sh"
  chmod 700 "$root/skills/add-bot/add-bot.sh" "$root/skills/add-bot/run.sh"
  chmod 700 "$root/skills/add-bot/git-credential-os-bot" "$root/skills/sync/sync.sh"
  chmod 700 "$root/skills/undo-run/undo-run.sh"
}

bots_people() {
  local root=$1
  mkdir -p "$root/people"
  cat > "$root/people/Ada.md" << 'EOF'
---
type: person
slug: ada
github: acme-admin
email: ada.admin@acme.test
role: admin
areas: [marketing, finance]
---

# Ada Admin
EOF
  cat > "$root/people/Dana.md" << 'EOF'
---
type: person
slug: dana
github: acme-director
email: dana.director@acme.test
role: director
areas: [marketing]
---

# Dana Director
EOF
}

bots_profile() {
  local root=$1 host=$2 switches=$3
  cat > "$root/company-profile.md" << EOF
---
type: company-profile
summary: "Acme Co"
updated: 2026-10-24
company_slug: acme
level: team
switches: [${switches}]
os_version: v1
host: ${host}
host_url: "http://localhost:3300"
org: acme
sync_engine: ""
runner: ubuntu-latest
---

# Acme Co
EOF
}

bots_stub_host() {
  local root=$1
  mkdir -p "$root/skills/_host"
  cat > "$root/skills/_host/host.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
if [ -n "${OS_HOST_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$OS_HOST_LOG"
fi
case "${1:-}" in
  get-token)
    n=0
    if [ -n "${OS_TOKEN_COUNT:-}" ] && [ -f "$OS_TOKEN_COUNT" ]; then
      n=$(tr -d '[:space:]' < "$OS_TOKEN_COUNT")
    fi
    n=$((n + 1))
    if [ -n "${OS_TOKEN_COUNT:-}" ]; then
      printf '%s\n' "$n" > "$OS_TOKEN_COUNT"
    fi
    printf 'unit-token-%s\n' "$n"
    ;;
  whoami)
    printf '%s\n' '{"login":"acme-bot"}'
    ;;
  open-pr)
    printf '%s\n' '{"number":7,"url":"http://localhost:3300/acme/bots-os/pulls/7"}'
    ;;
  grant|auto-merge|repo-access)
    printf '%s\n' '{"ok":true}'
    ;;
  *)
    printf '%s\n' '{"ok":true}'
    ;;
esac
EOF
  chmod 700 "$root/skills/_host/host.sh"
}

bots_secret_in_text() {
  local secret_file=$1 text_file=$2
  OS_SCRUB=$(tr -d '[:space:]' < "$secret_file")
  export OS_SCRUB
  awk 'index($0, ENVIRON["OS_SCRUB"]) > 0 { found = 1 } END { exit found ? 0 : 1 }' "$text_file"
}
