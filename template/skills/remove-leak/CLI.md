# remove-leak

```
remove-leak.sh --repo <name> (--path <p> | --pattern-rule <id>) [--root <dir>] [--pr <n>] [--head <branch>]
remove-leak.sh --help
```

Removes a leaked file or a matched pattern from history and force-pushes. The secret value is never printed and never passed as a child process argument.

The script calls the host only through `skills/_host/host.sh`. It does not call `gh` or the Forgejo API.

## Flags

| Flag | Meaning |
|---|---|
| `--repo <name>` | Host repo name, for example `<slug>-os` or `<slug>-<area>`. Required. |
| `--path <p>` | Repo-relative path to drop from all history. One of `--path` or `--pattern-rule` is required. |
| `--pattern-rule <id>` | Rule id. The matching text is replaced. The id is not the secret. |
| `--root <dir>` | Company folder, used to find the local checkout and `host.sh`. Default: the current directory. |
| `--pr <n>` | If this pull request is still open, revert the leak on it first. |
| `--head <branch>` | Head branch of that open pull request. Required when `--pr` is set and the pull request is open. |
| `--help` | Print usage and exit 0. |

## Pattern rules

Built in: `aws-access-key`, `generic-api-key`, `private-key`. Extra rules may live in `skills/sync/secret-patterns.txt`, one `id<TAB>regex` per line. An unknown id is exit 2.

The regex goes in a mode-600 file passed to `git filter-repo --replace-text`. It is not a command argument.

## What it does

1. If `--pr` is open, revert the path on `--head` and push that branch (no force). If the leak is not on `main`, stop there.
2. Clone the repo to a temp directory and rewrite with `git filter-repo`. `--path` drops that path. `--pattern-rule` replaces matches with `[removed]`.
3. Lift protection with `host.sh unprotect <name>`, force-push every branch and tag, then `host.sh protect <name> --code-owners --approvals 0`.
4. `host.sh purge-request <name>`.
5. Push an annotated tag `os-rewrite-<YYYYMMDDHHMMSS>`. The message is `rule: <id>` or `path: <p>`. It does not contain the secret.
6. Write one audit line in `memory/logs/YYYY-MM-DD-<person>.md` on the rewritten `main`. The line is `path: <p>` or `rule: <id>`. It does not name the secret.

`unprotect` lifts what `protect` set. After that, an exit trap always runs `protect` again. If the restore fails, the script prints `PROTECTION IS OFF on <repo>: run skills/_host/host.sh protect <repo> --code-owners --approvals 0` and does not print ok.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | usage |
| 2 | refused (unknown rule, repo not found locally or on the host) |
| 3 | host or tool error, including protection still on |
| 4 | auth failed |

## What it prints

```
remove-leak: ok
tag: os-rewrite-<YYYYMMDDHHMMSS>
rule: <id>
```

or `rule: path`. Never the secret, never a token.
