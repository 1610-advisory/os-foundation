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
| `--answers <file>` | Optional `key=value` lines. See "Answers keys". A missing key is left as it is. |
| `--help` | Print usage and exit 0. |

## Answers keys

| Key | Use |
|---|---|
| `level`, `os_version`, `host`, `host_url`, `org`, `sync_engine`, `runner` | Written to `company-profile.md`. |
| `slug` (or `company_slug`) | The company slug, for the rules merge. |
| `company_name`, `owner_name`, `owner_role`, `one_liner`, `areas`, `date` | Fill a value the old rules file never filled. `one_liner` also fills `summary:` in `company-profile.md` when it is still `{{ONE_LINER}}`. |

The rules merge takes each value from the old rules file first (the slug follows the order below). The answers file and `company-profile.md` fill only what is still missing.

The slug comes from the first of these that has one: the answers file, `company_slug:` in `company-profile.md`, a `~/<slug>-os/` path in an old rules file, the `origin` repo name `<slug>-os`, the folder name `<slug>-os`.

## v0 shape

Any of these means v0:

- a `logs` branch, often checked out at `memory/logs/`
- no committed `.agents/skills` link
- no `level:` in `company-profile.md`
- `skills/logs-folder/` exists

## What a real run does

A real run refuses a dirty tree. It stages only the upgrade paths. The result is always one merge commit on `upgrade/v1`, so `git revert -m 1` restores the old state even when there was no `logs` branch.

- the rules merge for `AGENTS.md` and `CLAUDE.md`, as its own commit (see "Rules merge")
- committed links `.agents/skills` and `.claude/skills` pointing at `../skills`
- the `logs` branch merged under `memory/logs/` with its history
- the `/memory/logs/` line removed from `.gitignore`
- `level`, `switches`, and `os_version` added to `company-profile.md`
- the approval tier table only when `level` is `team` or `app`
- new skills copied from the template
- new files copied into a skill the company already has; a file that exists is not touched
- `.gitattributes` from the template, only when the folder has none
- a stock skill file replaced only when its bytes match `v0-hashes.txt` (os-foundation `main` at `c2034af`)
- `skills/logs-folder/` removed only when it matches that hash

A stock skill file that does not match the hash is a conflict. It is left as it is. Company notes are never edited.

### Rules merge

The company's `AGENTS.md` and `CLAUDE.md` get the v1 rules. The company's own lines stay.

1. The script compares each file with the stock v0 file in `skills/upgrade/v0/`. A line that matches the stock line in the same section is stock. A line with a filled placeholder counts as stock too; its value is kept.
2. Every other line is a **company line**. A section whose heading is not in the stock file is a **company section**.
3. The script writes the v1 file and fills its placeholders. Then it adds each company line, byte for byte and in its old order, at the end of the matching v1 section (`skills/upgrade/rules-map.txt`). A company section goes at the end of the file under its own heading.
4. If the result is 10,000 characters or more, the company lines and sections go to `company-rules.md` instead, unchanged. `AGENTS.md` gets one line in "This company" that says to read it. That file is a rules file.
5. A value with no source stays as its placeholder, for example `{{OWNER_NAME}}`. The dry run prints one `todo: fill` line for each, for example `todo: fill {{OWNER_NAME}}`.

The rules merge is its own commit, `Upgrade: rules merge`, inside the one upgrade pull request. The pull request body lists it first, for the code owner. One `git revert -m 1` still undoes the whole upgrade.

A file that is still exactly stock becomes the plain v1 file. A folder whose `AGENTS.md` already has `## 1. Level first` is left alone.

Each area gets the same merge in its own `upgrade/scripts` pull request, with the v1 area template that fits best (`_area`, `apps`, `finance` or `marketing`). An area that spills uses `area-rules.md`, linked from the top of the area `AGENTS.md`. With no host, the area merge is committed on `upgrade/scripts` in the area repo.

### Skill links

A `.agents/skills` or `.claude/skills` that is already a link to `../skills` stays. A missing path, a file, or a wrong link becomes that link.

A folder of copies becomes the link only when every file in it is a copy of `skills/`, a stale stock copy, or a skill the company added. An added skill moves to `skills/` first (`change: skill-moved`). If one file differs from its copy in `skills/`, the dry run prints `conflict:` for it and the folder stays. The person resolves those files, then runs the upgrade again.

The old `logs` tip is tagged `logs-archive-<YYYY-MM-DD>`. Keep that tag for 90 days, then delete it. The script says so. It does not delete the tag.

If the folder is app-linked (`app-link.json` or `OS_APP_LINK=1`), the dry-run says groups need Track K and were not read.

When `host` is not `none` and `host.sh` is present, the script opens one pull request. It does not write to `main`.

Each area repo gets its own pull request for the check scripts, on `upgrade/scripts`. That pull request also adds `review-rules.md` when the area main lacks it, and carries the area rules merge as its own commit. It does not replace an existing file. A dry-run prints `pr-plan:` for that pull request and does not open it.

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
change: rules-merge <path> company-lines=<n> chars=<m>
change: rules-spill <path> -> company-rules.md
todo: fill {{OWNER_NAME}}
change: .gitattributes [areas/<name>]
change: skill-files skills/<name> new=<n>
change: .agents/skills
change: skill-moved skills/<path>
conflict: skills/<name>
conflict: .claude/skills/<path>
conflict: .claude/skills left: resolve the files above first
app-groups: needs Track K
tag: logs-archive-<YYYY-MM-DD>
keep: 90 days
pr: <number>
```

A dry-run prints `upgrade: dry-run` and no `pr:` line. A real run prints `upgrade: ok`.

- `change: rules-merge` comes once per rules file: `AGENTS.md`, `CLAUDE.md`, and each `areas/<name>/AGENTS.md` and `CLAUDE.md`. `company-lines` is the count of company lines kept. `chars` is the size of the merged file.
- `change: rules-spill` comes only when the merged file would be 10,000 characters or more. In an area the file is `area-rules.md`.
- A changed `AGENTS.md` or `CLAUDE.md` is not a conflict. The rules merge handles it.
