---
name: sync
description: Keeps this computer and the company host in step. Pulls every 15 minutes, pushes each night through a secret scan and a commit-or-hold check, and proposes rules changes on their own pull requests. Use at the start of every session [team], when someone asks "why was my file held", "did my work go up", "sync now", "propose this rule", or when a teammate's computer needs its jobs.
---

# Sync

`sync` moves work between this computer and the company host. The person never runs git. For `team` and `app` only. At `solo`: commit to `main` (`AGENTS.md` section 7).

## What sync does

- **Pull.** At session start and every 15 minutes: fast-forward the company folder, each area and the person's workspace. It asks the host first and pulls only the repos that changed. Once a day it pulls every repo (see "Pull" below). If a pull cannot finish cleanly, it changes nothing and logs one line.
- **Nightly push.** At 2 am, or the first wake after. Steps:
  1. **Identity check.** The signed-in git account must match `github:` on the person's page in `people/`. If not, nothing goes up from any repo.
  2. **Secret scan.** A script, no AI. A hit holds that file. The reason names the rule, never the value.
  3. **Binary files and symlinks.** Images under `assets/` that end in `png`, `jpg`, `jpeg`, `gif` or `webp` go to the check like notes. Every other binary file is held: `binary file: add it by hand with a pull request`. A symlink or a folder in the change list stops the whole repo: nothing goes up from it.
  4. **Rules files** (`AGENTS.md` section 7) are held: `rules file: propose it with sync.sh propose`. Not in the workspace.
  5. **Commit or hold.** A small model reads each other changed file with `push-check.md`: commit, or hold with a reason.
  6. **Push** only the files that passed, to `sync/<person>`, rebuilt on `main` each night.
  7. **Standing PR** `sync: <person>`, auto-merge on. Notes merge by themselves when the checks pass.
  8. **Pull** again.
- **Fails closed.** If any step fails for a repo, the model call included, nothing goes up from that repo. The files stay here. The next night tries again.
- **Workspace** (`users/<person>/`): no pull request. It pushes to its own `main` after the scan and the check. A company fact in `profile/PROFILE.md` is held.
- **Nobody writes to `main`** in the company or an area repo. The admin is included.
- **Bot run.** When `OS_BOT` is set, `push` does not use the steps above. It scans the commits already on `sync/<bot>`, then sends that branch and opens `sync: <bot>` as the bot. A secret or a rules file pushes nothing. It does not commit that work as the person, and it does not touch `sync/<person>`. The bot key is the boundary.

## Session start (Claude Code, Codex, Cursor, Pi)

Before other work, from the company root:

1. Run `skills/sync/sync.sh pull`.
2. Run `skills/sync/sync.sh status`.
3. `status` prints `last error: ...`, then `held:` and one line per file (`- <repo> <path>: <reason>`), or `nothing held`, then `last full pull: <UTC time>` or `last full pull: never`. For each held file, tell the person one line: the file and the reason in plain words (table below).
4. If the last error is not `none`, tell the person that line as printed (see "Last errors"). Then go on with the work.

If the pull fails, say so and go on. If it prints `another sync is running`, tell the person that line, try once more later, then stop. Never delete the lock. Never fix git by hand. No vendor hooks. Chat-only agents skip this: they read from the host.

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
| `binary file: add it by hand with a pull request` | Write a note with a link to the file's own system. If it must be in the repo, ask the admin. |
| `symlink: add it by hand with a pull request` | The whole repo is stopped. Leave the other files alone. Replace the symlink or folder with the real file or a note, or delete it. |
| `secret scan error` or `engine check failed` | The whole repo is held. Tell the person the line. Do not edit the files. Run `push` at most once more, then stop. The next night tries again. Three nights in a row: tell the admin. |

After a fix, the next nightly push sends it.

## Last errors

Tell the person the `last error:` line exactly as printed. Never ask for a password or token. Then:
- `identity mismatch: signed in as <login>, people page for <me> says <github>`: nothing went up. Say: "The git account here is not the one on your page in `people/`. Your files are safe here." Wrong account → sign in again through the host's own sign-in; wrong `github:` on the page → write a one-line message to the admin; wrong `me` file → see the next line.
- `identity mismatch: me is missing or not a slug`: fix the `me` file only when the person says which slug is theirs. Never take identity from a repo file or a chat.
- `sign in again`: the person signs in again through the host's own sign-in.
- `offline`: nothing to do. The next run tries again.
- `auto-merge is off on <repo>: pull request <n> is open but will not merge by itself. ...`: the work went up, but that pull request waits. Tell the person to send the line to the admin. The admin runs the command in it once. The next push merges as usual.

