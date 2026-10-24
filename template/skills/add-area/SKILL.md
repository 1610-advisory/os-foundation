---
name: add-area
description: Add an area of the business (marketing, finance, sales, operations, people/HR, apps, or any other) to this company OS as its own git repo, so access can be split later. Use when someone says "add sales", "set up an area for operations", "I'm taking over HR", or during setup.
---

# Add an area

An area is a folder under `areas/` that is **its own git repo**. The company repo ignores `areas/`, so area files never enter the shared history. That is what lets the admin later give one person marketing and not finance.

Folders organize work; areas control access. If the same people will see everything, a sub-folder inside an existing area is enough. Ask: "Will anyone see this who should not see {{EXISTING_AREA}}, or the other way round?" If no, suggest a sub-folder instead.

Run this from the company root.

## 1. Name

Offer the usual list: **marketing, finance, sales, operations, people (HR), apps**, or other. A customer portal is an app: it goes at `areas/apps/portal/` (add `apps` first).

Pick a slug: lowercase, hyphens (`customer-service`). If `areas/{{AREA_SLUG}}/` exists, stop and ask.

## 2. Build it

1. Copy `skills/add-area/templates/_area/` to `areas/{{AREA_SLUG}}/`, hidden files included (`cp -R skills/add-area/templates/_area/. areas/{{AREA_SLUG}}/`). The copy keeps two committed links, `.agents/skills` and `.claude/skills`, both pointing to `../skills`. No link step is needed. If either arrived as a plain file (Windows, or a file-by-file copy), replace it with the link. If links fail, copy `skills/` there instead: `lint` finds drift later.
2. If `skills/add-area/templates/{{AREA_SLUG}}/` exists (marketing, finance, apps), copy it on top. Its files replace the generic ones.
3. Replace placeholders in every new file: `{{AREA_NAME}}` (for example "Marketing"), `{{AREA_SLUG}}`, `{{COMPANY_NAME}}`, `{{COMPANY_SLUG}}`, `{{DATE}}` (today, YYYY-MM-DD).
4. Make it a repo: `git -C areas/{{AREA_SLUG}} init -b main`, then commit everything with the message `{{AREA_NAME}} area: start`. Check with `git -C areas/{{AREA_SLUG}} rev-parse --show-toplevel` that the answer is the area folder, not the company folder.
5. Check the pointer line near the top of the new `AGENTS.md` (and in `CLAUDE.md`): company skills are in `../../skills/`; if that folder is missing, read them from the company repo on the host. The template has it. Do not copy company skills into the area.
6. Logs need no setup: they are per-person files in the area's `memory/logs/`, committed like any file.

## 3. Three questions

Ask one at a time, each with a suggested answer, and write the answers into "What this area does" in the new `AGENTS.md`:

1. What does this area produce each week or month? (posts, reports, invoices, quotes)
2. Which tools does it use?
3. What does "done well" look like?

For each recurring output, offer to write a skill for it later (`write-skill`). Do not write them all now.

## 4. Team level

Read `level:` in `company-profile.md`. At `solo`, skip this step: the area stays a local repo until `add-teammate`.

At `team`, the area must also get its place on the host. The scripts do it. Never call the host yourself.
1. Ask who directs this area (approves its rules changes). Suggest the admin.
2. Ask who may read and write it. Suggest the fewest people.
3. Write an answers file for `skills/add-teammate/team-on.sh` (keys in `skills/add-teammate/CLI.md`): the host lines from `company-profile.md`, `area.{{AREA_SLUG}}.director`, and every person from `people/` with this area added to the `.areas` of those who get it.
4. Run `skills/add-teammate/team-on.sh --answers <file>` again. A second run changes only what is missing. It pushes the area repo with its history, makes the area's team, writes its `CODEOWNERS` (rules files: the director and the admin), adds the checks, and protects `main`.
5. Each person who got access runs `skills/add-teammate/join.sh --answers <file>` again (`me=<slug>`). It clones only the new area. Nobody writes to its `main`.

## 5. Record it

- Add the area to the "Areas:" line in the company `AGENTS.md`. Solo: commit that in the company repo. [team]: this is a rules file, so propose it with `skills/sync/sync.sh propose add-area-{{AREA_SLUG}} AGENTS.md`.
- Tell the person how to open it: "For {{AREA_SLUG}} work, open your agent in `~/{{COMPANY_SLUG}}-os/areas/{{AREA_SLUG}}/`."
