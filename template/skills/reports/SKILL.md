---
name: reports
description: Director and admin reports. A daily "to decide" page per area (only when there is something to decide), a weekly "what happened" page per area, and a weekly company page for the admin. Shows actions and plain counts, never workspace content, and never ranks people. Use when someone asks "what happened this week", "what do I need to decide", "where is my report", "send me the report", or to run a report by hand.
---

# Reports

A report saves the director the reading. It shows nothing the director could not already read in the area.

This skill is for `team` and `app`. At `team` an OS job runs it on the admin's computer, right after the nightly review. [app]: the kernel runs it.

## The three reports

| Report | When | File |
|---|---|---|
| To decide | Daily, only when not empty | `reports/YYYY-MM-DD-to-decide.md` in the area |
| What happened | Weekly | `reports/YYYY-Www.md` in the area |
| Company page | Weekly, for the admin | `reports/YYYY-Www-company.md` in the company repo |

**To decide** lists what needs a person: the nightly review's flags (the daily digest), open rules pull requests, and items waiting for approval. One line each, with a link. No flags, no rules PRs, no waiting items: no file that day.

**What happened** has, per area:
- New facts and skill changes, by topic.
- What each person did: actions and results, from the logs and merged pull requests.
- Stuck work and contradictions the review found.
- Plain counts: notes changed, pull requests merged, agent sessions logged, flags open.

**Company page** is made from the area reports. One short section per area, plus the company repo itself. No new sources.

## How it runs

- The job runs `skills/reports/run.sh` (daily) and `skills/reports/run.sh --week YYYY-Www` (weekly). The script gathers the sources and calls the headless engine with `report-prompt.md`.
- It writes as an area-scoped identity: the company bot when `bots` is on, else the admin's agent. Every commit carries a `Run-Id:` line.
- It writes on the branch `review/<date>` with auto-merge on. Reports are notes: no person approves them first.
- By hand: run the same command for the day or week the person names.

## What a report may show

Only what the area already holds: merged notes and logs, the review's flags, open rules pull requests, and items waiting for approval.

About a person, a report shows **what they did** (actions and results) and **plain counts** of agent use. Nothing more.

A report never shows:
- Workspace content (`users/`), drafts or the profile (`profile/PROFILE.md`).
- Traces, chat history or the AI's thinking.
- How a person works: habits, style, speed, hours.
- Private-source content. "Replied to a customer email" is fine. What the email said is not.
- Scores, ranks, "top" or "least active" lists, or any comparison of people.

If a source line breaks one of these rules, leave it out. Do not soften it.

## Format

- Markdown is the default.
- With the `mdx-reports` switch on, a report may use MDX with a fixed list of components only: `Chart`, `Table`, `Callout`, `CodeBlock`. Chart data sits inline in the file. No imports. No free JavaScript. A company with no app sees the data blocks as text. [app]: the app draws them with the company theme.

## Delivery

The file is the report. In v1 that is all that is built.

A director may also want a copy by email, Slack or Teams. Do this only when that tool is already connected (`connect-tool`) and the director asked for it. The copy is a short summary and a link to the file. Ask first before the first send (`AGENTS.md` section 10). If no tool is connected, say the report is in the file and offer `connect-tool`.

## When a person asks

- **"What do I need to decide?"** Read today's to-decide file for their area. No file means nothing to decide.
- **"What happened this week?"** Read the weekly file. Answer from it. Link the sources.
- **"Show me how much X uses the AI" or "who is most active?"** Say no plainly: reports never compare or rank people. Offer the plain counts for the area.

## Never

- Never read `users/`, traces or another area to write a report.
- Never rank, score or compare people.
- Never quote a private source, a workspace note, a profile or a secret.