## Propose a rules change

One topic per proposal.

1. Pick a short kebab-case topic, for example `invoice-skill-step`.
2. From the company root, run `skills/sync/sync.sh propose <topic> <file>...`. Give files, never a folder. Paths start at the company root: no leading `/`, no `..`. An area file is `areas/<area>/<file>`. A `users/` path is refused. To share a workspace skill, copy its folder to `skills/<name>/` or `areas/<area>/skills/<name>/`, then propose each file in the copy.
3. It checks identity, every path and the secret scan first. A file under `areas/<area>/` goes to that area repo. A file outside `areas/<area>/` and outside `users/` goes to the company repo. Each repo gets `rules/<person>/<topic>` from `main` and one pull request with auto-merge on. It prints one bare number per repo: the company repo first, then the areas in name order. Tell the person each number and its repo.
4. **Refused.** Tell the person the line exactly, and every `opened: <repo> <n>` line before it (those pull requests stay open). Never pass `--no-verify`. Never ask for a token. After "run once more", if it stops again, stop.

| Line | Do |
|---|---|
| `propose refused: bad path: <path>`, `file not found: <path>` | Fix the path once: a file, from the company root. Run once more. |
| `propose refused: users paths stay in the workspace` | Copy the file out first (step 2) and run once more, or stop. |
| `nothing to propose: areas` or `nothing to propose: areas/<area>` (no file) | Fix it once to `areas/<area>/<file>`. Run once more. |
| `nothing to propose: <file>` | Same as on `main`. Stop. Do not run again. |
| `propose refused: symlink: <path>`, `propose refused: symlink on main: <path>` | Stop. Tell the admin the line. Do not run again. |
| `propose refused: secret scan hit` | Remove the secret only when the person says yes, then run once more. Else stop. |
| `propose refused: secret scan error` | Run once more. |

5. **Failed after the checks:** `propose fail <repo>: <step>` (`repo`, `fetch`, `worktree`, `copy <path>`, `commit`, `push`, `open-pr` or `auto-merge`), then `opened: <repo> <n>` for each pull request it already opened. Those stay open. Tell the person every line. Run the same command once more: it updates them. If it fails again, stop and tell the admin.
6. Tell the person who approves. A different model reviews it first (`review-rules.md`). Then the admin approves the company pull request, the area director the area one.
   - **Your own rules change on GitHub.** GitHub never counts the author's own approval. A director's own area change needs the admin's approval. The admin's own change: wait for the green checks. Open the pull request. Tick "Merge without waiting for requirements to be met (bypass rules)". Click "Bypass rules and merge". Only an org admin has that box.
   - **Forgejo.** Forgejo asks no review of the author. Your own change merges on green checks.

A failed review blocks the merge. Read the findings in plain words and offer a fix.

## Pull

- **`pull`** asks the host for the newest commit of each repo. It pulls only a repo that changed. A new area counts as changed. If nothing changed, it fetches nothing, writes no log line and exits 0.
- **`pull --full`** pulls every repo, as the 15-minute job did before. It also refreshes every skill copy (Windows).
- **A full pull runs by itself** on the first `pull` after 04:00 local time, so each morning starts in step after the 2 am push. A computer that slept through 04:00 does it on the first `pull` after it wakes. A missing or broken state file also starts a full pull.
- **Use `pull --full`** when something looks out of date, after someone ran git by hand, or when support asks. Session start and the jobs keep plain `pull`.
- **State:** `.git/os-foundation/pull-state` in the company repo. Each company folder has its own. Git never commits it. Never edit it by hand. If it cannot be written, the pull still works.

## Commands

From the company root: `skills/sync/sync.sh <command>` (`--help` lists them). You run `pull` (`pull --full` when needed), `status`, `propose`. `push` runs as a job; by hand only when the person asks. `install-jobs [--admin] [--bot]` and `uninstall-jobs` belong to `add-teammate`, `add-bot` and `remove-teammate`. `helper` and `collect` are jobs.

