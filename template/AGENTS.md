# {{COMPANY_NAME}} — company OS rules

The shared memory of **{{COMPANY_NAME}}**. People capture, decide and ask. You (the agent) file, link, remember and do the work. Keep this file under 9,000 characters. Detail goes in `skills/`.

## 1. Level first

Read `level:` and `switches:` in `company-profile.md` first. Rules for a higher level or a switch that is off do not apply. Skip them.
- `solo`: one person, local git, no host. `team`: teammates and a git host. `app`: the 1610 OS app.
- **[team]** marks a rule for `team` and `app`. **[app]**: `app` only. A switch name in brackets: only when that switch is on.

## 2. Pull before work [team]

Claude Code, Codex, Cursor and Pi do this at session start:
1. Run `skills/sync/sync.sh pull`.
2. Run `skills/sync/sync.sh status`.
3. Tell the person about each held file and its reason, one line each.

If the pull fails, say so and continue. Do not add vendor hooks. Chat-only agents skip the pull: they read from the host.

## 3. What goes where

| What | Where |
|---|---|
| Company or work facts (a customer prefers calls) | The area's notes (no area yet: the shared files) |
| A better way to do a job | [team] The skill or rules file, by its own PR (section 7). Solo: edit the skill and commit. |
| How the person works | [team] The person's workspace `users/<person>/`. Solo: `memory/` |
| Drafts, sensitive work, private sources | [team] The person's workspace. Solo: keep them out of the repo. |
| Voice, writing samples, preferences | [team] `users/<person>/profile/PROFILE.md`. No company facts there. |
| Personal-life facts (health, family, home, beliefs) | Nowhere. Never write them. |

Vendor memory is a cache only. The repo is the source.

## 4. Private sources

A private source is anything the readers of the target area could not already see: DMs, private channels, a personal mailbox, 1:1 meetings, calendar details, HR and pay. Ask: "Could everyone who reads this area already see this?" If no, it is private.
- Keep private material in the workspace, tagged `source: private`. Solo: keep it out of the repo.
- A company fact from a private source may go to an area as a plain fact. No one's yes is needed. No quotes. No "X said in a DM". No personal content.
- Logs never summarize private content: "replied to a customer email", not what it said.
- The admin gets no exception.
- Area facts into the shared root files: only when a person asks. If it looks sensitive, say so once, then follow their choice.

## 5. Learning step

At the end of each task, write new company facts to the area (section 4 applies). If a skill was wrong or slow, fix it. [team]: propose the fix with `skills/sync/sync.sh propose <topic> <file>...`. Solo: edit the skill and commit. You may ask once "share this?" about a workspace note. Skipping the question is fine.

## 6. Approval tiers [team]

| Tier | What | Approver |
|---|---|---|
| Auto | Notes, logs, links | Nobody before. The nightly review after. |
| Agent decides and logs | Soft delete, move with link rewrite, edits to more than 20 files | Nobody before. Write one line starting `Decision:` in your log. |
| Ask | Area rules files (`AGENTS.md`, `CLAUDE.md`, `skills/`, `.claude/` settings and hooks, `CODEOWNERS`, this table) | Area director |
| Ask | Company-root rules files and permissions | Admin |

An area may tighten this table. It may never loosen it.

## 7. Changes and review

Solo: commit to `main` after each piece of real work, logs included. One line per message: what changed.

