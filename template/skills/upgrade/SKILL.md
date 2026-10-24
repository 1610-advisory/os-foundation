---
name: upgrade
description: Move this company OS to a newer os-foundation version. Shows a dry-run report first, then makes one pull request (or one commit at solo) that adds the new parts. Never rewrites company content. One commit reverts it. Use when lint says a newer version exists, or someone says "upgrade the OS", "update os-foundation", or "get the new version".
---

# Upgrade

Use this when `lint` says a newer os-foundation version exists, or when someone asks.

- **Folder only (no 1610 OS app):** the company manages its own upgrades. 1610 does not push them. Run this skill when you choose. Release notes are public at `1610.sh/os/changes`.
- **Linked to the 1610 OS app:** 1610 manages updates through the app. Do not run this. Say so and stop.

The flags are in `skills/upgrade/CLI.md`. Use exactly those.

## 1. Get the script

The script comes with the new os-foundation version.
1. Read the newest version: the one line at `https://1610.sh/os/version` (for example `v1.0.0`). `unreleased` means there is no version yet: say so and stop.
2. Clone it to a temporary folder outside the company folder:
   `git clone --depth 1 --branch <version> https://github.com/1610-advisory/os-foundation.git <temp>/os-foundation`
3. In the steps below, `<upgrade>` means `<temp>/os-foundation/template/skills/upgrade/upgrade.sh`. Always add `--root <company folder> --template <temp>/os-foundation/template`.
4. Check `git filter-repo --version`. Missing? Help install it (on a Mac, `brew install git-filter-repo`). The logs move needs it.

## 2. Level

Ask: "Does anyone else use this company OS with you?" Suggest no.
- No: the level is `solo`. Add nothing.
- Yes: still upgrade at `solo` first. Then run `add-teammate` Part A. It turns on the team level with the v1 parts.

## 3. Dry run

1. Run `<upgrade> --dry-run --root <company folder> --template <template>`.
2. It changes nothing. It prints `v0:` lines (the old shape it found), `change:` lines and `conflict:` lines.
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

## 4. Conflicts

For each conflict, say what it is and what the new version would change. Ask the person, one at a time:
- **Keep yours** (suggested). The upgrade skips that file.
- **Take the new one.** Do it later by its own rules change, so it gets a review.

`app-groups: needs Track K` means the folder is linked to the app. Stop and tell the person: 1610 manages that upgrade.

## 5. Apply

Ask once: "Apply this upgrade?" Suggest yes when the report has no surprises.

Run `<upgrade> --root <company folder> --template <template>`. It makes branch `upgrade/v1` with one merge commit. It never writes to `main` itself.

- **Host on** (`host:` is not `none`): it opens one pull request and prints `pr:`. Rules files change, so the model review runs. The admin is the author and the code owner, so the model review alone is enough. Nobody writes to `main`, the admin included.
- **Solo, no host:** merge the branch into `main` yourself: `git merge --no-ff upgrade/v1`. Solo commits to `main` as usual.

## 6. The old logs branch

If the folder has an old `logs` branch:
- Its files move to `memory/logs/` on `main`. Their history comes with them. The `/memory/logs/` line leaves `.gitignore`.
- The old branch is kept as a tag named `logs-archive-<date>` (the `tag:` line). Keep it 90 days. Then it may be deleted. The script never deletes it.

## 7. Going back

The whole upgrade is one merge commit. One revert undoes it.
- **With a host:** never commit on `main`. Make a new branch from `origin/main` (for example `upgrade/revert-v1`). On that branch run `git revert -m 1 <merge commit>`. Push the branch (`git push origin upgrade/revert-v1`). Open the pull request: `skills/_host/host.sh open-pr {{COMPANY_SLUG}}-os --head upgrade/revert-v1 --base main --title "Revert the v1 upgrade"`. The model review runs. It merges when the checks pass.
- **Solo, no host:** run `git revert -m 1 <merge commit>` on `main`. Solo commits to `main` as usual.

## 8. Tell the person

One line each:
- What changed.
- What was skipped (conflicts kept as they were).
- How to go back.
- With a host: the link to the pull request. It merges when the checks pass.

Then delete the temporary folder.
