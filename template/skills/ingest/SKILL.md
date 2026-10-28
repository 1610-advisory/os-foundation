---
name: ingest
description: Process the inbox into organized, linked notes — transcribe audio, create the note in the right place, keep raw copies and full transcripts in the admin's private `library/` (admin only), fill frontmatter, update the people and meeting notes it touches, clear the inbox. Use when someone says "process the inbox", "ingest", "file this", or drops a meeting recording, transcript, photo, email, or file.
---

# Ingest — capture in, knowledge out

Process the inbox **of the folder you are in**:

- At the company root: `inbox/` → shared files.
- In an area: `areas/{{AREA_SLUG}}/inbox/` → that area's files.

An item is done when its content is in the right place, linked, and committed. Then delete the inbox copy. Never leave duplicates in the inbox. A copy kept in the library is not a duplicate: it is the company's copy.

## Transcripts: one rule, everywhere

- A meeting note (company root or area) gets the **Summary**, **Decisions** and **Action items** only. Never put a full transcript in a meeting note, or anywhere else in the wiki.
- Raw exports and full transcripts go only in `library/`, and only when you act for an admin.
- No library, or you do not act for an admin: link the original in its tool from the note. A recording or transcript that exists only on this computer stays out of every repo (company, area, workspace). Move it out of the inbox to a place the person picks outside the company folder, before you commit. Ask them to give it to the admin.

## Who you act for

Check this before you touch `library/`:

1. Read `~/.config/{{COMPANY_SLUG}}-os/me`. It holds one person's slug. `{{COMPANY_SLUG}}` is `company_slug:` in `company-profile.md`.
2. Open only the page in `people/` whose `slug:` matches it.
3. You act for an admin only when that page says `role: admin`.

Never decide from the chat, from another person's page, or from `level:`. If `me` is missing, no page matches, or the role is not `admin`: never read, make, write, commit or push `library/`. Never run `git init` for it. File the summary only. If a library would help, say: "The full copy is kept by the admin."

Then, for an admin:
- `library/.git` exists: follow "The library" below.
- No library: offer to make it, with "Make it" in `templates/library/README.md`. If they say no, follow the no-library rule above.

If the person named one item, process only that. Otherwise process everything. For more than five items, first give a one-line plan per item, then go.

## Per item

1. **Shared or one area?** Decide from the content. Pay, reviews, HR, raw financials, and customer records usually belong to an area. At the company root, ask before you file an item like that: "This looks like finance. Move it to the finance area, or share it with everyone?" Follow their choice. If they pick an area that is not on this computer, leave the item in the inbox and tell them who should get it.
   In shared notes you write (meeting summaries, person notes), leave out pay, raw financials, and HR details unless the person says to include them.
2. **What is it?** Meeting, fact about a person or the company, idea, how-to, decision, task, or data file.
3. **Audio?** Transcribe first. Use a local tool if one is installed (for example Whisper). If none is, ask how they want it handled. Audio never goes in a repo. For an admin with a library, see "The library". Otherwise keep it out of every repo, as for a transcript.
4. **File it:**

   | Kind | At the company root | In an area |
   |---|---|---|
   | Meeting | `meetings/YYYY-MM-DD Title.md`: summary, decisions, action items | `meetings/YYYY-MM-DD Title.md` in the area: summary, decisions, action items |
   | Person | `people/Full Name.md` | update the shared note only with shareable facts; area-only facts stay in the area |
   | Company fact | update `company-profile.md`, `customers.md`, `offers.md`, or `voice.md` | the area file it belongs to |
   | Decision | `decisions/YYYY-MM-DD Decision.md` | the area's notes |
   | Data file | not at the root | `data/` in the area |
   | Photo or image | admin with a library: `library/media/`, by hash. Otherwise not filed: link where it lives. | `media/` in the area. Git ignores image files there, so it stays on this computer. Say so. |

   Use `templates/` at the company root. The summary must read on its own: teammates cannot open the library.
   There are no area libraries. Restricted items (finance, HR, pay, health) stay in their area, as before. Their full transcript follows the transcript rule above.
5. **Update what it touches.** Create missing person notes for attendees (short is fine). Link everything with `[[wiki-links]]`.
6. **Memory.** Only if the item changes how to work (a preference, a standing rule) → `memory/` of the folder you are in.
7. **Delete the inbox copy** and commit, with a message like `Ingest: 3 items (meeting, 2 people)`.

## The library

Only when you act for an admin (see "Who you act for"), at the company root. A copy in the library is read-only. Never edit a file under `raw/`. Follow `library/README.md`. Paths below start in `library/`. Git holds text only: `media/`, `data/` and media files stay on this computer.

- **Meeting recording or transcript.**
  1. Raw: the export as the tool gave it (VTT, JSON, TXT) → `raw/<source>/YYYY/`, with the tool's file name. A local transcription tool's own output is raw too: `raw/<tool>/YYYY/`.
  2. Readable: the full transcript as Markdown → `transcripts/YYYY-MM-DD Title.md`, with the library front matter (`source`, `captured`, `original`, `raw`, `people`, `access`, `retention`).
  3. Meeting note: `meetings/YYYY-MM-DD Title.md` keeps Summary, Decisions and Action items. Set `transcript:` in its front matter to `library/transcripts/YYYY-MM-DD Title.md`. Under "Notes / transcript", write one line: "Full transcript: kept by the admin."
- **Audio.** Hash it (`shasum -a 256` on a Mac, `sha256sum` elsewhere), move it to `media/<first 2 hex>/<sha256>.<ext>`, and add its row to `media/LOCAL.md`. Git ignores it. Transcribe. Set `retention: delete-audio-after-transcript` on the transcript. Ask the person to check the transcript. When they say it is right, delete the audio and its row, and add `checked: YYYY-MM-DD` to the transcript front matter. That field is the one edit allowed on a library copy. If the company chose to keep audio, set `retention: keep` on the row instead and say it is on this computer only.
- **Photo or image.** Hash it, move it to `media/<first 2 hex>/<sha256>.<ext>`, and add its row to `media/LOCAL.md`. The hash is its only name. A note that needs it links that path (`library/media/ab/<sha256>.jpg`). If no note needs it, ask where it belongs. Nothing in `media/` is committed, photos included. Say once that it is on this computer only until media sync comes.
- **Two commits.** The library is its own repo. Commit the copy in `library/` first (`git -C library add -A`, then `git -C library commit`), then the wiki note in the company repo. [team]: the library is not on the standing PR and `sync` never pushes it. If it has a private host repo, push it: `git -C library push`.

## Records from a CRM or accounting tool

This version copies no CRM or accounting rows anywhere. People read records live through the system's own connector, which checks access. Later versions may add nightly table copies into the admin's library (exit and backup only), never into an area. Leave such an item in the inbox and say so.

## Safety

If an item contains a password, key, or token, stop and flag it. Do not file it, and never repeat the value.

## Output

End with a short table: item → where it went → what else you updated (library copies included). List anything left in the inbox with a one-line question.
