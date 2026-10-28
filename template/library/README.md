---
type: reference
---

# Library

The company's own copy of what its tools hold: raw exports and full transcripts. The folder is the company's memory. Every tool is a worker that can be replaced. If the company leaves a tool, the copy here is enough.

This is a plain folder of the company repo. It has no rules file, skills, inbox or memory of its own. The company rules apply.

## Rules

1. **Copy by choice, per source.** Copy a source only after a person says yes to that source. Never bulk-import on your own. Each source and its mode (`index` or `copy`) is in `memory/existing-sources.md`.
2. **One writer per fact.** A copy is read-only. Never edit it. To update it, replace it with a newer copy. People and agents write in the wiki: `meetings/`, `people/`, `decisions/` and the company files. If a source moves into the folder for good, write in `existing-sources.md` that the folder is now where it is edited.
3. **Keep the raw form and the readable form.** Raw is the export as the tool gave it (JSON, VTT, TXT, CSV). Readable is the Markdown made from it. The readable form can always be made again from the raw.
4. **Records from business systems are rows, not Markdown.** CRM and accounting records come later as nightly table copies, in a restricted area. Do not turn them into notes.
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
access: company
retention: keep
---
```

- `raw`: the path from the company root, or `none`.
- `access`: `company`, or the area name for a restricted copy.
- `retention`: `keep`, `delete-after:YYYY-MM-DD`, or `delete-audio-after-transcript`.

## Media and data

- Git holds text only. Git ignores `media/` and `data/`, photos included: a repo that grew cannot shrink without rewriting its history.
- Name a media file by its SHA-256 hash: `media/<first 2 hex>/<sha256>.<ext>`. Hash with `shasum -a 256` (Mac) or `sha256sum` (Linux, Git Bash).
- List each media file in `media/LOCAL.md` (committed): hash, size, what it is, which computer, retention.
- **Media and data are on one computer only.** Sync to a store the company owns comes in a later version. Say so when a person adds a file.

## Restricted copies

Finance, HR, pay and health captures go in `areas/<area>/library/`, with the same layout. The area's access protects them. Never put them in this folder.

## How the wiki links here

- A meeting note keeps Summary, Decisions and Action items. It links the full transcript in front matter (`transcript: library/transcripts/YYYY-MM-DD Title.md`) and in the body (`[[transcripts/YYYY-MM-DD Title]]`). The folder in the link keeps it apart from the meeting note of the same name.
- A note names a media file by its path, for example `library/media/ab/<sha256>.jpg`. It shows only on the computer that has the file.
- More in the folder means more for an agent to read: a hosted AI provider processes what the agent reads.
