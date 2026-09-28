---
name: ingest
description: Drain the inbox into organized, linked notes — transcribe audio, decide personal vs which company, create the note in the right place, fill frontmatter, update the people and meeting notes it touches, refresh the indexes, clear the inbox. Use when the person says "process my inbox", "ingest", "file this", or drops a meeting recording or transcript.
---

# Ingest — capture in, knowledge out

Everything lands in `~/os/inbox/`. Nothing lives there. An item is done when its content is in the right place, linked, and indexed; then the inbox copy is deleted. Never leave duplicates.

If the person named one item, process only that. Otherwise drain everything. For more than five items, first give a one-line plan per item, then go.

## Per item

1. **Whose is it?** Personal, or which company? Decide from the content. If you cannot tell, leave it in the inbox and ask. Once it belongs to a company, follow that company's silo rules.
2. **What is it?** Meeting, fact about a person or company, idea, how-to, task, or data file.
3. **Audio?** Transcribe first. Use a local tool if one is installed (for example Whisper); otherwise ask how they want it handled.
4. **File it:**

   | Kind | Personal | Company |
   |---|---|---|
   | Meeting | `calendar/meetings/YYYY-MM-DD Title.md` | `<company>/core/meetings/YYYY-MM-DD Title.md` |
   | Person | `wiki/people/Full Name.md` | `<company>/core/people/Full Name.md` |
   | Idea, note | `wiki/notes/` | the function folder it belongs to |
   | Decision | a note in `efforts/` or `wiki/notes/` | `<company>/core/decisions/` |
   | Data file | next to the note it supports | `<company>/<function>/data/` |

   Use the templates in `templates/`. Meeting notes get a short **Summary** and **Action items** above any transcript.
5. **Update what it touches.** This is what makes it a wiki instead of a filing cabinet. Create missing person notes for attendees (minimal is fine). If the item changes a company fact, update the `core/` file. Link everything with `[[wiki-links]]`.
6. **Indexes.** Refresh the fenced `<!-- auto:index:begin -->` block of any map of content whose contents changed. Edit inside the fences only.
7. **Memory.** Only if the item changes how you should work (a preference, a standing decision). Personal → `system/memory/`, company → `<company>/memory/`.
8. **Delete the inbox copy.**

## Safety

If a capture contains a password, key, or token, stop and flag it. Do not file it.

## Output

End with a short table: item → where it went → what else you updated. List anything left in the inbox with a one-line question.
