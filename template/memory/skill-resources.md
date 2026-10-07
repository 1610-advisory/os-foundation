---
name: Skill resources
description: The bundled Anthropic skill creator and where to find other skills when needed
type: reference
---

# Skills and company knowledge

Company knowledge records what is true about the business. Skills record how an agent should do a recurring job. Keep facts in their authoritative sources and link them; do not turn every note into a skill or copy restricted facts into shared instructions.

## Included by default

Anthropic's [skill-creator](../skills/skill-creator/SKILL.md) is bundled at `skills/skill-creator/` with its scripts, review templates, references, Apache-2.0 license and upstream notices. Read its Foundation integration note before using it. It helps draft, improve and, where approved tools are available, test skills.

The company `write-skill` flow handles where the skill belongs, its trigger and review; Anthropic's creator supplies the authoring/testing workflow. Say "make this a skill", "improve this skill", or "test this skill". A repeated explanation is a reason to offer a skill, not permission to run paid tests.

## Other Anthropic skills

Browse [Anthropic's skills collection](https://github.com/anthropics/skills) for a specific job. Other skills from the collection are not bundled or automatically installed. Read each skill's license, dependencies and permissions before proposing it; some document skills are source-available under different terms, not Apache-2.0.

Offer only a skill that fits the current work. Show what it adds and ask before downloading more tools, installing dependencies, using external accounts or starting model runs. Record any chosen addition in the relevant area with its source and version. A skill is instructions and resources, not an automatic connector or a guarantee of compatibility.
