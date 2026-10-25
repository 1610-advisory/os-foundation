# Skills

The person's own skills. One folder each: `skills/<name>/SKILL.md`.

- Only this person and their AI use them.
- When a request matches one, read its `SKILL.md` and follow it.
- Company rules come before a skill's own steps.
- A skill the team could use: ask once if the person wants to share it. If yes, copy it to `skills/` in the company or an area, then propose that copy with `../../../skills/sync/sync.sh propose <topic> <path>...` (paths from the company root; the `sync` skill). `propose` refuses `users/` paths.
