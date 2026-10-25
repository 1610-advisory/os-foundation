#!/bin/bash
# Add a company bot or an area bot. Headless when given an answers file.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap bot_cleanup EXIT

usage() {
  cat << 'EOF'
Usage: add-bot.sh --answers <file> [--root <dir>]

Add a company bot (owner: admin) or an area bot (owner: that area's director).
The bots switch must be on. Grants never exceed the owner.

GitHub: write an App manifest and print the one-click create URL.
Forgejo: grant an existing bot user write on the named repos.

See CLI.md for the answers keys and the BOT.md frontmatter.
EOF
}

ANSWERS=""
BOT_ROOT_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --answers)
      [ $# -ge 2 ] || bot_die 1 "--answers needs a file"
      ANSWERS=$2
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || bot_die 1 "--root needs a directory"
      BOT_ROOT_ARG=$2
      export BOT_ROOT_ARG
      shift 2
      ;;
    *)
      bot_die 1 "unknown argument: $1"
      ;;
  esac
done

[ -n "$ANSWERS" ] || bot_die 1 "--answers is required"
[ -f "$ANSWERS" ] || bot_die 1 "answers file is missing"

ans() {
  local key=$1 default=${2-}
  local line val
  val=$default
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(bot_trim "$line")
    case "$line" in
      ''|\#*) continue ;;
    esac
    case "$line" in
      "$key"=*)
        val=${line#"$key"=}
        val=$(bot_trim "$val")
        ;;
    esac
  done < "$ANSWERS"
  printf '%s' "$val"
}

BOT_ROOT=$(bot_find_root)
export BOT_ROOT
export OS_PROFILE
OS_PROFILE=$(bot_profile)
bot_require_switch bots
bot_need jq
bot_need git

kind=$(ans kind "")
bot=$(ans bot "")
owner=$(ans owner "")
area=$(ans area "")
name=$(ans name "")
bot_user=$(ans bot_user "")
repos_csv=$(ans repos "")
inbox_csv=$(ans inbox "none")
connections_csv=$(ans connections "none")
routines_csv=$(ans routines "")
engine=$(ans engine "")
token_path=$(ans token_path "")
app_id=$(ans app_id "")
installation_id=$(ans installation_id "")
key_path=$(ans key_path "")
box=$(ans box "no")
replace_me=$(ans replace_me "no")
company_repo=$(ans company_repo "")
email=$(ans email "")

bot_slug_ok "kind" "$kind"
case "$kind" in
  company|area) ;;
  *) bot_die 1 "kind must be company or area" ;;
esac
bot_slug_ok "bot" "$bot"
bot_slug_ok "owner" "$owner"
[ -n "$name" ] || name=$bot
[ -n "$bot_user" ] || bot_user=$bot
bot_slug_ok "bot_user" "$bot_user"
[ -n "$repos_csv" ] || bot_die 1 "repos is required"
[ -n "$email" ] || bot_die 1 "email is required"
case "$email" in
  *" "*) bot_die 1 "email is not valid" ;;
  *@*.*) ;;
  *) bot_die 1 "email is not valid" ;;
esac
case "$box" in
  yes|no) ;;
  *) bot_die 1 "box must be yes or no" ;;
esac

profile=$(bot_profile)
slug=$(bot_field "$profile" company_slug) || bot_die 1 "company slug is not set"
slug=$(bot_trim "$slug")
if [ -n "$company_repo" ] && [ "$company_repo" != "${slug}-os" ]; then
  bot_die 2 "the company repo name must be ${slug}-os"
fi
company_repo="${slug}-os"
host=$(bot_field "$profile" host || true)
host=$(bot_trim "$host")
org=$(bot_field "$profile" org || true)
org=$(bot_trim "$org")
host_url=$(bot_field "$profile" host_url || true)
host_url=$(bot_trim "$host_url")

person=$(bot_person_file "$BOT_ROOT" "$owner") || bot_die 2 "owner page is missing"
role=$(bot_field "$person" role || true)
role=$(bot_trim "$role")

if [ "$kind" = "company" ]; then
  [ "$role" = "admin" ] || bot_die 2 "a company bot owner must be the admin"
  area=""
else
  bot_slug_ok "area" "$area"
  if [ "$role" = "admin" ]; then
    :
  elif [ "$role" = "director" ]; then
    if ! bot_field "$person" areas | bot_list_has "$area"; then
      bot_die 2 "the director does not own that area"
    fi
  else
    bot_die 2 "an area bot owner must be that area's director"
  fi
