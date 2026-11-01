#!/bin/bash
# Lint pass and fail cases. No host, no network.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/common.sh"
root=$(team_root)
lint="$root/template/skills/lint/lint.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass="$work/pass"
mkdir -p "$pass/skills/lint" "$pass/.agents" "$pass/.claude" \
  "$pass/areas/marketing/.agents" "$pass/areas/marketing/.claude" \
  "$pass/areas/marketing/skills" "$pass/users/mia/profile" "$pass/bots/helper"
ln -s ../skills "$pass/.agents/skills"
ln -s ../skills "$pass/.claude/skills"
ln -s ../skills "$pass/areas/marketing/.agents/skills"
ln -s ../skills "$pass/areas/marketing/.claude/skills"
printf '%s\n' "# Area" > "$pass/areas/marketing/AGENTS.md"
printf '%s\n' "same" > "$pass/skills/lint/SKILL.md"
mkdir -p "$pass/areas/marketing/skills/lint"
printf '%s\n' "same" > "$pass/areas/marketing/skills/lint/SKILL.md"
cp "$root/template/scale.md" "$pass/scale.md"
cat > "$pass/company-profile.md" << 'EOF'
---
type: company-profile
company_slug: acme
level: team
switches: []
os_version: v9.9.9
host: none
---

# Acme Co
EOF
printf '%s\n' "# Profile" > "$pass/users/mia/profile/PROFILE.md"
printf '%s\n' "# Bot" > "$pass/bots/helper/BOT.md"
# B33: the stock v0 logs README, moved by the upgrade. History: lint skips it.
mkdir -p "$pass/memory/logs-archive" "$pass/areas/marketing/memory/logs-archive"
printf '# Session logs\n\nOne file per person per day: YYYY-MM-DD-{{PERSON_SLUG}}.md\n' > "$pass/memory/logs-archive/README.md"
cp "$pass/memory/logs-archive/README.md" "$pass/areas/marketing/memory/logs-archive/README.md"
# B42: an area's own workflow uses the actions form, like the root one.
mkdir -p "$pass/areas/marketing/.github/workflows"
# shellcheck disable=SC2016
printf '%s\n' 'env:' '  OS_REVIEW_VENDOR: ${{ vars.OS_REVIEW_VENDOR }}' > "$pass/areas/marketing/.github/workflows/checks.yml"
# B42: a workspace made by add-teammate has no placeholder left.
(
  # shellcheck disable=SC1090,SC1091
  . "$root/template/skills/add-teammate/lib.sh"
  os_write_workspace "$pass/users/mia" mia "Mia Member" acme "Acme Co" "$root/template/skills/add-teammate/workspace" >/dev/null
)
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
mkdir -p "$HOME"
if ! out=$("$lint" --ci --root "$pass"); then
  printf '%s\n' "$out" >&2
  team_fail "clean tree should pass"
fi
[ -z "$out" ] || team_fail "clean tree printed findings"

fail="$work/fail"
mkdir -p "$fail/skills" "$fail/users/mia/profile"
cat > "$fail/company-profile.md" << 'EOF'
---
type: company-profile
company_slug: acme
level: dreamland
switches: [dream, not-a-switch]
os_version: v0.0.1
---

# Acme Co
EOF
printf '%s\n' "Hello {{COMPANY_NAME}}" > "$fail/README.md"
printf '%s\n' "Works at Acme Co in acme." > "$fail/users/mia/profile/PROFILE.md"
printf '%s\n' "# too big" > "$fail/AGENTS.md"
dd if=/dev/zero bs=10000 count=1 >> "$fail/AGENTS.md" 2>/dev/null
set +e
out=$("$lint" --ci --root "$fail")
rc=$?
set -e
[ "$rc" -eq 1 ] || team_fail "bad tree should exit 1"
printf '%s\n' "$out" | grep -q 'link: ' || team_fail "missing link finding"
printf '%s\n' "$out" | grep -q 'level: dreamland' || team_fail "missing level finding"
printf '%s\n' "$out" | grep -qx 'finding: host: missing (add host: none to company-profile.md, or github or forgejo)' || team_fail "missing host finding"
printf '%s\n' "$out" | grep -q 'switch: dream' || team_fail "missing dream finding"
printf '%s\n' "$out" | grep -q 'switch: not-a-switch' || team_fail "missing switch finding"
printf '%s\n' "$out" | grep -q 'placeholder: README.md' || team_fail "missing placeholder finding"
printf '%s\n' "$out" | grep -q 'profile: users/mia/profile/PROFILE.md' || team_fail "missing profile finding"
printf '%s\n' "$out" | grep -q 'size: AGENTS.md' || team_fail "missing size finding"

# Version notice: prerelease is not newer. Stable higher version is.
ver="$work/ver"
mkdir -p "$ver/.agents" "$ver/.claude" "$ver/skills"
ln -s ../skills "$ver/.agents/skills"
ln -s ../skills "$ver/.claude/skills"
cp "$pass/scale.md" "$ver/scale.md"
cat > "$ver/company-profile.md" << 'EOF'
---
company_slug: acme
level: solo
switches: []
os_version: v1.0.0
host: none
---

# Acme Co
EOF
printf 'v1.2.0\n' > "$work/newer"
printf 'v1.2.0-rc.1\n' > "$work/pre"
printf 'unreleased\n' > "$work/unrel"
export HOME="$work/home2" XDG_CONFIG_HOME="$work/home2/.config"
mkdir -p "$HOME"
out=$(OS_VERSION_URL="file://$work/newer" "$lint" --root "$ver")
printf '%s\n' "$out" | grep -q 'notice: a newer os-foundation version exists: v1.2.0' || team_fail "missing newer notice"
out=$(OS_VERSION_URL="file://$work/pre" "$lint" --root "$ver" || true)
printf '%s\n' "$out" | grep -q 'notice:' && team_fail "prerelease must not be newer"
out=$(OS_VERSION_URL="file://$work/unrel" "$lint" --root "$ver" || true)
printf '%s\n' "$out" | grep -q 'notice:' && team_fail "unreleased must not notice"

# Bot offer after 14 days, once. Fresh config so earlier runs do not count.
export HOME="$work/home3" XDG_CONFIG_HOME="$work/home3/.config"
mkdir -p "$HOME"
export OS_NOW=2026-01-01
OS_VERSION_URL="file://$work/unrel" "$lint" --root "$ver" >/dev/null
export OS_NOW=2026-01-20
out=$(OS_VERSION_URL="file://$work/unrel" "$lint" --root "$ver")
printf '%s\n' "$out" | grep -q 'offer: You have used this OS for two weeks' || team_fail "missing bot offer"
out=$(OS_VERSION_URL="file://$work/unrel" "$lint" --root "$ver")
printf '%s\n' "$out" | grep -q 'offer:' && team_fail "bot offer must be once"

# A link whose text is ../skills but whose target is missing is a finding.
dangle="$work/dangle"
mkdir -p "$dangle/.agents" "$dangle/.claude" "$dangle/skills"
ln -s ../skills "$dangle/.agents/skills"
ln -s ../missing "$dangle/.claude/skills"
rmdir "$dangle/skills"
cp "$pass/company-profile.md" "$dangle/company-profile.md"
cp "$pass/scale.md" "$dangle/scale.md"
set +e
out=$("$lint" --ci --root "$dangle")
rc=$?
set -e
[ "$rc" -eq 1 ] || team_fail "dangling link should fail"
printf '%s\n' "$out" | grep -q 'target is missing' || team_fail "dangling link was accepted"

printf '%s\n' "PASS lint"
