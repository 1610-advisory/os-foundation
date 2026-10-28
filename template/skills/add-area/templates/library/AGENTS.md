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

The library keeps {{COMPANY_NAME}}'s own copy of what its tools hold: meeting transcripts, exports, photos. The folder is the company's memory. Every tool is a worker that can be replaced. If the company leaves a tool, the copy here is enough.

<!-- add-area fills in: which sources it copies, who adds to it, what "done well" means. -->

### Rules for the library

1. **Copy by choice, per source.** Copy a source only after a person says yes to that source. Never bulk-import on your own. The list of sources, and the mode of each (`index` or `copy`), is in `../../memory/existing-sources.md`.
2. **One writer per fact.** A copy is read-only. Never edit it. To update it, replace it with a newer copy. People and agents write in the wiki: `meetings/`, `people/`, `decisions/` and the company files. If a source moves into the folder for good, write in `existing-sources.md` that the folder is now where it is edited.
3. **Keep the raw form and the readable form.** Raw is the export as the tool gave it (JSON, VTT, TXT, the original photo). Readable is the Markdown made from it. The readable form can always be made again from the raw.
4. **Records from business systems are rows, not Markdown.** CRM and accounting records will come later as nightly table copies, in a restricted area. Do not turn them into notes here.
5. **Plan for deletion.** Every copied item records a retention. Default: transcripts and notes keep. Audio is deleted after a person checks the transcript, unless the company chose to keep audio (local only, see Media).

**Never edit a file under `raw/`.** Never delete one without a person's yes.

### Layout

- `raw/<source>/YYYY/` — exports as the tool gave them. Keep the tool's file name. `<source>` is lowercase-kebab-case, for example `raw/meeting-recorder/2026/`.
- `transcripts/YYYY-MM-DD Title.md` — the full readable transcript of one meeting.
- `media/` — photos, images, audio and video, named by content (see Media).

### Front matter (every readable file)

```yaml
---
source: meeting-recorder          # the tool it came from
captured: YYYY-MM-DD              # the day the copy was made
original: <link or id in the tool, or none>
raw: raw/meeting-recorder/2026/<file>   # or none
people: ["[[Full Name]]"]
access: company                   # or the area name
retention: keep                   # or delete-after:YYYY-MM-DD, or delete-audio-after-transcript
---
```

### Media

- Name a file by its SHA-256 hash: `media/<first 2 hex>/<sha256>.<ext>`. Hash with `shasum -a 256` (Mac) or `sha256sum` (Linux, Git Bash).
- **Photos and images up to 2 MB are committed.** You may first make a smaller copy, for example longest side 2048 px, with a tool already on the computer (`sips` on a Mac, ImageMagick). Hash the file you commit. If no tool can shrink it, commit the original only if it is 2 MB or less.
- **Larger files and all audio and video stay on this computer.** Put them in `media/local/`, named the same way. List each in `media/LOCAL.md`: hash, size, what it is, which computer, retention. Git ignores them.
- Large media sync to a store the company owns comes in a later version. Until then a file in `media/local/` is on one computer only. Say so when a person adds one.
- A committed image takes the retention of the note that links it. Default: keep.

### How the wiki links here

- A meeting note keeps Summary, Decisions and Action items. It links the full transcript in front matter (`transcript: areas/{{AREA_SLUG}}/transcripts/YYYY-MM-DD Title.md`) and in the body (`[[transcripts/YYYY-MM-DD Title]]`). The folder in the link keeps it apart from the meeting note of the same name.
- A note shows an image with `![[media/ab/<sha256>.jpg]]`.
- A person without this area sees a link they cannot open. The summary still reads on its own.

### Access

The library is an ordinary area. Whoever the admin grants can read it. Sensitive captures (HR, pay, health) go in the area they belong to, not here. More in the folder means more for an agent to read: a hosted AI provider processes what the agent reads.

## Skills

Area skills live in `skills/` here. Company skills live in `../../skills/`: read and follow them the same way. `ingest` files captures here when this area is on the computer.

| Skill | Use when someone says |
|---|---|
| (none yet) | |

## Folders

- `inbox/`: capture for this area only.
- `meetings/`: meetings only this area should see.
- `memory/`: how to work in this area.
- `memory/logs/YYYY-MM-DD-<person>.md`: session logs, one file per person per day. `<person>` is the `slug:` on their page in `../../people/`. Write what was done and what is open. Never summarize private content.
- `skills/`: this area's skills.
- `raw/`, `transcripts/`, `media/`: the copies (see above).

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
