#!/usr/bin/env bash
# Helpers for Acme scenarios S1-S14. Source this file. Do not run it.
# A scenario prints result lines on stdout and logs on stderr.

# shellcheck disable=SC1091
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# shellcheck disable=SC1091
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/api.sh"

osf_scenario_log() {
  printf '%s\n' "$*" >&2
}

osf_line() {
  printf '%s\n' "$*"
}

osf_result() {
  printf '%s\n' "$*"
  exit 0
}

# Exit with BLOCKED when a product file is not on this tree yet.
osf_need_product() {
  local id="$1"
  local team="$2"
  shift 2
  local root rel
  root=$(osf_acme_root)
  for rel in "$@"; do
    if [ ! -e "$root/$rel" ]; then
      osf_result "$id BLOCKED not merged: $team"
    fi
  done
}

osf_work() {
  local name="$1"
  local root dir
  root=$(osf_acme_root)
  dir="$root/tests/acme/.out/${name}-$$"
  mkdir -p "$dir"
  chmod 700 "$root/tests/acme/.out" "$dir"
  printf '%s\n' "$dir"
}

# Call before changing HOME. Token files stay at the real cache path.
osf_keep_cache() {
  if [ -z "${OSF_ACME_CACHE:-}" ]; then
    export OSF_ACME_CACHE="${HOME}/.cache/os-foundation/forgejo"
  fi
}

osf_sandbox() {
  local base="$1"
  osf_keep_cache
  mkdir -p "$base/home" "$base/xdg" "$base/jobs"
  chmod 700 "$base" "$base/home" "$base/xdg" "$base/jobs"
  export HOME="$base/home"
  export XDG_CONFIG_HOME="$base/xdg"
  export OS_JOBS_DIR="$base/jobs"
  export OS_JOBS_LOAD=0
  export OS_TEST_MODE=1
  export OS_JOBS_PLATFORM=macos
}

osf_today() {
  date +%Y-%m-%d
}

osf_os_version() {
  local root
  root=$(osf_acme_root)
  git -C "$root" describe --tags --always 2>/dev/null || printf '%s\n' unknown
}

osf_count_steps_text() {
  awk 'BEGIN { n = 0 } /^[0-9]+\. / { n++ } END { print n }'
}

osf_steps_file() {
  osf_count_steps_text < "$1"
}

osf_steps_rev() {
  local rev="$1"
  local root
  root=$(osf_acme_root)
  git -C "$root" show "${rev}:start-core.md" | osf_count_steps_text
}

# A fake token-shaped string. The prefix is split so this file stays clean.
osf_fake_pat() {
  local prefix rest
  prefix=$(printf '%s%s' 'gh' 'p_')
  rest=$(openssl rand -hex 18 | tr -d '\n')
  printf '%s%s\n' "$prefix" "$rest"
}

osf_fill_placeholders() {
  local dest="$1"
  local version="$2"
  local day="$3"
  local slug="$4"
  OSF_DEST="$dest" OSF_VERSION="$version" OSF_DAY="$day" OSF_SLUG="$slug" python3 - << 'PY'
import os
from pathlib import Path

dest = Path(os.environ["OSF_DEST"])
repl = {
    "{{COMPANY_NAME}}": "Acme Co",
    "{{COMPANY_SLUG}}": os.environ["OSF_SLUG"],
    "{{OWNER_NAME}}": "Ada Admin",
    "{{OWNER_ROLE}}": "Owner",
    "{{OWNER_SLUG}}": "ada",
    "{{DATE}}": os.environ["OSF_DAY"],
    "{{OS_VERSION}}": os.environ["OSF_VERSION"],
    "{{ONE_LINER}}": "Acme Co makes sample goods.",
    "{{AREAS}}": "none yet",
    "{{FULL_NAME}}": "Ada Admin",
}
skip = {"skills", ".git"}
for dirpath, dirnames, filenames in os.walk(dest):
    dirnames[:] = [name for name in dirnames if name not in skip]
    for name in filenames:
        path = Path(dirpath) / name
        if path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        new = text
        for key, value in repl.items():
            new = new.replace(key, value)
        if new != text:
            path.write_text(new, encoding="utf-8")
PY
}

osf_write_owner_page() {
  local dest="$1"
  local slug="$2"
  local github="$3"
  mkdir -p "$dest/people"
  cat > "$dest/people/Ada Admin.md" << EOF
---
type: person
summary: "Owner of Acme Co"
job_title: "Owner"
company: "Acme Co"
related: []
slug: ada
github: ${github}
email: ada.admin@acme.test
role: admin
areas: []
kernel_id: ""
left: ""
---

# Ada Admin

## Who they are

Owner of Acme Co.

## Notes

Website: none.
EOF
}

