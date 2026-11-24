#!/bin/bash
# GitHub App token: dry-run path and a JWT signed with a fixture key.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/lib.sh"
repo=$(automations_repo)
automations_need bash git jq openssl

host_dir="$repo/template/skills/_host"
if [ ! -f "$host_dir/host.sh" ]; then
  printf '%s\n' "BLOCKED: host.sh is not in this tree"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

root="$tmp/company"
mkdir -p "$root/automations/helper" "$root/skills"
cp -R "$host_dir" "$root/skills/_host"
chmod 700 "$root/skills/_host/host.sh"
cat > "$root/company-profile.md" << 'EOF'
---
type: company-profile
summary: "Acme Co"
updated: 2026-10-24
company_slug: acme
level: team
switches: [automations]
os_version: v1
host: github
host_url: ""
org: acme
sync_engine: ""
runner: ubuntu-latest
---

# Acme Co
EOF
key="$tmp/fixture.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$key" >/dev/null 2>&1
chmod 600 "$key"
cat > "$root/automations/helper/AUTOMATION.md" << EOF
---
type: automation
summary: "Helper"
automation: helper
owner: ada
app_id: 100
installation_id: 200
key_path: "$key"
---

Helper.
EOF

out=$(OS_PROFILE="$root/company-profile.md" HOST_DRY_RUN=1 \
  bash "$root/skills/_host/host.sh" get-token --automation helper)
printf '%s\n' "$out" | jq -e '.method == "POST" and .path == "/app/installations/200/access_tokens"' >/dev/null
if printf '%s\n' "$out" | grep -q 'Bearer'; then
  automations_fail "dry-run printed a token"
fi
if printf '%s\n' "$out" | jq -e 'has("token")' >/dev/null 2>&1; then
  automations_fail "dry-run printed a token field"
fi
automations_pass "github dry-run token path"

# Sign and verify in this process. The JWT is not passed as an argument.
# shellcheck disable=SC1091
. "$host_dir/lib.sh"
trap 'rm -rf "$tmp"; host_cleanup' EXIT
jwt=$(host_github_app_jwt 100 "$key")
rest=${jwt#*.}
payload=${rest%%.*}
sig=${rest#*.}
signing=${jwt%.*}
signfile="$tmp/signing"
sigfile="$tmp/sig.bin"
pub="$tmp/pub.pem"
printf '%s' "$signing" > "$signfile"
pad=$sig
mod=$((${#pad} % 4))
if [ "$mod" -eq 2 ]; then
  pad="${pad}=="
elif [ "$mod" -eq 3 ]; then
  pad="${pad}="
fi
printf '%s' "$pad" | tr '_-' '/+' | openssl base64 -d -A > "$sigfile"
openssl pkey -in "$key" -pubout -out "$pub" >/dev/null 2>&1
openssl dgst -sha256 -verify "$pub" -signature "$sigfile" "$signfile" >/dev/null
iss=$(printf '%s' "$payload" | tr '_-' '/+' | openssl base64 -d -A | jq -r '.iss')
[ "$iss" = "100" ] || automations_fail "jwt iss is $iss"
automations_pass "github jwt verifies with the fixture key"
