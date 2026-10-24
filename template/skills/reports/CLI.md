# reports CLI

`skills/reports/run.sh` writes director reports. It runs after `nightly-review/run.sh` on the admin's computer. Delivery in v1 is the file. This script does not send mail or chat.

## Command

```text
skills/reports/run.sh [--date YYYY-MM-DD] [--week YYYY-Www] [--daily] [--root DIR]
```

Run it from the company root. With no flags it writes the daily "to decide" file and the weekly pages for the local date. `--daily` writes only the daily file. `--week` writes that week (and the daily file unless `--daily` is also the only extra flag). `--date` and `OS_NOW` work the same way as nightly review.

Exit `0` when the files that should exist were written, including a quiet day. Exit `1` on a bad flag. Exit `2` when a push did not finish. Solo prints `skipped: solo` and exits `0`.

## OS job

Same job as nightly review, next command, 03:30, company root, `--admin` only:

```text
skills/reports/run.sh
```

## Files

| File | Where | When |
|---|---|---|
| `reports/YYYY-MM-DD-to-decide.md` | each area, and the company root if the root has flags | only when the file would not be empty |
| `reports/YYYY-Www.md` | each area that had actions, commits, or logs that week | weekly |
| `reports/YYYY-Www-company.md` | company root | weekly |

Week labels are ISO weeks, Monday start, such as `2026-W43`.

The daily file lists flags for that area, rules branches not merged into `main`, and `The review did not run.` when the digest says so. It does not list another area's flags.

The weekly area file is "what happened". Sections, in this order:

- Per person: actions and results. People are in slug order, not by how much they did.
- New facts and skill changes: paths added or changed that week, as links, plus a count. Not the note text.
- Stuck work: a project file under `projects/` whose status is fail. If none, one line that says so.
- Contradictions: review flags whose summary says the notes disagree. Path and summary only. If none, one line that says so.
- Counts: commits merged, people with actions, and log files.

These come from git and the review digest. Counts and links only. No workspace content. No scores. No ranking.

The company page has plain counts per area. It does not copy area sentences into the company repo.

## Sources

Merged commits and `memory/logs/` on `main` for the week. The digest JSON from nightly review (`state/digests/YYYY-MM-DD.json`). Open `rules/*` branches that are not in `main`.

Never read `users/`, `profile/`, `traces/`, or a line marked `source: private`. Drop a line that contains a ranking word: rank, ranking, ranked, score, scores, scored, scoring, leaderboard, rating, ratings, outperform, underperform.

## Engine input

Same command as nightly review (`sync_engine`, or `OS_SYNC_ENGINE`). One call per weekly area page. Stdin:

1. The whole file `report-prompt.md` (same folder as `run.sh`), when that file exists.
2. A blank line.
3. The block below.

```text
---INPUT---
kind: report
week: 2026-W43
area: finance

person: mia
action: Filed the widget note.
result: The note is on main.
commit: Add the widget note

counts:
commits: 1
log_files: 1
people: 1
---END---
```

If `report-prompt.md` is missing, or the engine fails, the script still writes the page from these facts and adds the line `The summary did not run.`

## JSON the engine must print

One line, no code fence:

```json
{"ok":true,"people":[{"slug":"mia","actions":["Filed the widget note."],"results":["The note is on main."]}]}
```

The script keeps an action or result only when that exact sentence was in the input. It drops the rest. Counts in the file are the script's counts, not the model's.

## Markdown and MDX

Default front matter has `format: markdown`. When `mdx-reports` is on, `format: mdx` and the body may use only these components: `Callout`, `Table`, `Chart`, `CodeBlock`. Chart data is inline. No import. No script. No renderer in this skill.

```yaml
---
type: report
summary: "What happened in finance, week 2026-W43"
week: 2026-W43
area: finance
format: markdown
---
```

## Delivery

The file is the source. This script does not post it. If `architecture.md` already lists email, Slack, or Teams (the row `connect-tool` writes), the company page names that channel and says a copy is not sent by this job. If none is listed, the page says so. Sending stays in `connect-tool`.

## Branch and identity

Same branch as nightly review: `review/<date>`. Same trailers (`Run-Id: review-...`, and `Bot-Owner:` when `bots` is on). Notes tier: `host.sh open-pr` and `host.sh auto-merge`. No secret in a child process's arguments. No host list call from this skill. Rules branches are read with `git for-each-ref`, which returns the full list.
