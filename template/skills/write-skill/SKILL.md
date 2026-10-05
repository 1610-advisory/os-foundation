---
name: write-skill
description: Turn a process someone keeps re-explaining into a written skill (an SOP for the agent), so it is done the same way every time. Use when someone says "write this down", "make a skill for this", "remember how I like this done", or when you notice you have been told the same thing twice.
---

# Write a skill

A skill is an SOP for the agent: one markdown file that says exactly how to do one recurring job.

1. **Name the job** in two to four words: `weekly-sales-report`, `quote-follow-up`, `title-hooks`.
2. **Decide where it lives.**
   - Only for one area → `areas/{{AREA_SLUG}}/skills/{{SKILL_NAME}}/SKILL.md`, and add a row to the Skills table in that area's `AGENTS.md`.
   - For the whole company → `skills/{{SKILL_NAME}}/SKILL.md` at the company root, and add a row to the Skills table in the company `AGENTS.md`.
   - A company skill holds no area facts (no pay, raw numbers, or customer records).
3. **Write it** in this shape:

   ```
   ---
   name: {{SKILL_NAME}}
   description: {{WHAT_IT_DOES}}. Use when someone says "{{PHRASE}}", "{{PHRASE}}".
   ---

   # {{TITLE}}

   ## Inputs
   ## Steps
   ## Output (format, length, where it is saved)
   ## Good example
   ```

   Be concrete: "Title hooks are 3 to 5 words, sentence case, on screen in the first 3 seconds" beats "write good hooks." Use the person's own words and a real example from this session.
4. **Show it** to the person and ask what is wrong. Fix it. Commit (a teammate who is not the admin opens a pull request).
5. **Keep it alive.** When the output drifts or someone corrects you, update the skill in the same session.

Something that would help every business, not just this one? Offer `suggest`.
