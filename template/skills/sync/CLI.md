# sync CLI

The person does not run git. An agent or an OS job runs `sync.sh`. The script commits, pushes, and opens pull requests. It never writes to `main` in the company repo or an area repo.

Run it from the company folder, or set `OS_COMPANY_ROOT` to that folder. The company folder has `company-profile.md`.

```
skills/sync/sync.sh <command> [flags]
```

## Commands

| Command | Does |
|---|---|
| `pull [--full]` | Fast-forward the company repo, each `areas/*` repo, and `users/<me>`. Plain `pull` asks the host first and pulls only the repos that changed. `--full` pulls every repo. Any other flag prints `unknown flag` and exits 1. On failure, leave that repo's working copy unchanged and write one line to the log. See "Pull". |
| `push` | Nightly push. Identity check first. Then, in each repo: secret scan, engine check, commit, push. Company and area repos go to `sync/<me>` and one standing pull request. The workspace repo goes to its own `main`. When `OS_BOT` is set, this is a bot run: see "Bot run push". |
| `propose <topic> <file>...` | Put rules files on `rules/<me>/<topic>` and open a pull request. A path under `areas/<area>/` goes to that area repo. A `users/` path is refused. The nightly push never does this. Refusal and failure lines are listed in `SKILL.md` under "Propose a rules change". |
| `status` | Print held files, the last error, and `last full pull: <time>`. The next session reads this. |
| `install-jobs [--admin] [--bot]` | Write OS job files. Refuses when `level: solo`. |
| `uninstall-jobs` | Remove the job files this script wrote. |
| `helper` | Device helper. Counts days with no access. Warns from day 7. Deletes the company folder on day 14. |
| `collect` | Traces collector. Runs only when `level: app` and `traces` is in `switches`. |
| `admin-run` | Admin job. Runs `skills/nightly-review/run.sh`, then `skills/reports/run.sh`. Exit 1 if either fails or is missing. |
| `--help` | Print the command list. |

`secret-scan.sh` is the secret scan. `sync.ps1` is the Windows launcher. It runs `sync.sh` through Git for Windows bash. See "Windows".

## State

Per computer, never in a repo: `${XDG_CONFIG_HOME:-$HOME/.config}/<slug>-os/`

| File | Contents |
|---|---|
| `me` | The person's slug, one line. On a bot box, the bot slug. |
| `engine` | Optional one-line override of `sync_engine`. |
| `forgejo-token` | Forgejo token, mode 0600. The host layer reads it. |
| `state/sync.log` | One line per event. No secret values. |
| `state/held.json` | Held files and the last error. |
| `state/helper.json` | Counted days for the device helper. |
| `state/rewrite` | Last `os-rewrite-*` tag applied, one repo per line. |

`held.json` shape:

```json
{"last_error":"","files":[{"repo":"root","path":"notes/a.md","reason":"..."}]}
```

`repo` is `root`, `area:<name>`, or `workspace`.

## Identity

Before `push` or `propose`, `host.sh whoami` must equal the `github:` field of the `people/*.md` page whose `slug:` is `me`. A mismatch pushes nothing. `status` says why.

## Nightly push

For each repo that has changes:

1. Secret scan. A hit holds that file. The reason names the rule, never the value. A scan error pushes nothing for that repo.
2. Rules files in the company repo or an area are held. They are not sent to the engine. The reason is exactly: `rules file: propose it with sync.sh propose`. A rules file is any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, `CODEOWNERS`, `docs/CODEOWNERS`, anything under `skills/`, `bots/*/BOT.md`, or anything under `.github/`, `.gitea/`, `.forgejo/`, or `.claude/`. In the workspace these files are the person's own. They are not held for this reason.
   - A file whose content is already on a `rules/*` branch on the host (from `remove-teammate`, `add-person`, or `propose`) is held first, with the reason `waits for its own pull request (rules/<person>/<topic>)`. That pull request is its only path to `main`. Once it merges, the next `pull` makes the file clean. Push and pull fetch with `--prune`, so the hold reads the branches the host has now. If that pull request was closed and its branch deleted, push prints `<file>: its own pull request (<branch>) was closed and its branch is gone, so push no longer waits for it` and treats the file like any other. A closed pull request whose branch is kept still holds the file: delete the branch on the host to let it go.
