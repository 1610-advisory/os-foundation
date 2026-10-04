# {{AREA_NAME}} — {{COMPANY_NAME}}

This is the **{{AREA_NAME}}** area of {{COMPANY_NAME}}'s company OS. It is its own git repo, so only people with access to this area have it on their computer.

## Must-have rules (every agent, every session)

- **One company only.** Use only files inside `~/{{COMPANY_SLUG}}-os/`. Never read or copy from another company's folder.
- **Sharing is a person's choice.** Never move facts from this area into the shared company files (`../../`) on your own. When a person asks to share something, do it (say once if it looks sensitive); a teammate's share goes to the admin as a pull request.
- **No secrets.** No passwords, API keys, or tokens in any file. Connections use each tool's own sign-in.
- **Git only in this repo.** Commit here, by this folder's path. Never run destructive git at the company root.
- **Ask first** before you send, post, publish, pay, or delete anything outside this folder.

## Start of a session

Read these if your agent did not load them already:

1. `../../AGENTS.md` — the company rules (layout, skills, memory, review).
2. `../../memory/MEMORY.md`, then `memory/MEMORY.md` here.
3. `../../company-profile.md`, and any other shared file the task needs (`customers.md`, `offers.md`, `voice.md`, `people/`).

## What this area does

Marketing for {{COMPANY_NAME}}: content, campaigns, email, social, and the numbers that show what works.

<!-- add-area fills in: what it produces each week, the tools it uses, what "done well" means. -->

### Before any marketing work, read

- `../../voice.md` and `../../customers.md` — how we sound, who we talk to (shared, so sales and others use them too)
- `../../offers.md` — what we sell
- `personas.md` — the specific people marketing speaks to
- `goals.md` — what this period is for, and how we measure it
- `DESIGN.md` — the visual system (colors, fonts, layout), when it exists

If a file is empty or missing and the task needs it, ask only the questions that file would answer for this task, then write the answers into it.

### Marketing Toolkit (optional)

The free [Marketing Toolkit](https://github.com/1610-advisory/mktkit) adds skills for content plans, captions, video cuts, carousels, and performance reports. It reads the files above. It holds no company data: its outputs live in this area.

Check whether it is installed (Claude: the `ai-cmo` skills are listed). If not, offer it once, say what installing does, and ask first:

- **Claude Code:** `/plugin marketplace add 1610-advisory/mktkit`, then `/plugin install ai-cmo@mktkit`
- **Claude Desktop / Cowork:** Customize → Plugins → add marketplace `1610-advisory/mktkit` → install **ai-cmo**
- **Codex, Cursor, others:** `git clone https://github.com/1610-advisory/mktkit.git ~/toolkits/1610-mktkit`, then read its `CLAUDE.md` when you do marketing work here. If its last update is more than 7 days old, run `git -C ~/toolkits/1610-mktkit pull` first.

`~/toolkits/` is the one place on this computer for every toolkit: 1610's (named `1610-…`), others, and the company's own.

### Folders

- `plans/` — content plans
- `drafts/` — copy in progress
- `data/` — exports and metrics

## Skills

Area skills live in `skills/` here. Company skills live in `../../skills/` (ingest, connect-tool, write-skill, lint, suggest, logs-folder): read and follow those files the same way.

| Skill | Use when someone says |
|---|---|
| (none yet) | |

## Folders

- `inbox/` — capture for this area only. "Process the inbox" here files it into this area.
- `meetings/` — meetings only this area should see.
- `memory/` — how to work in this area. Session logs: `memory/logs/YYYY-MM-DD-<person-slug>.md`, on the `logs` branch (`../../skills/logs-folder/`).
- `skills/` — this area's SOPs.

## Changes and review

Same as the company rules: the admin commits directly; everyone else opens a pull request; session logs go on the `logs` branch in `memory/logs/`, committed directly.
