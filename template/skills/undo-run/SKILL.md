---
name: undo-run
description: Undo everything one bot run changed, in one step, by its Run-Id. Makes one revert commit per repo and opens a pull request that merges by itself. Use when someone says "undo what the bot did", "roll back last night's bot run", "the bot got it wrong", or names a Run-Id.
---

# Undo a bot run

Every commit a bot makes carries `Run-Id: <id>` and `Bot-Owner: <owner>`. This skill undoes all commits of one run at once. It works only when `bots` is in `switches:`. The script refuses otherwise.

Undo is a revert. History keeps the run and the undo. Nothing is deleted.

## Steps

1. **Find the run.** Ask what went wrong and when. Search history for the trailer: `git log origin/main --grep 'Run-Id: '`. A run id starts with the run's date and time, then 8 random letters and digits. Show the person the run's date, its routine and the files it changed. Ask: "Undo this whole run?"
2. **Run the script** from the company root: `skills/undo-run/undo-run.sh <run-id>`.
3. It fetches `main` in the company repo and each area repo. A repo the bot cannot see is skipped. The line is `undo-run skip <repo>: not visible to this token`. That is normal. Say which repo was skipped, then go on. It finds every commit with that `Run-Id` **and** the bot's author email from its `BOT.md`. A `Run-Id` line copied onto someone else's commit is not undone.
4. Per repo, it makes **one** revert commit on the branch `undo/<run-id>`, in a temporary copy. The person's working copy is not touched. The commit says `Reverts: <run-id>`. It opens a pull request with auto-merge on.
5. Tell the person, in plain words: which repos, which commits, and the pull request links. The script prints them. The pull request is the last check: the checks run on it before it merges.

## When it cannot finish

The script goes on with the other repos. Repos that reverted keep their pull requests. Tell the person each failure line exactly as printed. Never revert, push, merge or delete `undo/<run-id>` by hand. Never ask for a token. Run the script at most once more, then stop.

| Line | Meaning | Do |
|---|---|---|
| `conflict: revert stopped; this repo was left unchanged` | A later change touched the same lines. | Tell the owner which repo. A person decides the fix as a normal change. |
| `conflict: could not open a worktree; this repo was left unchanged` | The script could not make its temporary copy. | Run once more. If it repeats, stop. |
| `refused: undo/<run-id> already exists` | The run was undone before, or an undo is still open. | Say an undo for this run already exists. Do not make another. The owner checks its pull request on the host. |
| `revert: empty` | The run's changes are already gone in that repo. | Say nothing was reverted there. |
| `no commits for that run` | No commit has that run id and the bot's email. | Check the id with the person. A run not yet merged is still on the bot's standing PR: the owner may close that PR. |
| `undo-run skip <repo>: not visible to this token` | That repo is outside this token's grant. | Say which repo was skipped. The other repos still undo. |
| `get-token failed`, `whoami returned no login` | Sign-in problem. | The owner signs in again through the host's own sign-in. Then run once more. |

## Rules

- Undo a whole run, not part of one. To keep some of it, undo the run, then redo the good part as a new change.
- Tell the bot's owner (`owner:` in `BOT.md`) what was undone and why.
- If the run did something outside the repos (sent mail, posted a message), the undo cannot reach it. Say so plainly.
- If the run leaked a secret or private content, undo is not enough. History still holds it. Tell the admin to run `remove-leak`.
