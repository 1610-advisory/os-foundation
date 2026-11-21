---
name: handover
description: Move a company folder that an advisor firm holds in its own GitHub org ("held" mode) to the company's own org. A fresh copy of each repo with no history, the company admin as owner on record, then the holder copies are archived. Run by the holder's owner. Use when someone says "hand over the company", "move the repos to their org", "the company bought it", or "end held mode".
---

# Handover

Only in held mode: `host_mode: held` in `company-profile.md`. There the repos sit in the advisor firm's org (the holder, `holder_org`). At handover a fresh copy goes to the company's own org. Own mode: say there is nothing to hand over, and stop.

Only the holder's owner runs this, on their computer, in the company folder.

## Before you start

Ask, one at a time:
1. **The company's own org.** It must exist, on GitHub Team (paid). The company admin must be an owner of it.
2. **The company admin.** Their slug. They need a people page with their github login, on `main`. Not a holder person. No page yet: write it as a note first (a page gives no access).

Tell the holder's owner, plainly:
- Each repo moves as one new commit, "Handover from <holder>". The old history stays with the holder.
- A holder person's workspace (`users/<slug>`) and people page (`holder: true`) never move.
- Notes on an open pull request do not move. Merge or close every open pull request first.

## Run it

1. Dry run: `skills/handover/handover.sh --to-org <org> --admin <slug>`. It checks every repo and the new org, prints each step, and changes nothing. Read the output to the holder's owner. A `step 1` or `step 2` stop says what to fix.
2. Wait for a clear yes. Then run it again with `--go`. It pushes the copies to the new org and prints a `team-on:` line.
3. Give the company admin the `team-on:` line. They run team-on in the new org (`skills/add-teammate/SKILL.md`, own mode).
4. Do the `manual:` line: point the kernel's GitHub team link at the new org. The script does not do that.
5. When the company admin says the new repos work, run it with `--archive`. It archives the holder copies. It never deletes them.

Something wrong before `--archive`: run `--undo`. It archives the copies in the new org (never deletes them) and forgets the handover. The holder copies were not changed. An owner of the new org deletes the archived copies before the next try.

## What it prints

- `step <n>: ...`: each step, in order.
- `ok: <repo> (<holder>/<name>)`: that repo is clean and pushed.
- `skip: users/<slug> (a holder person's workspace ...)`: it stays.
- `left out: people/<page> (holder page)`: it stays.
- `pushed: <org>/<name>`: the copy is in the new org.
- `this folder still points at <holder>`: the holder's folder is not changed. The company admin clones from the new org.

The record of the handover is in `~/.config/<slug>-os/handover.json`. Flags and exits: `handover.sh --help`.
