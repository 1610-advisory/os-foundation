# undo-run CLI

The prose skill asks for the run id. The script does the work. Read `add-bot/CLI.md` for the bot page keys, the run id, and the trailers.

The `bots` switch must be on. If it is off, the script refuses and changes nothing.

```
undo-run.sh <run-id> [--root <dir>]
undo-run.sh --help
```

Run it from the company root, or pass `--root`. `OS_PROFILE` may point at `company-profile.md`.

`<run-id>` is the `Run-Id` trailer from the bot run. It is a plain name: letters, digits, `.`, `_`, and `-`.

## What it does

1. Fetch `origin/main` in the company repo and in each `areas/*` repo. A fetch that says the repo is not found or this token has no access is skipped only when the local `origin/main` and the local branch have no commit for this run. The script prints `undo-run skip <repo>: not visible to this token` and goes on. If that clone has a match, or there is no local `origin/main` to prove it does not, the visible repos are still reverted, then it prints `undo-run partial: <repo> not visible; revert it there by hand or rerun` and exits 4. Any other fetch error stops the script (exit 3). If no repo was visible, it exits 2 with `no repo visible to this token`.
2. Find every commit whose message has a `Run-Id` trailer equal to the argument.
3. In each repo that has such commits, make one revert commit on branch `undo/<run-id>`.
4. Open a pull request into `main` through `host.sh open-pr`.
5. Ask for auto-merge through `host.sh auto-merge`. Merge commit, not squash.
6. Print the repo, the reverted commit ids, the revert commit, and the pull request URL.

The revert runs in a temporary worktree from `origin/main`. The live checkout is not touched. If a revert conflicts, the script removes that worktree, stops for that repo, and changes nothing there. It prints `conflict:` and continues with the other repos. Exit 3 means at least one repo conflicted. Repos that reverted still have their pull requests.

A commit matches only when `git interpret-trailers --parse` shows `Run-Id` equal to the argument and the author email is the bot email on a bot page. A copied trailer on another person's commit is not reverted. Trailers are not proof. The pull request is the check. The script prints every SHA it reverts.

The revert commit does not reuse the original `Run-Id`. Its message is:

```
Revert run <run-id>

Reverts: <run-id>
```

It does not print a diff. It does not print a token.

The push token comes from `host.sh get-token`. When `OS_BOT` is set, that call is `get-token --bot <bot>`. The token goes to git through an environment variable and a password helper script. It is not put in the remote URL or in a child argument list.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | the revert pull requests are open |
| 1 | usage |
| 2 | refused, no commit has that run id, or no repo was visible to this token |
| 3 | host or git error, or a revert conflict in at least one repo |
| 4 | auth failed, or a skipped repo may still hold this run |

## Related

`add-bot/run.sh` makes the run id and the trailers `Run-Id` and `Bot-Owner`. See `add-bot/CLI.md`.
