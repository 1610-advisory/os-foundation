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
3. Recent work: if there is a GitHub remote, pull the logs here and at the company root (`git -C memory/logs pull -q`, `git -C ../../memory/logs pull -q`). Skim the last two or three days of logs here and in `../../memory/logs/`.
4. `../../company-profile.md`, and any other shared file the task needs (`customers.md`, `offers.md`, `voice.md`, `people/`).

## What this area does

<!-- add-area fills this in: what it produces each week, the tools it uses, what "done well" means. -->

## Skills

Area skills live in `skills/` here. Company skills live in `../../skills/` (ingest, connect-tool, write-skill, lint, suggest, logs-folder): read and follow those files the same way.

| Skill | Use when someone says |
|---|---|
| (none yet) | |

## Folders

- `inbox/` — capture for this area only. "Process the inbox" here files it into this area.
- `meetings/` — meetings only this area should see.
- `memory/` — how to work in this area. Session logs: `memory/logs/YYYY-MM-DD-{{PERSON_SLUG}}.md`, on the `logs` branch (`../../skills/logs-folder/`).
- `skills/` — this area's SOPs.

## Changes and review

Same as the company rules: the admin commits directly; everyone else opens a pull request; session logs go on the `logs` branch in `memory/logs/`, committed directly.
