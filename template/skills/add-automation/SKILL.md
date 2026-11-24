---
name: add-automation
description: Add an automation to the company OS. An automation is a company agent that runs on a schedule with no person, under its own identity, on its own box. Makes the identity, grants it only its repos, writes automations/<automation>/AUTOMATION.md, and installs its jobs. Use when someone says "add an automation", "add a scheduled agent", "make a company automation", "run this every night by itself", "give the area its own automation", or "who owns this automation now". Not for a person's own bots in their workspace.
---

# Add an automation

A person starts a task: their own agent does it. A schedule starts a task with no person: an automation does it.

Read `level:` and `switches:` in `company-profile.md` first. This skill works only when `automations` is in `switches:`. If it is not, say so and stop. The scripts refuse too. Only the admin turns the switch on.

## What an automation is

- **One automation, one identity.** On GitHub: one GitHub App per automation. On Forgejo: one machine user. Never a person's account or token.
- **Its own box.** A computer or server that runs the automation. The automation's key stays on that box, outside every repo.
- **Only its repos.** The automation gets the repos it needs, and no more. Its grants never exceed its owner's. The script refuses a grant above the owner.
- **A company-owned vendor account.** The automation's engine runs on an account the company owns, never on a person's own account. So the automation keeps running when a person leaves.
- **A folder unit.** `automations/<automation>/AUTOMATION.md` (persona, routines, allowed connections), plus `routines/`, `skills/` and `logs/`. Vendor memory holds pointers only.

## Who owns it

| Kind | Owner | May grant |
|---|---|---|
| Company automation (one by default) | The admin | The company repo and any area |
| Area automation (only when the area needs one) | The area director | Only that area's repos, within the director's own access |

The owner gets the automation's flags and approves changes to its `AUTOMATION.md`.

## Steps

Ask one question at a time. Write each answer as one `key=value` line in an answers file outside the repo. Never put a key or token in it: only file locations.

1. **Kind** (`kind=company` or `kind=area`). For an area automation, the area (`area=`).
2. **Name.** Short, lowercase, kebab-case (`automation=acme-inbox`). A display name is optional (`name=`).
3. **Owner** (`owner=`): the admin for a company automation, the director for an area automation.
4. **Email** (`email=`): the automation's own git author email, never a person's. `undo-run` uses it to find the automation's commits.
5. **Repos** (`repos=`, comma list of repo short names). Suggest the fewest. The scope comes from the name only: `<company>-os` is the company repo, `<company>-<area>` is that area. Any other name is refused. The owner must have access to each one.
6. **Routines** (`routines=`, comma list of slugs). For each, write `automations/<automation>/routines/<slug>.md`: when it runs, and the prompt. Example: "Each weekday at 6 am, file the shared inbox."
7. **Allowed connections** (`connections=`, or `none`). Shared mailboxes and public channels only.
8. **Shared inbox** (`inbox=`, default `none`). Only with the inbox owner's yes. See below.

**On the admin computer, where `me` is the admin:**

9. **First run:** `skills/add-automation/add-automation.sh --answers <file>` (`box=no`). It writes `automations/<automation>/`.
   - **GitHub:** it prints `create_url:` and `status: waiting-for-app`. Open the link in any browser and click **Create GitHub App**. Install the App on the listed repos only ("Only select repositories"). Save the key file **on the automation's box**, outside every repo, mode 0600.
   - **Forgejo:** first the admin makes one machine user (a host account, not a person) and saves its token in a file outside every repo, mode 0600. Add `host_user=` and `token_path=` to the answers. The run grants that user the listed repos and prints `status: ready`. Later, the admin moves the token file to the automation's box at the same path.
10. **Propose the folder** before any `box=yes` run. The script prints the command as `propose:`. Run it with the routine files written out, one path each: `skills/sync/sync.sh propose add-automation-<automation> automations/<automation>/AUTOMATION.md automations/<automation>/routines/<slug>.md`. No routine files: leave that part out. Never pass a literal `*`. `AUTOMATION.md` and the routines are rules files. The owner approves after the model review.

**On the automation's box** (never a person's own computer; the owner signs in for setup only):

