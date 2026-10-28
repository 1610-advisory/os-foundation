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
| `slug` (or `company_slug`) | The company slug. Written to `company-profile.md` as `company_slug`. Names the repos `<slug>-os` and `<slug>-<area>`. |
| `review_vendor`, `review_kind`, `review_model` | Host on: written to `.github/review.conf` when `main` has none. Same meaning as in `add-teammate/CLI.md`. |
| `company_name`, `owner_name`, `owner_role`, `one_liner`, `areas`, `date` | Fill a value the old rules file never filled. `one_liner` also fills `summary:` in `company-profile.md` when it is still `{{ONE_LINER}}`. |

The rules merge takes each value from the old rules file first (the slug follows the order below). The answers file and `company-profile.md` fill only what is still missing.

The slug comes from the first of these that has one: the answers file, `company_slug:` in `company-profile.md`, a `~/<slug>-os/` path in an old rules file, the `origin` repo name `<slug>-os`, the folder name `<slug>-os`. The real run writes it to `company-profile.md` with the other profile lines.

The host comes from the answers file first, then `company-profile.md` (a v0 profile has no `host:`). The script sets it for `host.sh` once, before the first host call, so the area fetch in the checks below already reaches the host.

## v0 shape

Any of these means v0:

- a `logs` branch, often checked out at `memory/logs/`
- no committed `.agents/skills` link
- no `level:` in `company-profile.md`
- `skills/logs-folder/` exists

## Before it starts

The script stops early in these cases. Each one changes nothing.

- **Windows.** Under Git Bash on Windows it prints `run the upgrade from a Mac or Linux clone of the company repo` and exits 2. Windows teammates get the result by their normal pull.
- **Already v1.** `main` has `level:` in `company-profile.md` and both skill links committed as links. It prints `upgrade: already v1` and exits 0.
- **Pending.** A branch `upgrade/v1` exists but is not merged. It prints `upgrade: pending upgrade/v1` and how to start over: `git checkout main`, then delete the `upgrade/v1` branch and any area `upgrade/scripts` branch. It exits 0.
- **A dirty area.** An area repo has uncommitted changes. It prints `the area areas/<name> has uncommitted changes. Commit or stash them, then run upgrade again.` A real run exits 2 before any company commit. The dry run prints the same line. An area `memory/logs/` worktree with uncommitted logs prints `areas/<name>/memory/logs has uncommitted changes. Commit them on the logs branch, then run upgrade again.` the same way.
- **An area fetch fails** (host on). It prints `could not fetch <repo>`. A real run exits 3 before any commit.
- **Free GitHub org** (team or app on GitHub). `host.sh plan-check` stops it with exit 3, before any commit or push: `This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again.` Solo does not check the plan. A plan the sign-in cannot see stops it the same way: `Could not read the plan of the GitHub org <org>: sign in as an org owner, then run this again. Team setup needs an org owner.` A dry run does not stop: it prints `finding: plan: <that line>` and `finding: plan blocks: check tools on main, protect, and the upgrade pull requests. A real run stops before any change.`, then the full report.
- **No slug** (host on). It prints `the company slug is not known. Add slug=<slug> to the answers file, then run upgrade again.` and exits 2, before any commit or push.
- **A spill file is already there.** It prints `conflict: company-rules.md exists` or `conflict: areas/<name>/area-rules.md exists`. The upgrade will not write a spill file over it. A real run exits 2 before any write. The dry run prints the same line.

## What a real run does

A real run refuses a dirty tree. It stages only the upgrade paths. The result is always one merge commit on `upgrade/v1`, so `git revert -m 1` restores the old state even when there was no `logs` branch.