3. Each other changed file goes to the engine, one call per file. The engine gets `push-check.md`, then `REPO:`, `FILE:`, and `DIFF:`. It must print one JSON line: `{"decision":"commit"|"hold","reason":"...","message":"..."}`. A non-zero exit, a timeout, or bad JSON holds every changed file in that repo and pushes nothing.
   - Rule 5 ("belongs in the workspace") is a path rule. It never holds a log under `memory/logs/` (company repo or area) or a file under an area's `drafts/` folder. If the engine holds one of those for that reason, the script commits it and logs `push path-rule <repo> <path> area work`. A hold for any other reason (a private source, a personal-life fact) stands.
   - An area's `drafts/` folder is shared copy in progress. Its files go to the area on the standing pull request, and everyone who reads the area sees them. A private draft goes in the person's workspace `drafts/`.
4. Committable files are committed on `sync/<me>`, rebuilt from `origin/main`. The script force-pushes only that branch. It then calls `host.sh open-pr` and `host.sh auto-merge`, then `pull`.
5. The workspace repo is pushed to its own `main`. No pull request. A company fact in `profile/PROFILE.md` is held by the engine check.

Held files stay in the working copy, unchanged. Nothing held is pushed. After the pull request merges, the next `pull` is clean apart from held files. If it has not merged, `pull` still works and keeps local changes.

Any failed step pushes nothing for that repo. A network failure writes one log line and pushes nothing.

## Bot run push

When `OS_BOT` is set, `push` is a bot run, not the nightly push. `run.sh` sets that name. The script does not check the person's sign-in. It does not commit. It does not read or write `sync/<me>`. The bot key is the boundary. This path does not check that `me` is the bot.

For each company or area repo that already has commits on `sync/<bot>` that are not on `origin/main`:

1. Refuse a credential in the origin URL before any fetch. The message does not include the URL.
2. Take the bot token from `host.sh get-token --bot`. If that fails, stop before the push. The token is an environment value for the pull request calls only (`GH_TOKEN` on GitHub, `FORGEJO_TOKEN` on Forgejo). It is not an argument, a URL, or a log line.
3. Scan every blob in `origin/main..sync/<bot>` with `secret-scan.sh`. If `origin/main` is missing, scan every blob on the branch. A hit or a scan error pushes nothing.
4. If any changed path in that range is a rules file, stop. The reason is `rules file: propose it with sync.sh propose`.
5. Push that branch as it is. The commits stay the same, including `Run-Id` and `Bot-Owner`. Git uses `skills/add-bot/git-credential-os-bot`.
6. Open or update the standing pull request `sync: <bot>` and turn on auto-merge, as the bot. Wait until it merges.

`OS_BOT_MERGE_WAIT` is the wait in seconds. The default is 180. A person's push does not use this path. The workspace repo is not part of a bot run push.

## Pull

`pull` has two forms. Both take the lock.

- **`pull --full`** fast-forwards every repo: the company repo, each `areas/*` repo with `.git`, and `users/<me>`. It runs the skill-copy pass in each one (see "Skill links"). A repo with no `origin` is not fetched, but its missing copies are still made.
- **`pull`** is the quick pull. For each repo it runs `git ls-remote origin refs/heads/main`, with the same sign-in as `fetch`. The token is fetched once per run, kept in a shell variable only, and cleared on exit. A repo is changed when its remote commit differs from the state file, when `HEAD` does not contain the recorded commit, when it has no line there (a new area), when its line is `retry`, when an `ok none` repo now has an `origin`, or when `ls-remote` fails or prints nothing. Only the changed repos are pulled, each with its own skill-copy pass. If no repo changed, it fetches nothing, runs no copy pass, writes no log line and exits 0.

`pull` runs as a full pull instead when:

