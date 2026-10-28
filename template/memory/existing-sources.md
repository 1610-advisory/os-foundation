---
name: Existing sources
description: Every tool or place that holds company knowledge, whether the folder points to it or keeps a copy, and where each fact is edited
type: reference
---

# Existing sources

The list of every source of company knowledge outside this folder. The folder is the company's memory; each tool is a worker it can replace. Each source has a mode: `index` (the folder keeps a pointer) or `copy` (the owner's private `library/` repo keeps a full copy; the team reads the summaries in the wiki). Rules for copies: `library/README.md` (or `templates/library/README.md` before the library exists). A person picks the mode per source. No sources recorded yet.

For each source, record:

- **Name** and what it holds.
- **Link or path.**
- **Maintained by:** the person, if known.
- **Access method:** connector, local file, export, or an excerpt shared by the person.
- **Access status:** not checked, unavailable, or verified YYYY-MM-DD.
- **Mode:** `index` or `copy`.
- **Copy goes to:** `library/raw/<source>/`, or `none` for `index`.
- **Refreshed:** `manual` (a person asks for a new copy). `nightly` comes in a later version. `none` for `index`.
- **Edited in:** the tool, or the folder. One place only. A copy is never edited.
- **Retention:** `keep`, `delete-after:YYYY-MM-DD`, or `delete-audio-after-transcript`.

Example (made up):

```
- Meeting recorder — call recordings and transcripts. Link: (the tool's web app). Maintained by: the office manager. Access: export. Status: verified 2026-01-15. Mode: copy. Copy goes to: library/raw/meeting-recorder/. Refreshed: manual. Edited in: the tool. Retention: delete-audio-after-transcript.
```

A link is not proof of access. Copy a source only after a person says yes to that source. Never bulk-import on your own, and never say a copy stays current by itself. CRM and accounting records will come later as nightly table copies in a restricted area; do not copy them as notes.

Never record credentials. Keep restricted source entries in the relevant area's memory, following the company's sharing rules.