- the rules merge for `AGENTS.md` and `CLAUDE.md`, as its own commit (see "Rules merge")
- committed links `.agents/skills` and `.claude/skills` pointing at `../skills`
- the `logs` branch merged under `memory/logs/` with its history; each area with its own v0 `logs` branch gets the same in its `upgrade/scripts` branch (`Upgrade: logs history`), and its own `logs-archive-<date>` tag
- the `/memory/logs/` line removed from `.gitignore`
- `level`, `switches`, and `os_version` added to `company-profile.md`
- the approval tier table only when `level` is `team` or `app`
- new skills copied from the template
- new files copied into a skill the company already has; a file that exists is not touched
- `.gitattributes` from the template, only when the folder has none
- `/company-rules.md` and `/area-rules.md` lines in the code-owner files, when the folder has them, with the owners of `AGENTS.md`
- a stock skill file replaced only when its bytes match `v0-hashes.txt` (os-foundation `main` at `c2034af`)
- `skills/logs-folder/` removed only when it matches that hash

A stock skill file that does not match the hash is a conflict. It is left as it is. Company notes are never edited.

### Rules merge

The company's `AGENTS.md` and `CLAUDE.md` get the v1 rules. The company's own lines stay.

1. The script compares each file with the stock v0 file in `skills/upgrade/v0/`. A line that matches the stock line in the same section is stock. A line with a filled placeholder counts as stock too; its value is kept.
2. Every other line is a **company line**. A section whose heading is not in the stock file is a **company section**.
3. The script writes the v1 file and fills its placeholders. Then it adds each company line, byte for byte and in its old order, at the end of the matching v1 section (`skills/upgrade/rules-map.txt`). A company section goes at the end of the file under its own heading.
4. If the result is 10,000 bytes or more (`wc -c`), the company lines and sections go to `company-rules.md` instead, unchanged. `AGENTS.md` gets one line in "This company" that says to read it. That file is a rules file. If `CLAUDE.md` spills too, its lines go at the end of the same file under `## From CLAUDE.md`. Nothing in the file is replaced.
5. A value with no source stays as its placeholder, for example `{{OWNER_NAME}}`. The dry run prints one `todo: fill` line for each, for example `todo: fill {{OWNER_NAME}}`.

The rules merge is its own commit, `Upgrade: rules merge`, inside the one upgrade pull request. The pull request body lists it first, for the code owner. One `git revert -m 1` still undoes the whole upgrade.

A file that is still exactly stock becomes the plain v1 file. A folder whose `AGENTS.md` already has `## 1. Level first` is left alone.

Each area gets the same merge in its own `upgrade/scripts` pull request, with the v1 area template that fits best (`_area`, `apps`, `finance` or `marketing`). An area that spills uses `area-rules.md`, linked from the top of the area `AGENTS.md`. With no host, the area merge is committed on `upgrade/scripts` in the area repo.

### Skill links

A `.agents/skills` or `.claude/skills` that is already a link to `../skills` stays. A missing path, a file, or a wrong link becomes that link.

A folder of copies that git tracks becomes the link only when every file in it is a copy of `skills/`, a stale stock copy, or a skill the company added. An added skill moves to `skills/` first (`change: skill-moved`). A file that differs from both its copy in `skills/` and the v0 hash prints `conflict: .claude/skills/<path>`, then `conflict: .claude/skills left: resolve the files above first`. The folder stays. The person resolves those files, then runs the upgrade again.

A folder of copies that git does not track becomes the link only when every file is a copy of `skills/` or a stale stock copy. Any other file prints `conflict: .claude/skills (untracked; commit it first)`. The folder is not moved or deleted. The same holds for `.agents/skills`.

The old `logs` tip is tagged `logs-archive-<YYYY-MM-DD>`. Keep that tag for 90 days, then delete it. The script says so. It does not delete the tag.

If the folder is app-linked (`app-link.json` or `OS_APP_LINK=1`), the dry-run says groups need Track K and were not read.

When `host` is not `none` and `host.sh` is present, the script opens one pull request. At `team` or `app` it first does these steps, once per repo (the company repo, then each area repo), and prints each one. Solo skips steps 1 and 2:

1. `checks-on-main: <repo>`. The checks job copies its tools from `main`, never from the pull request head. A v0 `main` has no tools, so no upgrade pull request could pass. When `main` lacks `.github/workflows/checks.yml`, `.github/scripts/` or `.github/review.conf`, the script commits only those files on top of `origin/main`, plus rules-only `CODEOWNERS` files in place of a v0 `* <owners>` line (same owners). Every other `CODEOWNERS` line stays, after the rules lines, under `# Kept from before the upgrade.` Then `host.sh unprotect <repo>` (on GitHub this also removes the v0 classic rule, which would refuse the push), a push to `main`, and step 2. If the push is refused, it runs `protect` at once and stops: `main` is never left open. If that `protect` fails too, it prints `PROTECTION IS OFF on <repo>: run skills/_host/host.sh protect <repo> --code-owners --approvals 0`. No company content goes to `main`. When `main` has them: `checks-on-main: <repo> already`, no push.
2. `protected: <repo>`: `host.sh protect <repo> --code-owners --approvals 0`. On GitHub that also replaces the v0 classic rule (one code-owner approval, which only the admin could give) and turns on auto-merge.
3. The area pull requests, then the company pull request. Each gets `host.sh auto-merge`. If that fails, it prints `auto-merge is off on <repo>: pull request <n> stays open until the admin merges it.` and goes on. On GitHub every upgrade pull request is the admin's own rules change, and GitHub never counts the author's own approval. So each one also prints `merge-by-hand: <repo> <n>`. The `rules-review` ruleset lets an org admin bypass it on a pull request (`bypass_mode: pull_request`); auto-merge does not use that bypass. Solo with a host: no auto-merge; the person merges.

At `team` or `app` it prints `review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY` first, and `no review key yet: ...` when the org key is not there.

Each area repo gets its own pull request for the check scripts, on `upgrade/scripts`. That pull request also adds `review-rules.md` when the area main lacks it, and carries the area rules merge as its own commit. It does not replace an existing file. A dry-run prints `pr-plan:` for that pull request and does not open it.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok, including a dry-run that found conflicts, `upgrade: already v1` and `upgrade: pending upgrade/v1` |
| 1 | usage |
| 2 | refused (not a v0 folder, not a git repo, Windows, uncommitted changes, a spill file already there, no slug with host on) |
| 3 | tool error (`git filter-repo` missing) or host error (an area fetch failed, the check tools could not reach `main`, a Free GitHub org at team level) |
| 4 | auth failed |

## What it prints

```
upgrade: already v1
upgrade: pending upgrade/v1
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
conflict: .claude/skills (untracked; commit it first)
conflict: company-rules.md exists
conflict: areas/<name>/area-rules.md exists
app-groups: needs Track K
tag: logs-archive-<YYYY-MM-DD>
keep: 90 days
change: logs-history areas/<name>
change: checks-on-main <repo>
change: protect <repo>
todo: answer slug (...)
todo: answer review_vendor (...)
review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY
checks-on-main: <repo> [already]
protected: <repo>
pr: <repo> <number>
auto-merge is off on <repo>: pull request <n> stays open until the admin merges it.
merge-by-hand: <repo> <n>
pr: <number>
admin, on GitHub: wait for the green checks. Open each pull request. Tick "Merge without waiting for requirements to be met (bypass rules)". Click "Bypass rules and merge".
upgrade: open pull requests: <repo> <n>, ... Merge each one when its checks pass.
```

A dry-run prints `upgrade: dry-run` and no `pr:` line. A real run prints `upgrade: ok` when nothing is left for a person to merge. When any pull request will not merge by itself, the last line is `upgrade: open pull requests: ...` instead, never `upgrade: ok`.

- `change: rules-merge` comes once per rules file: `AGENTS.md`, `CLAUDE.md`, and each `areas/<name>/AGENTS.md` and `CLAUDE.md`. `company-lines` is the count of company lines kept. `chars` is the size of the merged file in bytes.
- `change: rules-spill` comes only when the merged file would be 10,000 bytes or more. In an area the file is `area-rules.md`.
- `change: skill-moved` comes only for a company skill in a tracked copy folder.
- A changed `AGENTS.md` or `CLAUDE.md` is not a conflict. The rules merge handles it.
