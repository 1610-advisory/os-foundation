---
name: setup
description: First-run setup for this OS folder. Interview the person, fill in AGENTS.md, build their first company folder, connect one or two tools, and show them how to start a day. Use when the person says "run setup", "set me up", or this is the first session in a fresh copy (AGENTS.md still shows {{PERSON_NAME}}).
---

# Setup

The person just got this folder. By the end they should have: their details in `AGENTS.md`, one company folder built, one tool connected (if they want), and a clear idea of where to open their agent tomorrow morning.

Ask **one question at a time**, each with a suggested answer. Keep messages short. Write answers to files as you go, so a dropped session loses nothing.

## 1. About them (about 3 minutes)

Ask, in order:

1. Their name.
2. Their role, in their own words ("I run marketing at a seed company").
3. The companies they work in. Most people have one. Some have a main job plus a side business, a board seat, or a family business. Each gets its own folder.
4. How they like answers: short and direct, or with more explanation? (Suggest short.)

Fill the "About me" block in `~/os/AGENTS.md`. Write `system/memory/user-profile.md` (type `user`) with the same facts plus anything useful they said, and add its line to `system/memory/MEMORY.md`.

## 2. The first company (about 5 minutes)

Pick the company they spend the most time in. Follow `system/skills/add-company/SKILL.md` for it. That skill asks about the company, picks functions, and builds the folder.

For the other companies from question 3, offer: "Want me to set those up now, or later? Later is fine — just say 'add a company'." Suggest later.

## 3. Connect a tool (about 5 minutes, optional)

Ask which tools they open every day for this company (email, calendar, docs, chat, books, CRM, store, email marketing). Write the list into `<company>/company.md` under "Tools".

Suggest connecting the one they use most, usually email and calendar. Follow `system/skills/connect-tool/SKILL.md`. One connection is enough today. Tell them they can connect more any time.

If they say no, that is fine. The OS works with files alone.

## 4. Toolkits

If they chose a marketing function, tell them about the free Marketing Toolkit (brand voice, personas, content plans, performance tracking). Offer to install it. Follow the "Marketing Toolkit" section in `<company>/marketing/AGENTS.md`.

## 5. Obsidian (optional)

Everything is plain markdown, so any editor works. Suggest [Obsidian](https://obsidian.md) to read and browse the files: open `~/os` as a vault. Tell them two things:

- If they sync the vault (Obsidian Sync, iCloud, Dropbox), do not also make a synced folder a git repo. Pick one way to sync each folder.
- Obsidian hides folders that start with a dot. That is why `AGENTS.md` sits at the top level and not in `.claude/`.

## 6. First win

Show one thing working before you finish. Pick one:

- Ask them to paste a recent email, meeting notes, or a rough idea into a file in `inbox/`, then run `ingest` on it.
- Ask "What should I know about {{COMPANY_NAME}}?" and answer from the files you just built.
- If a tool is connected: "What is on my calendar this week?"

## 7. How to start each day

Tell them, in about this many words:

> Open your agent in the folder for the work you are doing. Marketing work: `~/os/<company>/marketing`. Something personal: `~/os`. Drop anything you capture in `~/os/inbox`, and ask me to process it when you have a minute. When I do something your way after you explain it, tell me to write it down as a skill.

Give the exact command for their agent, for example `cd ~/os/<company>/marketing && claude`, or "In Claude Desktop, choose the folder `~/os/<company>/marketing`."

## 8. Close out

- Replace any `{{PLACEHOLDER}}` left in `~/os/AGENTS.md` with a real value or delete the line.
- Delete `START.md` from `~/os` (it was only for the first run). Keep this skill so setup can be re-run.
- Append a log entry to `system/memory/logs/YYYY-MM-DD.md`: what was built, what is open (companies not yet added, tools not yet connected).
- Tell them what was built, in three to five lines, and what is left.
