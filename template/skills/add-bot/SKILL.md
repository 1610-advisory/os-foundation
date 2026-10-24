---
name: add-bot
description: Add a bot to the company OS. A bot is an agent that runs on a schedule with no person, under its own identity, on its own box. Makes the identity, grants it only its repos, writes bots/<bot>/BOT.md, and installs its jobs. Use when someone says "add a bot", "make a company bot", "run this every night by itself", "give the area its own bot", or "who owns this bot now".
---

# Add a bot

A person starts a task: their own agent does it. A schedule starts a task with no person: a bot does it.

Read `level:` and `switches:` in `company-profile.md` first. This skill works only when `bots` is in `switches:`. If it is not, say so and stop. Only the admin turns the switch on.

## What a bot is

- **One bot, one identity.** On GitHub: one GitHub App per bot. On Forgejo: one bot user. Never a person's account or token.
- **Its own box.** A computer or server that runs the bot. The bot's key stays on that box, outside every repo.
- **Only its repos.** The bot is installed on the repos it needs, and no more. Its grants never exceed its owner's.
- **A company-owned vendor account.** The bot's engine runs on an account the company owns, never on a person's own account. So the bot keeps running when a person leaves.
- **A folder unit.** `bots/<bot>/BOT.md` (persona, routines, allowed connections), plus `skills/` and `logs/`. Vendor memory holds pointers only.

## Who owns it

| Kind | Owner | Runs this skill |
|---|---|---|
| Company bot (one by default) | The admin | The admin |
| Area bot (only when the area needs one) | The area director | The director |

The owner gets the bot's flags and reports. The owner approves changes to its `BOT.md`.

## Steps

Ask one question at a time. Write the answers to a file. Never put a key or token in it.

1. **Name.** Short, lowercase, kebab-case. Example: `acme-bot`.
2. **Kind.** Company or area. For an area bot, which area.
3. **Repos.** Which repos the bot may read and write. Suggest the fewest. Check that the owner has access to each one.
4. **Routines.** What it does and when. One line each. Example: "Each weekday at 6 am, file the shared inbox."
5. **Allowed connections.** Which tools it may use. Shared mailboxes and public channels only. Never a person's private mailbox or DMs, unless that person shares it on purpose (below).
6. **Box.** Which computer runs it. The company folder must be cloned there, signed in to the bot's company-owned engine account.
7. **Run the script** on the bot's box: `skills/add-bot/add-bot.sh --answers <file>`.
8. **Make the identity.**
   - **GitHub:** the script prints one link. The owner opens it and clicks **Create GitHub App**. Then they install the App on the listed repos only (choose "Only select repositories"). They save the downloaded key file at the path the script prints. That path is outside every repo. The script records the App id, the install id and the key **path** in `BOT.md`. Never the key.
   - **Forgejo:** the admin makes one bot user and its token file at the path the script prints. The script grants the bot only the listed repos.
9. **Propose `BOT.md`.** It is a rules file. Run `skills/sync/sync.sh propose add-bot-<bot> bots/<bot>/BOT.md`. The owner approves it after the model review.
10. **Jobs.** The script installs the box's OS jobs (`sync.sh install-jobs --bot`). The bot pulls and pushes like a person, on its own `sync/<bot>` branch and standing PR.
11. **Tell the owner** in plain words: the bot's name, its repos, its routines, and where its logs are.

After setup, no person step is needed. The bot gets a fresh short-lived token each time git needs one, by its own credential helper.

## Every bot run

- Each run has a `Run-Id`. Every commit of the run carries two lines: `Run-Id: <id>` and `Bot-Owner: <owner>`.
- The bot follows the same tiers as a person (`AGENTS.md` section 6). Its notes go on its standing PR. Its rules changes go by `propose`.
- The bot writes one log line per run in `bots/<bot>/logs/`.
- To undo a whole run in one step: the `undo-run` skill.

## Shared inbox

A bot never reads a person's private mailbox or DMs, except an inbox shared with it on purpose.
- Who may share: the person who owns the inbox (for that person's own bot), or the team (a role inbox, for a team bot).
- How: name the inbox in `shared_inbox:` in `BOT.md`, by `propose`. The default is `none`.
- It is visible (in `BOT.md`), revocable (set it back to `none`), and logged (each read is a line in `bots/<bot>/logs/`).
- Before the share, tell the person plainly: **anyone who can ask the bot may see what it finds there.**
- The bot treats the inbox as a private source (`AGENTS.md` section 4). Only plain facts go to areas.

## Hand-off to cloud agents

Only when `cloud-handoff` is in `switches:`. Then a bot may hand a task to another agent the company has turned on (a cloud coding agent or another bot). Rules:
- The target is the better tool for the task.
- It works only on repos inside the bot's grant.
- It opens a pull request. It never merges.
- The bot checks the result and tells its owner.
- Health data only if the target is covered for it.

With the switch off, the bot refuses every hand-off.

## When the owner leaves

The bot keeps running. Bots are company infrastructure.
- `remove-teammate` names a new owner: the leaving owner's manager, else the admin.
- Until the new owner is set, the bot's flags go to the admin.
- Change `owner:` in `BOT.md` by `propose`. The bot's identity does not change: it was never the person's.

## Never

- Never use a person's token, account or sign-in for a bot.
- Never put a key or token in a repo, a prompt, a log or chat. Write the **location** only.
- Never install the bot on all repos. Never grant more than the owner has.
- Never let a bot merge its own rules change, or merge a hand-off.