fi

scope_file=$(bot_mktemp)
repo_file=$(bot_mktemp)
old_ifs=$IFS
IFS=','
for raw in $repos_csv; do
  IFS=$old_ifs
  repo=$(bot_trim "$raw")
  [ -n "$repo" ] || continue
  bot_slug_ok "repo" "$repo"
  if ! scope=$(bot_name_scope "$slug" "$repo"); then
    bot_die 2 "repo ${repo} name does not say its scope"
  fi
  claimed=$(ans "scope.${repo}" "")
  if [ -n "$claimed" ] && [ "$claimed" != "$scope" ]; then
    bot_die 2 "scope.${repo} does not match the repo name"
  fi
  if [ "$scope" = "company" ]; then
    [ "$role" = "admin" ] || bot_die 2 "repo ${repo} exceeds the owner's grant"
    if [ "$kind" = "area" ]; then
      bot_die 2 "an area bot cannot take the company repo"
    fi
  else
    bot_slug_ok "scope" "$scope"
    if [ "$kind" = "area" ] && [ "$scope" != "$area" ]; then
      bot_die 2 "an area bot cannot take a repo outside its area"
    fi
    if [ "$role" = "admin" ]; then
      :
    elif [ "$role" = "director" ]; then
      if ! bot_field "$person" areas | bot_list_has "$scope"; then
        bot_die 2 "repo ${repo} exceeds the owner's grant"
      fi
    else
      bot_die 2 "repo ${repo} exceeds the owner's grant"
    fi
  fi
  printf '%s\n' "$repo" >> "$repo_file"
  printf '%s=%s\n' "$repo" "$scope" >> "$scope_file"
  IFS=','
done
IFS=$old_ifs

if [ ! -s "$repo_file" ]; then
  bot_die 1 "repos is required"
fi

case "$host" in
  github)
    [ -n "$org" ] || bot_die 1 "org is not set"
    if [ -n "$app_id" ] || [ -n "$installation_id" ] || [ -n "$key_path" ]; then
      [ -n "$app_id" ] || bot_die 1 "app_id is required with the other App fields"
      [ -n "$installation_id" ] || bot_die 1 "installation_id is required with the other App fields"
      [ -n "$key_path" ] || bot_die 1 "key_path is required with the other App fields"
      bot_slug_ok "app_id" "$app_id"
      bot_slug_ok "installation_id" "$installation_id"
      bot_require_secret_file "$key_path" "$BOT_ROOT"
    fi
    ;;
  forgejo)
    [ -n "$token_path" ] || bot_die 1 "token_path is required on Forgejo"
    bot_require_secret_file "$token_path" "$BOT_ROOT"
    ;;
  *)
    bot_die 1 "host is not set. Run add-teammate first."
    ;;
esac

old_repos=$(bot_mktemp)
if [ -f "${BOT_ROOT}/bots/${bot}/BOT.md" ]; then
  bot_field "${BOT_ROOT}/bots/${bot}/BOT.md" repos > "$old_repos" || true
fi

bot_dir="${BOT_ROOT}/bots/${bot}"
mkdir -p "${bot_dir}/skills" "${bot_dir}/logs" "${bot_dir}/routines"
printf '%s\n' "Bot skills live here." > "${bot_dir}/skills/README.md"
printf '%s\n' "Inbox reads are logged here. The log has no message text." > "${bot_dir}/logs/README.md"
printf '%s\n' "One routine file per scheduled task." > "${bot_dir}/routines/README.md"

updated=$(bot_now_utc "$(bot_now_epoch)" "%Y-%m-%d")
page=$(bot_mktemp)