- the state file is missing or does not parse, or
- a full pull is due: the last full pull is before the most recent 04:00 local time. So the first `pull` after 04:00 (after the 02:00 push) is a full one. A computer that slept through 04:00 does it on its first `pull` after wake. A daylight-saving change can move that hour by one. A last full pull more than one day in the future (a wrong clock) also makes it due, or
- a repo path is not the company root, `areas/<name>` or `users/<name>`.

Use `pull --full` when something looks out of date, after a git step by hand, or for support. Session start in every `AGENTS.md` and the 15-minute job keep plain `pull`.

A working copy left on the person's own branch `sync/<me>` never fast-forwards, because each push rebuilds that branch on the host. Before it fast-forwards, `pull` checks that every change made on that branch is on the host already (`origin/main` or `origin/sync/<me>`). If so, it switches to `main` and logs `pull ok <repo> back on main from sync/<me>`. Uncommitted and untracked files come along. If a change is not on the host, it stays on the branch and logs `pull hold <repo> on sync/<me>: <path> is not pushed yet`. It never drops that work. The next push sends it.

The log lines (`pull ok <repo>`, `pull fail <repo> <reason>`) and exit codes are the same for both forms.

A v0 clone keeps `memory/logs/` as a git worktree of branch `logs`. The upgrade removes it only on the computer that ran it. Once `origin/main` has the upgrade (it tracks `memory/logs-archive/` or `memory/logs/`), `pull` moves it out before the fast-forward: it pushes log commits the host lacks to `logs` (when the host's `logs` moved, it merges that first in a temporary folder; if both changed the same log it stops with the exact steps: `In memory/logs run: git pull --no-rebase origin logs, keep both texts ..., git commit -am "Logs: merge", git push origin logs. Then run this again`), fast-forwards the folder to the host's `logs` so the copy has both sides, copies every file (committed, edited or untracked), removes the worktree, fast-forwards, then puts files back. When a file changed here blocks that fast-forward, only the files changed or added here are kept aside; the folder resets to the host's `logs`, and they come back. When the host has other text for one of them, that text goes beside it as `<name>.old-branch.md`, with one line (`logs: <n> files in the old logs folder were changed here and on the old logs branch ...`). A file changed or added here goes back when `main` lacks it or holds a different copy. A file as committed goes back only when `main` lacks it or has an earlier version of it from branch `logs`, so older text never replaces newer text. A file goes to `memory/logs-archive/` when `main` has that folder (the upgrade made it), unless `main` tracks it at `memory/logs/` already. Those are local changes; the next push sends them. Log line: `pull v0-logs <repo> worktree removed, <n> files kept as local changes, <m> beside`. If the push or the copy fails, nothing is removed and the pull fails with one line. If the removal stops part way, or a file cannot be copied back, the pull fails with one line that names the folder holding a full copy. That folder stays. It never logs success then. Plain text: `the old logs folder memory/logs could not be moved: <reason>.` Each reason ends with what to do.

Logs pushed to the old `logs` branch after the upgrade: a full pull (and any pull that fast-forwards) compares the newest `logs-archive-<date>` tag with `origin/logs`. It writes each file added or changed since then into `memory/logs-archive/` as a local change and prints `logs: <n> files written to the old logs branch after the upgrade are now in memory/logs-archive/ in <repo>. The next push sends them.` It skips a file that already matches. It never writes over a file, tracked or not: the old text goes beside it as `<name>.old-branch.md`, with one line. If that name holds other text (the old branch changed again), it uses the next free name, `<name>.old-branch-2.md` and on. The same text is never written twice (`logs: <n> files from the old logs branch had a different copy here ...`). Log line: `pull logs-catch-up <repo> <n> files <m> beside`. If a write fails, the pull fails with one line (`could not write <path> from the old logs branch. Check the free disk space, then run skills/sync/sync.sh pull --full again.`) and sets `last_error`.

While the host still has a `logs` branch, `push` holds every changed file under `memory/logs/` (company and areas) with the reason `waits until the old logs branch is deleted on the host (skills/upgrade/SKILL.md section 11)`. A teammate's old clone ignores `memory/logs/`, and its first plain `git pull` would write over any log `main` has there. It asks the host with `ls-remote` on each push, even when this clone has no `logs` ref, because an old copy can push the branch back after the admin deleted it. Only "no such branch" lets logs go; offline counts as still there. A repo with no v0 history (no `logs` branch, no `logs-archive-*` tag, no `memory/logs-archive/`) asks nobody.

A failed pull also prints one plain line, `pull failed for <repo>: <reason and what to do>`, and sets `last_error` in `held.json`, so `sync.sh status` shows it. One line per repo; the first reason wins. The next clean pull clears an error that a pull set. It never clears a push error. A good push clears only an error that a push set. It never clears a pull error.

### State file

`<company root>/.git/os-foundation/pull-state`. It is inside the company repo's git folder, next to `skills-copy/`. One per clone. Git never commits it. It is plain ASCII:

```
os-sync-state 1
full <unix seconds of the last full pull>
me <slug, or ->
bot <1 or 0>
repo <ok|retry> <sha|none> <rel>
```

One `repo` line per repo, in pull order. `<rel>` is `.` for the company repo, `areas/<name>`, or `users/<me>`. `<sha>` is the local `origin/main` after the run, or `none`. A line is `ok` only when that repo's pull returned 0 and `HEAD` contains `origin/main`. A repo with no `origin` whose pull returned 0 is `ok none`. A repo with an `origin` but no `origin/main` is `retry none`. Any other result is `retry`, and the next `pull` pulls that repo again.

The file is written to a temp file, then moved into place. If it cannot be written, the pull does not fail. A quick pull keeps the lines of repos it did not pull and keeps `full`. A full pull writes `full <now>`.

`status` reads it: `last full pull: YYYY-MM-DDTHH:MM:SSZ` (UTC), or `last full pull: never` when there is no usable state.

## History rewrite

Each pull of a repo uses `git pull --ff-only`. A failure changes nothing in that working copy.

`remove-leak` pushes an annotated tag `os-rewrite-<YYYYMMDDHHMMSS>` on the new `main`. The tag message names rules, not values, one per line:

```
rule: github-pat
```

The rule id is the id `secret-scan.sh` printed. If `pull` cannot fast-forward and a newer tag of that shape is on the host, `pull` clones the repo again, carries uncommitted and held files, and drops a file whose content matches a named rule. Nested area and workspace repos are kept. The script records the tag and writes one log line.

It never clones again while this copy has a commit the host never had, on `HEAD` or on any local branch: a fresh copy would lose it. It holds instead and prints `pull failed for <repo>: this copy has <n> commits (on any local branch) that are not on the host, so it was not swapped for a fresh copy ...`. A commit that was on the host before the rewrite does not count.

## OS jobs

`install-jobs` refuses `level: solo`. It writes files into `OS_JOBS_DIR`. On macOS and Linux it loads them only when `OS_JOBS_LOAD=1`. On Windows it registers them unless `OS_JOBS_LOAD=0`.

Default folder: macOS `~/Library/LaunchAgents`, Linux `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user`, Windows `%LOCALAPPDATA%\os-foundation\tasks`.

| Job | When |
|---|---|
| pull | Every 15 minutes (`StartInterval` 900). |
| push | 02:00, or the first wake after that. Linux adds a random delay of up to 30 minutes. |
| helper | Daily at 04:00. |
| admin (`--admin`) | 03:30. Runs `admin-run`: nightly review, then reports. |

`--bot` installs the pull, push, and helper jobs for a bot box. The `me` file is the bot slug. Push asks the host layer for that bot's token.

`OS_JOBS_PLATFORM=macos|linux|windows` picks the templates. The default is the current system.

## Windows

The jobs run `sync.sh` through Git Bash from Git for Windows. There is no PowerShell copy of `sync.sh`. All platforms use one script and one secret scan.

Needs on `PATH`: `git`, `gh`, `jq`, and the first word of the engine command (for example `claude`, from the Claude Code CLI). The Claude desktop app does not put `claude` on `PATH`.

### sync.ps1

```
skills\sync\sync.ps1 <command> [flags]
```

It finds `bash.exe` in this order:

1. `OS_GIT_BASH`.
2. `git.exe` on `PATH`: `<git root>\bin\bash.exe`.
3. The `InstallPath` value of `HKLM:\SOFTWARE\GitForWindows`, then `HKCU:\SOFTWARE\GitForWindows`, then `HKLM:\SOFTWARE\WOW6432Node\GitForWindows`: `<InstallPath>\bin\bash.exe`.
4. `%ProgramFiles%\Git\bin\bash.exe`.

It never uses `%SystemRoot%\System32\bash.exe`. That is WSL. It runs `bash.exe <sync.sh> <same arguments>` and exits with that exit code.

#### Quick check before bash

For `sync.ps1 pull` with no other argument, PowerShell checks first, so a pull with nothing new starts no Git Bash. The check is read-only. It never writes the state file or the log, and never takes the lock. It skips bash only when it is sure. Any doubt runs `sync.sh pull` as usual, and bash checks again.

1. Find the company root: `OS_COMPANY_ROOT`, else walk up to `company-profile.md`.
2. Read the state file strictly. Run bash if it is missing or odd, if a full pull is due (same 04:00 rule), if `bot 1`, or if any line is `retry`.
3. The repos on disk (the root, each `areas/*` with `.git`, `users/<me>` with `.git`) must be the same set as the `repo` lines. A `users/*` repo for anyone other than the `me` in the state file also runs bash.
4. An `ok none` repo must still have no `origin`. Else bash. For each repo with a sha: `HEAD` must contain that sha, then `git.exe -C <repo> -c credential.helper= ls-remote origin refs/heads/main`, no prompt, 20 seconds at most. The git trace variables are removed from that process. A local path or `file://` origin needs no sign-in. An `https://github.com/` origin uses the token from `gh auth token`, given to that one git process through its own environment. It is never in `$env:` or on a command line, so bash never sees it. Any other origin runs bash.
5. Every remote sha equals its line: print `sync: no change` and exit 0. Else bash.

`pull --full` and every other command go straight to bash.

| Exit | Meaning |
|---|---|
| 0 | `-h` or `--help`: usage printed. Or `pull` printed `sync: no change`. |
| 3 | No Git Bash found. It prints `install Git for Windows: winget install --id Git.Git -e`. Nothing ran. |
| other | The exit code of `sync.sh`. |

The file is ASCII only. It works in Windows PowerShell 5.1 and PowerShell 7.

### Tasks

`install-jobs` writes one XML file per job into `%LOCALAPPDATA%\os-foundation\tasks`, then registers each one with `Register-ScheduledTask`. `uninstall-jobs` unregisters each task and deletes its file.

| Task | Runs |
|---|---|
| `osfoundation-<slug>-pull` | `pull`, every 15 minutes |
| `osfoundation-<slug>-push` | `push`, 02:00 |
| `osfoundation-<slug>-helper` | `helper`, 04:00 |
| `osfoundation-<slug>-admin` (`--admin`) | `admin-run`, 03:30 |

`<slug>` is the company slug. Each task runs:

```
conhost.exe --headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "<sync.ps1>" <command>
```

The working folder is the company folder. `conhost.exe --headless` keeps a window from opening. `-ExecutionPolicy Bypass` lets the job run where the default policy is `Restricted`.

Settings: runs as the signed-in person (`InteractiveToken`, `LeastPrivilege`, no stored password), so the job sees that person's git and `gh` sign-in. `DisallowStartIfOnBatteries` and `StopIfGoingOnBatteries` are `false`. `StartWhenAvailable` is `true`: a missed time runs at the next start or wake. `MultipleInstancesPolicy` is `IgnoreNew`. `ExecutionTimeLimit` is `PT1H`. The tasks are hidden. To see them: Task Scheduler, View, Show Hidden Tasks, or `Get-ScheduledTask -TaskName 'osfoundation-*'`.

### Skill links

Git for Windows checks out with `core.symlinks=false`. The committed links `.agents/skills` and `.claude/skills` arrive as plain files that hold `../skills`.

When a link path is a plain file, the script replaces it with a copy of the `skills/` folder it points to. It runs `git update-index --skip-worktree <path>` and adds `/<path>/` to `.git/info/exclude`. This covers the company root and every `areas/*`. `git status` stays clean.

- `join.sh` makes the copies.
- `pull` makes any missing copy in a repo it pulls. The copy pass runs on a `pull` that changes that repo (a new area counts), on every full pull, and at the start of every `push`. It compares every copy file with `skills/` and with the last copy (a manifest under `.git/os-foundation/skills-copy/`). A file that changed only in `skills/` is copied again. A quick `pull` that finds no change in a repo leaves its copies alone; the daily full pull refreshes them.
- `push` never sends a path under a copy.
- A real link (macOS, Linux) is left alone.

Change or add a skill in `skills/`, not in the copy. If a file in a copy was edited or added, the next copy pass (a full pull, a pull that changes that repo, or `push` before it builds its list) moves that change into `skills/` first and logs `skills copy folded <path>`. A file deleted only in a copy is copied back. `skills/` is a rules path, so the nightly push holds it: `rules file: propose it with sync.sh propose`.

If the same file changed in the copy and in `skills/` in two different ways, sync leaves that copy file alone and logs `skills copy conflict <path>`. The other files still refresh. The same change on both sides is not a conflict. Copy the wanted version into `skills/` by hand, then run `lint` again.

`lint` accepts a real link to `../skills` or a folder copy. A copy that differs from `skills/` is the finding `skills copy drift: <path>`.

### Line ends

`.gitattributes` sets `* text=auto eol=lf` and `eol=crlf` for `*.ps1`, `*.cmd` and `*.bat`. So `.sh` files keep LF on Windows, where Git's default `core.autocrlf=true` would break bash. The company folder and each new area repo get the same `.gitattributes`.

## Device helper

`helper` calls `host.sh repo-access <slug>-os`.

| Answer | Effect |
|---|---|
| `ok` (exit 0) | Reset the count. |
| `no-access` (exit 2) | Count this date once. |
| auth failed (exit 4) | Do not count. Print `sign in again`. |
| offline (exit 5) | Do not count. |

From day 7 the script prints a local warning. On day 14 it deletes the company folder. `OS_NOW=YYYY-MM-DD` fakes the clock. `OS_TEST_MODE=1` refuses to delete a path outside `$HOME`.

## Traces collector

`collect` runs only when `level` is `app` and `switches` contains `traces`. Otherwise it logs `collect off` and writes nothing.

It reads local session files:

- Claude Code: `$HOME/.claude/projects/**/*.jsonl`
- Pi, including subagent files under the session folder: `$HOME/.pi/agent/sessions/**/*.jsonl`
- Cursor: `$HOME/.cursor/projects/**/agent-transcripts/**/*.jsonl` when the file has a working folder
- Codex: `$HOME/.codex/sessions/**/*.jsonl` when the file has a working folder (format not verified on a live file)

A session is uploaded only if every working folder is inside this company folder and no tool-call path, including subagents, is inside another company's folder. A path on the shared list does not count. The list is `${XDG_CONFIG_HOME:-$HOME/.config}/os-shared-list`, one path per line.

Anything else is held. One line goes to the local log. Nothing is uploaded. A session started above a company folder is never collected.

Secrets are scrubbed before upload. The v1 target is the folder `OS_TRACES_TARGET`. If `OS_TRACES_UPLOAD_URL` is set, the script also posts the scrubbed file. Unset means the post is off. A token for that post is read from `OS_TRACES_UPLOAD_TOKEN_FILE` (mode 0600). It is never a command argument.

## Secret scan

```
skills/sync/secret-scan.sh --staged
skills/sync/secret-scan.sh --range <a>..<b>
skills/sync/secret-scan.sh --files -- <file>...
```

Paths are separate arguments. They are not split or globbed. Exit 0 is clean. Exit 1 is a hit. The line is `file:line:rule`. The value is not printed. Exit 2 is an error. `--files` with no paths is an error. A missing path, a directory, or a symlink is an error. The bundled scan checks a known-bad sample first. If that sample is not flagged, it exits 2 and prints `secret scan error: self-test failed`.

On push, a deleted file is not scanned. There is nothing to read. A symlink or a directory in the change list is a scan error: that repo pushes nothing.

## What is checked

The change list is the working tree plus any file that differs from `origin/main`, including a local commit. A rename is a delete of the old path and an add of the new path. The new path is scanned and checked. Only approved paths are committed. The commit is built from `origin/main`, not from the index, so a staged file that was not approved is not published.

A binary file is held. The reason is `binary file: add it by hand with a pull request`. It is not sent to the engine. Images under `assets/` with the suffix `png`, `jpg`, `jpeg`, `gif`, or `webp` are the exception. Those go to the engine.

If `gitleaks` is on `PATH`, the script uses it. Otherwise it uses bundled patterns and an entropy check. `OS_SECRET_SCAN=bundled` forces the bundled scan. `OS_SECRET_SCAN=gitleaks` forces gitleaks.

## Engine

The command is `OS_SYNC_ENGINE`, else the `engine` file, else `sync_engine` in `company-profile.md`. Example: `claude -p --model haiku`. The prompt is on stdin. One JSON line is on stdout. `OS_ENGINE_TIMEOUT` is seconds (default 120).

Test only: `OS_SYNC_ENGINE` overrides the engine. The Acme S10 test uses it.

`REPO:` is `root`, `area`, or `workspace`.

## Environment

| Name | Use |
|---|---|
| `OS_COMPANY_ROOT` | Company folder. Default: walk up to `company-profile.md`. |
| `OS_HOST_SH` | Path to `host.sh`. Default: `../_host/host.sh` beside this skill. |
| `OS_PROFILE_SH` | Path to `profile.sh`. Default: beside `host.sh`. |
| `OS_NOW` | Fake clock, `YYYY-MM-DD` or a UTC timestamp. |
| `OS_TEST_MODE` | `1` refuses deletes outside `$HOME`. |
| `OS_JOBS_DIR` | Where job files are written. |
| `OS_JOBS_LOAD` | macOS and Linux: `1` loads the jobs into the OS. Windows: `0` writes the files only, with no registration. |
| `OS_JOBS_PLATFORM` | `macos`, `linux`, or `windows`. |
| `OS_SYNC_ENGINE` | Engine command. |
| `OS_GIT_BASH` | Windows: full path to Git for Windows `bin\bash.exe`, for `sync.ps1`. |
| `OS_ENGINE_TIMEOUT` | Engine timeout in seconds. |
| `OS_SECRET_SCAN` | `auto`, `bundled`, or `gitleaks`. |
| `OS_TRACES_TARGET` | Local folder for collected sessions. |
| `OS_TRACES_UPLOAD_URL` | Optional post target. Unset means off. |
| `OS_TRACES_UPLOAD_TOKEN_FILE` | Optional token file for that post. |
| `OS_HOST`, `OS_HOST_URL`, `OS_ORG`, `OS_PROFILE` | Host layer overrides. See `skills/_host/README.md`. |

The script calls `host.sh` only. It does not call `gh` or the host HTTP API. It does not put a token, key, or secret in a child process's arguments. Git asks a helper. The token is in an environment variable. HTTP posts use a mode-0600 config file.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The command finished. Holds may still be recorded. |
| 1 | Usage (including `unknown flag`), lock, solo refusal, identity mismatch, a refused delete, or a repo push or pull that failed closed. |
| 2 | `propose` failed. A secret scan error: `propose refused: secret scan error`, before any repo changes. Or a `fetch`, `worktree`, `commit`, `push`, `open-pr` or `auto-merge` step failed: `propose fail <repo>: <step>`, then `opened: <repo> <n>` for each pull request this run already opened. Those stay open. |
| 3 | Windows only: `sync.ps1` found no Git Bash. |

## Lock

One lock file under `state/`. A second run exits 1 if the first is still alive. `status` and `--help` do not take the lock.
