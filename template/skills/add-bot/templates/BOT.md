---
type: bot
summary: ""
updated: YYYY-MM-DD
name: ""                  # display name
bot: ""                   # slug. Folder name under bots/
kind: company             # company | area
owner: ""                 # person slug. The Bot-Owner trailer uses this
area: ""                  # area slug, or empty for the company bot
bot_user: ""              # host login
email: ""                 # the bot's own git author email. undo-run matches it. Never a person's
app_id: ""                # GitHub App id. Not a secret. Omit until the App exists
installation_id: ""       # GitHub installation id. Omit until install
key_path: ""              # GitHub key file LOCATION, outside every repo. Never the key
token_path: ""            # Forgejo token file LOCATION, outside every repo. Never the token
repos: []                 # repo short names this bot may write. No more
repo_scope: []            # repo=company or repo=<area slug>. Set from the repo name only
routines: []              # routine slugs. Each is bots/<bot>/routines/<slug>.md
allowed_connections: none # none, or a list of tools
shared_inbox: none        # none, or a list of inboxes shared on purpose
engine: ""                # optional engine command. Empty: sync_engine
cloud_handoff: "PR only, never merge; only when the cloud-handoff switch is on"
---

# About this bot

This file is a rules file. Change it only by `skills/sync/sync.sh propose`. The owner approves after the model review.

## Persona

<!-- Who the bot is and how it writes, in two to four lines. Example: "The Acme Co office bot. Files the shared inbox and keeps meeting notes tidy. Short, plain notes. Never writes to customers." -->

## Routines

Each routine is one file: `routines/<slug>.md`. Its body is the prompt the bot runs. A schedule starts it. No person starts it.

<!-- One line per routine: when it runs, what it does, which repo it writes. -->

Every run has a `Run-Id`. Every commit of the run carries `Run-Id:` and `Bot-Owner:` lines. A run starts only on a clean working copy. The bot pushes only to `sync/<bot>` and `undo/*`, never to `main`. The `undo-run` skill undoes a whole run in one step.

## Allowed connections

The bot uses only the tools in `allowed_connections:`. Shared mailboxes and public channels only. Never a person's private mailbox or DMs, except a shared inbox below.

<!-- One line per tool: read or write, and what for. -->

## Shared inbox

Default: `shared_inbox: none`. The bot reads no person's mailbox or DMs.

An inbox may be shared with the bot on purpose: by the person who owns it (for that person's own bot), or as a role inbox (for a team bot).
- **Visible.** The share is the `shared_inbox:` line in this file.
- **Revocable.** Set it back to `none` by `propose`. The next run follows the file.
- **Logged.** Each read, and each refused read, is one line in `logs/`: the time, the run id and the inbox name. Never the message text.
- **Anyone who can ask the bot may see what it finds there.** Say this to the person before they share.
- The bot treats the inbox as a private source. Only plain facts go to areas: no quotes, no "X wrote in an email".

## Hand-off to cloud agents

A hand-off needs the `cloud-handoff` switch in `company-profile.md`. With the switch off, the bot refuses every hand-off. In this version the bot refuses every hand-off: no cloud agent is connected yet. When one is, these rules apply:
- The target is turned on for this company and is the better tool for the task.
- It works only on repos in `repos:` above.
- It opens a pull request. It never merges.
- Health data only if the target is covered for it.
- The bot checks the result and tells its owner.

## Owner

The owner gets this bot's flags and approves changes to this file. When the owner leaves, the bot keeps running. The new owner is the leaving owner's manager, else the admin. Until then, flags go to the admin.
