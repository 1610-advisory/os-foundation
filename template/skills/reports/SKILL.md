---
name: reports
description: Director and admin reports. A daily "to decide" page per area (only when there is something to decide), a weekly "what happened" page per area, and a weekly company page for the admin. Shows actions and plain counts, never workspace content, and never ranks people. Use when someone asks "what happened this week", "what do I need to decide", "where is my report", "send me the report", or to run a report by hand.
---

# Reports

A report saves the director the reading. It shows nothing the director could not already read in the area.

This skill is for `team` and `app`. At `team` an OS job runs it on the admin's computer each night, right after the nightly review. [app]: the kernel runs it.

## The three reports

| Report | When | File |
|---|---|---|
| To decide | Daily, only when not empty | `reports/YYYY-MM-DD-to-decide.md` in each area (and the company repo when it has flags) |
| What happened | Weekly | `reports/YYYY-Www.md` in each area that had work that week |
| Company page | Weekly, for the admin | `reports/YYYY-Www-company.md` in the company repo |

Weeks are ISO weeks that start on Monday, such as `2026-W43`.

**To decide** lists what needs a person in that area: the nightly review's flags, and rules branches not yet merged. One line each. If the review did not run, it says `The review did not run.` Nothing to decide: no file that day.

**What happened** lists, per person, actions and results from the logs and merged commits. Then plain counts for the area: commits merged, people with actions, and log files. People are in slug order, never by how much they did.

**Company page** has plain counts per area. It does not copy area sentences into the company repo.

## How it runs

- The job runs `skills/reports/run.sh` from the company root. With no flags it writes the day's to-decide files and the week's pages.
- By hand: `--date YYYY-MM-DD` for one day, `--week YYYY-Www` for one week, `--daily` for the to-decide files only.
- The script gathers the facts. A small model (`report-prompt.md`) only picks which action and result sentences to keep, word for word. The counts are the script's, not the model's.
- If the model fails, the page still has the facts and the line `The summary did not run.`
- It writes as an area-scoped identity: the company bot when `bots` is on, else the admin's agent. Every commit carries a `Run-Id:` line.
- It writes on the branch `review/<date>` with auto-merge on. Reports are notes: no person approves them first.

## What a report may show

Only what the area already holds: merged commits and logs on `main`, the nightly review's flags, and open rules branches.

About a person, a report shows **what they did** (actions and results) and **plain counts**. Nothing more.

A report never shows:
- Workspace content (`users/`), drafts or the profile (`profile/PROFILE.md`).
- Traces, chat history or the AI's thinking.
- How a person works: habits, style, speed, hours.
- Private-source content, or any line marked `source: private`. "Replied to a customer email" is fine. What the email said is not.
- Scores, ranks, "top" or "least active" lists, or any comparison of people. The script drops any line with a ranking word.

If you write or edit a report by hand, the same rules apply.

## Format

- Markdown is the default (`format: markdown` in the front matter).
- With the `mdx-reports` switch on: `format: mdx`, and the body may use only these components: `Callout`, `Table`, `Chart`, `CodeBlock`. Chart data sits inline in the file. No imports. No scripts. A company with no app sees the data as text. [app]: the app draws it with the company theme.

## Delivery

The file is the report. This job does not send it anywhere.

A director may want a copy by email, Slack or Teams. If that tool is already connected (`connect-tool` writes it in `architecture.md`), the company page names the channel. Send a copy only when the director asked for it: a short summary and a link to the file. Ask first before the first send (`AGENTS.md` section 10). If no tool is connected, say the report is in the file and offer `connect-tool`.

## When a person asks

- **"What do I need to decide?"** Read today's to-decide file for their area. No file means nothing to decide.
- **"What happened this week?"** Read the weekly file. Answer from it. Link the sources.
- **"Who is most active?" or "how much does X use the AI?"** Say no plainly: reports never compare or rank people. Offer the plain counts for the area.

## Never

- Never read `users/`, traces or another area to write a report.
- Never rank, score or compare people.
- Never quote a private source, a workspace note, a profile or a secret.
