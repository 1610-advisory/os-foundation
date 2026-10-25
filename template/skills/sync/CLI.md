# sync CLI

The person does not run git. An agent or an OS job runs `sync.sh`. The script commits, pushes, and opens pull requests. It never writes to `main` in the company repo or an area repo.

Run it from the company folder, or set `OS_COMPANY_ROOT` to that folder. The company folder has `company-profile.md`.

```
skills/sync/sync.sh <command> [flags]
```

## Commands

| Command | Does |
|---|---|
| `pull` | Fast-forward the company repo, each `areas/*` repo, and `users/<me>`. On failure, leave that repo's working copy unchanged and write one line to the log. |
| `push` | Nightly push. Identity check first. Then, in each repo: secret scan, engine check, commit, push. Company and area repos go to `sync/<me>` and one standing pull request. The workspace repo goes to its own `main`. When `OS_BOT` is set, this is a bot run: see "Bot run push". |
| `propose <topic> <file>...` | Put rules files on `rules/<me>/<topic>` and open a pull request. A path under `areas/<area>/` goes to that area repo. A `users/` path is refused. The nightly push never does this. Refusal and failure lines are listed in `SKILL.md` under "Propose a rules change". |
| `status` | Print held files and the last error. The next session reads this. |
| `install-jobs [--admin] [--bot]` | Write OS job files. Refuses when `level: solo`. |
| `uninstall-jobs` | Remove the job files this script wrote. |
| `helper` | Device helper. Counts days with no access. Warns from day 7. Deletes the company folder on day 14. |
| `collect` | Traces collector. Runs only when `level: app` and `traces` is in `switches`. |
| `--help` | Print the command list. |

`secret-scan.sh` is the secret scan. `sync.ps1` is the Windows entry. It is not tested.

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
3. Each other changed file goes to the engine, one call per file. The engine gets `push-check.md`, then `REPO:`, `FILE:`, and `DIFF:`. It must print one JSON line: `{"decision":"commit"|"hold","reason":"...","message":"..."}`. A non-zero exit, a timeout, or bad JSON holds every changed file in that repo and pushes nothing.
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

## Pull and history rewrite

`pull` uses `git pull --ff-only` in each repo. A failure changes nothing in that working copy.

`remove-leak` pushes an annotated tag `os-rewrite-<YYYYMMDDHHMMSS>` on the new `main`. The tag message names rules, not values, one per line:

```
rule: github-pat
```

The rule id is the id `secret-scan.sh` printed. If `pull` cannot fast-forward and a newer tag of that shape is on the host, `pull` clones the repo again, carries uncommitted and held files, and drops a file whose content matches a named rule. Nested area and workspace repos are kept. The script records the tag and writes one log line.

## OS jobs

`install-jobs` refuses `level: solo`. It writes files into `OS_JOBS_DIR`. It loads them only when `OS_JOBS_LOAD=1`.

Default folder: macOS `~/Library/LaunchAgents`, Linux `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user`, Windows `%LOCALAPPDATA%\os-foundation\tasks`.

| Job | When |
|---|---|
| pull | Every 15 minutes (`StartInterval` 900). |
| push | 02:00, or the first wake after that. Linux adds a random delay of up to 30 minutes. |
| helper | Daily at 04:00. |
| admin (`--admin`) | 03:30. Runs nightly review, then reports. |

`--bot` installs the pull, push, and helper jobs for a bot box. The `me` file is the bot slug. Push asks the host layer for that bot's token.

`OS_JOBS_PLATFORM=macos|linux|windows` picks the templates. The default is the current system.

Windows files are marked not tested. `sync.ps1` says so and exits.

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
| `OS_JOBS_LOAD` | `1` loads the jobs into the OS. |
| `OS_JOBS_PLATFORM` | `macos`, `linux`, or `windows`. |
| `OS_SYNC_ENGINE` | Engine command. |
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
| 1 | Usage, lock, solo refusal, identity mismatch, or a refused delete. |
| 2 | A repo push or pull failed closed. |

## Lock

One lock file under `state/`. A second run exits 1 if the first is still alive. `status` and `--help` do not take the lock.