osf_setup_solo() {
  local dest="$1"
  local slug="${2:-acme}"
  local github="${3:-acme-admin}"
  local root day version
  root=$(osf_acme_root)
  day=$(osf_today)
  version=$(osf_os_version)
  mkdir -p "$dest"
  cp -R "$root/template/." "$dest/"
  osf_fill_placeholders "$dest" "$version" "$day" "$slug"
  python3 - "$dest/company-profile.md" << 'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("<!-- URL, or \"none\". -->", "none")
text = text.replace("<!-- One or two sentences. -->", "Acme Co makes sample goods.")
path.write_text(text, encoding="utf-8")
PY
  osf_write_owner_page "$dest" "$slug" "$github"
  if [ -f "$dest/skills/privacy/privacy.sh" ]; then
    bash "$dest/skills/privacy/privacy.sh" --root "$dest" >&2
  fi
  mkdir -p "$dest/memory/logs"
  cat > "$dest/memory/logs/${day}-ada.md" << EOF
# ${day} ada

Built the solo company folder. Open: no areas yet. Tools: email only.
EOF
  git -C "$dest" init -b main >&2
  git -C "$dest" add -A >&2
  git -C "$dest" \
    -c user.name="Ada Admin" \
    -c user.email="ada.admin@acme.test" \
    commit -m "Company OS: start" >&2
  printf '%s\n' "$day"
}

osf_solo_problems() {
  local dest="$1"
  local day="$2"
  local root link mode target level host
  root=$(osf_acme_root)
  level=$(OS_PROFILE="$dest/company-profile.md" bash "$root/template/skills/_host/profile.sh" level)
  host=$(OS_PROFILE="$dest/company-profile.md" bash "$root/template/skills/_host/profile.sh" host)
  if [ "$level" != "solo" ]; then
    printf '%s\n' "level is not solo"
    return 0
  fi
  if [ "$host" != "none" ]; then
    printf '%s\n' "host is not none"
    return 0
  fi
  for link in .agents/skills .claude/skills; do
    if [ ! -L "$dest/$link" ]; then
      printf '%s\n' "$link is not a symlink"
      return 0
    fi
    target=$(readlink "$dest/$link")
    if [ "$target" != "../skills" ]; then
      printf '%s\n' "$link points at $target"
      return 0
    fi
    if [ ! -e "$dest/$link/privacy/SKILL.md" ] && [ ! -e "$dest/$link/add-area/SKILL.md" ]; then
      printf '%s\n' "$link does not resolve to a skill"
      return 0
    fi
    mode=$(git -C "$dest" ls-files -s "$link" | awk '{print $1}')
    if [ "$mode" != "120000" ]; then
      printf '%s\n' "$link is not a committed symlink"
      return 0
    fi
  done
  if [ -e "$dest/.github" ] || [ -e "$dest/CODEOWNERS" ] || [ -d "$dest/users" ] || [ -d "$dest/bots" ]; then
    printf '%s\n' "team parts are present"
    return 0
  fi
  if git -C "$dest" rev-parse --verify logs >/dev/null 2>&1; then
    printf '%s\n' "logs branch exists"
    return 0
  fi
  if ! git -C "$dest" cat-file -e "main:memory/logs/${day}-ada.md" 2>/dev/null; then
    printf '%s\n' "per-person log is not on main"
    return 0
  fi
  if ! OSF_DEST="$dest" python3 - << 'PY'
import os
import sys
from pathlib import Path
dest = Path(os.environ["OSF_DEST"])
skip = {"skills", ".git"}
for dirpath, dirnames, filenames in os.walk(dest):
    dirnames[:] = [name for name in dirnames if name not in skip]
    for name in filenames:
        path = Path(dirpath) / name
        if path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if "{{" in text and "}}" in text:
            sys.exit(1)
sys.exit(0)
PY
  then
    printf '%s\n' "placeholder left outside skills"
  fi
  return 0
}

osf_token_file() {
  local user="$1"
  printf '%s\n' "$(osf_acme_token_dir)/$user"
}

osf_export_token() {
  local user="$1"
  local file token
  file=$(osf_token_file "$user")
  if [ ! -s "$file" ]; then
    return 1
  fi
  token=$(tr -d '[:space:]' < "$file")
  export FORGEJO_TOKEN="$token"
  token=""
  export OS_HOST=forgejo
  export OS_HOST_URL
  OS_HOST_URL=$(osf_acme_url)
  export OS_ORG="${OS_ORG:-acme}"
  export OS_TEST_MODE=1
}