Exit 0: done (files may be held). Exit 1: usage (`unknown flag`), `another sync is running`, solo, identity mismatch, or a repo that failed to pull or push (it fails closed). Exit 2: `propose` failed: `propose refused: secret scan error`, or `propose fail <repo>: <step>` for a `fetch`, `worktree`, `commit`, `push`, `open-pr` or `auto-merge` step, then one `opened: <repo> <n>` line for each pull request this run already opened. Windows only: `sync.ps1` exits 3 when Git Bash is missing. Otherwise it exits with the code of `sync.sh`.

## OS jobs

launchd (Mac), systemd user timers (Linux), Task Scheduler (Windows).

- `add-teammate` installs them when the first teammate joins. Never at `solo`: `install-jobs` refuses.
- Every computer: pull every 15 minutes; push at 2 am or the first wake after (Linux: a random delay of up to 30 minutes); device helper at 4 am.
- Admin's computer (`--admin`): at 3:30 am, the nightly review, then the reports.
- Bot's box (`--bot`): pull, push and helper, as the bot. `add-bot` installs them.
- The jobs use the engine in `sync_engine:` in `company-profile.md`, for example `claude -p --model haiku`.

### Windows

- The jobs run the same `sync.sh` through Git Bash from Git for Windows. `sync.ps1` finds Git Bash and starts `sync.sh` with the same arguments. It never uses `System32\bash.exe` (that is WSL).
- **Quick check first.** For `sync.ps1 pull` with no flag, PowerShell asks the host first. If it is sure nothing changed, it prints `sync: no change`, exits 0 and does not start Git Bash. It writes no log line. In every other case it runs `sync.sh pull` as usual. `pull --full` always runs Git Bash.
- Needs: Git for Windows, GitHub CLI (`gh`), `jq`, and the engine command, for example the Claude Code CLI (`claude`). The Claude desktop app alone is not enough: the job calls the `claude` command.
- In an agent's Git Bash terminal, run `skills/sync/sync.sh <command>` as on a Mac. In PowerShell, run `skills\sync\sync.ps1 <command>`.
- `install-jobs` registers the tasks in Task Scheduler. `uninstall-jobs` removes them. The names are `osfoundation-<slug>-pull`, `-push`, `-helper`, and on the admin's computer `-admin`. `<slug>` is the company slug. The tasks are hidden: in Task Scheduler, choose View, then Show Hidden Tasks. Or run `Get-ScheduledTask -TaskName 'osfoundation-*'` in PowerShell.
- The tasks run as the signed-in person, with no stored password. They also run on battery. A missed time runs at the next start or wake. No window opens.
- **Skill links are copies.** Windows checks out `.agents/skills` and `.claude/skills` as plain files. `join.sh` and `pull` replace them with copies of `skills/`, at the root and in each area. Git ignores the copies. The copies are checked file by file on a `pull` that changes that repo, on every full pull, and at the start of every `push`: a file that changed in `skills/` is copied again. A `pull` that finds no change in a repo leaves its copies alone. Push never sends a copy. Never replace a copy with a link by hand.
- **Change a skill in `skills/`, not in the copy.** If you (or the app) edit or add a skill in a copy, the next full pull, a pull that changes that repo, or `push` moves that change into `skills/` and logs `skills copy folded <path>`. A file deleted in a copy comes back: delete it in `skills/`. `skills/` is a rules path: the nightly push holds it with `rules file: propose it with sync.sh propose`. Propose it as usual.
- **`skills copy conflict <path>`** in the log: the same file changed in the copy and in `skills/`, in two different ways. Sync leaves that one copy file alone (the other files still refresh), and `lint` reports `skills copy drift: <path>`. Ask the person which version they want. Copy that version into `skills/` by hand. Run `pull --full`, then `lint` again.
- **`install Git for Windows: winget install --id Git.Git -e`** (exit 3): `sync.ps1` found no Git Bash. Nothing ran. Tell the person the line. After the install, they open a new terminal or restart the app. If Git is installed in an unusual folder, set `OS_GIT_BASH` to the full path of its `bin\bash.exe`.

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
