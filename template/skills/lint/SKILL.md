---
name: lint
description: Health-check the company OS (or one area). Runs the lint script for the fixed checks (skill links, skill copies, level and switches, rules file size, placeholders, profile), then checks links, meetings, inbox, sensitive facts and git by reading. Fixes the mechanical issues and lists the judgment calls. Use when someone says "health check", "lint", or weekly.
---

# Lint

Check the folder you are in: the company root (shared files only, not `areas/`), or one area. Collect every finding first, then fix.

## 1. Run the script

Run `skills/lint/lint.sh` from the company root. In an area, run `../../skills/lint/lint.sh --root .`. Exit 0: no findings. Exit 1: findings, one per line. The flags are in `skills/lint/CLI.md`.

What each check means:

1. **Skill links.** `.agents/skills` and `.claude/skills` must exist and point to `../skills`, at the root and in each area. They let every agent find the same skills. Missing or wrong: agents miss skills.
2. **Skill copies.** On a computer with no link support, setup copies the skills. A copy that differs from `skills/` is drift. Agents then follow old steps.
3. **Level and switches.** `level:` must be `solo`, `team` or `app`. Each name in `switches:` must be a known switch. `dream` is not a switch: it is an error.
4. **Rules file size.** Each `AGENTS.md` and `CLAUDE.md` must be under 10,000 characters. Agents may cut a longer file. Move detail into a skill.
5. **Placeholders.** No `{{...}}` left outside `skills/`. A skill's `{{...}}` is filled when it runs.
6. **Profile.** [team] A profile (`users/<person>/profile/`) must hold no company name or slug. This is a simple check. The nightly check is the real one.

The script may also print two lines that are not findings. Pass each on as it is, in one line:
- **Newer version.** "A newer os-foundation version exists." Add: "Say 'upgrade the OS' when you want it." Nothing else. Offline, it prints nothing.
- **Bot offer.** One sentence. It comes once, after two weeks of use, when the `bots` switch is off. Say it once. Do not repeat it. If the person asks about bots before then, give the same sentence.

Never offer the dream pass. It is not available.

## 2. Read the rest

These need judgment. The script does not do them.

1. **Secrets.** Strings that look like keys or passwords: an API key value, a `password:` line, a private key block. [team] Also run `skills/sync/secret-scan.sh --files <file>...` on the files you check. Put any hit at the top of the report. Never repeat the value: name the file and line only.
2. **Broken links.** Every `[[target]]` that matches no file. Ignore `#heading` and `|alias`. Match by file name, any case. Do not make pages. List the most-linked missing ones.
3. **Meetings.** Meeting notes with an empty `summary:` or no attendees. Fill from the note body if you can. Otherwise list them.
4. **Inbox age.** Items older than 14 days. Report the count and the oldest five. Do not file them (that is `ingest`).
5. **Sensitive facts in shared files** (company root only). Pay, raw financial figures, HR notes or customer records in a shared file. List them so the admin can confirm each one was meant to be shared. Do not move or delete anything.
6. **Other companies.** Any mention of, or link to, another company's folder. Report it.
7. **Git.** Uncommitted changes, and commits not yet pushed. Solo: commit them. [team]: the nightly push sends them. Report held files from `skills/sync/sync.sh status`.

## 3. Output

Write `memory/lint/YYYY-MM-DD.md` with:
- **Fixed:** what, how many.
- **Needs you:** one line each, linked.
- **Missing pages.**
- **Stats:** notes per folder.

Save it like any note (solo: commit; [team]: the nightly push sends it). Give a three-line summary in chat. Then the version line and the bot sentence, if the script printed them.
