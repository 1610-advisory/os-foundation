---
name: ingest
description: Process the inbox into organized, linked notes — transcribe audio, create the note in the right place, keep raw copies and full transcripts in `library/`, fill frontmatter, update the people and meeting notes it touches, clear the inbox. Use when someone says "process the inbox", "ingest", "file this", or drops a meeting recording, transcript, photo, email, or file.
---

# Ingest — capture in, knowledge out

Process the inbox **of the folder you are in**:

- At the company root: `inbox/` → shared files.
- In an area: `areas/{{AREA_SLUG}}/inbox/` → that area's files.

An item is done when its content is in the right place, linked, and committed. Then delete the inbox copy. Never leave duplicates in the inbox. A copy kept in the library is not a duplicate: it is the company's copy.

**Library.** The library is a plain folder of the repo you file into: `library/` at the company root, `library/` inside an area for restricted material. Its rules are in `library/README.md` at the company root. If the company root has no `library/README.md` (an older folder), file as before, with the transcript under the meeting note, and say once, at the end of the run: "A `library/` folder would keep raw copies and full transcripts. It comes with new setups."

If the person named one item, process only that. Otherwise process everything. For more than five items, first give a one-line plan per item, then go.

## Per item

1. **Shared or one area?** Decide from the content. Pay, reviews, HR, raw financials, and customer records usually belong to an area. At the company root, ask before you file an item like that: "This looks like finance. Move it to the finance area, or share it with everyone?" Follow their choice. If they pick an area that is not on this computer, leave the item in the inbox and tell them who should get it.
   In shared notes you write (meeting summaries, person notes), leave out pay, raw financials, and HR details unless the person says to include them.
2. **What is it?** Meeting, fact about a person or the company, idea, how-to, decision, task, or data file.
3. **Audio?** Transcribe first. Use a local tool if one is installed (for example Whisper). If none is, ask how they want it handled. Keep the audio until a person checks the transcript (see "The library").
4. **File it:**

   | Kind | At the company root | In an area |
   |---|---|---|
   | Meeting | `meetings/YYYY-MM-DD Title.md`; full transcript to `library/` | `meetings/YYYY-MM-DD Title.md` in the area; full transcript to the area's `library/` |
   | Person | `people/Full Name.md` | update the shared note only with shareable facts; area-only facts stay in the area |
   | Company fact | update `company-profile.md`, `customers.md`, `offers.md`, or `voice.md` | the area file it belongs to |
   | Decision | `decisions/YYYY-MM-DD Decision.md` | the area's notes |
   | Data file | not at the root | `data/` in the area |
   | Photo or image | `library/media/`, named from the note that needs it | the area's `library/media/` |

   Use `templates/` at the company root. Meeting notes get a short **Summary**, **Decisions**, and **Action items**. The note links the full transcript in the library and does not hold it.
   Restricted items (finance, HR, pay, health) go in the area's own `library/`, never the company `library/`. Their `access:` is the area name.
5. **Update what it touches.** Create missing person notes for attendees (short is fine). Link everything with `[[wiki-links]]`.
6. **Memory.** Only if the item changes how to work (a preference, a standing rule) → `memory/` of the folder you are in.
7. **Delete the inbox copy** and commit, with a message like `Ingest: 3 items (meeting, 2 people)`.

## The library

A copy in the library is read-only. Never edit a file under `raw/`. Follow `library/README.md`. Paths below start in the `library/` folder you file into. Git holds text only: `media/` and `data/` stay on this computer.

An area's `library/` starts empty. Before its first copy, make the same folders and a `media/LOCAL.md` like the company one. Check that the area's `.gitignore` has the three library lines from the company `.gitignore`; add them if missing, so no media is committed.

- **Meeting recording or transcript.**
  1. Raw: the export as the tool gave it (VTT, JSON, TXT) → `raw/<source>/YYYY/`, with the tool's file name. A local transcription tool's own output is raw too: `raw/<tool>/YYYY/`.
  2. Readable: the full transcript as Markdown → `transcripts/YYYY-MM-DD Title.md`, with the library front matter (`source`, `captured`, `original`, `raw`, `people`, `access`, `retention`).
  3. Meeting note: `meetings/YYYY-MM-DD Title.md` keeps Summary, Decisions and Action items. Set `transcript:` in its front matter to the path from the company root (`library/transcripts/YYYY-MM-DD Title.md`, or `areas/<area>/library/transcripts/...`). Add the link `[[transcripts/YYYY-MM-DD Title]]` under "Notes / transcript".
- **Audio.** Hash it (`shasum -a 256` on a Mac, `sha256sum` elsewhere), move it to `media/<first 2 hex>/<sha256>.<ext>`, and add its row to `media/LOCAL.md`. Git ignores it. Transcribe. Set `retention: delete-audio-after-transcript` on the transcript. Ask the person to check the transcript. When they say it is right, delete the audio and its row, and add `checked: YYYY-MM-DD` to the transcript front matter. If the company chose to keep audio, set `retention: keep` on the row instead and say it is on this computer only.
- **Photo or image.** Hash it, move it to `media/<first 2 hex>/<sha256>.<ext>`, and add its row to `media/LOCAL.md`. Nothing in `media/` is committed, photos included. Name it from the note that needs it by its path (`library/media/ab/<sha256>.jpg`). If no note needs it, ask where it belongs. Say once that it is on this computer only until media sync comes.
- **One commit.** The company `library/` is part of the company repo; an area's `library/` is part of the area repo. Commit the copy with the note in the same repo.
- **Records from a CRM or accounting tool** are not filed here. Leave them in the inbox and say they come later as table copies.

## Safety

If an item contains a password, key, or token, stop and flag it. Do not file it, and never repeat the value.

## Output

End with a short table: item → where it went → what else you updated (library copies included). List anything left in the inbox with a one-line question.
