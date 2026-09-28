---
name: write-skill
description: Turn a process the person keeps re-explaining into a written skill (an SOP for the agent) so it is done the same way every time. Use when the person says "write this down", "make a skill for this", "remember how I like this done", or when you notice you have been told the same thing twice.
---

# Write a skill

A skill is an SOP for the agent: one markdown file that says exactly how to do one recurring job.

1. **Name the job** in two to four words: `weekly-sales-report`, `quote-follow-up`, `title-hooks`.
2. **Decide where it lives.**
   - Only for one company → `~/os/<company>/<function>/skills/<name>/SKILL.md`, and list it in that function's `AGENTS.md` under "Skills."
   - For any company or personal use (and no company facts in it) → `~/os/system/skills/<name>/SKILL.md`, and add a row to the Skills table in `~/os/AGENTS.md`.
3. **Write it** with this shape:

   ```
   ---
   name: <name>
   description: <what it does>. Use when the person says "<phrase>", "<phrase>".
   ---

   # <Title>

   ## Inputs
   ## Steps
   ## Output (format, length, where it is saved)
   ## Good example
   ```

   Be concrete: "Title hooks are 3 to 5 words, sentence case, on screen in the first 3 seconds" beats "write good hooks." Use the person's own words and a real example from this session.
4. **Show it** to the person and ask what is wrong. Fix it.
5. **Keep it alive.** When the output drifts or they correct you, update the skill in the same session.
