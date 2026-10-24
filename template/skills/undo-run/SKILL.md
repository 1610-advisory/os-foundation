---
name: undo-run
description: Undo everything one bot run changed, in one step, by its Run-Id. Makes one revert commit per repo and opens a pull request that merges by itself. Use when someone says "undo what the bot did", "roll back last night's bot run", "the bot got it wrong", or names a Run-Id.
---

# Undo a bot run

Every commit a bot makes carries `Run-Id: <id>` and `Bot-Owner: <owner>`. This skill undoes all commits of one run at once. It works only when `bots` is in `switches:`.

Undo is a revert. History keeps the run and the undo. Nothing is deleted.

## Steps

1. **Find the run.** Ask what went wrong and when. Look in `bots/<bot>/logs/` for that run's line, or search history for the trailer: `git log --grep 'Run-Id: '`. Show the person the run's date, its routine and the files it changed. Ask: "Undo this whole run?"
2. **Run the script:** `skills/undo-run/undo-run.sh <run-id>`.
3. It finds every commit with that `Run-Id` on `main`, in each repo on this computer.
4. It makes **one** revert commit per repo, on its own branch, and opens a pull request with auto-merge on.
5. Tell the person, in plain words: which repos, how many commits, which files. Give the pull request links.

## When it cannot finish

- **A later change touched the same lines.** The script stops for that repo and changes nothing there. Tell the person which file. Offer to fix that file by hand as a normal change.
- **Run-Id not found.** Check the id with the person. A run that has not merged yet is still on the bot's standing PR: the owner may close that PR instead.
- **No access to a repo.** Say which. The bot's owner or the admin runs the undo there.

## Rules

- Undo a whole run, not part of one. To keep some of it, undo the run, then redo the good part as a new change.
- Tell the bot's owner (`owner:` in `BOT.md`) what was undone and why.
- If the run did something outside the repos (sent mail, posted a message), the undo cannot reach it. Say so plainly.
- If the run leaked a secret or private content, undo is not enough. History still holds it. Tell the admin to run `remove-leak`.
