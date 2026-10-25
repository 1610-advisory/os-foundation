# add-bot CLI

Scripts in this folder and in `undo-run/` read these names. The prose skill asks the person and writes the answers file. The scripts do the work.

The `bots` switch must be on. If it is off, every script here refuses and changes nothing.

These scripts call `skills/_host/host.sh` only. They do not call `gh` or the host API. They do not list host resources. A future list call must follow pages until a short page (GitHub 30, Forgejo 50).

No token, key, or JWT goes in a child process argument list. A token moves through a mode 0600 file, stdin, or an environment variable.

## add-bot.sh

```
add-bot.sh --answers <file> [--root <dir>]
add-bot.sh --help
```

Run it from the company root, or pass `--root`. `OS_PROFILE` may point at `company-profile.md`.

`--answers` is a text file. One `key=value` pair per line. Blank lines and lines that start with `#` are ignored.

| Key | Required | Meaning |
|---|---|---|
| `kind` | yes | `company` or `area` |
| `bot` | yes | bot slug. Folder name under `bots/` |
| `owner` | yes | person slug. Company bot: the admin. Area bot: that area's director, or the admin after the director leaves |
| `area` | area bot | area slug |
| `name` | no | display name. Default: the bot slug |
| `bot_user` | no | host login. Default: the bot slug. Forgejo: the existing bot user |
| `repos` | yes | comma-separated repo short names to grant write |
| `scope.<repo>` | no | Must match the name, or be omitted. `<company_slug>-os` is company. `<company_slug>-<area>` is that area. Any other name, or a scope that disagrees with the name, is refused |
| `email` | yes | bot author email. undo-run matches this email, not a copied trailer alone |
| `inbox` | no | `none` (default) or a comma list of shared inbox names |
| `connections` | no | `none` (default) or a comma list of allowed connections |
| `routines` | no | comma list of routine slugs. Files live in `bots/<bot>/routines/` |
| `engine` | no | headless engine command. Default: `sync_engine` in the company profile |
| `token_path` | Forgejo | absolute path to the bot user token file. Outside the repo. Mode 0600. The file is not copied into the repo |
| `app_id` | GitHub, after create | GitHub App id |
| `installation_id` | GitHub, after create | installation id |
| `key_path` | GitHub, after create | absolute path to the App private key. Outside the repo. Mode 0600 |
| `box` | no | `yes` if this computer is the bot's box. Default `no`. `yes` writes the `me` file, installs OS jobs, and sets the git credential helper |
| `replace_me` | no | `yes` to replace a `me` file that names someone else. Use only on the bot's box |

Exit codes: `0` ready or waiting for the App, `1` usage, `2` refused (switch off, grant above the owner, bad path), `3` a needed script or host call failed, `4` auth or key problem.

Grants never exceed the owner. The scope comes from the repo name only. An answers line cannot relabel the company repo as an area. A second run revokes repos that left the list and prints granted and revoked.

### GitHub

The script writes an App manifest under the config dir (mode 0600) and prints a one-click create URL. Permissions in the manifest and the URL are contents write, pull requests write, and metadata read. There is no org admin permission. It also prints the install step: install the App on only the named repos, save the key outside the repo, then run again with `app_id`, `installation_id`, and `key_path`.

The create URL is:

```
https://github.com/organizations/<org>/settings/apps/new?name=...&public=false&contents=write&pull_requests=write&metadata=read&webhook_active=false
```

A Forgejo or GitHub Enterprise host uses `host_url` as the base.

### Forgejo

The script does not make a user. It uses `bot_user` and `token_path`. It grants that user write on each named repo through `host.sh grant`. A second run revokes repos that are no longer named.

### What it writes

`bots/<bot>/BOT.md`, `bots/<bot>/skills/`, `bots/<bot>/logs/`, `bots/<bot>/routines/`.

If `skills/add-bot/templates/BOT.md` exists, its body sections are kept and the frontmatter below replaces the template frontmatter.

On the bot's box (`box=yes`) it writes `<config>/<slug>-os/me` (the bot slug) and `<config>/<slug>-os/root` (the company folder). It runs `skills/sync/sync.sh install-jobs --bot`. It points each local granted repo at `git-credential-os-bot`.

`add-bot.sh` does not commit `BOT.md`. That page is a rules file. The nightly push will not put it on the standing pull request. After add-bot, on the admin's computer, while `me` is still the admin, run:

```
skills/sync/sync.sh propose add-bot-<bot> bots/<bot>/BOT.md bots/<bot>/routines/*.md
```

That is the command. `sync.sh propose` is defined in `skills/sync/CLI.md`. The shell expands the routine glob. If no routine file matches, omit that argument. Do not pass the glob as a literal path. It opens `rules/<me>/add-bot-<bot>`. It checks that `host.sh whoami` matches the `github:` field of the person page for `me`. The bot slug is not a person, so do not run propose on the bot box after `box=yes` has replaced `me`. Run propose first, from the admin computer. The script prints this command as `propose:`.

## git-credential-os-bot

```
git-credential-os-bot get
```

Git credential helper protocol. `get` only. `store` and `erase` do nothing and exit 0, so git does not fail. Any other operation exits 1.

It answers only when the request protocol and host match the company host URL. GitHub with an empty host URL is https and github.com. Any other request prints nothing and exits 0. If the request includes a path, that path must name a repo in this bot's grant list. The bots switch must be on. With the switch off, it prints nothing, refreshes nothing, and writes nothing. OS_BOT and the company root must already be set. It does not guess the bot from a me file.

