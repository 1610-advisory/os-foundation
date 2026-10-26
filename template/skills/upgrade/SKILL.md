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

Run the upgrade from a Mac or Linux computer. On Windows the script stops (`run the upgrade from a Mac or Linux clone of the company repo`) and changes nothing. If the person only has Windows, the admin runs it from a Mac or Linux clone. Windows teammates get the result by their normal pull.

1. Read the newest version: the one line at `https://1610.sh/os/version` (for example `v1.0.0`). `unreleased` means there is no version yet: say so and stop.
2. Clone it to a temporary folder outside the company folder:
   `git clone --depth 1 --branch <version> https://github.com/1610-advisory/os-foundation.git <temp>/os-foundation`
3. In the steps below, `<upgrade>` means `<temp>/os-foundation/template/skills/upgrade/upgrade.sh`. Always add `--root <company folder> --template <temp>/os-foundation/template`.
4. Check `git filter-repo --version`. Missing? Help install it (on a Mac, `brew install git-filter-repo`). The logs move needs it.

## 2. Level

Ask: "Does anyone else use this company OS with you?" Suggest no.
- No: the level is `solo`. Add nothing.
- Yes: still upgrade at `solo` first. Then run `add-teammate` Part A. It turns on the team level with the v1 parts.

## 3. Clean folder

A real run refuses a folder with uncommitted changes. The same goes for each area repo. Check with `git status --short` at the company root and in each `areas/<area>/`.
- **Solo:** commit the changes first, as usual.
- **Team:** the nightly push sends them. Run the upgrade the next day. Never commit them on `main`.

## 4. Dry run

1. Run `<upgrade> --dry-run --root <company folder> --template <template>`.
2. It changes nothing. It prints `v0:` lines (the old shape it found), `change:` lines, `todo:` lines and `conflict:` lines.
3. Read the report to the person in plain words, one line each.
   - `upgrade: already v1`: `main` already has the v1 parts. Say so and stop.
   - `upgrade: pending upgrade/v1`: an upgrade branch is already there. Either its pull request is open, or an earlier run stopped. Check for an open upgrade pull request first. If it is open, finish that one (step 7). Start over only with the person's OK. Then follow the `To start over:` line the script printed.
   - `the area areas/<name> has uncommitted changes`: go to step 3 for that area. Then run the dry run again.
   - `could not fetch <repo>`: the area repo on the host could not be reached. Check the sign-in and the network. Then run the dry run again.
4. Show the person each `change: rules-merge` line. Say plainly: "Your own lines in the rules files are kept exactly as written. They move under the new v1 headings." Give the count from `company-lines=`.
5. A `change: rules-spill` line means the rules file would be 10,000 bytes or more. Say: "Your own rules lines go to `company-rules.md` (an area: `area-rules.md`), unchanged. `AGENTS.md` gets one line that says to read it." When `CLAUDE.md` spills too, its lines go to the end of the same file under `## From CLAUDE.md`.
6. For each `todo: fill` line, ask the person for that value, one at a time. Write the answers to a file in the temporary folder, one `key=value` per line (the keys are in `skills/upgrade/CLI.md`). Add `--answers <file>` to every later run. Run the dry run again.

What an upgrade may add or change:
- the committed skill links (`.agents/skills` and `.claude/skills`),
- old session logs on the `logs` branch, moved to per-person files in `memory/logs/` on `main`, with their history,
- the `level:`, `switches:` and `os_version:` lines in `company-profile.md`,
- the approval tier table in `AGENTS.md` (team level only),
- the v1 rules in `AGENTS.md` and `CLAUDE.md`, in the company folder and in each area,
- new stock skills, and new files inside a stock skill,
- `.gitattributes`, only when the folder has none.

What it never changes:
- **Company content.** Notes, people, customers, decisions, meetings, area files, workspaces.
- **A skill you changed.** A stock skill is replaced only if it is still exactly as shipped. A changed one is listed as a conflict. It stays as it is.
- **Your own rules lines.** Each line the company added to `AGENTS.md` or `CLAUDE.md` is kept byte for byte, in its old order. It moves to the end of the matching v1 section. A section the company added stays whole at the end.

## 5. Conflicts

For each conflict, say what it is and what the new version would change. Ask the person, one at a time:
- **Keep yours** (suggested). The upgrade skips that file.
- **Take the new one.** Do it later by its own rules change, so it gets a review.

