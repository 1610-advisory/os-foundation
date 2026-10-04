---
name: lint
description: Health-check the company OS (or one area) — broken links, empty summaries, old inbox items, leftover placeholders, area facts in shared files, oversized rules files, secrets. Fixes the mechanical issues and lists the judgment calls. Use when someone says "health check", "lint", or weekly.
---

# Lint

Check the folder you are in: the company root (shared files only, not `areas/`), or one area. Collect every finding first, then fix.

## Checks

1. **Secrets.** Strings that look like keys or passwords (`sk-`, `api_key`, `password:`, `-----BEGIN`). Stop and flag them at the top of the report. Never repeat the value.
2. **Broken links.** Every `[[target]]` that matches no file (ignore `#heading` and `|alias`; match by file name, any case). Do not create pages. List the most-linked missing ones.
3. **Meetings.** Meeting notes with an empty `summary:` or no attendees. Fill from the note body if you can; otherwise list.
4. **Inbox age.** Items older than 14 days. Report the count and the oldest five. Do not process them (that is `ingest`).
5. **Placeholders.** Any `{{...}}` left outside `skills/add-area/templates/`. Fill it if the answer is in the files; otherwise list.
6. **Sensitive facts in shared files** (company root only). Pay, raw financial figures, HR notes, or customer records in a shared file. List them so the admin can confirm each one was meant to be shared. Do not move or delete anything.
7. **Other companies.** Any mention of, or link to, another company's folder. Report.
8. **Size.** Any `AGENTS.md` over 10,000 characters. Suggest what to move into a skill or memory file.
9. **Git.** Uncommitted changes, and (if there is a GitHub remote) commits not yet pushed, in the repo and in `memory/logs/`. Check that `memory/logs/` is on the `logs` branch; if not, use `skills/logs-folder/` → "Repair". Report.

## Output

Write `memory/lint/YYYY-MM-DD.md` with: **Fixed** (what, how many), **Needs you** (one line each, linked), **Missing pages**, **Stats** (notes per folder). Commit. Give a three-line summary in chat.