osf_write_token_file() {
  local slug="$1"
  local user="$2"
  local dest dir
  dest="${XDG_CONFIG_HOME}/${slug}-os"
  mkdir -p "$dest"
  chmod 700 "$dest"
  dir=$(osf_token_file "$user")
  if [ ! -s "$dir" ]; then
    return 1
  fi
  cp "$dir" "$dest/forgejo-token"
  chmod 600 "$dest/forgejo-token"
}

osf_me() {
  local slug="$1"
  local person="$2"
  local dest
  dest="${XDG_CONFIG_HOME}/${slug}-os"
  mkdir -p "$dest"
  chmod 700 "$dest"
  printf '%s\n' "$person" > "$dest/me"
  chmod 600 "$dest/me"
}

osf_delete_repo() {
  local owner="$1"
  local repo="$2"
  local token
  token=$(osf_acme_admin_token)
  if [ ! -s "$token" ]; then
    token=$(osf_token_file acme-admin)
  fi
  osf_api "$token" DELETE "/api/v1/repos/${owner}/${repo}" || true
  osf_api_discard
}

osf_delete_org() {
  local org="$1"
  local token
  token=$(osf_acme_admin_token)
  if [ ! -s "$token" ]; then
    token=$(osf_token_file acme-admin)
  fi
  osf_api "$token" DELETE "/api/v1/orgs/${org}" || true
  osf_api_discard
}

osf_create_org() {
  local org="$1"
  local token body code
  token=$(osf_token_file acme-admin)
  body=$(mktemp)
  chmod 600 "$body"
  jq -n --arg name "$org" '{username:$name, visibility:"private"}' > "$body"
  osf_api "$token" POST "/api/v1/orgs" "$body"
  code="$OSF_HTTP_CODE"
  rm -f "$body"
  osf_api_discard
  if [ "$code" = "201" ] || [ "$code" = "200" ] || [ "$code" = "409" ] || [ "$code" = "422" ]; then
    return 0
  fi
  return 1
}

osf_results() {
  local root
  root=$(osf_acme_root)
  python3 "$root/tests/acme/lib/results.py" "$@"
}

osf_seat_line() {
  local seat="$1"
  local root out rc
  root=$(osf_acme_root)
  set +e
  out=$(bash "$root/tests/acme/seat.sh" --check "$seat" 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "$out"
  return 3
}

osf_engine_name() {
  case "$1" in
    claude) printf '%s\n' admin ;;
    codex) printf '%s\n' director ;;
    cursor) printf '%s\n' member-c ;;
    pi) printf '%s\n' member-d ;;
    *) return 1 ;;
  esac
}

osf_write_team_answers() {
  local file="$1"
  local company="$2"
  local slug="$3"
  local org="$4"
  local engine="$5"
  local url
  url=$(osf_acme_url)
  cat > "$file" << EOF
root=${company}
host=forgejo
host_url=${url}
org=${org}
sync_engine=${engine}
runner=ubuntu-latest
admin_slug=ada
company_slug=${slug}
company_name=Acme Co
person.ada.name=Ada Admin
person.ada.github=acme-admin
person.ada.email=ada.admin@acme.test
person.ada.role=admin
person.ada.areas=marketing
person.dana.name=Dana Director
person.dana.github=acme-director
person.dana.email=dana.director@acme.test
person.dana.role=director
person.dana.areas=marketing
person.mia.name=Mia Member
person.mia.github=acme-member-a
person.mia.email=mia.member@acme.test
person.mia.role=writer
person.mia.areas=marketing
person.max.name=Max Member
person.max.github=acme-member-b
person.max.email=max.member@acme.test
person.max.role=writer
person.max.areas=marketing
person.noa.name=Noa Member
person.noa.github=acme-member-c
person.noa.email=noa.member@acme.test
person.noa.role=writer
person.noa.areas=
person.sam.name=Sam Member
person.sam.github=acme-member-d
person.sam.email=sam.member@acme.test
person.sam.role=writer
person.sam.areas=marketing
area.marketing.director=dana
EOF
  chmod 600 "$file"
}

osf_approve() {
  local owner="$1"
  local repo="$2"
  local number="$3"
  local user="$4"
  local body
  if ! osf_export_token "$user"; then
    return 1
  fi
  body=$(mktemp)
  chmod 600 "$body"
  jq -n '{body:"Approved from the test.", event:"APPROVED"}' > "$body"
  osf_api "$(osf_token_file "$user")" POST "/api/v1/repos/${owner}/${repo}/pulls/${number}/reviews" "$body"
  rm -f "$body"
  if [ "$OSF_HTTP_CODE" = "200" ] || [ "$OSF_HTTP_CODE" = "201" ]; then
    osf_api_discard
    return 0
  fi
  osf_api_discard
  return 1
}
