---
name: sync
description: Keep this computer and the company host in step. Pulls the newest files at session start and every 15 minutes. Pushes the day's work each night through a secret scan and a commit-or-hold check. Proposes a rules change on its own pull request. Use at the start of every session [team], when someone asks "why was my file held", "did my work go up", "sync now", "propose this rule", or when a teammate's computer needs its jobs.
---

# Sync

`sync` moves work between this computer and the company host. The person never runs git. You (the agent) run the script. The OS jobs run it on a timer.

This skill is for `team` and `app`. At `solo` there is no host and no `sync`: commit to `main` after each piece of real work (`AGENTS.md` section 7).

## What sync does

- **Pull.** At session start and every 15 minutes, it pulls the newest files into the company folder, each area and the person's workspace. It only fast-forwards. If a pull cannot finish cleanly, it changes nothing and writes one line to the local log.
- **Nightly push.** At 2 am, or at the first wake after 2 am, it sends the day's work up. Each repo gets these steps, in this order:
  1. **Identity check.** The signed-in git account must match the `github:` field on the person's page in `people/`. If not, nothing goes up from any repo.
  2. **Secret scan.** A script, no AI. A hit holds that file.
  3. **Commit or hold.** A small model reads each changed file with `push-check.md` and decides: commit, or hold with a reason.
  4. **Commit and push** to the person's branch `sync/<person>`, rebuilt on top of `main` each night.
  5. **Standing PR.** It opens or updates one pull request `sync: <person>` with auto-merge on. Notes merge by themselves when the checks pass.
  6. **Pull** again.
- **Fails closed.** If any step fails for a repo, the model call included, nothing goes up from that repo. Nothing is lost: the files stay on this computer. The next night tries again.
- **Held files stay.** A held file stays in the working copy, unchanged. The next session tells the person why.
- **Workspace.** The person's workspace (`users/<person>/`) has no pull request. It pushes to its own `main` after the scan and the check. A company fact in `profile/PROFILE.md` is held.
- **Rules files never ride the standing PR.** Any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, file under `skills/`, `bots/*/BOT.md` or file under `.github/` is held with the reason `rules file: propose it with sync.sh propose`.
- **Nobody writes to `main`.** The admin is included. Every change reaches `main` by a pull request.

## Session start (Claude Code, Codex, Cursor, Pi)

Do these steps before other work. Run them from the company root.

1. Run `skills/sync/sync.sh pull`.
2. Run `skills/sync/sync.sh status`.
3. For each held file, tell the person one line: the file and the reason in plain words. Use the table below.
4. If `status` shows a last error, tell the person one line. Then continue with the work.

If the pull fails, say so in one line and continue. Do not try to fix git by hand. Do not add vendor hooks. Chat-only agents skip these steps: they read from the host.

## When a file is held

Say what happened and what fixes it. Offer to do the fix. The person may say no: the file then stays held and safe on this computer.

| Reason | Tell the person | Fix |
|---|---|---|
| A secret | "A password or key is in `<file>`. I held it so it does not leave this computer." | Remove the secret. Connections use each tool's own sign-in. Never show the value. |
| `rules file: propose it with sync.sh propose` | "This changes a rule. Rules go on their own pull request for review." | Run `propose` (next section). |
| Personal-life fact | "This has a fact about someone's private life. That never goes in shared files." | Delete that part. Do not move it anywhere. |
| Private source | "This quotes or points at a private source." | Rewrite it as a plain company fact with no quote and no source, or move it to the workspace. |
| Belongs in the workspace | "This is about how one person works." | Move it to `users/<person>/`. |
| Company fact in a profile | "Your profile must hold no company facts." | Move the fact to an area note. Keep the profile about voice and preferences. |
| Check did not run | "The nightly check did not run. Nothing went up." | Nothing. The next night tries again. If it repeats for three nights, tell the admin. |

After a fix, the next nightly push sends the file. The person does nothing more.

