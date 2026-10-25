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
3. It fetches `main` in the company repo and each area repo. It finds every commit with that `Run-Id` **and** the bot's author email from its `BOT.md`. A `Run-Id` line copied onto someone else's commit is not undone.
4. Per repo, it makes **one** revert commit on the branch `undo/<run-id>`, in a temporary copy. The person's working copy is not touched. The commit says `Reverts: <run-id>`. It opens a pull request with auto-merge on.
5. Tell the person, in plain words: which repos, which commits, and the pull request links. The script prints them. The pull request is the last check: the checks run on it before it merges.

## When it cannot finish

The script goes on with the other repos. Repos that reverted keep their pull requests.

- **`conflict:`** A later change touched the same lines. That repo is unchanged. Tell the person which repo. Offer to undo that part by hand as a normal change.
- **`refused: undo/<run-id> already exists`** The run was undone before, or an undo is still open. Find that pull request and show it. Do not delete the branch to try again.
- **No commit has that run id.** Check the id with the person. A run that has not merged yet is still on the bot's standing PR. The owner may close that PR instead.
- **No access to a repo.** Say which. The bot's owner or the admin runs the undo there.

## Rules

- Undo a whole run, not part of one. To keep some of it, undo the run, then redo the good part as a new change.
- Tell the bot's owner (`owner:` in `BOT.md`) what was undone and why.
- If the run did something outside the repos (sent mail, posted a message), the undo cannot reach it. Say so plainly.
- If the run leaked a secret or private content, undo is not enough. History still holds it. Tell the admin to run `remove-leak`.