A `conflict: .claude/skills/<path>` (or `.agents/skills/<path>`) line means that folder holds a copy of a skill file that differs from the one in `skills/`. The line `conflict: .claude/skills left: resolve the files above first` follows. The folder stays until each such file is resolved. Ask the person which copy to keep. Put the kept copy in `skills/` and commit it. Then run the dry run again.

`conflict: .claude/skills (untracked; commit it first)` (or `.agents/skills`) means git does not track that folder, and it holds a file that is not a plain copy. The upgrade does not move or delete it. Ask the person to keep what they need: move a skill they wrote into `skills/` and commit it. Then run the dry run again.

`conflict: company-rules.md exists` (or `conflict: areas/<name>/area-rules.md exists`) means the folder already has that file. The upgrade will not write its spill file there, and a real run stops before any write. Ask the person to rename that file or merge it into `AGENTS.md` by hand, in a normal rules change ([team] `skills/sync/sync.sh propose <topic> <file>...`; solo: commit). After that merges, run the dry run again.

`app-groups: needs Track K` means the folder is linked to the app. Stop and tell the person: 1610 manages that upgrade.

## 6. Apply

Ask once: "Apply this upgrade?" Suggest yes when the report has no surprises.

Run `<upgrade> --root <company folder> --template <template>`. It stages only the upgrade paths. It makes branch `upgrade/v1` with one merge commit, even when there was no `logs` branch. It never writes to `main` itself.

- **Host on** (`host:` is not `none`): it opens one pull request and prints `pr:`. Rules files change, so the model review runs. The admin is the author and the code owner, so the model review alone is enough. Nobody writes to `main`, the admin included.
- **Solo, no host:** do step 7 first. Then merge the branch into `main` yourself: `git merge --no-ff upgrade/v1`. Solo commits to `main` as usual.
  Each area repo with old rules also has a branch `upgrade/scripts` with its rules merge. The upgrade leaves that branch checked out. After step 7, in each such area run `git -C areas/<area> checkout main`, then `git -C areas/<area> merge --no-ff upgrade/scripts`.

The branch has its own commit for the rules merge, `Upgrade: rules merge`. With a host, the pull request body lists it first, for the code owner. Each area gets the same commit in its own `upgrade/scripts` pull request.

## 7. Read the new rules together

Before the person approves the upgrade pull request (solo: before the merge), open the merged `AGENTS.md` with them. Do the same for `company-rules.md` if the upgrade made one. Then read each area `AGENTS.md` (and `area-rules.md`) the same way. An area pull request may merge by itself when its checks pass. That is fine: a fix there also goes by a follow-up rules change.
1. Show where each of their own lines now sits.
2. Ask: "Does each of your lines still fit under its heading?"
3. A line that sits under a heading that does not fit: write it down. Do not change it in the upgrade branch or pull request. That keeps the one-commit revert clean.
4. After the upgrade merges, move those lines by a follow-up rules change: [team] `skills/sync/sync.sh propose <topic> AGENTS.md`. Solo: edit and commit on `main`.

## 8. The old logs branch

If the folder has an old `logs` branch:
- Its files move to `memory/logs/` on `main`. Their history comes with them. The `/memory/logs/` line leaves `.gitignore`.
- The old branch is kept as a tag named `logs-archive-<date>` (the `tag:` line). Keep it 90 days. Then it may be deleted. The script never deletes it.

## 9. Going back

The whole upgrade is one merge commit. One revert undoes it.
- **With a host:** never commit on `main`. Make a new branch from `origin/main` (for example `upgrade/revert-v1`). On that branch run `git revert -m 1 <merge commit>`. Push the branch (`git push origin upgrade/revert-v1`). Open the pull request: `skills/_host/host.sh open-pr {{COMPANY_SLUG}}-os --head upgrade/revert-v1 --base main --title "Revert the v1 upgrade"`. The model review runs. It merges when the checks pass.
- **Solo, no host:** run `git revert -m 1 <merge commit>` on `main`. Solo commits to `main` as usual.

## 10. Tell the person

One line each:
- What changed.
- How many of their own rules lines were kept, and where (or that they went to `company-rules.md`).
- Any line to move later by its own rules change.
- What was skipped (conflicts kept as they were).
- How to go back.
- With a host: the link to the pull request. It merges when the checks pass.

Then delete the temporary folder.
