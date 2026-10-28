---
type: reference
---

# Library

The company's own full copy of what its tools hold: raw exports and full transcripts. The folder is the company's memory. Every tool is a worker that can be replaced. If the company leaves a tool, the copy here is enough.

## Who has it

- `library/` is **its own private git repo** at the company root. The company repo ignores it.
- Only the owner and admins have it. Teammates never clone it. Sync, join and upgrade never touch it.
- Only the admin's capture steps write it: `ingest` at the company root, on the admin's computer. (Nightly copies come in a later version.)
- It has no rules file, skills, inbox or memory of its own. The company rules apply.

## How people get value from it

- **The team reads the wiki.** The agent writes meeting summaries, people notes and decisions from the library into `meetings/`, `people/` and `decisions/`. Everyone with access reads those.
- **Records and photos with per-person access come from the business system** that already checks who may see what, for example a CRM through its own connector. Not from this folder.
- **The library is for completeness, exit, backup, and the admin's agent.** It holds the whole record so the company can leave any tool.

## Rules

1. **Copy by choice, per source.** Copy a source only after a person says yes to that source. Never bulk-import on your own. Each source and its mode (`index` or `copy`) is in `memory/existing-sources.md`.
2. **One writer per fact.** A copy is read-only. Never edit it. To update it, replace it with a newer copy. People and agents write in the wiki: `meetings/`, `people/`, `decisions/` and the company files. If a source moves into the folder for good, write in `existing-sources.md` that the folder is now where it is edited.
3. **Keep the raw form and the readable form.** Raw is the export as the tool gave it (JSON, VTT, TXT, CSV). Readable is the Markdown made from it. The readable form can always be made again from the raw.
4. **Records from business systems are rows, not Markdown.** CRM and accounting records come later as nightly table copies. Do not turn them into notes.
5. **Plan for deletion.** Every copied item records a retention. Default: transcripts and notes keep. Audio is deleted after a person checks the transcript (`checked: YYYY-MM-DD` in its front matter), unless the company chose to keep audio.

**Never edit a file under `raw/`.** Never delete one without a person's yes.

## Layout

- `raw/<source>/YYYY/`: text exports as the tool gave them (JSON, VTT, TXT, CSV). Keep the tool's file name. `<source>` is lowercase-kebab-case, for example `raw/meeting-recorder/2026/`.
- `transcripts/YYYY-MM-DD Title.md`: the full readable transcript of one meeting.
- `media/`: photos, images, audio and video. Not in git.
- `data/`: large or binary exports. Not in git.

## Front matter (every readable file)

```yaml
---
source: meeting-recorder
captured: YYYY-MM-DD
original: <link or id in the tool, or none>
raw: library/raw/meeting-recorder/2026/<file>
people: ["[[Full Name]]"]
access: admin
retention: keep
---
```

- `raw`: the path from the company root, or `none`.
- `access`: `admin` (the owner and admins).
- `retention`: `keep`, `delete-after:YYYY-MM-DD`, or `delete-audio-after-transcript`.

## Media and data

- Git holds text only. The library's `.gitignore` ignores `media/` and `data/`, photos included: a repo that grew cannot shrink without rewriting its history.
- Name a media file by its SHA-256 hash: `media/<first 2 hex>/<sha256>.<ext>`. Hash with `shasum -a 256` (Mac) or `sha256sum` (Linux, Git Bash).
- List each media file in `media/LOCAL.md` (committed): hash, size, what it is, which computer, retention.
- **Media and data are on one computer only.** Sync to a store the company owns comes in a later version. Say so when a person adds a file.

## Make it (admin's computer only)

Never make it on a teammate's computer.

1. Check that the company `.gitignore` has the line `/library/`. Add it if it is missing.
2. From the company root: `cp -R templates/library/. library/`, then `git -C library init -b main`, then commit everything with the message `Library: start`.
3. Team level only (`host:` in `company-profile.md` is not `none`). A library made at solo gets this step when the company moves to the team level. `<slug>` is `company_slug:` in `company-profile.md`.
   1. Make an empty private repo: `skills/_host/host.sh create-repo <slug>-library --private`. Note its `clone_url`.
   2. Grant it to each other admin (`skills/_host/host.sh grant <slug>-library <their login> admin`) and to nobody else.
   3. For each teammate, `skills/_host/host.sh user-access <slug>-library <their login>` must show no access. If a teammate has access, stop. Tell the admin the org's base permission lets members read every repo, and that it must change in the host's settings first. Push nothing until it shows no access.
   4. Then: `git -C library remote add origin <clone_url>` and `git -C library push -u origin main`.
4. Record it in `memory/existing-sources.md`.

## How the wiki links here

- A meeting note keeps Summary, Decisions and Action items. Its front matter names the transcript: `transcript: library/transcripts/YYYY-MM-DD Title.md`. Only the owner and admins can open it. The summary must read on its own.
- More in the folder means more for an agent to read: a hosted AI provider processes what the admin's agent reads.