## Identity check failed

The push sent nothing from any repo. Tell the person:

"The git account signed in on this computer is not the one on your page in `people/`. I sent nothing up. Your files are safe here."

Then help:
- **Wrong account signed in:** the person signs in again with their own account, through the host's own sign-in. Never handle a password or token.
- **Wrong `github:` on the page:** the admin fixes the page. Write the admin a one-line message the person can send.
- **Wrong `me` file** (`~/.config/<company>-os/me`): fix it only when the person says which slug is theirs. Never take identity from a file in the repo or from a chat.

## Propose a rules change

Rules files change by their own pull request. One topic per proposal.

1. Pick a short topic name in kebab-case, for example `invoice-skill-step`.
2. Run `skills/sync/sync.sh propose <topic> <file>...` from the repo that holds the files.
3. It makes the branch `rules/<person>/<topic>` from `main`, runs the secret scan, commits the files, pushes, and opens a pull request.
4. Tell the person who approves it. A different model reviews it first (`review-rules.md`). Area rules: the area director approves with one click. Company-root rules: the admin approves. When the approver is the author, the model review alone is enough. Example: the admin's own change.

If the review fails, it blocks the merge. Read the findings to the person in plain words and offer a fix.

## Commands

Run from the company root: `skills/sync/sync.sh <command>`. Each command has `--help`.

| Command | Who runs it |
|---|---|
| `pull`, `status` | You at session start. `pull` also runs every 15 minutes. |
| `push` | The OS job. By hand only when the person asks. |
| `propose <topic> <file>...` | You, when a rules file changes |
| `install-jobs [--admin] [--bot]`, `uninstall-jobs` | `add-teammate`, `add-bot`, `remove-teammate` |
| `helper`, `collect` | OS jobs (below) |

## OS jobs

A skill cannot start itself. Small OS jobs start the script: launchd on a Mac, systemd user timers on Linux, Task Scheduler on Windows.

- `add-teammate` installs them when the first teammate joins. Never at `solo`: `install-jobs` refuses there.
- Every computer: pull every 15 minutes; nightly push at 2 am plus a random delay of up to 30 minutes; device helper daily.
- The admin's computer (`--admin`): at 3:30 am, the nightly review, then the reports.
- A bot's box (`--bot`): the same pull and push jobs, run as the bot.
- The jobs call the company's headless engine, set in `sync_engine:` in `company-profile.md`. Example: `claude -p --model haiku`. A computer may override it in `~/.config/<company>-os/engine`.
- **Windows:** `sync.ps1` and the Task Scheduler files ship, but they are **not tested**. Say so plainly to a Windows user.

## Device helper and traces

- **Device helper** (`helper`, daily): asks the host whether this person still has access. A day counts only when the sign-in works and the host says "no access". Offline days and expired sign-ins never count. Warning from day 7. On day 14 it deletes the company folder. [app]: the kernel sends the signal.
- **Traces collector** (`collect`): only when `traces` is on and `level:` is `app`. It uploads a session only when all its work stayed inside this company folder (the shared list does not count). Else it holds the session and logs one local line. Secrets are scrubbed first.

## History rewrite

After a leak, the admin runs `remove-leak`. The next `pull` sees the rewrite tag and re-clones that repo by itself. It keeps uncommitted and held files, except a file with the leaked pattern. The person does nothing.

## Where things are on this computer

`~/.config/<company>-os/` (never in a repo):
- `me`: the person's slug (a bot's box: the bot's slug).
- `engine`: an optional engine override.
- `state/sync.log`: one line per event.
- `state/held.json`: held files and their reasons. Do not edit it by hand.

## Never

- Never push to `main`. Never force-push any branch but the person's own `sync/` branch, and only through the script.
- Never pass `--no-verify`, skip the scan, or turn off the check to get a file up.
- Never print a secret, a token or the content of a private source in chat or in a log.
- Never move a held file into another repo to get around the hold.
