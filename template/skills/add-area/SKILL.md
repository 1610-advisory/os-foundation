---
name: add-area
description: Add an area of the business (marketing, finance, sales, operations, people/HR, apps, or any other) to this company OS as its own git repo, so access can be split later. Use when someone says "add sales", "set up an area for operations", "I'm taking over HR", or during setup.
---

# Add an area

An area is a folder under `areas/` that is **its own git repo**. The company repo ignores `areas/`, so area files never enter the shared history. That is what lets the admin later give one person marketing and not finance.

Folders organize work; areas control access. If the same people will see everything, a sub-folder inside an existing area is enough. Ask: "Will anyone see this who should not see <existing area>, or the other way round?" If no, suggest a sub-folder instead.

Run this from the company root.

## 1. Name

Offer the usual list: **marketing, finance, sales, operations, people (HR), apps**, or other. A customer portal is an app: it goes at `areas/apps/portal/` (add `apps` first).

Pick a slug: lowercase, hyphens (`customer-service`). If `areas/<slug>/` exists, stop and ask.

## 2. Build it

1. Copy `skills/add-area/templates/_area/` to `areas/<slug>/`.
2. If `skills/add-area/templates/<slug>/` exists (marketing, finance, apps), copy it on top. Its files replace the generic ones.
3. Replace placeholders in every new file: `{{AREA_NAME}}` (for example "Marketing"), `{{AREA_SLUG}}`, `{{COMPANY_NAME}}`, `{{COMPANY_SLUG}}`, `{{DATE}}` (today, YYYY-MM-DD).
4. Make it a repo: `git -C areas/<slug> init -b main`, then commit everything with the message `<Area> area: start`. Check with `git -C areas/<slug> rev-parse --show-toplevel` that the answer is the area folder, not the company folder.
5. Make its logs folder: from `areas/<slug>/`, follow `skills/logs-folder/SKILL.md` → "Make it".
6. Claude Code only: link the area's skills so they show as slash commands: in `areas/<slug>/`, make `.claude/` and run `ln -s ../skills .claude/skills`. If the link fails, skip it; the `AGENTS.md` table still works.

## 3. Three questions

Ask one at a time, each with a suggested answer, and write the answers into "What this area does" in the new `AGENTS.md`:

1. What does this area produce each week or month? (posts, reports, invoices, quotes)
2. Which tools does it use?
3. What does "done well" look like?

For each recurring output, offer to write a skill for it later (`write-skill`). Do not write them all now.

## 4. Record it

- Add the area to the "Areas:" line in the company `AGENTS.md`, and commit that in the company repo.
- Tell the person how to open it: "For <area> work, open your agent in `~/<slug>-os/areas/<area>/`."
