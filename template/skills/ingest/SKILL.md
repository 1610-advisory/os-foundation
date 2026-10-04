---
name: ingest
description: Process the inbox into organized, linked notes — transcribe audio, create the note in the right place, fill frontmatter, update the people and meeting notes it touches, clear the inbox. Use when someone says "process the inbox", "ingest", "file this", or drops a meeting recording, transcript, email, or file.
---

# Ingest — capture in, knowledge out

Process the inbox **of the folder you are in**:

- At the company root: `inbox/` → shared files.
- In an area: `areas/<area>/inbox/` → that area's files.

An item is done when its content is in the right place, linked, and committed. Then delete the inbox copy. Never leave duplicates.

If the person named one item, process only that. Otherwise process everything. For more than five items, first give a one-line plan per item, then go.

## Per item

1. **Shared or one area?** Decide from the content. Pay, reviews, HR, raw financials, and customer records belong to an area. At the company root, do **not** read further into an item like that: tell the person which area it belongs to, and ask them to move it to that area's `inbox/` (or move it for them with one `mv`, with their OK). Then process it from the area.
2. **What is it?** Meeting, fact about a person or the company, idea, how-to, decision, task, or data file.
3. **Audio?** Transcribe first. Use a local tool if one is installed (for example Whisper). If none is, ask how they want it handled.
4. **File it:**

   | Kind | At the company root | In an area |
   |---|---|---|
   | Meeting | `meetings/YYYY-MM-DD Title.md` | `meetings/YYYY-MM-DD Title.md` in the area |
   | Person | `people/Full Name.md` | update the shared note only with shareable facts; area-only facts stay in the area |
   | Company fact | update `company-profile.md`, `customers.md`, `offers.md`, or `voice.md` | the area file it belongs to |
   | Decision | `decisions/YYYY-MM-DD Decision.md` | the area's notes |
   | Data file | not at the root | `data/` in the area |

   Use `templates/` at the company root. Meeting notes get a short **Summary**, **Decisions**, and **Action items** above any transcript.
5. **Update what it touches.** Create missing person notes for attendees (short is fine). Link everything with `[[wiki-links]]`.
6. **Memory.** Only if the item changes how to work (a preference, a standing rule) → `memory/` of the folder you are in.
7. **Delete the inbox copy** and commit, with a message like `Ingest: 3 items (meeting, 2 people)`.

## Safety

If an item contains a password, key, or token, stop and flag it. Do not file it, and never repeat the value.

## Output

End with a short table: item → where it went → what else you updated. List anything left in the inbox with a one-line question.
