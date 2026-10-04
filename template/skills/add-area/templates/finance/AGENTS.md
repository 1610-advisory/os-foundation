# {{AREA_NAME}} — {{COMPANY_NAME}}

This is the **{{AREA_NAME}}** area of {{COMPANY_NAME}}'s company OS. It is its own git repo, so only people with access to this area have it on their computer.

## Must-have rules (every agent, every session)

- **One company only.** Use only files inside `~/{{COMPANY_SLUG}}-os/`. Never read or copy from another company's folder.
- **Area facts stay here.** Do not copy facts from this area into the shared company files (`../../`). Only a person decides to share them.
- **No secrets.** No passwords, API keys, or tokens in any file. Connections use each tool's own sign-in.
- **Git only in this repo.** Commit here, by this folder's path. Never run destructive git at the company root.
- **Ask first** before you send, post, publish, pay, or delete anything outside this folder.

## Start of a session

Read these if your agent did not load them already:

1. `../../AGENTS.md` — the company rules (layout, skills, memory, review).
2. `../../memory/MEMORY.md`, then `memory/MEMORY.md` here.
3. `../../company-profile.md`, and any other shared file the task needs (`customers.md`, `offers.md`, `voice.md`, `people/`).

## What this area does

The numbers for {{COMPANY_NAME}}: books, cash, reports, invoices.

<!-- add-area fills in: what it produces each month, the tools it uses, what "done well" means. -->

### Rules for numbers

- Every number you give has a source: a file in `data/`, a connected tool, or a formula you show. If you cannot trace it, say so.
- Show your math for anything that feeds a decision.
- Never move money, send an invoice, or change the books without showing the exact change and getting a yes.
- Raw numbers stay in this area. A shared summary goes to the company files only when a person decides to share it.

Finance Toolkit: coming. Until then, these rules and the area skills are the method.

### Folders

- `data/` — exports (P&L, balance sheet, bank CSVs), named `YYYY-MM source.csv`
- `reports/` — what you make from them

## Skills

Area skills live in `skills/` here. Company skills live in `../../skills/` (ingest, connect-tool, write-skill, lint, suggest): read and follow those files the same way.

| Skill | Use when someone says |
|---|---|
| (none yet) | |

## Folders

- `inbox/` — capture for this area only. "Process the inbox" here files it into this area.
- `meetings/` — meetings only this area should see.
- `memory/` — how to work in this area. Session logs: `memory/logs/YYYY-MM-DD-<person-slug>.md`.
- `skills/` — this area's SOPs.

## Changes and review

Same as the company rules: the admin commits directly; everyone else opens a pull request; session logs go straight to `main`.
