# remove-teammate

```
remove.sh --person <slug> [--new-bot-owner <slug>] [--root <dir>] [--date YYYY-MM-DD]
remove.sh --help
```

Revoke first. Then record the leaving. Changes to files go by pull request. Nobody writes to `main`.

The script calls the host only through `skills/_host/host.sh`. A token never appears in a child process's arguments.

## Flags

| Flag | Meaning |
|---|---|
| `--person <slug>` | Required. The person to remove. |
| `--new-bot-owner <slug>` | New owner for each bot this person owns. Default: the person's `manager:` if set, otherwise the admin. |
| `--root <dir>` | Company folder. Default: the current directory. |
| `--date YYYY-MM-DD` | Leaving date. Default: today, or `OS_NOW` when that is set (`YYYY-MM-DD`). |
| `--help` | Print usage and exit 0. |

## What it does

1. Refuses to remove the last admin (a person with `role: admin` and an empty `left:`).
2. Revoke first: `team-remove`, `revoke`, `cancel-invites` on each repo, `cancel-invites` on the org, then `org-remove`. A person who never accepted has only pending invites, and an invite is access: they get it the moment they accept. Then it checks after the fact: `host.sh invites` on the org must be empty, and `host.sh user-access` on the company repo, each area repo, and the workspace must be `none` (a pending repo invite is `invited`). Print `revoked:` only when all of that holds. Otherwise exit 3 and list each place that still has access, with what is left (`(write)`, `(invited)`, or `(not checked)`). `remove: ok` comes only after `revoked:`.
3. Archives the workspace repo `<slug>-user-<person>`. Admin read stays through org ownership. Non-PHI workspaces are kept. PHI deletion is app level and is not in v1. The script says so.
4. Sets `left: <date>` on `people/<Name>.md`.
5. Sets `owner:` on each `bots/*/BOT.md` this person owns.
6. Puts those file changes on branch `rules/<admin>/offboard-<person>` and opens a pull request. It commits only those files. Untracked or held files in the company folder stay out. After the push it switches the company folder back to `main` and leaves those changes there as local edits, so the person sees the page marked `left:` at once. They reach `main` only by that pull request: `sync push` holds them until it merges. If that switch is refused, it prints one plain line and still opens the pull request. A second run rebuilds the branch from `origin/main`, replaces it on the host, and opens the pull request if none is open. It turns on auto-merge, like `propose`, so the pull request merges by itself when its checks pass (`auto-merge: on`). If the host refuses, it prints one line that auto-merge is off and what the admin runs. When a `BOT.md` changed on GitHub, the admin is the author of a rules change and GitHub never counts the author's approval, so it prints `merge-by-hand:` with the boxes to click.
7. Prints a checklist of vendor seats from `architecture.md`, under the heading `Connections`. Bullets and table rows both count. That list is for the admin. It is not a daily-path step. A missing file prints that no seats are listed.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | usage |
| 2 | refused (unknown person, last admin) |
| 3 | host or tool error |
| 4 | auth failed |

## What it prints

```
remove: ok
revoked: <slug>
archived: <slug>-user-<slug>
left: YYYY-MM-DD
bot-owner: <new-slug>
pr: <number>
auto-merge: on
merge-by-hand: <repo> <number>: ...   (GitHub, only when bots/ changed)
phi: app-level-not-in-v1
seat: <line from Connections>
```

No tokens. No mailbox contents.