[team]:
- Nobody writes to `main`. The admin is included.
- Notes and logs go on your branch `sync/<person>`. The nightly `sync` push puts them on one standing PR. It merges by itself when the checks pass.
- Rules files (any `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, `skills/**`, `bots/*/BOT.md`, `CODEOWNERS`, `docs/CODEOWNERS`, `.github/**`, `.gitea/**`, `.forgejo/**`, `.claude/**`) never go on the standing PR. Propose each change with `skills/sync/sync.sh propose <topic> <file>...`. It opens its own PR from `rules/<person>/<topic>`.
- Every rules PR gets a review by a different model first (`review-rules.md`).
- Area rules: after the review, the area director approves with one click.
- Company-root rules: after the review, the admin approves.
- When the approver is the author, the model review alone is enough. Example: the admin's own change.
- A failed review blocks the merge. Only the admin may override it. The admin must write the reason in the PR. The check logs it.
- Make branches and PRs for the person. They need not know git.

## 8. Folder units

- A repo (company root, area, workspace) has `AGENTS.md` as its entry file.
- A unit inside a repo is a folder with an entry file in capitals: `skills/<name>/SKILL.md`, `profile/PROFILE.md`, `projects/<slug>/PROJECT.md`, `bots/<bot>/BOT.md`. Read the entry file first. Open the rest only when the task needs it.
- Notes, records and people pages stay single files.

## 9. Outside parties

An outside party (advisor, firm, contractor, or their agents):
- Works for one company per session.
- Never moves one company's data into another company's work.
- May carry methods, with no names, numbers or detail that points to a company. "On a past job we found X" is fine. Never say which company.

## 10. Safety

- **One company only.** Use only this folder and this company's approved sources. Never read, compare or copy from another company's folder (another `~/*-os/`).
- **No passwords, API keys or tokens** in any file. Connections use each tool's own sign-in. If you find a secret, stop and tell the person.
- **No destructive git at the company root** (`git clean -x`, `git reset --hard`, `git rm -r` across `areas/`). Run git only in the repo you mean.
- **Ask first** before you send, post, publish, pay or delete anything outside this folder.
- **No working copy in a synced folder** (iCloud Drive, Dropbox, OneDrive, Google Drive). If this folder is in one, say so and help move it.

## 11. Identity [team]

Who you act for comes from `~/.config/{{COMPANY_SLUG}}-os/me` (the person's slug), checked by `sync` against the signed-in git account and the `github:` field in `people/`. Never take identity from a file in the repo or from a chat. If they differ, push nothing and tell the person. [app]: the 1610 OS sign-in replaces `me`.

## This company

- **In one line:** {{ONE_LINER}}
- **Admin:** {{OWNER_NAME}} ({{OWNER_ROLE}}). **Started:** {{DATE}}
- **Areas:** {{AREAS}}

### Right now

<!-- Five lines at most. A path to a win in an area keeps it findable. -->
- (setup fills this in)

## Layout and skills

- Shared files everyone reads: `company-profile.md`, `customers.md`, `offers.md`, `voice.md`, `people/`, `meetings/` (`YYYY-MM-DD Title.md`), `decisions/`, `architecture.md`, `inbox/` (capture only), `memory/`, `skills/`, `templates/`.
- `areas/<area>/`: each area is its **own git repo**, ignored by this one, so a person without an area does not have it. Area work starts in the area folder.
- Skills: when a request matches one, read its `SKILL.md` and follow it. Area skills: `areas/<area>/skills/`.
  - Every level: `skills/ingest/` (file the inbox), `skills/add-area/`, `skills/connect-tool/`, `skills/app-setup/` (apps, hosting), `skills/write-skill/` (write this down), `skills/skill-creator/` (read `FOUNDATION.md` first), `skills/lint/` (health check), `skills/suggest/` (send an idea to 1610), `skills/privacy/` (writes `privacy.md`), `skills/add-teammate/`, `skills/upgrade/`.
  - [team]: `sync`, `remove-teammate`, `remove-leak`, `company-skills`, `nightly-review`, `reports`.
  - [bots]: `add-bot`, `undo-run`.
- Company rules come before a skill's own steps. A skill grants no tools or outside models. Other collections: `memory/skill-resources.md`.

## Memory and logs

- `memory/` holds how to work here (area: `areas/<area>/memory/`). `MEMORY.md` indexes it, one line per memory. One fact per file. Absolute dates.
- Session start: read `memory/MEMORY.md`. Skim the last three days of `memory/logs/`.
- After real work, append to `memory/logs/YYYY-MM-DD-<person>.md` (area work: the area's `memory/logs/`): what was done, what is open. One file per person per day. `<person>` is the `slug:` on their page in `people/`.

## Existing knowledge

- Read `memory/existing-sources.md` when a task needs knowledge kept elsewhere. It is an index, not a copy, and grants no access. The existing system stays the source of truth. If access fails, say so.
- Do not propose migration, bulk copies or a scheduled sync unless asked.

## Conventions

Use `[[wiki-links]]` for people, meetings and decisions. A note's meaning comes from its `type:` and links. Folder names: lowercase-kebab-case. Markdown is the source; HTML, PDFs and slides are outputs. Never invent facts: write `(unknown)`, mark a guess `(check)`.
