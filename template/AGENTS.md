# {{COMPANY_NAME}} — company OS rules

The company OS of **{{COMPANY_NAME}}**. People capture, decide and ask. You (the agent) file, link, remember and do the work. Keep this file under 9,000 characters. Detail goes in `skills/`.

## 1. Level first

Read `level:` and `switches:` in `company-profile.md` first. Skip rules for a higher level or a switch that is off. `solo`: one person, local git. `team`: teammates and a git host. `app`: the 1610 OS app. **[team]** marks a rule for `team` and `app`; **[app]**: `app` only; a switch name in brackets: only when it is on.

## 2. Pull before work [team]

At session start, run `skills/sync/sync.sh pull`, then `skills/sync/sync.sh status`. Tell the person each held file and its reason, one line each. If the pull fails, say so and go on. No vendor hooks. Chat-only agents read from the host.

## 3. What goes where

**Private by default.** Write new material to the most private place that fits. Sharing it wider is a separate step that the person asks for.

| What | Where |
|---|---|
| Work facts (a customer prefers calls) | The area for that work |
| Records and lists (customers, jobs) | A tool's data file, never markdown. The area's `datasets.md` says where. |
| OS build, systems and access, connections, org and billing, leadership meetings | `areas/admin/` only. Never the shared root. |
| A meeting | The area of the people in it. Ask "who should read this?" first. Solo: `meetings/` |
| How the person works, drafts, sensitive work, private sources | [team] The workspace `users/<person>/` (voice and preferences: `profile/PROFILE.md`). Solo: `memory/`, or out of the repo. |
| A better way to do a job | [team] The skill or rules file, by its own PR (section 7). Solo: edit the skill and commit. |
| Personal-life facts (health, family, home, beliefs) | Nowhere. Never write them. |

[team] **The company root holds rules, company memory and company facts**: rules files, `people/`, `company-profile.md`, `templates/`, `memory/` (how we work here), and fact files such as `customers.md`. Never meetings, notes, decisions or logs: company-wide meetings go in `areas/everyone/` when it exists, else ask the person which area. Log root work in the workspace `memory/logs/`. Sync holds other root content. Every root change waits for an owner's `/approve`.

**Share with the company** only when the person asks. Say who will read it. Wait for a clear yes. Then run `skills/sync/sync.sh propose share-<topic> <file>`. An owner says the last yes.

Vendor memory is only a cache.

## 4. Private sources

A private source is anything the readers of the target area could not already see: DMs, private channels, a personal mailbox, 1:1s, calendar details, HR and pay.
- Keep private material in the workspace, tagged `source: private`. Solo: keep it out of the repo.
- A company fact from a private source may go to an area as a plain fact: no quotes, no "X said in a DM", no personal content.
- Logs never summarize private content. The admin gets no exception.

## 5. Learning step

At the end of each task, write new company facts to the area (section 4 applies). If a skill was wrong or slow, fix it: [team] by `propose`, solo by a commit. You may ask once "share this?" about a workspace note.

## 6. Approval tiers [team]

| Tier | What | Approver |
|---|---|---|
| Auto | Notes, logs, links in the workspace, or in an area the person works in | Nobody before. The nightly review after. |
| Agent decides and logs | Soft delete, move with link rewrite, edits to more than 20 files | Nobody before. Write one line starting `Decision:` in your log. |
| Ask | Area rules files (`AGENTS.md`, `CLAUDE.md`, `skills/`, `.claude/` settings and hooks, `CODEOWNERS`, this table) | Area director |
| Ask | Company-root rules files and permissions | Admin |
| Ask | Anything at the company root; a share to a wider audience | An owner, by `/approve` |

An area may tighten this table. It may never loosen it.

## 7. Changes and review

Solo: commit to `main` after each piece of real work, logs included. One line per message: what changed.