{
  printf '%s\n' "---"
  printf 'type: bot\n'
  printf 'summary: %s\n' "$(bot_yaml_quote "$name")"
  printf 'updated: %s\n' "$updated"
  printf 'name: %s\n' "$(bot_yaml_quote "$name")"
  printf 'bot: %s\n' "$bot"
  printf 'kind: %s\n' "$kind"
  printf 'owner: %s\n' "$owner"
  if [ -n "$area" ]; then
    printf 'area: %s\n' "$area"
  else
    printf 'area: ""\n'
  fi
  printf 'bot_user: %s\n' "$bot_user"
  printf 'email: %s\n' "$(bot_yaml_quote "$email")"
  if [ "$host" = "github" ] && [ -n "$app_id" ]; then
    printf 'app_id: %s\n' "$(bot_yaml_quote "$app_id")"
    printf 'installation_id: %s\n' "$(bot_yaml_quote "$installation_id")"
    printf 'key_path: %s\n' "$(bot_yaml_quote "$key_path")"
  fi
  if [ "$host" = "forgejo" ] && [ -n "$token_path" ]; then
    printf 'token_path: %s\n' "$(bot_yaml_quote "$token_path")"
  fi
  printf 'repos:\n'
  while IFS= read -r repo; do
    printf '  - %s\n' "$repo"
  done < "$repo_file"
  printf 'repo_scope:\n'
  while IFS= read -r line; do
    printf '  - %s\n' "$line"
  done < "$scope_file"
  if [ -n "$routines_csv" ] && [ "$routines_csv" != "none" ]; then
    printf 'routines:\n'
    IFS=','
    for raw in $routines_csv; do
      item=$(bot_trim "$raw")
      [ -n "$item" ] || continue
      bot_slug_ok "routine" "$item"
      printf '  - %s\n' "$item"
    done
    IFS=$old_ifs
  else
    printf 'routines: []\n'
  fi
  if [ "$connections_csv" = "none" ] || [ -z "$connections_csv" ]; then
    printf 'allowed_connections: none\n'
  else
    printf 'allowed_connections:\n'
    IFS=','
    for raw in $connections_csv; do
      item=$(bot_trim "$raw")
      [ -n "$item" ] || continue
      bot_slug_ok "connection" "$item"
      printf '  - %s\n' "$item"
    done
    IFS=$old_ifs
  fi
  if [ "$inbox_csv" = "none" ] || [ -z "$inbox_csv" ]; then
    printf 'shared_inbox: none\n'
  else
    printf 'shared_inbox:\n'
    IFS=','
    for raw in $inbox_csv; do
      item=$(bot_trim "$raw")
      [ -n "$item" ] || continue
      bot_slug_ok "inbox" "$item"
      printf '  - %s\n' "$item"
    done
    IFS=$old_ifs
  fi
  if [ -n "$engine" ]; then
    printf 'engine: %s\n' "$(bot_yaml_quote "$engine")"
  fi
  printf 'cloud_handoff: %s\n' "$(bot_yaml_quote "$(bot_handoff_rule)")"
  printf '%s\n' "---"
  printf '\n'
  printf '# %s\n\n' "$name"
  template="${DIR}/templates/BOT.md"
  if [ -f "$template" ]; then
    awk '
      BEGIN { fm = 0; n = 0 }
      /^---[[:space:]]*$/ {
        n++
        if (n == 1) { fm = 1; next }
        if (n == 2) { fm = 0; next }
      }
      fm { next }
      { print }
    ' "$template"
  else
    cat << 'EOF'
## Persona

This bot acts for its owner. It does not act as the owner. Its commits carry the owner slug and a run id.

## Routines

Routine files live in `routines/`. A schedule starts the run. A person does not start it.

## Allowed connections

`allowed_connections` lists what this bot may connect to. `none` means no extra connection. A bot never gets a person's private mailbox or DMs unless that inbox is named in `shared_inbox`.

## Shared inbox

`shared_inbox` is the only allow list. `none` means the bot reads no inbox. The share is visible here and revocable: change this file. The next run follows it. Anyone who can ask this bot may see what it finds in a shared inbox. A read is logged. The log does not include the message. Only a plain fact may go into an area note.

## Hand-off

A hand-off runs only when the company switch `cloud-handoff` is on. The target must be turned on for this company. It works only on repos inside this bot's grant. It opens a pull request. It never merges. This version does not call a cloud agent.
EOF
  fi
} > "$page"
mv "$page" "${bot_dir}/BOT.md"

