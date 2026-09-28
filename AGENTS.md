# My OS — rules for any AI agent

This folder is one person's whole working world: their personal knowledge and one folder per company they work in. You (the agent) keep it organized. The person captures, decides, and asks. You file, link, remember, and do the work.

`CLAUDE.md` only imports this file. Codex, Cursor, and other agents read this file directly. Keep it under 10,000 characters; put detail in `system/`.

## About me

<!-- setup fills this in -->
- **Name:** {{PERSON_NAME}}
- **Role:** {{ROLE}}
- **Companies:** {{COMPANY_LIST}}
- **How I like answers:** {{ANSWER_STYLE}}

## The layout

| Path | What it is |
|---|---|
| `inbox/` | Capture. Everything lands here. Nothing lives here. |
| `wiki/` | Personal knowledge: people, notes, ideas, reference, maps of content (`mocs/`) |
| `calendar/` | Time: meetings (`meetings/`), daily notes, reviews |
| `efforts/` | Personal projects, one folder or note each |
| `home/` | Dashboards |
| `templates/` | Note templates |
| `tools/` | Shared toolkits (for example the Marketing Toolkit). No company data ever goes in here. |
| `system/` | Your operating layer: `memory/`, `skills/`, `company-template/`, logs |
| `<company-slug>/` | One folder per company. See "Companies" below. |

A note's meaning comes from its YAML `type:` and its `[[wiki-links]]`, not its folder. Moving a file must never break it.

## Companies — one at a time

Each company folder is a **silo**.

- When you work inside `<company-slug>/`, use only that company's files. Never read, compare, or copy from another company's folder. Do not mention that other companies exist.
- Company knowledge (customers, offers, team, meetings, numbers) goes in the company folder, never in `wiki/` or `tools/`.
- Personal knowledge (the person's own notes, family, side interests) stays out of company folders.
- If you are unsure which company something belongs to, ask.

Inside a company:

| Path | What it is |
|---|---|
| `AGENTS.md` | What the company is, who the person is there, which functions and tools exist |
| `company.md` | The manifest: functions, connected tools, where data comes from |
| `core/` | Shared knowledge every function uses: `about.md`, `customers.md`, `offers.md`, `voice.md`, `people/`, `meetings/`, `decisions/` |
| `<function>/` | One folder per function the person works in (`marketing/`, `finance/`, `sales/`, ...) with its own `AGENTS.md` |
| `memory/` | How to work at this company (preferences, standing decisions). Same format as `system/memory/`. |

**Work starts in a function folder.** If the person opens `~/os/acme/marketing/`, read (if your agent did not load them already) `~/os/AGENTS.md`, then `~/os/acme/AGENTS.md`, then `marketing/AGENTS.md`, then `acme/memory/MEMORY.md`. Then you are briefed. `core/` is for reading and curating, not for day-to-day work.

## Skills — how to do the recurring jobs

Skills are SOPs in plain markdown under `system/skills/<name>/SKILL.md`. When the person's request matches one, read the file and follow it. Claude Code also sees them as slash commands (`.claude/skills` links here).

| Skill | Use when the person says |
|---|---|
| `setup` | "run setup", first session in a fresh copy |
| `add-company` | "add a company", "I also work at ..." |
| `add-function` | "add sales / operations / HR to ..." |
| `connect-tool` | "connect my email / calendar / QuickBooks / Slack / CRM ..." |
| `ingest` | "process my inbox", "file this", "here's a meeting recording" |
| `vault-lint` | "lint the vault", "health check", weekly |
| `write-skill` | "write this down", "make a skill for this", or you notice you are being told the same thing twice |

Every time the person re-explains how they want something done, offer to write it as a skill. That is how this system gets better.

## Memory

Memory holds facts about **how to work**. The wiki and company folders hold facts about **the world**.

- Personal memory: `system/memory/`. Company memory: `<company-slug>/memory/`. Each has a `MEMORY.md` index, one line per memory: `- [Title](file.md) — hook`.
- One fact per file, with frontmatter `name`, `description`, `type: user | feedback | project | reference`. Update an existing file before making a new one. Delete memories that turn out wrong. Use absolute dates.
- Read the right `MEMORY.md` at the start of a session. At the end of real work, append a short entry to `system/memory/logs/YYYY-MM-DD.md` (or the company's `memory/logs/`): what was done, what is open.

## Conventions

1. `[[Wiki-links]]` everywhere. Link people, companies, and meetings each time you mention them.
2. Meeting notes: `YYYY-MM-DD Title.md`. Company meetings go in `<company>/core/meetings/`; personal ones in `calendar/meetings/`.
3. Folder names: lowercase-kebab-case, no emoji.
4. Maps of content carry a static list between `<!-- auto:index:begin -->` and `<!-- auto:index:end -->`. You own the inside of the fence. The person owns the outside.
5. Markdown is the source. HTML, PDFs, and slides are outputs made from markdown. No fact lives only in an output.
6. Put links to other notes in a `related:` list in frontmatter, not in `tags:`.

## Safety

- No passwords, API keys, or tokens in any file, ever. If you find one, stop and tell the person.
- Connections belong to the company they serve. Set them up from inside that company's folder (see `connect-tool`).
- Before you send, post, publish, pay, or delete anything outside this folder, show it and ask.
