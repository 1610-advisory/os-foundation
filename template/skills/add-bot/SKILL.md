---
name: add-bot
description: Add a bot to the company OS. A bot is an agent that runs on a schedule with no person, under its own identity, on its own box. Makes the identity, grants it only its repos, writes bots/<bot>/BOT.md, and installs its jobs. Use when someone says "add a bot", "make a company bot", "run this every night by itself", "give the area its own bot", or "who owns this bot now".
---

# Add a bot

A person starts a task: their own agent does it. A schedule starts a task with no person: a bot does it.

Read `level:` and `switches:` in `company-profile.md` first. This skill works only when `bots` is in `switches:`. If it is not, say so and stop. The scripts refuse too. Only the admin turns the switch on.

## What a bot is

- **One bot, one identity.** On GitHub: one GitHub App per bot. On Forgejo: one bot user. Never a person's account or token.
- **Its own box.** A computer or server that runs the bot. The bot's key stays on that box, outside every repo.
- **Only its repos.** The bot gets the repos it needs, and no more. Its grants never exceed its owner's. The script refuses a grant above the owner.
- **A company-owned vendor account.** The bot's engine runs on an account the company owns, never on a person's own account. So the bot keeps running when a person leaves.
- **A folder unit.** `bots/<bot>/BOT.md` (persona, routines, allowed connections), plus `routines/`, `skills/` and `logs/`. Vendor memory holds pointers only.

## Who owns it

| Kind | Owner | May grant |
|---|---|---|
| Company bot (one by default) | The admin | The company repo and any area |
| Area bot (only when the area needs one) | The area director | Only that area's repos, within the director's own access |

The owner gets the bot's flags and approves changes to its `BOT.md`.

## Steps

Ask one question at a time. Write each answer as one `key=value` line in an answers file outside the repo. Never put a key or token in it: only file locations.

1. **Kind** (`kind=company` or `kind=area`). For an area bot, the area (`area=`).
2. **Name.** Short, lowercase, kebab-case (`bot=acme-bot`). A display name is optional (`name=`).
3. **Owner** (`owner=`): the admin for a company bot, the director for an area bot.
4. **Email** (`email=`): the bot's own git author email, never a person's. `undo-run` uses it to find the bot's commits.
5. **Repos** (`repos=`, comma list of repo short names). Suggest the fewest. The scope comes from the name only: `<company>-os` is the company repo, `<company>-<area>` is that area. Any other name is refused. The owner must have access to each one.
6. **Routines** (`routines=`, comma list of slugs). For each, write `bots/<bot>/routines/<slug>.md`: when it runs, and the prompt. Example: "Each weekday at 6 am, file the shared inbox."
7. **Allowed connections** (`connections=`, or `none`). Shared mailboxes and public channels only.
8. **Shared inbox** (`inbox=`, default `none`). Only with the inbox owner's yes. See below.

**On the admin computer, where `me` is the admin:**

9. **First run:** `skills/add-bot/add-bot.sh --answers <file>` (`box=no`). It writes `bots/<bot>/`.
   - **GitHub:** it prints `create_url:` and `status: waiting-for-app`. Open the link in any browser and click **Create GitHub App**. Install the App on the listed repos only ("Only select repositories"). Save the key file **on the bot's box**, outside every repo, mode 0600.
   - **Forgejo:** first the admin makes one bot user and saves its token in a file outside every repo, mode 0600. Add `bot_user=` and `token_path=` to the answers. The run grants that user the listed repos and prints `status: ready`. Later, the admin moves the token file to the bot's box at the same path.
10. **Propose the folder** before any `box=yes` run. The script prints the command as `propose:`. Run it with the routine files written out, one path each: `skills/sync/sync.sh propose add-bot-<bot> bots/<bot>/BOT.md bots/<bot>/routines/<slug>.md`. No routine files: leave that part out. Never pass a literal `*`. `BOT.md` and the routines are rules files. The owner approves after the model review.

**On the bot's box** (never a person's own computer; the owner signs in for setup only):

11. **Box run:** add `box=yes` and `replace_me=yes` to the answers. GitHub: also `app_id=`, `installation_id=` and `key_path=`. Run the script. It prints `status: ready` and `jobs: installed`. It sets the bot as `me`, points git at the bot's credential helper, and installs the OS jobs (`sync.sh install-jobs --bot`). It records the key **location**, never the key.
12. If it prints `propose-note:`, do not run `propose` on this box: `me` is now the bot.
13. **GitHub only:** the App fields are now in `BOT.md` on the box. They are not secrets. The admin adds the same three lines to `BOT.md` on the admin computer, where `me` is the admin, and proposes it. The owner approves.
14. **Sign the owner out** of the host on the box. Then **tell the owner** in plain words: the bot's name, its repos, its routines, and where its logs are.

**When the script stops.** Tell the person its last line exactly. Examples: `email is required`, `bots switch is off`, `repo <repo> exceeds the owner's grant`, `an area bot cannot take the company repo`, `secret file is missing`, `secret file mode is not 0600`, `me file is <slug>, not <bot>. Set replace_me=yes on the bot box only.` Fix the answers file at most once and run again. If it stops again, stop and tell the owner. Never ask for a key or token in chat. If `propose` fails, tell the person its line and stop.

After setup, no person step is needed. The bot's credential helper gets a fresh short-lived token each time git needs one, only for the company host and the bot's repos.

**Change the repos later:** the owner changes `repos:` in `BOT.md` on their own computer and proposes it. After it merges, the owner signs in on the box for one step: update `repos=` in the answers and run the script again. It prints `granted:` and `revoked:` lines. Then the owner signs out.

## Every bot run

- The OS job runs `skills/add-bot/run.sh <bot> <routine>`.
- Each run gets a `Run-Id`. Every commit of the run carries `Run-Id: <id>` and `Bot-Owner: <owner>`.
- A run starts only when every repo it writes is clean. A file left over from an earlier run stops the next run: find out why before you remove it.
- The bot works on its own `sync/<bot>` branch, taken fresh from `main`. It may push only to `sync/<bot>` and `undo/*`. It never merges, pulls or rebases on `main`.
- `sync.sh push` sends its work up on the bot's standing PR, like a person's notes.
- The bot follows the same tiers as a person (`AGENTS.md` section 6). Its rules changes go by `propose`.
- To undo a whole run in one step: the `undo-run` skill.

## Shared inbox

A bot never reads a person's private mailbox or DMs, except an inbox shared with it on purpose.
- Who may share: the person who owns the inbox (for that person's own bot), or the team (a role inbox, for a team bot).
- How: name the inbox in `shared_inbox:` in `BOT.md`, by `propose`. The default is `none`. A routine reads an inbox only when `BOT.md` names it.
- It is visible (in `BOT.md`), revocable (set it back to `none`), and logged (each read is a line in `bots/<bot>/logs/`, never the message text).
- Before the share, tell the person plainly: **anyone who can ask the bot may see what it finds there.**
- The bot treats the inbox as a private source (`AGENTS.md` section 4). Only plain facts go to areas.

## Hand-off to cloud agents

A hand-off needs the `cloud-handoff` switch. With it off, the bot refuses every hand-off. In this version the bot refuses every hand-off anyway: no cloud agent is connected yet. The rules for later are in `BOT.md`: the target is turned on and is the better tool; only repos inside the bot's grant; a pull request, never a merge; the bot checks the result and tells its owner.

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
