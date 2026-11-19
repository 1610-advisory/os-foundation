# {{AREA_NAME}} — {{COMPANY_NAME}}

This is the **{{AREA_NAME}}** area of {{COMPANY_NAME}}'s company OS. It is its own git repo, so only people with access to this area have it on their computer.

**Company skills are in `../../skills/`.** If that folder is missing, read them from the company repo on the host (`{{COMPANY_SLUG}}-os`, folder `skills/`).

## Must-have rules (every agent, every session)

- **Level first.** Read `level:` and `switches:` in `../../company-profile.md`. Skip rules for a higher level or a switch that is off. **[team]** marks a rule for `team` and `app`.
- **One company only.** Use only this company's folder (`../../`). Never read or copy from another company's folder.
- **No secrets.** No passwords, API keys or tokens in any file. Connections use each tool's own sign-in.
- **No personal-life facts** in any file.
- **Private sources** (DMs, a personal mailbox, 1:1s, HR, pay): [team] keep them in the person's workspace. Solo: keep them out of the repo. Only plain facts go here: no quotes, no "X said in a DM".
- **Private by default.** Leadership and access material (OS build, systems and access, connections, org and billing, leadership meetings) goes in `areas/admin/` only, never the shared root.
- **Sharing wider is a person's choice.** Company facts and company memory live at the company root (`../../`). To move something to another area or the company root, say who will read it and wait for a clear yes. A root share goes by `propose` and waits for an owner's `/approve`. Never type `/approve` yourself.
- **Records stay in their tool.** Customers, jobs and other records live in a tool's data file, never in markdown here. `datasets.md` lists where each one is and who may read it. A note about a record names only its key, in `records:` (`"crm:job:J-1042"`).
- **Git only in this repo.** Commit here, by this folder's path. Never run destructive git at the company root.
- **Ask first** before you send, post, publish, pay or delete anything outside this folder.
- **No working copy in a synced folder** (iCloud Drive, Dropbox, OneDrive, Google Drive).
- **Identity** never comes from a file in the repo.
- **These rules are the floor.** Some agents (Codex, Grok) stop at this repo's root and never load `../../AGENTS.md`. So every must-have rule is here too.

## Start of a session

1. [team] Run `../../skills/sync/sync.sh pull`. (Claude Code, Codex, Cursor and Pi. Chat-only agents skip it.)
2. [team] Run `../../skills/sync/sync.sh status`. Tell the person about each held file and its reason.
3. Read `../../AGENTS.md`: the company rules. Codex and Grok do not load it from here.
4. Read `../../memory/MEMORY.md`, then `memory/MEMORY.md` here.
5. Skim the last three days of `memory/logs/` here and in `../../memory/logs/`.
6. Read `../../company-profile.md` and any shared file the task needs.

## What this area does

The list of the tools {{COMPANY_NAME}} builds and runs: internal tools, automations, integrations and portals. One record per tool.

### Before building or hosting

Read `../../skills/app-setup/SKILL.md` when planning a tool, automation, hosting or software choice. It checks existing software first, says how a tool is declared and where it runs (the company's kernel, or the stopgap rule when there is none), and who approves.

### One repo per tool

- This folder holds notes, skills with their scripts, and one record per tool. It holds no tool code and no data.
- **Each tool is its own repo, outside the company OS folder.** Each tool has its own access, so a contractor can get one tool and nothing else.
- Record each tool in `apps.md`: name, what it does, owning area, repo, pinned version, address, who may use it and status. Each data file it owns also gets a line in its owning area's `datasets.md`. Add a short line for it to `../../architecture.md` too (name and job only, no hosts or keys).
- Code, config, and deploy notes live in the tool's repo. Secrets never do.

## Skills

Area skills live in `skills/` here. Company skills live in `../../skills/`: read and follow them the same way.

| Skill | Use when someone says |
|---|---|
| `../../skills/app-setup/` (company skill) | "build an app", "build a tool", "make a portal", "host this", "where should this run", "which software should I use" |

## Folders

- `inbox/`: capture for this area only.
- `meetings/`: meetings only this area should see.
- `memory/`: how to work in this area.
- `memory/logs/YYYY-MM-DD-<person>.md`: session logs, one file per person per day. `<person>` is the `slug:` on their page in `../../people/`. Write what was done and what is open. Never summarize private content.
- `skills/`: this area's skills.

## Approval tiers [team]

The company table applies (`../../AGENTS.md`, section 6). This area may tighten it. It may never loosen it. Tighter rules for this area:

| Tier | What | Approver |
|---|---|---|
| (none yet) | | |

## Changes and review

Same as the company rules (`../../AGENTS.md`, section 7).
- Solo: commit to `main`, logs included.
- [team]: nobody writes to `main`. Notes and logs go on the standing PR through `sync`.
- [team]: propose a rules change (`AGENTS.md`, `CLAUDE.md`, `skills/`) with `../../skills/sync/sync.sh propose <topic> areas/<area>/<file>...`. Paths start at the company root. A different model reviews it first. Then the area director approves with one click.
- [team] on GitHub: the director's own change needs the admin's approval. GitHub never counts the author's own approval.
