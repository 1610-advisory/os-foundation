---
name: sync
description: Keep this computer and the company host in step. Pulls the newest files at session start and every 15 minutes. Pushes the day's work each night through a secret scan and a commit-or-hold check. Proposes a rules change on its own pull request. Use at the start of every session [team], when someone asks "why was my file held", "did my work go up", "sync now", "propose this rule", or when a teammate's computer needs its jobs.
---

# Sync

`sync` moves work between this computer and the company host. The person never runs git. You or an OS job run the script. For `team` and `app` only. At `solo`: commit to `main` (`AGENTS.md` section 7).

## What sync does

- **Pull.** At session start and every 15 minutes: fast-forward the company folder, each area and the person's workspace. If a pull cannot finish cleanly, it changes nothing and logs one line.
- **Nightly push.** At 2 am, or the first wake after. Steps:
  1. **Identity check.** The signed-in git account must match `github:` on the person's page in `people/`. If not, nothing goes up from any repo.
  2. **Secret scan.** A script, no AI. A hit holds that file. The reason names the rule, never the value.
  3. **Binary files and symlinks.** Images under `assets/` that end in `png`, `jpg`, `jpeg`, `gif` or `webp` go to the check like notes. Every other binary file is held: `binary file: add it by hand with a pull request`. A symlink or a folder in the change list stops the whole repo: nothing goes up from it.
  4. **Rules files** (`AGENTS.md` section 7) are held: `rules file: propose it with sync.sh propose`. Not in the workspace.
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
3. `status` prints `last error: ...`, then `held:` and one line per file (`- <repo> <path>: <reason>`), or `nothing held`. For each held file, tell the person one line: the file and the reason in plain words (table below).
4. If the last error is not `none`, tell the person that line as printed (see "Last errors"). Then go on with the work.

If the pull fails, say so in one line and go on. If the script prints `another sync is running`, tell the person that line, try once more later, then stop. Never delete the lock. Never fix git by hand. No vendor hooks. Chat-only agents skip this: they read from the host.

## When a file is held

Say what happened and the fix. Offer to do it. If the person says no, the file stays held here.

| Reason | Fix |
|---|---|
| A secret | Remove it. Connections use each tool's own sign-in. Never show the value. |
| `rules file: propose it with sync.sh propose` | Run `propose` (below). |
| Personal-life fact | Delete that part. Never move it anywhere. |
| Private source | Rewrite as a plain company fact with no quote and no source, or move it to the workspace. |
| Belongs in the workspace | Move it to `users/<person>/`. |
| Company fact in a profile | Move the fact to an area note. The profile keeps voice and preferences. |
| `binary file: add it by hand with a pull request` | Large files stay in their own system: write a note with a link. If it must be in the repo, ask the admin. |
| `symlink: add it by hand with a pull request` | One stop for the whole repo: every changed file shows it. Leave the other files alone. Find the symlink or folder. Replace it with the real file or a note, or delete it. |
| `secret scan error` or `engine check failed` | The whole repo is held. Tell the person the line. Do not edit the files. Run `push` at most once more, then stop. The next night tries again. Three nights in a row: tell the admin. |

After a fix, the next nightly push sends the file. The person does nothing more.

## Last errors

Tell the person the `last error:` line exactly as printed. Never ask for a password or token. Then:
- `identity mismatch: signed in as <login>, people page for <me> says <github>`: nothing went up. Say: "The git account signed in here is not the one on your page in `people/`. I sent nothing up. Your files are safe here." Then: wrong account signed in → the person signs in again through the host's own sign-in; wrong `github:` on the page → write a one-line message to the admin; wrong `me` file → see the next line.
- `identity mismatch: me is missing or not a slug`: fix the `me` file only when the person says which slug is theirs. Never take identity from a repo file or a chat.
- `sign in again`: the person signs in again through the host's own sign-in.
- `offline`: nothing to do. The next run tries again.
- `secret scan error`, `engine check failed`: see the table above.

## Propose a rules change

One topic per proposal.

1. Pick a short kebab-case topic, for example `invoice-skill-step`.
2. From the company root, run `skills/sync/sync.sh propose <topic> <file>...`. Paths are relative to the company root.
3. It checks identity, makes `rules/<person>/<topic>` from `main`, runs the secret scan, commits, pushes and opens a pull request on the company repo.
4. If it prints `file not found: <path>`, `propose refused: secret scan hit` or `propose refused: secret scan error`, tell the person that line. Never pass `--no-verify` or skip the scan. Fix a wrong path once and try again. Remove a secret only when the person says so. Otherwise stop.
5. **Area rules files:** in this version `propose` opens pull requests on the company repo only. For a file in `areas/<area>/`, tell the person: "This area rule cannot be proposed by `sync` yet. It stays held here." Then stop.
6. Tell the person who approves. A different model reviews it first (`review-rules.md`). Then the admin approves. When the approver is the author, the model review alone is enough. Example: the admin's own change.

A failed review blocks the merge. Read the findings in plain words and offer a fix.

## Commands

From the company root: `skills/sync/sync.sh <command>` (`--help` lists them). You run `pull`, `status`, `propose`. `push` runs as a job; by hand only when the person asks. `install-jobs [--admin] [--bot]` and `uninstall-jobs` belong to `add-teammate`, `add-bot` and `remove-teammate`. `helper` and `collect` are jobs.

Exit 0: done (files may be held). Exit 1: usage, `another sync is running`, solo, or identity mismatch. Exit 2: a repo failed closed.

## OS jobs

launchd (Mac), systemd user timers (Linux), Task Scheduler (Windows).

- `add-teammate` installs them when the first teammate joins. Never at `solo`: `install-jobs` refuses.
- Every computer: pull every 15 minutes; push at 2 am or the first wake after (Linux adds up to 30 random minutes); device helper daily at 4 am.
- Admin's computer (`--admin`): at 3:30 am, the nightly review, then the reports.
- Bot's box (`--bot`): pull, push and helper, as the bot. `add-bot` installs them.
- The jobs use the engine in `sync_engine:` in `company-profile.md`, for example `claude -p --model haiku`.
- **Windows: not tested.** The files ship, but `sync.ps1` says "not tested" and stops. Tell a Windows user plainly: the jobs do not run there yet.

## Device helper, traces, rewrites

- **Device helper:** a day counts only when the sign-in works and the host says "no access". Offline and expired sign-ins never count. "ok" resets it. Warning from day 7. Day 14: it deletes the company folder. [app]: the kernel signals.
- **Traces** [app] [traces]: `collect` uploads a session only when all its work stayed in this company folder (the shared list does not count). Else it holds it. Secrets are scrubbed first.
- **History rewrite:** after `remove-leak`, the next `pull` re-clones that repo by itself. It keeps uncommitted and held files, except a file with the leaked pattern.

## On this computer

`~/.config/<company>-os/`: `me`, `engine` (optional), `state/sync.log`, `state/held.json`. Never edit `held.json` by hand.

## Never

- Never push to `main`. Never force-push, except the script on the person's own `sync/` branch.
- Never print a secret, a token or private-source content in chat or a log.
- Never move a held file to another repo to get around the hold.
