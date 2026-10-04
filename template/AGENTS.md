# {{COMPANY_NAME}} — company OS rules

This folder is the company OS for **{{COMPANY_NAME}}**: the shared memory of the business, set up so any AI agent opened here already knows how the company works. You (the agent) keep it organized. People capture, decide, and ask. You file, link, remember, and do the work.

`CLAUDE.md` imports this file. Codex, Cursor, and other agents read it directly. Keep it under 10,000 characters; put detail in `skills/` or `memory/`.

## The company in one line

{{ONE_LINER}}

## Admin

- **Admin:** {{OWNER_NAME}} ({{OWNER_ROLE}}). The admin approves changes to shared files. See "Changes and review."
- **Started:** {{DATE}}

## Right now

<!-- What the company is focused on this quarter. Five lines at most. -->
- (setup fills this in)

## The layout

| Path | What it is | Who reads it |
|---|---|---|
| `company-profile.md` | What the company does, history, size, how it makes money | everyone |
| `customers.md` | Who buys, what problem they solve, the best customer | everyone |
| `offers.md` | What is for sale, rough prices, what people buy first | everyone |
| `voice.md` | How the company sounds when it writes | everyone |
| `people/` | One note per teammate, customer contact, or partner | everyone |
| `meetings/` | Shared meeting notes, `YYYY-MM-DD Title.md` | everyone |
| `decisions/` | One note per decision that should outlast a meeting | everyone |
| `architecture.md` | Connected tools and apps (made when the first one is added) | everyone |
| `inbox/` | Capture for shared items. Nothing lives here. | everyone |
| `memory/` | How to work at this company. `memory/logs/` holds session logs (its own branch). | everyone |
| `skills/` | Company skills (SOPs for the agent) | everyone |
| `templates/` | Note templates | everyone |
| `areas/<area>/` | One folder per area of the business. Each area is its own git repo. | only people with access to that area |

A note's meaning comes from its YAML `type:` and its `[[wiki-links]]`, not its folder.

## Areas — access lives here

Areas: {{AREAS}}

- Each area under `areas/` is its **own git repo**. The company folder's git ignores `areas/`. That is how access works: a person who should not see finance never gets the finance repo, so `areas/finance/` is not on their computer.
- **Work starts in an area.** Marketing work: open your agent in `areas/marketing/`. General company questions: open it here, at the company root. A session here may read the areas on this computer: a person only has the areas they are allowed to see.
- **Never copy area facts into shared files.** Pay, raw numbers, HR notes, and customer records stay in their area. Everyone with access to the company folder reads the shared files, including people without that area. Area facts reach shared files only when a person decides to share them.
- Folders organize work. Areas control access. A sub-folder inside an area is fine when the same people see all of it. A group of people with different access gets its own area.
- `areas/apps/` holds software: one repo per app inside it (a customer portal goes at `areas/apps/portal/`).

## Skills — the recurring jobs

Skills are SOPs in plain markdown. When a request matches one, read the file and follow it. Claude Code also sees `skills/` as slash commands.

| Skill | Use when someone says |
|---|---|
| `skills/ingest/` | "process the inbox", "file this", "here's a meeting recording" |
| `skills/add-area/` | "add sales / operations / HR", "set up an area for ..." |
| `skills/connect-tool/` | "connect email / calendar / QuickBooks / Slack / CRM ..." |
| `skills/add-teammate/` | "give <person> access", "share this with my team" |
| `skills/write-skill/` | "write this down", "make a skill for this", or you are told the same thing twice |
| `skills/lint/` | "health check", "lint", weekly |
| `skills/suggest/` | "I solved this", "send this idea to 1610", "suggest a fix" |
| `skills/logs-folder/` | "the logs folder is missing" (setup and add-area use it too) |

Each area can have its own skills in `areas/<area>/skills/`. Every time someone re-explains how they want something done, offer to write it as a skill. That is how the OS gets better.

## Memory

Memory holds facts about **how to work**. The other files hold facts about **the company**.

- Company memory: `memory/`. Area memory: `areas/<area>/memory/`. Each has a `MEMORY.md` index, one line per memory: `- [Title](file.md) — hook`.
- One fact per file, with frontmatter `name`, `description`, `type: user | feedback | project | reference`. Update an existing file before you make a new one. Delete memories that turn out wrong. Use absolute dates.
- Read `memory/MEMORY.md` at the start of a session.
- At the end of real work, append a short entry to `memory/logs/YYYY-MM-DD-<your-person-slug>.md` (in the area's `memory/logs/` for area work): what was done, what is open. One file per person per day, so teammates never edit the same file.
- `memory/logs/` is the repo's `logs` branch, checked out as a folder. Commit and push logs there directly (`skills/logs-folder/` → "Write a log"). Curated memory stays on `main`.

## Changes and review

- **The admin** may commit directly to `main`.
- **Everyone else** opens a pull request for any change to shared files (knowledge, memory, skills, rules). The admin approves it. Make the branch and the PR for the person; they do not need to know git.
- **Session logs** are the exception: they live on the `logs` branch (`memory/logs/`), which has no review rule. Commit and push them directly.
- Commit after each piece of real work, with a one-line message that says what changed. Local git works with no GitHub account. GitHub is needed only when a teammate joins (`skills/add-teammate/`).

## Conventions

1. `[[Wiki-links]]` everywhere. Link people, meetings, and decisions each time you mention them.
2. Meeting notes: `YYYY-MM-DD Title.md`. Shared meetings in `meetings/`. Area-only meetings in that area's `meetings/`.
3. Folder names: lowercase-kebab-case, no emoji.
4. Markdown is the source. HTML, PDFs, and slides are outputs made from markdown. No fact lives only in an output.
5. Never invent facts. Leave a blank or write `(unknown)`. Mark a guess with `(check)`.

## Safety

- **One company only.** Use only files inside this company folder. Never read, compare, or copy from another company's folder (another `~/*-os/`). Do not mention that other companies exist.
- **No passwords, API keys, or tokens** in any file, ever. Connections use each tool's own sign-in. If you find a secret in a file, stop and tell the person.
- **Never run destructive git at the company root** (`git clean -x`, `git reset --hard`, `git rm -r` across `areas/`). Run git only inside the one repo you mean.
- Before you send, post, publish, pay, or delete anything outside this folder, show it and ask.
