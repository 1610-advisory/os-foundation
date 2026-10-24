---
name: nightly-review
description: The nightly review of the day's merged changes in each repo. A small model fixes clear errors by pull request and flags judgment calls to the last author, then the approver, in one daily digest. Folds logs older than 30 days into a monthly summary. Use when someone asks "what did the review find", "why did the review change my note", "the review did not run", or to run the review by hand.
---

# Nightly review

Notes go in at once (the auto tier). The nightly review reads them after. It is the check after the change, not a gate before it.

This skill is for `team` and `app`. At `team` it runs on the admin's computer. [app]: the kernel runs it.

## When and how it runs

- An OS job runs it at 3:30 am, after the nightly push window. Then the reports run. `sync.sh install-jobs --admin` installs that job.
- The job runs `skills/nightly-review/run.sh`. The script calls the company's headless engine with `review-prompt.md`, once per repo and day.
- It writes as an area-scoped identity: the company bot when `bots` is on, else the admin's agent. Every commit carries a `Run-Id:` line.
- To run it by hand for one day: `skills/nightly-review/run.sh --date YYYY-MM-DD`.

## What it does

For the company repo and each area repo, it reads the changes merged into `main` since the last run.

**Clear errors: it fixes them.** One pull request per repo, on the branch `review/<date>`, with auto-merge on. Clear errors are:
- A broken `[[wiki-link]]` or relative link, where the right target is plain.
- A wrong date: an impossible date, or a date that does not match its own file name or meeting.
- A duplicated note: the same fact or note twice. It keeps one and links the other.
- A typo in a name of a person, customer or product, where `people/` or the area notes show the right spelling.

It never edits a rules file (any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, `skills/**`, `bots/*/BOT.md`, `.github/**`). An error there becomes a flag to the approver.

**Judgment calls: it flags them.** Examples: two notes that disagree, a fact that looks out of date, a note in the wrong area, a possible private-source detail, a rules file that looks wrong.
- A flag goes first to the note's last author.
- If the author does not act by the next run, it goes to the approver from the tiers table (`AGENTS.md` section 6).
- Each approver gets **one daily digest**, grouped by area and capped. Overflow is one line: "and N more".
- The digest is the top of the area's daily "to decide" report (`reports` skill).

**A possible leak** (a secret, a personal-life fact, or a private-source quote on `main`) is always a flag to the admin, never a fix. Editing the file does not remove it from history. The admin runs `remove-leak`.

**Log fold.** Logs older than 30 days fold into one `memory/logs/YYYY-MM-summary.md` per repo per month. The fold removes the old daily files from `main`. History keeps them.

## Privacy

- It reads only what is merged on `main` in each repo. Never `users/` (workspaces). Never traces.
- A flag names the file, the line and the kind of problem. It never quotes private content and never copies a secret.
- It applies `AGENTS.md` section 4 (private sources) to its own writing. Its fixes and its digest add no new facts.

## Fails closed

If the engine fails (no answer, bad JSON, timeout), the review makes no edits. It writes one line to the log. The digest says plainly: "The review did not run last night." The next night tries again. Nobody needs to act unless it fails three nights in a row: then tell the admin.

## When a person asks about it

- **"Why did the review change my note?"** Find the `review/<date>` pull request. Show the change and its one-line reason. If it was wrong, revert that one change as a normal note change, and tell the person the review will not fight it.
- **"What is in my digest?"** Read the "to decide" file for that day. Explain each flag in one line. Offer to fix the ones the person agrees with.
- **"Turn it off."** Only the admin may. Say what is lost: notes would then get no check after they merge.

## Never

- Never fix a rules file. Never merge a flag's fix without the person's yes.
- Never quote a private source, a workspace note, a profile or a secret in a fix, a flag or a log.
- Never score or rank people.
