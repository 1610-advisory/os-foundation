---
name: sync
description: Keep this computer and the company host in step. Pulls the newest files at session start and every 15 minutes. Pushes the day's work each night through a secret scan and a commit-or-hold check. Proposes a rules change on its own pull request. Use at the start of every session [team], when someone asks "why was my file held", "did my work go up", "sync now", "propose this rule", or when a teammate's computer needs its jobs.
---

# Sync

`sync` moves work between this computer and the company host. The person never runs git. You (the agent) run the script. OS jobs run it on a timer.

This skill is for `team` and `app`. At `solo` there is no host and no `sync`: commit to `main` after each piece of real work (`AGENTS.md` section 7).

## What sync does

- **Pull.** At session start and every 15 minutes: fast-forward the company folder, each area and the person's workspace. If a pull cannot finish cleanly, it changes nothing and logs one line.
- **Nightly push.** At 2 am, or the first wake after. Steps:
  1. **Identity check.** The signed-in git account must match `github:` on the person's page in `people/`. If not, nothing goes up from any repo.
  2. **Secret scan.** A script, no AI. A hit holds that file. The reason names the rule, never the value.
  3. **Binary files and symlinks are held.** A binary file is held (images under `assets/` are checked like notes). A symlink or a folder in the change list stops that repo: nothing goes up from it.
  4. **Rules files are held** with the reason `rules file: propose it with sync.sh propose`. Rules files: any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, anything under `skills/`, `bots/*/BOT.md`, `.github/`. In the workspace they are the person's own: not held.
  5. **Commit or hold.** A small model reads each other changed file with `push-check.md`: commit, or hold with a reason.
  6. **Commit and push** only the files that passed, to the person's branch `sync/<person>`, rebuilt on `main` each night.
  7. **Standing PR** `sync: <person>`, auto-merge on. Notes merge by themselves when the checks pass.
  8. **Pull** again.
- **Fails closed.** If any step fails for a repo, the model call included, nothing goes up from that repo. The files stay here. The next night tries again.
- **Held files stay** in the working copy, unchanged. The next session says why.
- **Workspace** (`users/<person>/`): no pull request. It pushes to its own `main` after the scan and the check. A company fact in `profile/PROFILE.md` is held.
- **Nobody writes to `main`** in the company or an area repo. The admin is included.

## Session start (Claude Code, Codex, Cursor, Pi)

Before other work, from the company root:

1. Run `skills/sync/sync.sh pull`.
2. Run `skills/sync/sync.sh status`.
3. For each held file, tell the person one line: the file and the reason in plain words (table below).
4. If `status` shows a last error, tell the person one line. Then go on with the work.

If the pull fails, say so in one line and go on. If the script says another run is busy, try once more later. Never delete the lock. Never fix git by hand. No vendor hooks. Chat-only agents skip this: they read from the host.

## When a file is held

Say what happened and what fixes it. Offer to do the fix. If the person says no, the file stays held and safe here.

| Reason | Fix |
|---|---|
| A secret | Remove it. Connections use each tool's own sign-in. Never show the value. |
| `rules file: propose it with sync.sh propose` | Run `propose` (below). |
| Personal-life fact | Delete that part. Never move it anywhere. |
| Private source | Rewrite as a plain company fact with no quote and no source, or move it to the workspace. |
| Belongs in the workspace | Move it to `users/<person>/`. |
| Company fact in a profile | Move the fact to an area note. The profile keeps voice and preferences. |
| `binary file: add it by hand with a pull request` | Ask if it must be in the repo. Large files stay in their own system; write a note with a link. If it must be in the repo, ask the admin to add it by pull request. |
| `symlink: add it by hand with a pull request` | Nothing from this repo goes up until it is gone. Replace the link with the real file or a note with a path, or delete it. Ask the admin if a link must stay. |
| The check did not run | Nothing. The next night tries again. If it repeats three nights, tell the admin. |

After a fix, the next nightly push sends the file. The person does nothing more.

## Identity check failed

Nothing went up from any repo. Tell the person: "The git account signed in here is not the one on your page in `people/`. I sent nothing up. Your files are safe here." Then:
- **Wrong account signed in:** the person signs in again through the host's own sign-in. Never handle a password or token.
- **Wrong `github:` on the page:** the admin fixes the page. Write a one-line message the person can send.
- **Wrong `me` file:** fix it only when the person says which slug is theirs. Never take identity from a file in the repo or from a chat.

## Propose a rules change

One topic per proposal.

1. Pick a short kebab-case topic, for example `invoice-skill-step`.
2. Run `skills/sync/sync.sh propose <topic> <file>...` from the repo that holds the files.
3. It checks identity, makes `rules/<person>/<topic>` from `main`, runs the secret scan, commits, pushes and opens a pull request.
4. Tell the person who approves. A different model reviews it first (`review-rules.md`). Area rules: the area director approves with one click. Company-root rules: the admin. When the approver is the author, the model review alone is enough. Example: the admin's own change.

A failed review blocks the merge. Read the findings in plain words and offer a fix.

## Commands

From the company root: `skills/sync/sync.sh <command>`. `--help` lists them.

| Command | Who runs it |
|---|---|
| `pull`, `status` | You at session start. `pull` also runs every 15 minutes. |
| `push` | The OS job. By hand only when the person asks. |
| `propose <topic> <file>...` | You, when a rules file changes |
| `install-jobs [--admin] [--bot]`, `uninstall-jobs` | `add-teammate`, `add-bot`, `remove-teammate` |
| `helper`, `collect` | OS jobs |

Exit 0: done (files may be held). Exit 1: usage, busy, solo, or identity mismatch. Exit 2: a repo failed closed.

## OS jobs

A skill cannot start itself. OS jobs start the script: launchd (Mac), systemd user timers (Linux), Task Scheduler (Windows).

- `add-teammate` installs them when the first teammate joins. Never at `solo`: `install-jobs` refuses.
- Every computer: pull every 15 minutes; push at 2 am or the first wake after (Linux adds up to 30 random minutes); device helper daily at 4 am.
- Admin's computer (`--admin`): at 3:30 am, the nightly review, then the reports.
- Bot's box (`--bot`): pull, push and helper, as the bot. `add-bot` installs them.
- The jobs use the engine in `sync_engine:` in `company-profile.md`, for example `claude -p --model haiku`.
- **Windows: not tested.** The files ship, but `sync.ps1` says "not tested" and stops. Tell a Windows user plainly: the jobs do not run there yet.

## Device helper, traces, rewrites

- **Device helper:** once a day it asks the host if this person still has access. A day counts only when the sign-in works and the host says "no access". Offline days and expired sign-ins never count. One "ok" resets the count. Warning from day 7. Day 14: it deletes the company folder. [app]: the kernel sends the signal.
- **Traces** [app] [traces]: `collect` uploads a session only when all its work stayed in this company folder (the shared list does not count). Else it holds it and logs one local line. Secrets are scrubbed first.
- **History rewrite:** after `remove-leak`, the next `pull` re-clones that repo by itself. It keeps uncommitted and held files, except a file with the leaked pattern.

## On this computer

`~/.config/<company>-os/`, never in a repo: `me` (the person's slug; on a bot's box, the bot's), `engine` (optional override), `state/sync.log`, `state/held.json` (held files, reasons, last error). Never edit `held.json` by hand.

## Never

- Never push to `main`. Never force-push, except the script on the person's own `sync/` branch.
- Never skip the scan or the check, or pass `--no-verify`.
- Never print a secret, a token or private-source content in chat or a log.
- Never move a held file to another repo to get around the hold.
