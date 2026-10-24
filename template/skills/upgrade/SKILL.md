---
name: upgrade
description: Move this company OS to a newer os-foundation version. Shows a dry-run report first, then makes one pull request (or one commit at solo) that adds the new parts. Never rewrites company content. One commit reverts it. Use when lint says a newer version exists, or someone says "upgrade the OS", "update os-foundation", or "get the new version".
---

# Upgrade

Use this when `lint` says a newer os-foundation version exists, or when someone asks.

- **Folder only (no 1610 OS app):** the company manages its own upgrades. 1610 does not push them. Run this skill when you choose. Release notes are public at `1610.sh/os/changes`.
- **Linked to the 1610 OS app:** 1610 manages updates through the app. Do not run this. Say so and stop.

The flags are in `skills/upgrade/CLI.md`. Use exactly those.

## 1. Dry run first

1. Run `skills/upgrade/upgrade.sh --dry-run` from the company root.
2. It changes nothing. It prints what will change and what conflicts.
3. Read the report to the person in plain words, one line each.

What an upgrade may add or change:
- the committed skill links (`.agents/skills` and `.claude/skills`),
- old session logs on the `logs` branch, moved to per-person files in `memory/logs/` on `main`, with their history,
- the `level:`, `switches:` and `os_version:` lines in `company-profile.md`,
- the approval tier table in `AGENTS.md` (team level only),
- new stock skills.

What it never changes:
- **Company content.** Notes, people, customers, decisions, meetings, area files, workspaces.
- **A skill you changed.** A stock skill is replaced only if it is still exactly as shipped. A changed one is listed as a conflict. It stays as it is.

## 2. Conflicts

For each conflict, say what it is and what the new version would change. Ask the person, one at a time:
- **Keep yours** (suggested). The upgrade skips that file.
- **Take the new one.** Do it later by its own rules change, so it gets a review.

## 3. Apply

Ask once: "Apply this upgrade?" Suggest yes when the report has no surprises.

Run `skills/upgrade/upgrade.sh`.

- **Team level:** it makes one branch and one pull request. Rules files change, so the model review runs. The admin is the author and the code owner, so the model review alone is enough. It merges like any rules change. Nobody writes to `main`, the admin included.
- **Solo:** it makes one commit on `main`.

If the folder is linked to the app, the script reads the groups from the app. If it cannot, it says so: stop and tell the person.

## 4. The old logs branch

If the folder has an old `logs` branch:
- Its files move to `memory/logs/` on `main`. Their history comes with them.
- The old branch is kept as a tag named `logs-archive-<date>` for 90 days. Then it may be deleted.

## 5. Going back

The whole upgrade is one merge (team) or one commit (solo). One revert undoes it. The script prints the exact command. At the team level the revert also goes by pull request.

## 6. Tell the person

One line each:
- What changed.
- What was skipped (conflicts kept as they were).
- How to go back.
- Team level: the link to the pull request. It merges when the checks pass.
