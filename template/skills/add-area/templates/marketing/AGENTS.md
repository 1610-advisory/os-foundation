# {{AREA_NAME}} — {{COMPANY_NAME}}

This is the **{{AREA_NAME}}** area of {{COMPANY_NAME}}'s company OS. It is its own git repo, so only people with access to this area have it on their computer.

**Company skills are in `../../skills/`.** If that folder is missing, read them from the company repo on the host (`{{COMPANY_SLUG}}-os`, folder `skills/`).

## Must-have rules (every agent, every session)

- **Level first.** Read `level:` and `switches:` in `../../company-profile.md`. Skip rules for a higher level or a switch that is off. **[team]** marks a rule for `team` and `app`.
- **One company only.** Use only this company's folder (`../../`). Never read or copy from another company's folder.
- **No secrets.** No passwords, API keys or tokens in any file. Connections use each tool's own sign-in.
- **No personal-life facts** in any file.
- **Private sources** (DMs, a personal mailbox, 1:1s, HR, pay): [team] keep them in the person's workspace. Solo: keep them out of the repo. Only plain facts go here: no quotes, no "X said in a DM".
- **Sharing up is a person's choice.** Move facts from this area into the shared company files (`../../`) only when a person asks.
- **Git only in this repo.** Commit here, by this folder's path. Never run destructive git at the company root.
- **Ask first** before you send, post, publish, pay or delete anything outside this folder.
- **No working copy in a synced folder** (iCloud Drive, Dropbox, OneDrive, Google Drive).

## Start of a session

1. [team] Run `../../skills/sync/sync.sh pull`. (Claude Code, Codex, Cursor and Pi. Chat-only agents skip it.)
2. [team] Run `../../skills/sync/sync.sh status`. Tell the person about each held file and its reason.
3. Read `../../AGENTS.md` if your agent did not load it: the company rules.
4. Read `../../memory/MEMORY.md`, then `memory/MEMORY.md` here.
5. Skim the last three days of `memory/logs/` here and in `../../memory/logs/`.
6. Read `../../company-profile.md` and any shared file the task needs.

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

### Work folders

- `plans/` — content plans
- `drafts/` — copy in progress, shared with everyone who reads this area. A private draft goes in your workspace `drafts/`.
- `data/` — exports and metrics

## Skills

Area skills live in `skills/` here. Company skills live in `../../skills/`: read and follow them the same way.

| Skill | Use when someone says |
|---|---|
| (none yet) | |

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
