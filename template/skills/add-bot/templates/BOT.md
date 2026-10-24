---
type: bot
name: <bot>
owner: <owner-slug>
kind: company              # company | area
area: ""                   # area slug for an area bot; empty for the company bot
host: github               # github | forgejo
app_id: ""                 # GitHub only. Not a secret.
installation_id: ""        # GitHub only. Not a secret.
key_path: ""               # GitHub only. Location of the key file on the bot's box, outside every repo. Never the key.
token_path: ""             # Forgejo only. Location of the bot user's token file. Never the token.
repos: []                  # the only repos the bot may read and write
routines: []               # one line each: when, and what
connections: []            # tools the bot may use
shared_inbox: none         # none, or one inbox shared on purpose (see below)
cloud_handoff: off         # off | on. Works only when cloud-handoff is in switches.
updated: <YYYY-MM-DD>
---

# <bot>

This file is a rules file. Change it only by `skills/sync/sync.sh propose`. The owner approves.

## Persona

<!-- Who the bot is and how it writes, in two to four lines. Example: "The Acme Co office bot. Files the shared inbox and keeps meeting notes tidy. Short, plain notes. Never chats with customers." -->

## Routines

<!-- One line per routine: when it runs, what it does, which repo it writes. Each run gets a Run-Id. Every commit carries "Run-Id:" and "Bot-Owner:" lines. -->

## Allowed connections

<!-- The tools the bot may use, one per line, read or write. Shared mailboxes and public channels only. Never a person's private mailbox or DMs, except a shared inbox below. -->

## Shared inbox

Default: `shared_inbox: none`. The bot reads no person's mailbox or DMs.

An inbox may be shared with the bot on purpose: by the person who owns it (for that person's own bot), or as a role inbox (for a team bot).
- **Visible.** The share is the `shared_inbox:` line in this file.
- **Revocable.** Set it back to `none` by `propose`. The bot stops reading at its next run.
- **Logged.** Each read is one line in `logs/`.
- **Anyone who can ask the bot may see what it finds there.** Say this to the person before they share.
- The bot treats the inbox as a private source. Only plain facts go to areas: no quotes, no "X wrote in an email".

## Hand-off to cloud agents

Only when `cloud-handoff` is in `switches:` in `company-profile.md` and `cloud_handoff: on` here. Otherwise the bot refuses every hand-off.
- The target is turned on for this company and is the better tool for the task.
- It works only on repos in `repos:` above.
- It opens a pull request. It never merges.
- Health data only if the target is covered for it.
- The bot checks the result and tells its owner.

## Owner

The owner gets this bot's flags and approves changes to this file. When the owner leaves, the bot keeps running. The new owner is the leaving owner's manager, else the admin. Until then, flags go to the admin.