ready=0
case "$host" in
  github)
    cfg=$(bot_config_dir)
    mkdir -p "${cfg}/bots/${bot}"
    chmod 700 "$cfg" "${cfg}/bots" "${cfg}/bots/${bot}"
    manifest="${cfg}/bots/${bot}/app-manifest.json"
    jq -n --arg name "$name" '{
      name: $name,
      description: "Company or area bot. It can write contents and pull requests. It cannot administer the organization.",
      url: "https://example.com",
      public: false,
      default_permissions: {
        contents: "write",
        pull_requests: "write",
        metadata: "read"
      },
      hook_attributes: { active: false },
      request_oauth_on_install: false
    }' > "$manifest"
    chmod 600 "$manifest"
    if grep -q 'organization_administration' "$manifest"; then
      bot_die 3 "manifest has an admin permission"
    fi
    enc_name=$(jq -rn --arg v "$name" '$v|@uri')
    enc_desc=$(jq -rn --arg v "Writes contents and pull requests. It does not administer the organization." '$v|@uri')
    if [ -n "$host_url" ]; then
      base=${host_url%/}
    else
      base="https://github.com"
    fi
    create_url="${base}/organizations/${org}/settings/apps/new?name=${enc_name}&description=${enc_desc}&url=https%3A%2F%2Fexample.com&public=false&contents=write&pull_requests=write&metadata=read&webhook_active=false"
    printf 'create_url: %s\n' "$create_url"
    printf 'manifest: %s\n' "$manifest"
    printf '%s\n' "install: Open the create URL. Confirm the permissions. Create the App. Install it on only the named repos. Save the private key outside the repo, mode 0600. Run add-bot again with app_id, installation_id, and key_path."
    if [ -z "$app_id" ]; then
      printf '%s\n' "status: waiting-for-app"
    else
      ready=1
      printf '%s\n' "status: ready"
    fi
    ;;
  forgejo)
    host_sh=$(bot_host_sh)
    while IFS= read -r old; do
      [ -n "$old" ] || continue
      if ! grep -qx "$old" "$repo_file"; then
        bash "$host_sh" revoke "$old" "$bot_user"
        printf 'revoked: %s\n' "$old"
      fi
    done < "$old_repos"
    while IFS= read -r repo; do
      if ! grep -qx "$repo" "$old_repos"; then
        printf 'granted: %s\n' "$repo"
      fi
      bash "$host_sh" grant "$repo" "$bot_user" write
    done < "$repo_file"
    ready=1
    printf '%s\n' "status: ready"
    ;;
esac

if [ "$box" = "yes" ] && [ "$ready" -eq 1 ]; then
  cfg=$(bot_config_dir)
  mkdir -p "$cfg"
  chmod 700 "$cfg"
  if [ -f "${cfg}/me" ]; then
    current=$(bot_trim "$(cat "${cfg}/me")")
    if [ "$current" != "$bot" ] && [ "$replace_me" != "yes" ]; then
      bot_die 2 "me file is ${current}, not ${bot}. Set replace_me=yes on the bot box only."
    fi
  fi
  printf '%s\n' "$bot" > "${cfg}/me"
  chmod 600 "${cfg}/me"
  printf '%s\n' "$BOT_ROOT" > "${cfg}/root"
  chmod 600 "${cfg}/root"
  wrap="${cfg}/git-credential"
  helper="${DIR}/git-credential-os-bot"
  {
    printf '%s\n' "#!/bin/bash"
    printf '%s\n' "set -euo pipefail"
    printf 'export OS_ROOT=%q\n' "$BOT_ROOT"
    printf 'export OS_BOT=%q\n' "$bot"
    printf 'export OS_PROFILE=%q\n' "$profile"
    printf 'exec %q "$@"\n' "$helper"
  } > "$wrap"
  chmod 700 "$wrap"
  while IFS= read -r line; do
    repo=${line%%=*}
    scope=${line#*=}
    path=$(bot_repo_path "$BOT_ROOT" "$scope")
    if bot_is_git "$path"; then
      git -C "$path" config --local --unset-all credential.helper >/dev/null 2>&1 || true
      git -C "$path" config --local credential.helper "!${wrap}"
    fi
  done < "$scope_file"
  sync_sh=$(bot_sync_sh)
  bash "$sync_sh" install-jobs --bot
  printf '%s\n' "jobs: installed"
fi

printf 'bot: %s\n' "$bot"
printf 'owner: %s\n' "$owner"
printf 'kind: %s\n' "$kind"
while IFS= read -r repo; do
  printf 'repo: %s\n' "$repo"
done < "$repo_file"
printf 'propose: skills/sync/sync.sh propose add-bot-%s bots/%s/BOT.md bots/%s/routines/*.md\n' "$bot" "$bot" "$bot"
if [ "$box" = "yes" ]; then
  printf '%s\n' "propose-note: me on this box is the bot. Run propose on the admin computer, where me is the admin, before that."
fi