11. **Box run:** add `box=yes` and `replace_me=yes` to the answers. GitHub: also `app_id=`, `installation_id=` and `key_path=`. Run the script. It prints `status: ready` and `jobs: installed`. It sets the automation as `me`, points git at the automation's credential helper, and installs the OS jobs (`sync.sh install-jobs --automation`). It records the key **location**, never the key.
12. If it prints `propose-note:`, do not run `propose` on this box: `me` is now the automation.
13. **GitHub only:** the App fields are now in `AUTOMATION.md` on the box. They are not secrets. The admin adds the same three lines to `AUTOMATION.md` on the admin computer, where `me` is the admin, and proposes it. The owner approves.
14. **Sign the owner out** of the host on the box. Then **tell the owner** in plain words: the automation's name, its repos, its routines, and where its logs are.

**When the script stops.** Tell the person its last line exactly. Examples: `email is required`, `automations switch is off`, `repo <repo> exceeds the owner's grant`, `secret file is missing`, `me file is <slug>, not <automation>. Set replace_me=yes on the automation box only.` Fix the answers file at most once and run again. If it stops again, stop and tell the owner. Never ask for a key or token in chat. If `propose` stops, tell the person its line exactly and follow the `sync` skill (Propose a rules change).

After setup, no person step is needed. The automation's credential helper gets a fresh short-lived token each time git needs one, only for the company host and the automation's repos.

**Change the repos later:** the owner changes `repos:` in `AUTOMATION.md` on their own computer and proposes it. After it merges, the owner signs in on the box for one step: update `repos=` in the answers and run the script again. It prints `granted:` and `revoked:` lines. Then the owner signs out.

## Every automation run

- The OS job runs `skills/add-automation/run.sh <automation> <routine>`.
- Each run gets a `Run-Id`. Every commit of the run carries `Run-Id: <id>` and `Automation-Owner: <owner>`.
- A run starts only when every repo it writes is clean. A file left over from an earlier run stops the next run: find out why before you remove it.
- The automation never works in the folder itself. `run.sh` takes any folder (`--root`), a person's too, so each run gets a temporary worktree of each repo in its scope, on its own `sync/<automation>` branch. The folder stays on `main`, so its pull and push go on. A change the run did not commit goes with the worktree (`not committed: <n> files in <repo> ...`).
- `sync/<automation>` starts from the last run's commits when they never reached the host (offline, a failed push): they are never reset. Else from the host's `sync/<automation>` while its pull request has not merged. Else from `main`. It may push only to `sync/<automation>` and `undo/*`. It never merges, pulls or rebases on `main`.
- The run's log (`automations/<automation>/logs/<day>.md`: inbox reads) is committed on `sync/<automation>` with the run.
- `sync.sh push` sends its work up on the automation's standing PR, like a person's notes.
- The automation follows the same tiers as a person (`AGENTS.md` section 6). Its rules changes go by `propose`.
- To undo a whole run in one step: the `undo-run` skill.

## Shared inbox

An automation never reads a person's private mailbox or DMs, except an inbox shared with it on purpose.
- Who may share: the person who owns the inbox (for an automation that person owns), or the team (a role inbox, for a team automation).
- How: name the inbox in `shared_inbox:` in `AUTOMATION.md`, by `propose`. The default is `none`. A routine reads an inbox only when `AUTOMATION.md` names it.
- It is visible (in `AUTOMATION.md`), revocable (set it back to `none`), and logged (each read is a line in `automations/<automation>/logs/`, never the message text).
- Before the share, tell the person plainly: **anyone who can ask the automation may see what it finds there.**
- The automation treats the inbox as a private source (`AGENTS.md` section 4). Only plain facts go to areas.

## Hand-off to cloud agents

A hand-off needs the `cloud-handoff` switch. With it off, the automation refuses every hand-off. In this version the automation refuses every hand-off anyway: no cloud agent is connected yet. The rules for later are in `AUTOMATION.md`: the target is turned on and is the better tool; only repos inside the automation's grant; a pull request, never a merge; the automation checks the result and tells its owner.

## When the owner leaves

The automation keeps running. Automations are company infrastructure.
- `remove-teammate` names a new owner: the leaving owner's manager, else the admin.
- Until the new owner is set, the automation's flags go to the admin.
- Change `owner:` in `AUTOMATION.md` by `propose`. The automation's identity does not change: it was never the person's.

## Never

- Never use a person's token, account or sign-in for an automation.
- Never put a key or token in a repo, a prompt, a log or chat. Write the **location** only.
- Never install the automation on all repos. Never grant more than the owner has.
- Never let an automation merge its own rules change, or merge a hand-off.
