---
name: vault-lint
description: Health-check the whole OS folder — broken links, empty summaries, stale inbox, drifted indexes, orphans, silo leaks, leftover placeholders, secrets. Fixes the mechanical issues, lists the judgment calls. Use when the person says "lint the vault", "health check", or weekly.
---

# Vault lint

Collect every finding first, then fix.

## Checks

1. **Broken links.** Every `[[target]]` that matches no file (ignore `#heading` and `|alias`; match by filename, any case). Do not create pages. List the most-linked missing ones as "wanted pages."
2. **Meetings.** Meeting notes with an empty `summary:` or no attendees. Fill from the note body if you can; otherwise list.
3. **Inbox age.** Items older than 14 days. Report the count and the oldest five. Do not process them (that is `ingest`).
4. **Indexes.** Regenerate each fenced index and fix drift. Inside the fences only.
5. **Orphans.** Notes with no links in or out (skip `system/`, `home/`, `inbox/`, templates). Report only.
6. **Silo leaks.** Any file in one company folder that links to or names another company folder, and any company facts sitting in `wiki/` or `tools/`. Report; do not move without asking.
7. **Placeholders.** Any `{{...}}` left outside `system/company-template/`. Fill if the answer is in the files; otherwise list.
8. **Size.** Any `AGENTS.md` over 10,000 characters. Suggest what to move into a separate file.
9. **Secrets.** Strings that look like keys (`sk-`, `api_key`, `-----BEGIN`). Stop and flag at the top of the report. Never repeat the value.

## Output

Write `system/lint/YYYY-MM-DD.md` with: **Fixed** (what, how many), **Needs you** (one line each, linked), **Wanted pages**, **Stats** (notes per zone and per company). Give a three-line summary in chat.
