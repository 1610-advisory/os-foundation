# nightly-review CLI

`skills/nightly-review/run.sh` reviews one day's merged changes on `main`. It runs on the admin's computer after the sync push window. It does not run a dream pass.

## Command

```text
skills/nightly-review/run.sh [--date YYYY-MM-DD] [--root DIR]
```

Run it from the company root. `--root` points at that root when the shell is elsewhere. `--date` defaults to the local date. `OS_NOW` (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS`) overrides the clock when `--date` is absent.

Exit `0` when the run finished, including a quiet day and `skipped: solo`. Exit `1` on a bad flag. Exit `2` when the review did not run (engine failure, missing prompt, or a push that did not finish). A non-zero exit still writes the log line and the digest. It does not edit a repo.

Solo (`level: solo`) prints `skipped: solo` and exits `0`. It makes no commit.

## OS job

`skills/sync/sync.sh install-jobs --admin` should run this, then reports, at 03:30 local time. Working directory is the company root. No flags.

```text
skills/nightly-review/run.sh
skills/reports/run.sh
```

Do not install this job for solo. Do not install it without `--admin`.

## What it reads

Company root, then each `areas/<area>/` that is its own git repo. It does not read `users/`, `profile/`, or `traces/`.

For each repo it takes commits on `main` whose committer date falls on `--date`, after the sha stored for that repo. State is `${XDG_CONFIG_HOME:-$HOME/.config}/<slug>-os/state/review.json`. The first run has no sha, so it reviews that day only, not older history.

It skips commits whose message has a `Run-Id: review-` trailer (this job's own fixes and folds). It does not send `reports/` to the engine.

## Engine input

The command is `sync_engine` from `company-profile.md`. `OS_SYNC_ENGINE` overrides it. The command gets the prompt on stdin. It must print one JSON object and nothing else. No code fence. Timeout is `OS_ENGINE_TIMEOUT` seconds (default 120). A non-zero exit, a timeout, or anything other than one JSON object is a failure.

Stdin for a change set:

1. The whole file `review-prompt.md` (same folder as `run.sh`).
2. A blank line.
3. The block below.

```text
---INPUT---
kind: review
repo: areas/finance
date: 2026-10-24
range: <from>..<to>

commits:
<sha> <author-slug> <subject>

files:
<path on main>

diff:
<unified diff, at most 200000 characters>
---END---
```

`repo` is `.` for the company root. `author-slug` is the commit author matched to a `people/` page by email or name. It is `-` when there is no match. The script does not guess a slug from a log file name. `files:` lists paths on `main` so a link target can be checked. It skips `users/`, `profile/` and `traces/`. At most 400 paths. If the list is cut, the last line is `and N more files`. If the diff is cut, the last diff line is `diff truncated`.

If `review-prompt.md` is missing, the review does not run.

A month fold is a second call. It does not send `review-prompt.md`. Stdin is:

```text
---INPUT---
kind: fold
month: 2026-09
repo: areas/finance
instruction: Summarize these logs in plain sentences. No scores. No ranking. No private quotes.

file: memory/logs/2026-09-23-mia.md
---
<log text>
---END---
```

## JSON the engine must print

Review call, one line:

```json
{"ok":true,"findings":[{"kind":"clear-error","path":"notes/widget.md","summary":"Broken link.","author":"mia","fix":{"action":"replace","old":"[[Ada]]","new":"[[Ada Admin]]"}},{"kind":"judgment","path":"notes/widget.md","summary":"Confirm the price.","author":"mia"}]}
```

| Field | Rule |
|---|---|
| `ok` | `true` or the call failed |
| `findings` | array, may be empty |
| `kind` | `clear-error` or `judgment` |
| `path` | relative path, no leading slash, no `..` |
| `summary` | one plain sentence |
| `author` | person slug, or `""`. The script does not fill it from a log file name. |
| `fix` | only on `clear-error` |
| `fix.action` | `replace` or `write` |
| `fix.old` / `fix.new` | one line each; `old` must match once |
| `fix.content` | full file text when `action` is `write` |

Fold call, one line:

```json
{"ok":true,"summary":"Plain sentences of what the month's logs did."}
```

## What it does with findings

`clear-error` on a note, log, or link: apply the fix. A rules file is never edited. A rules file is any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, `CODEOWNERS`, anything under `skills/`, `bots/*/BOT.md`, `.github/`, `.gitea/`, `.forgejo/`, `.claude/`, or `docs/CODEOWNERS`. A clear error on a rules file becomes a flag to the approver.

A finding whose `summary` starts with `Possible leak:` goes to the admin digest under the state dir, not the author. It is never written into a repo file, a pull request title, or a pull request body. Its fix is never applied, even when the model sends one. The admin runs `remove-leak`. An edit does not remove a leak from history.

`judgment`: do not edit. Flag the last author first. The approver is the area director from `people/` (the admin if none). Company-root flags go to the admin. If the same flag is still open on a later day, the digest goes to the approver.

`Decision:` lines in the day's changes are listed first. They are not edits.

Fixes and folds land on branch `review/<date>`, one commit, then `host.sh open-pr` and `host.sh auto-merge`. The script does not call `gh` or the host API. It makes no host list call. `open-pr` finds an open pull request from the same head.

A token never goes in a child process's arguments. `host.sh get-token` output is an environment variable for `GIT_ASKPASS` only. It is not printed and not written into a URL.

## Digest

One file per approver, grouped by area, under `state/digests/`:

- `YYYY-MM-DD.json` for `reports/run.sh`
- `YYYY-MM-DD-<slug>.md` for a person

Cap is 20 items (`OS_REVIEW_CAP` overrides it in tests). After the cap, the line is `and N more`.

Every engine call runs and is checked before any worktree, commit, or pull request. On engine failure, or if `review-prompt.md` or the engine command is missing: no edits, no fold, no pull request, one log line in `state/review.log`:

```text
YYYY-MM-DD The review did not run.
```

The digest includes the sentence `The review did not run.`

## Log fold

A log `memory/logs/YYYY-MM-DD-<slug>.md` whose date is more than 30 days before the run date is folded into `memory/logs/YYYY-MM-summary.md` (one file per month per repo). The originals are removed on that branch. Git history keeps them. A file exactly 30 days old is kept.

## Identity

When `bots` is on, the company bot commits (an area bot if `bots/<bot>/BOT.md` has `area:` set to that area). Trailers:

```text
Run-Id: review-<date>-<8 hex>
Bot-Owner: <owner slug>
```

`OS_BOT` picks the bot. `OS_RUN_ID` fixes the run id in tests.

When `bots` is off, the admin's agent commits with `Run-Id:` and no `Bot-Owner`.

## Host verbs

`open-pr`, `auto-merge`, `get-token`, `pr-status`. Repo name comes from the `origin` URL, not from a guessed slug.
