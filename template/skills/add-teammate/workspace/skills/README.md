# Skills

The person's own skills. One folder each: `skills/<name>/SKILL.md`.

- Only this person and their AI use them.
- When a request matches one, read its `SKILL.md` and follow it.
- Company rules come before a skill's own steps.
- A skill the team could use: ask once if the person wants to share it. If yes, copy its folder to `skills/<name>/` (company) or `areas/<area>/skills/<name>/` (area). Then run `../../../skills/sync/sync.sh propose <topic> <file>...` with each file from the company root, for example `skills/<name>/SKILL.md`. Never a folder. Never a `users/` path. Details: the `sync` skill.
