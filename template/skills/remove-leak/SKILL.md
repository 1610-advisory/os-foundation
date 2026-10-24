---
name: remove-leak
description: Remove a secret or private content that reached the git host. Reverts it, rewrites the repo history so the file is gone, force-pushes, asks the host to purge its caches, and lets every other computer re-clone by itself. Team level only. Use when someone says "a key got pushed", "remove this from history", "we leaked a password", "this private note went to main", or the secret scan finds a hit on the host.
---

# Remove a leak

Team level only. Read `level:` in `company-profile.md`. At `solo` nothing left the computer: remove the file, commit, and stop.

Only the admin runs this. It runs on the admin's computer.

Deleting a file in a new commit does not remove it. The history and every clone still hold it. This skill rewrites the history on the host. Copies already on computers or in AI vendor transcripts may remain. That is why the checks run before each push.

The flags are in `skills/remove-leak/CLI.md`. Use exactly those.

## 1. Stop the harm first

- **Never repeat the secret.** Not in the chat, not in a file, not in a log. Name the file and line only.
- **A key, password or token:** tell the admin to revoke it now, at the service that issued it, and to make a new one. Revoking is the real fix. The rest is cleanup.
- **Private content** (a DM, an HR note, a personal fact): no revoke exists. Go on.

## 2. Questions (one at a time)

1. **Which repo?** The company repo (`{{COMPANY_SLUG}}-os`), an area repo (`{{COMPANY_SLUG}}-<area>`) or a workspace. Suggest the repo where the hit was found.
2. **What to remove?** One of:
   - **A file path**, when the whole file must go. Suggest the path from the hit.
   - **A scan rule id**, when a secret sits inside a file that should stay. Built-in ids: `aws-access-key`, `generic-api-key`, `private-key`. More may be in `skills/sync/secret-patterns.txt`. The script replaces each match with `[removed]`.
3. **Is it still in an open pull request?** Suggest yes if the nightly push sent it today. Then ask for the pull request number and its branch (for example `sync/<person>`).

## 3. Check the tool

The rewrite needs `git filter-repo`. Check with `git filter-repo --version`. Missing? Help install it (on a Mac, `brew install git-filter-repo`; otherwise `pip install git-filter-repo`).

## 4. Run it

Run one of:
- `skills/remove-leak/remove-leak.sh --repo <name> --path <path>`
- `skills/remove-leak/remove-leak.sh --repo <name> --pattern-rule <id>`

Add `--pr <number> --head <branch>` when the leak is in an open pull request.

If it stops, read its message. Fix the cause. Run it again.

## 5. What it does

1. **Revert.** If the leak is in an open pull request, it reverts it on that branch first. If the leak never reached `main`, it stops there.
2. **Rewrite.** It rewrites the repo history so the file or the secret is gone from every commit.
3. **Force-push.** It lifts the branch protection for this one push, pushes every branch and tag, and turns the protection back on.
4. **Purge.** It asks the host to drop old cached copies.
   - GitHub: it prints the text of a support request. The admin sends it to GitHub Support. This is the one manual step: GitHub has no other way.
   - Forgejo: it drops what the API allows by itself.
5. **Signal.** It pushes a tag named `os-rewrite-<date and time>` on the new `main`. The tag names the rule id or the path. Never the value.
6. **Audit.** It writes one line to the admin's log in `memory/logs/`. The line names the repo and the rule id or path. Never the value.

## 6. Other computers

No one needs to do anything. At the next pull (within 15 minutes), each computer sees the `os-rewrite-` tag. It clones the repo fresh, carries over its own unsaved and held files, and swaps the folders. A file that still holds the leaked pattern is not carried over.

## 7. Tell the admin

One line each:
- The file (or secret) is gone from the history on the host. Give the `tag:` the script printed.
- GitHub only: send the printed support request.
- If it stopped after the revert (the leak never reached `main`): the old commits of that branch and its pull request still hold the leak on the host. If it was a key, the revoke in step 1 is what makes it safe.
- Other computers re-clone by themselves at their next pull.
- Copies may remain where the rewrite cannot reach: AI vendor transcripts, backups, and copies people made by hand. If it was a key, the revoke in step 1 is what makes it safe.