It calls `host.sh get-token --bot <bot>`. It caches the token and its expiry under `<config>/<slug>-os/bots/<bot>/token-cache` (mode 0600). It refreshes when under 5 minutes remain. If `OS_BOT_TOKEN_TTL` is under 5 minutes, it refreshes only at expiry, so a short test token can be reused and then refreshed. Default life is 3600 seconds. `OS_NOW` is an epoch second that fakes the clock. `OS_BOT_TOKEN_TRACE`, when set to a path, receives the word `cache` or `refresh` and never the token.

The password line is the git protocol. It is not a log. The script never writes the token anywhere else.

## run.sh

```
run.sh <bot> <routine> [--root <dir>]
run.sh --help
```

Refuses when `bots` is off.

The routine file is `bots/<bot>/routines/<routine>.md`. Optional frontmatter:

| Key | Meaning |
|---|---|
| `inbox` | inbox to read. `none` or absent means no read |
| `handoff` | cloud target name. `none` or absent means local work |

`shared_inbox` in `BOT.md` is the only allow list. `none` allows no inbox. A read that is not named is refused. Each read, and each refusal, is one line in `bots/<bot>/logs/YYYY-MM-DD.md`. The line has the time, the run id, and the inbox name. It has no message text.

A hand-off is refused when `cloud-handoff` is off. When the switch is on, v1 still does not call a cloud agent. It refuses with the rule: pull request only, never merge. There is no cloud client in this version.

The script makes a `Run-Id` of `YYYYMMDD-HHMMSS` plus 8 hex characters. `OS_NOW` fakes the clock. It runs the engine with the routine body on stdin, in `bots/<bot>/`. The engine is `engine` in `BOT.md`, else `OS_SYNC_ENGINE`, else `sync_engine`. Every `git commit` the engine makes gets trailers `Run-Id: <id>` and `Bot-Owner: <owner-slug>`.

Before the engine, each granted local repo must be clean. Untracked files count as dirty. A dirty tree is refused. The branch `sync/<bot>` is then taken from `origin/main`. The git wrapper allows a push only to `sync/<bot>` or `undo/*`. It refuses `merge`, `pull`, and `rebase` while on `main`. After the engine, the script runs `skills/sync/sync.sh push` with `OS_BOT` set. That push sends the commits already on `sync/<bot>`. It does not commit them again. It owns the standing pull request and auto-merge. This script does not open that pull request itself.

Exit codes: `0` ok, `1` usage, `2` refused, `3` engine, sync, or hand-off caller missing.

## Conflict

`undo-run.sh` reverts each repo in a temporary worktree. It does not touch the live checkout. If a revert conflicts, it removes that worktree, stops for that repo, and changes nothing there. It prints `conflict:` and continues with the other repos. Exit 3 means at least one repo conflicted. Repos that reverted still have their pull requests.

## undo-run.sh

```
undo-run.sh <run-id> [--root <dir>]
undo-run.sh --help
```

Refuses when `bots` is off.

It fetches `origin/main` in the company repo and in each `areas/*` repo. It finds commits whose exact `Run-Id` trailer matches and whose author email is the bot email on a bot page. A copied trailer line on someone else's commit is not enough. Trailers are not proof. The pull request is the check. Per repo, it makes one revert commit on branch `undo/<run-id>` in a temporary worktree, pushes that branch, and asks for auto-merge. It prints every reverted SHA. The live checkout is not changed. The revert commit does not reuse the original `Run-Id`. Its message has `Reverts:`.

It prints the repo, the reverted commit ids, the revert commit, and the pull request URL. It does not print a diff.

The push token comes from `host.sh get-token` (`--bot` when `OS_BOT` is set). It is passed to git through an environment variable and a password helper script, never through the remote URL or an argument.

## BOT.md frontmatter

`host.sh get-token` reads `app_id`, `installation_id`, `key_path`, and `token_path`. Empty GitHub keys are omitted until the App exists. `token_path` may be omitted on Forgejo; the host then uses `<config>/<slug>-os/bots/<bot>/token`.

```yaml
---
type: bot
summary: ""
updated: YYYY-MM-DD
name: ""                  # display name
bot: ""                   # slug
kind: company             # company | area
owner: ""                 # person slug. Trailer Bot-Owner uses this
area: ""                  # area slug, or empty
bot_user: ""              # host login
app_id: ""                # GitHub App id. Omit until the App exists
installation_id: ""       # GitHub installation id. Omit until install
key_path: ""              # GitHub private key path, outside the repo. Omit until saved
token_path: ""            # Forgejo token file path, outside the repo. Omit to use the default path
repos:                    # repo short names this bot may write
  - acme-os
repo_scope:               # repo=company or repo=area-slug, one per line
  - acme-os=company
routines:                 # routine slugs
  - daily-notes
allowed_connections: none # none, or a list
shared_inbox: none        # none, or a list of shared inbox names
engine: ""                # optional engine command. Omit to use sync_engine
cloud_handoff: ""         # one-line rule. The body has the full rule
---
```

`shared_inbox` default is `none`. Change the line to revoke a share. The next run follows the file.

`cloud_handoff` is the one-line rule: a hand-off opens a pull request and never merges, and it runs only when the company switch `cloud-handoff` is on.

The body holds the persona, the routines, the allowed connections, the shared inbox rule, and the hand-off rule. Vendor memory holds pointers only.
