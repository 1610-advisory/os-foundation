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
2. Revoke first, in this order: `team-remove` from each area team and from `company`, `revoke` on the company repo, each area repo, and the workspace repo, then `org-remove`.
3. Archives the workspace repo `<slug>-user-<person>`. Admin read stays through org ownership. Non-PHI workspaces are kept. PHI deletion is app level and is not in v1. The script says so.
4. Sets `left: <date>` on `people/<Name>.md`.
5. Sets `owner:` on each `bots/*/BOT.md` this person owns.
6. Puts those file changes on branch `rules/<admin>/offboard-<person>` and opens a pull request.
7. Prints a checklist of vendor seats from `architecture.md`, under the heading `Connections`. That list is for the admin. It is not a daily-path step. A missing file prints that no seats are listed.

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
phi: app-level-not-in-v1
seat: <line from Connections>
```

No tokens. No mailbox contents.
