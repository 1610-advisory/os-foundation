---
name: write-skill
description: Capture a recurring company process as a skill using the bundled Anthropic skill creator, with company placement and review rules. Use when someone says "write this down", "make a skill for this", "remember how I like this done", or when you notice you have been told the same thing twice.
---

# Write a company skill

Use this flow to turn a repeated explanation into a reusable way of working. Anthropic's bundled creator handles authoring and optional testing; this file handles company scope, placement and review.

1. **Name the job.** Use two to four words, such as `weekly-sales-report` or `quote-follow-up`. Read any existing skill for it before creating a duplicate. Offer the skill when someone repeats a process; confirm they want it captured.
2. **Choose where it belongs.**
   - One area: `areas/{{AREA_SLUG}}/skills/{{SKILL_NAME}}/SKILL.md`.
   - Whole company: `skills/{{SKILL_NAME}}/SKILL.md` at the company root.
   - Company-wide skills contain no restricted area facts. Use synthetic examples or a specifically approved example.
3. **Use the creator.** Locate the company root from its rules. Read `skills/skill-creator/FOUNDATION.md`, then `skills/skill-creator/SKILL.md`. Follow its intent, draft and human-review process. Check capabilities and get approval before dependency installs, external model calls, delegation or paid evaluations. Keep test work in the relevant private workspace, not shared company knowledge.
4. **Make it findable.** Set `name` to the directory name. Give the description concrete trigger phrases. Add a row to the Skills table in the appropriate `AGENTS.md`.
5. **Review and save.** Show the person the draft and any checks actually run; distinguish local checks from unrun model tests. Fix their corrections. Follow the company rules: admin commits, other teammates open a pull request; log in the relevant area.
6. **Keep it current.** Update the same skill when the person corrects the process. Preserve its existing name unless they request a rename.

Something that would help other businesses? Offer `suggest`; do not share the company's version automatically.
