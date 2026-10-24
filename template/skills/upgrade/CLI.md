# upgrade

```
upgrade.sh [--dry-run] [--root <dir>] [--template <dir>] [--level solo|team|app] [--answers <file>]
upgrade.sh --help
```

Moves a v0 company folder to v1. Dry-run first. Then one branch and one pull request. Company content is not rewritten. One `git revert -m 1 <merge>` restores the old state.

## Flags

| Flag | Meaning |
|---|---|
| `--dry-run` | Print what would change and what conflicts. Change nothing. Exit 0. |
| `--root <dir>` | Company folder. Default: the current directory. |
| `--template <dir>` | v1 template folder. Default: the `template/` next to this skill when that folder is still the os-foundation template. |
| `--level solo\|team\|app` | Level to write. Default: `solo`, or the `level` key in the answers file. |
| `--answers <file>` | Optional `key=value` lines: `level`, `os_version`, `host`, `host_url`, `org`, `sync_engine`, `runner`. |
| `--help` | Print usage and exit 0. |

## v0 shape

Any of these means v0:

- a `logs` branch, often checked out at `memory/logs/`
- no committed `.agents/skills` link
- no `level:` in `company-profile.md`
- `skills/logs-folder/` exists

## What a real run does

One merge commit on branch `upgrade/v1`:

- committed links `.agents/skills` and `.claude/skills` pointing at `../skills`
- the `logs` branch merged under `memory/logs/` with its history
- the `/memory/logs/` line removed from `.gitignore`
- `level`, `switches`, and `os_version` added to `company-profile.md`
- the approval tier table only when `level` is `team` or `app`
- new skills copied from the template
- a stock skill file replaced only when its bytes match `v0-hashes.txt` (os-foundation `main` at `c2034af`)
- `skills/logs-folder/` removed only when it matches that hash

A stock skill file that does not match the hash is a conflict. It is left as it is. Company notes are never edited.

The old `logs` tip is tagged `logs-archive-<YYYY-MM-DD>`. Keep that tag for 90 days, then delete it. The script says so. It does not delete the tag.

If the folder is app-linked (`app-link.json` or `OS_APP_LINK=1`), the dry-run says groups need Track K and were not read.

When `host` is not `none` and `host.sh` is present, the script opens one pull request. It does not write to `main`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok, including a dry-run that found conflicts |
| 1 | usage |
| 2 | refused (not a v0 folder, not a git repo) |
| 3 | tool error (`git filter-repo` missing) or host error |
| 4 | auth failed |

## What it prints

```
upgrade: dry-run
v0: logs-branch
v0: no-links
v0: no-level
v0: logs-folder
change: links
change: logs-history
change: level-block
change: tier-table
conflict: skills/<name>
app-groups: needs Track K
tag: logs-archive-<YYYY-MM-DD>
keep: 90 days
pr: <number>
```

A dry-run prints `upgrade: dry-run` and no `pr:` line. A real run prints `upgrade: ok`.