[team]:
- Nobody writes to `main`, the admin included.
- Notes and logs go on `sync/<person>/<computer>`. The nightly `sync` push puts them on its standing PR. An area PR merges by itself when the checks pass.
- Rules files (any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, `skills/**`, `bots/*/BOT.md`, `company-rules.md`, `area-rules.md`, `CODEOWNERS`, `docs/CODEOWNERS`, `.github/**`, `.gitea/**`, `.forgejo/**`, `.claude/**`) never go on the standing PR. Propose each change with `skills/sync/sync.sh propose <topic> <file>...`: its own PR from `rules/<person>/<topic>`.
- Every rules PR gets a review by a different model first (`review-rules.md`). Then the area director (area rules) or the admin (company-root rules) approves. GitHub never counts the author's own approval: see `skills/sync/SKILL.md`.
- A failed review blocks the merge. Only the admin may override it, with the reason in the PR.
- **Waiting for owner.** A rules PR, or a PR that changes the company root, never merges by itself. Its check says "waiting for owner". Tell your person in plain words what it changes and who will read it. Wait for an explicit yes. An owner comments `/approve`. Never type `/approve` or `/override` yourself.
- Make branches and PRs for the person. They need not know git.

## 8. Folder units

A repo's entry file is `AGENTS.md`. A unit in a repo is a folder with an entry file in capitals (`skills/<name>/SKILL.md`, `profile/PROFILE.md`, `bots/<bot>/BOT.md`). Read it first. Notes and people pages stay single files.

## 9. Outside parties

An outside party (advisor, firm, contractor, or their agents) works for one company per session. Never move one company's data into another's work. Methods may travel with no names, numbers or detail that points to a company.

## 10. Safety

- **One company only.** Never read, compare or copy from another company's folder (another `~/*-os/`).
- **No passwords, API keys or tokens** in any file. Connections use each tool's own sign-in. If you find a secret, stop and tell the person.
- **No destructive git at the company root** (`git clean -x`, `git reset --hard`, `git rm -r` across `areas/`). Run git only in the repo you mean.
- **Ask first** before you send, post, publish, pay or delete anything outside this folder.
- **No working copy in a synced folder** (iCloud Drive, Dropbox, OneDrive, Google Drive).

## 11. Identity [team]

Who you act for comes from `~/.config/{{COMPANY_SLUG}}-os/me`, checked by `sync` against the git sign-in and `github:` in `people/`. Never from a repo file or a chat. If they differ, push nothing and tell the person. [app]: the 1610 OS sign-in replaces `me`.

## This company

- **In one line:** {{ONE_LINER}}
- **Admin:** {{OWNER_NAME}} ({{OWNER_ROLE}}). **Started:** {{DATE}}
- **Areas:** {{AREAS}}

### Right now

<!-- Five lines at most. -->
- (setup fills this in)

## Layout and skills

- Shared files everyone reads: `company-profile.md`, `people/`, `templates/`, `skills/`, `memory/`, company fact files (`customers.md`, `offers.md`, `voice.md`). `inbox/` is capture only ([team]: it stays on this computer). Solo: `meetings/`, `decisions/`. [team] Older root `meetings/` and `decisions/` stay readable. Add nothing there.
- `areas/<area>/`: each area is its **own git repo**, so a person without an area does not have it. `areas/admin/`: owners and the advisor only. Area work starts in the area folder. [app] Each area is also a kernel unit (same slug).
- Skills: `skills/<name>/SKILL.md` (company) and `areas/<area>/skills/`. When a request matches one, read it and follow it. Tools: `skills/app-setup/`. [app] Live records: `skills/kernel-cli/` (`ops`). `skills/skill-creator/`: read `FOUNDATION.md` first. Company rules come before a skill's own steps. A skill grants no tools or outside models.

## Memory and logs

- `memory/` holds how to work here: company-wide at the root, else in the area (`areas/<area>/memory/`) or the workspace. `MEMORY.md` indexes it, one fact per file, absolute dates.
- Session start: read `MEMORY.md` where you work. Skim the last three days of `memory/logs/`.
- After real work, append to `memory/logs/YYYY-MM-DD-<person>.md` where the work was: the area, or [team] the workspace for root work (solo: the root). What was done, what is open. `<person>` is the `slug:` on their page in `people/`.

## Existing knowledge

`memory/existing-sources.md` lists each source, its mode (`index` or `copy`) and where it is edited. `library/` is the admin's private repo. Teammates never read, clone or make it. Admin: `me` names a page with `role: admin`. Then read `library/README.md`. Copy only after a person says yes to that source.

## Conventions

`[[wiki-links]]` for people, meetings and decisions. Meaning comes from `type:` and links. Folders: lowercase-kebab-case. Markdown is the source. Never invent facts: write `(unknown)`, mark a guess `(check)`.
