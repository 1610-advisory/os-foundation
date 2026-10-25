---
name: nightly-review
description: The nightly review of the day's merged changes in each repo. A small model fixes clear errors by pull request and flags judgment calls to the last author, then the approver, in one daily digest. Folds logs older than 30 days into a monthly summary. Use when someone asks "what did the review find", "why did the review change my note", "the review did not run", or to run the review by hand.
---

# Nightly review

Notes go in at once (the auto tier). The nightly review reads them after. It is the check after the change, not a gate before it.

This skill is for `team` and `app`. At `team` it runs on the admin's computer. [app]: the kernel runs it. At `solo` it prints `skipped: solo` and does nothing.

## When and how it runs

- An OS job runs it at 3:30 am, after the nightly push window. Then the reports run. `sync.sh install-jobs --admin` installs that job.
- The job runs `skills/nightly-review/run.sh` from the company root. By hand, for one day: `skills/nightly-review/run.sh --date YYYY-MM-DD`.
- For the company repo and each area repo, it reads the commits merged into `main` that day, since its last run. It skips its own fixes.
- It sends the day's diff, each commit's author and the list of files on `main` to the company's headless engine with `review-prompt.md`, once per repo. The author is matched to a page in `people/`; it is never guessed from a file name.
- It writes as an area-scoped identity: the company bot (or that area's bot) when `bots` is on, else the admin's agent. Every commit carries `Run-Id: review-<date>-...`, and `Bot-Owner:` when a bot writes.

## What it does

**Clear errors: it fixes them.** One commit per repo on the branch `review/<date>`, one pull request with auto-merge on. Clear errors are:
- A broken `[[wiki-link]]` or relative link, where the right target is plain.
- A wrong date: an impossible date, or one that does not match its own file name.
- A duplicated note: it keeps one and links the other to it.
- A typo in a name of a person, customer or product.

It never edits a rules file (any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, `CODEOWNERS`, anything under `skills/`, `bots/*/BOT.md`, `.github/`, `.gitea/`, or `.claude/`). An error there becomes a flag to the approver.

**Judgment calls: it flags them.** Examples: two notes that disagree, a fact that looks out of date, a note in the wrong place, a rules file that looks wrong.
- A flag goes first to the last author.
- If the same flag is still open on a later day, it goes to the approver: the area director from `people/`, or the admin if the area has none. Company-repo flags go to the admin.
- Each approver gets **one daily digest**, grouped by area, capped at 20 items. Overflow is one line: `and N more`.
- `Decision:` lines from the day's logs (the "agent decides and logs" tier) are listed first.
- The digest becomes the area's daily "to decide" report (`reports` skill).

**A possible leak** (a secret, a personal-life fact, or a private-source quote on `main`) is a flag that starts with `Possible leak:`. It goes to the admin's digest only, on the admin's computer. It is never written into a repo file, a report, or a pull request title or body. It is never fixed: an edit does not remove it from history. The admin runs `remove-leak`.

**Log fold.** A daily log more than 30 days old folds into one `memory/logs/YYYY-MM-summary.md` per repo per month. The model writes the summary in plain sentences: no scores, no ranking, no private quotes. The fold removes the old daily files from `main`. History keeps them.

## Privacy

- It reads only what is merged on `main`.
- It never sends `users/`, profiles or traces to the engine, not even as file names.
- A flag names the file and the kind of problem. It never quotes private content and never copies a secret.
- Its fixes add no new facts.

## Fails closed

Every engine call runs and is checked before any edit. If one fails (no answer, bad JSON, timeout), or the prompt or the engine is missing, the review makes no edits, no fold and no pull request. It exits 2 and writes `The review did not run.` to the log and the digest. The next night tries again. Nobody needs to act unless it fails three nights in a row: then tell the admin.

When you run it by hand and it exits 2: tell the person `The review did not run.` Run it at most once more, then stop. Never apply a fix yourself.

## Where things are

On the admin's computer, never in a repo (`~/.config/<company>-os/state/`):
- `review.json`: the last commit reviewed in each repo.
- `review.log`: one line per run.
- `digests/YYYY-MM-DD-<person>.md`: each person's digest for the day.

## When a person asks about it

- **"Why did the review change my note?"** Find the `review/<date>` pull request. Show the change and its one-line reason. If it was wrong, change it back as a normal note change. If the review makes the same change again, tell the admin.
- **"What is in my digest?"** Read the to-decide report for that day, or the digest file. Explain each flag in one line. Offer to fix the ones the person agrees with.
- **"Turn it off."** Only the admin changes jobs. Do not run `sync.sh uninstall-jobs`: it also removes the pull and push jobs. Say what is lost (notes would get no check after they merge), then stop.

## Never

- Never fix a rules file. Never fix a possible leak by editing it.
- Never quote a private source, a workspace note, a profile or a secret in a fix, a flag or a log.
- Never score or rank people.
