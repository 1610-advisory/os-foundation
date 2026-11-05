# upgrade

```
upgrade.sh [--dry-run] [--root <dir>] [--template <dir>] [--level solo|team|app] [--answers <file>]
upgrade.sh --refresh [--dry-run] [--root <dir>] [--template <dir>]
upgrade.sh --help
```

Moves a v0 company folder to v1. Dry-run first. Then one branch and one pull request. Company content is not rewritten. One `git revert -m 1 <merge>` restores the old state. `--refresh` brings a v1 company's stock skills and checks to a newer template (see "Refresh").

## Flags

| Flag | Meaning |
|---|---|
| `--dry-run` | Print what would change and what conflicts. Change nothing. Exit 0. |
| `--refresh` | A v1 company: refresh stock skills and checks. A v0 company: refused (exit 2); run the upgrade first. |
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
- **Already v1.** `main` has `level:` in `company-profile.md` and both skill links committed as links. Without `--refresh` it prints `upgrade: already v1. To bring stock skills and checks to this template, run it with --refresh.` and exits 0.
- **Pending, no host.** A branch `upgrade/v1` exists and there is no host: the person merges it by hand. It prints `upgrade: pending upgrade/v1` and `To start over, run in the company folder: git checkout main && git branch -D upgrade/v1` (plus the same for each area `upgrade/scripts`). It exits 0 and changes nothing.
- **An earlier run's branches (host on).** The upgrade owns `upgrade/v1` (company) and `upgrade/scripts` (each area), in the folder and on the host. A branch is its own when its last commit is one the upgrade makes (`Upgrade to v1`, or a subject that starts `Upgrade: `). A folder left on its own upgrade branch goes back to `main`: `switched <folder> to main from <branch> (an earlier upgrade run)`. With a host, the dry run prints `change: replace <repo> <branch> (an earlier upgrade run made it; its pull request is reused)`. A real run rebuilds the branch from `main` and pushes it with `--force-with-lease` (only if the host branch has not moved since the run looked). It prints `replaced: <repo> <branch> (an earlier upgrade run made it)`. `open-pr` updates the open pull request from that branch, or opens a new one when the old one was closed. So a stopped or superseded run needs no start-over: run it again.
- **Someone else's commits on an upgrade branch.** It prints one line per branch: `upgrade: stopped: <repo> has commits on <branch> that the upgrade did not make. To keep them, merge or close its pull request first. To start over, in <folder> run: <commands> (that also closes its pull request). Then run upgrade again.` The commands are exact: `git checkout main && git branch -D <branch>` for the folder, `git push origin --delete <branch>` for the host, only the parts that hold such commits. A real run exits 2 before any change. The dry run prints the same line and goes on.
- **A dirty area.** An area repo has uncommitted changes. It prints `the area areas/<name> has uncommitted changes. Commit or stash them, then run upgrade again.` A real run exits 2 before any company commit. The dry run prints the same line. An area `memory/logs/` worktree with uncommitted logs prints `areas/<name>/memory/logs has uncommitted changes. Commit them on the logs branch, then run upgrade again.` the same way.
- **An area fetch fails** (host on). It prints `could not fetch <repo>`. A real run exits 3 before any commit.
- **Free GitHub org** (team or app on GitHub). `host.sh plan-check` stops it with exit 3, before any commit or push: `This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again.` Solo does not check the plan. A plan the sign-in cannot see stops it the same way: `Could not read the plan of the GitHub org <org>: sign in as an org owner, then run this again. Team setup needs an org owner.` A dry run does not stop: it prints `finding: plan: <that line>` and `finding: plan blocks: check tools on main, protect, and the upgrade pull requests. A real run stops before any change.`, then the full report.
- **No slug** (host on). It prints `the company slug is not known. Add slug=<slug> to the answers file, then run upgrade again.` and exits 2, before any commit or push.
- **A spill file is already there.** It prints `conflict: company-rules.md exists` or `conflict: areas/<name>/area-rules.md exists`. The upgrade will not write a spill file over it. A real run exits 2 before any write. The dry run prints the same line.

## What a real run does

A real run refuses a dirty tree. It stages only the upgrade paths. The result is always one merge commit on `upgrade/v1`, so `git revert -m 1` restores the old state even when there was no `logs` branch.

- the rules merge for `AGENTS.md` and `CLAUDE.md`, as its own commit (see "Rules merge")
- committed links `.agents/skills` and `.claude/skills` pointing at `../skills`
- the `logs` branch merged under `memory/logs-archive/` with its history (outside `memory/logs/`: a teammate's old logs worktree is there, ignored by its `main`, and a plain `git pull` writes over ignored files; sync push also keeps logs off `main` while the host has the old branch); each area with its own v0 `logs` branch gets the same in its `upgrade/scripts` branch (`Upgrade: logs history`), and its own `logs-archive-<date>` tag
- the `/memory/logs/` line removed from `.gitignore`
- the `/users/` and `/library/` lines added to `.gitignore`, when they are missing
- `level`, `switches`, `os_version` and `host` added to `company-profile.md`. With no host answer and no `host:` there, it writes `host: none`.
- the approval tier table only when `level` is `team` or `app`
- new skills copied from the template
- new files copied into a skill the company already has; a file that exists is not touched
- `joining-terms.md` and `scale.md`, the company-root files v1 ships, when the folder lacks them (v1.0.3). The company name goes in place of `{{COMPANY_NAME}}`: the `company_name` answer, else the first heading of `company-profile.md`. A copy the company has, edited or not, is never touched. Join stops without `joining-terms.md`.
- `.gitattributes` from the template, only when the folder has none. Each area gets the `_area` copy, merged or not.
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

The rules merge is its own commit, `Upgrade: rules merge`, inside the one upgrade pull request. The commit message records each rules file and each company line kept. The pull request body opens with `Upgrade to os-foundation release <release>: the release's rules text, with the company's own lines kept (listed).` Then it lists, per rules file, each company line it kept and each line moved to a spill file. Then it says what moves between approval tiers (the release's default table, and why: it is the release's default). The code owner reads that first. The model review reads the body too: a change the body lists is explained, and a table set to the release's default is not a loosening (`review-rules.md`, section "Pull requests from the admin's own steps"). One `git revert -m 1` still undoes the whole upgrade.

A file that is still exactly stock becomes the plain v1 file. A folder whose `AGENTS.md` already has `## 1. Level first` is left alone.

Each area gets the same merge in its own `upgrade/scripts` pull request, with the v1 area template that fits best (`_area`, `apps`, `finance` or `marketing`). An area that spills uses `area-rules.md`, linked from the top of the area `AGENTS.md`. With no host, the area merge is committed on `upgrade/scripts` in the area repo.

### Skill links

A `.agents/skills` or `.claude/skills` that is already a link to `../skills` stays. A missing path, a file, or a wrong link becomes that link.

A folder of copies that git tracks becomes the link only when every file in it is a copy of `skills/`, a stale stock copy, or a skill the company added. An added skill moves to `skills/` first (`change: skill-moved`). A file that differs from both its copy in `skills/` and the v0 hash prints `conflict: .claude/skills/<path>`, then `conflict: .claude/skills left: resolve the files above first`. The folder stays. The person resolves those files, then runs the upgrade again.

A folder of copies that git does not track becomes the link only when every file is a copy of `skills/` or a stale stock copy. Any other file prints `conflict: .claude/skills (untracked; commit it first)`. The folder is not moved or deleted. The same holds for `.agents/skills`.

The old `logs` tip is tagged `logs-archive-<YYYY-MM-DD>`. Keep that tag for 90 days, then delete it. The script says so. It does not delete the tag. With a host, the tag goes up with the upgrade branch, so every clone has it: `sync.sh pull` uses it to bring in logs pushed to the old `logs` branch after the run (sync `CLI.md`). If that push fails it prints `logs-tag: could not push the logs-archive tag to <repo>. ...` and goes on.

When the company or an area has an old `logs` branch and a host, the upgrade prints `log-freeze: ...` near the top (dry run and real run): before the real run every teammate commits and pushes their logs, and nobody writes a log until the pull requests merge. Before its last line, a real run prints four `teammates:` lines: in an old copy of the folder, do not run `git pull`; save the logs (`git -C memory/logs add -A`, `commit`, `pull --rebase`, `push`); after the merge and Part A, rename the old folder and join as a new teammate (Part B); join brings each file, commit and log the old folder holds that the host lacks into the new folder (`old-folder:` lines): a new file or log is copied, and a change to a file the host has is set aside for the agent to re-apply; never copy a whole file by hand. A stash is listed, to redo by hand. Delete the old folder only after each stash is redone, the agent has re-applied what was set aside, and sync has sent it (SKILL.md section 11). A teammate who already has the v1 `sync` skill runs `skills/sync/sync.sh pull` instead. Then one `admin:` line: sync push holds logs until the old branch is gone; v0 protected that branch, so a plain `git push origin --delete logs` fails; when every teammate has moved, run `skills/_host/host.sh drop-logs <repo>` for the company repo and each area repo that had one (the line names each repo; without a host it gives `git push origin --delete logs`).

If the folder is app-linked (`app-link.json` or `OS_APP_LINK=1`), the dry-run says groups need Track K and were not read.

When `host` is not `none` and `host.sh` is present, the script opens one pull request. At `team` or `app` it first does these steps, once per repo (the company repo, then each area repo), and prints each one. Solo skips steps 1 and 2:

1. `checks-on-main: <repo>`. The checks job copies its tools from `main`, never from the pull request head. A v0 `main` has no tools, so no upgrade pull request could pass. When `main` lacks `.github/workflows/checks.yml`, `.github/scripts/` or `.github/review.conf`, the script commits only those files on top of `origin/main`, plus rules-only `CODEOWNERS` files in place of a v0 `* <owners>` line (same owners). Every other `CODEOWNERS` line stays, after the rules lines, under `# Kept from before the upgrade.` Then `host.sh unprotect <repo>` (on GitHub this also removes the v0 classic rule, which would refuse the push), a push to `main`, and step 2. If the push is refused, it runs `protect` at once and stops: `main` is never left open. If that `protect` fails too, it prints `PROTECTION IS OFF on <repo>: run skills/_host/host.sh protect <repo> --code-owners --approvals 0`. When `main` lacks `review-rules.md`, this release's goes on `main` in the same commit (only the release's file: a company's own `review-rules.md` in the folder goes up in the upgrade pull request, which the review judges) (`checks-on-main: <repo> ... and review-rules.md`, or `checks-on-main: <repo> added review-rules.md to main` when it is the only change). So the review judges the upgrade pull request with the release's rules, which know the upgrade. The checks job copies `review-rules.md` from `main`, never from the pull request head, so the head cannot change the rules it is judged by. After this step the company folder fast-forwards to the new `main`. No company content goes to `main`. When `main` has them, it compares them with this release's (`.github/workflows/checks.yml` and `.github/scripts/`; `review.conf` and `CODEOWNERS` stay as they are). The same: `checks-on-main: <repo> already`, no push. Different, and `.github/scripts/tools-release` on `main` is lower (tools from before the marker are release 0): it commits this release's tools on top of `origin/main` (`Upgrade: update check tools on main`) and pushes them by the same safe path, then prints `checks-on-main: <repo> updated the check tools on main (release <old> to <new>)`. Different, and `main`'s release is the same or higher: no push, `checks-on-main: <repo> already: kept the check tools on main (release <main>; this upgrade has <new>)`. Older tools never go over newer ones.
2. `protected: <repo>`: `host.sh protect <repo> --code-owners --approvals 0`. On GitHub that also replaces the v0 classic rule (one code-owner approval, which only the admin could give) and turns on auto-merge.
3. The area pull requests, then the company pull request. On Forgejo each gets `host.sh auto-merge`. If that fails, it prints `auto-merge is off on <repo>: pull request <n> stays open until the admin merges it.` and goes on. On GitHub every upgrade pull request is the admin's own rules change, and the admin merges it by hand. Each one gets `host.sh auto-merge-off` (a pull request reused from an earlier run may still have auto-merge on, and would merge by itself), then prints `merge-by-hand: <repo> <n>: it will not merge by itself. When lint and the secret scan pass and the model review passes (or the admin overrides it, see the override: line), the admin opens it and merges it. When the admin is the only code owner, a plain merge works. If GitHub asks for a review, tick "Merge without waiting for requirements to be met (bypass rules)" and click "Bypass rules and merge".` If auto-merge cannot be turned off, or is still on when the host is read again, the line says `auto-merge may still be on, so it may merge by itself: open it and click "Disable auto-merge" first.` in place of `it will not merge by itself.` The `rules-review` ruleset lets an org admin bypass it on a pull request (`bypass_mode: pull_request`). The dry-run `pr-plan:` line ends in `merge-by-hand` on GitHub and `auto-merge` on Forgejo. At team level the company pull request's diff is measured as the checks job measures it: `.github/scripts/review-diff.sh` from the merge base with `origin/main`, which leaves out each file exactly as this release ships it (main's `stock-current.txt`). Over 100000 bytes (for example a long log the upgrade moves), it prints `override: <repo> <n> is too large for the model review ...` with the exact comment: after lint and the secret scan pass, the admin comments `/override v1 upgrade: stock skills, too large for the model review` on it. The override still runs lint and the secret scan. Solo with a host: no auto-merge; the person merges.

At `team` or `app` it prints `review-command: OS_HOST=<host> OS_ORG=<org> skills/_host/host.sh set-secret OS_REVIEW_KEY (it asks for the key and does not show it)` first (Forgejo adds `OS_HOST_URL=<url>`), and `no review key yet: ...` when the org key is not there.

Each area repo gets its own pull request for the check scripts, on `upgrade/scripts`. That pull request also adds `review-rules.md` when the area main lacks it, and carries the area rules merge as its own commit. It does not replace an existing file. A dry-run prints `pr-plan:` for that pull request and does not open it.

## Refresh

`--refresh`, on a v1 company, from the company folder, with `--template` the newer os-foundation `template/`:

- **Stock files** are the files the template has under `skills/` and `.github/`. The company repo gets both. Each area repo gets `.github/` (its checks).
- **Root files (v1.0.3).** The company repo also gets `joining-terms.md` and `scale.md` when its `main` lacks them, with the company name filled, as new files in the same pull request (or commit). One that is on `main` is the company's: never replaced, never `kept:`.
- **Unchanged or not.** `.github/scripts/stock-hashes.txt` (it ships with the check tools) lists the git blob id and path of every stock file any release has shipped. A company copy on `main` that matches one is as shipped: it is replaced. A copy that matches none was changed by the company: it is kept, and the run prints `kept: <folder> <path> (changed by the company; compare it with the template by hand)`. A stock file this template no longer ships is removed when it is as shipped. A company skill of its own is never in the list, so it is never touched. Scripts keep their mode.
- **Check tools first (team on a host).** The checks job runs main's tools, so each repo first gets this release's tools on `main` by the upgrade's own `checks-on-main:` step: `host.sh unprotect`, one push of `.github/workflows/checks.yml` and `.github/scripts/` only, then `protect` (an exit on the way puts protection back). Tools on main from a newer release are kept. The stock list is merged into main's whatever the release: it only grows. At the same release, this upgrade's `stock-current.txt` goes on main too. A dry run prints `change: checks-on-main <folder>`.
- **The review.** The model review leaves out every file whose text is exactly the stock text this release ships at that path (`.github/scripts/stock-current.txt`; `# <n> files are left out` heads its diff). A file put back to an older release's text is a change, and is reviewed. The list comes from the base tools on `main`, never from the pull request, so a pull request cannot add to it, and a change to it is a `.github/` change that needs the code owner. A changed file is still reviewed, and lint and the secret scan read every file. So a refresh pull request passes on its own. If its diff is still over 100000 bytes (removed stock files count), the run prints `override: <repo> <n> is too large for the model review (<bytes> bytes, limit 100000). After lint and the secret scan pass, the admin comments on it: /override refresh: stock skills, too large for the model review`.
- **With a host:** one rules pull request per repo that has something to change, on `rules/<me>/refresh-<release>` (`<release>` from `.github/scripts/tools-release`), built in a temporary worktree on `origin/main`, never over the folder. Title `Refresh stock skills and checks (<release>)`. Auto-merge on, like `propose`: code owners approve it. It prints `opened: <repo> <n>`, the auto-merge line, and an `override: <repo> <n> if the model review fails it: ...` line with the exact comment. Teammates get the files with their next pull once it merges. A second run replaces the branch and reuses the open pull request. An open refresh pull request of the admin's for an older release (`rules/<me>/refresh-<older>`) is closed with a comment that names the new one (`closed: <repo> <n> (refresh for release <older>; replaced by <n>)`). The fetch uses `--prune`, so a branch deleted on the host leaves no stale ref. When the fetch fails, the line says why: `could not reach the host` only when the network failed; when the host answered, it names what it said (sign-in or repo refused, or the git error).
- **Solo (no host):** one commit on `main` per repo, of those paths only (`committed: <folder>`). A path with a change not committed stops that repo with one line.
- Per repo it prints `refresh: <folder>: <n> new, <n> replaced, <n> removed, <n> kept`, or `refresh: <folder> is current (<n> kept)`. `.github/scripts/stock-current.txt` and `stock-hashes.txt` are generated, never `kept:`: on a team they go on `main` with the check tools, and a solo folder takes this release's. While an old v0 `logs` branch is still on the host, a team refresh prints the same `admin:` line as the upgrade, ending `delete it with: skills/_host/host.sh drop-logs <repo>; ...` for each repo that has one. Then `refresh: ok. ...`, or with `--dry-run` `refresh: dry run, nothing changed`. A repo it could not fetch prints one line, the others go on, and it exits 3.

Before a release, a maintainer runs `tests/static/stock-hashes.sh --write` in os-foundation; It writes both lists. `--check` fails when a stock file is missing from the list, or when `stock-current.txt` is not this release's stock files.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok, including a dry-run that found conflicts or `upgrade: stopped:` lines, `upgrade: already v1`, `upgrade: pending upgrade/v1` (no host) and a refresh |
| 1 | usage |
| 2 | refused (`--refresh` on a v0 folder, not a v0 folder, not a git repo, Windows, uncommitted changes, a spill file already there, no slug with host on, someone else's commits on an upgrade branch) |
| 3 | tool error (`git filter-repo` missing) or host error (an area fetch failed, the check tools could not reach `main`, a Free GitHub org at team level) |
| 4 | auth failed |

## What it prints

```
upgrade: already v1. To bring stock skills and checks to this template, run it with --refresh.
upgrade: pending upgrade/v1
To start over, run in the company folder: git checkout main && git branch -D upgrade/v1. Then run upgrade again.
switched <folder> to main from <branch> (an earlier upgrade run)
upgrade: stopped: <repo> has commits on <branch> that the upgrade did not make. ...
upgrade: dry-run
v0: logs-branch
v0: no-links
v0: no-level
v0: logs-folder
log-freeze: before the real run, every teammate saves their logs ... Nobody writes a log until the upgrade pull requests merge.
change: links
change: logs-history
change: level-block
change: tier-table
change: review-rules.md (new: the model review reads it from main)
change: rules-merge <path> company-lines=<n> chars=<m>
change: rules-spill <path> -> company-rules.md
todo: AGENTS.md is <m> characters, over the 9,000 it sets for itself. Move ...
todo: fill {{OWNER_NAME}}
change: .gitattributes [areas/<name>]
change: skill-files skills/<name> new=<n>
change: add joining-terms.md
change: add scale.md
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
change: replace <repo> <branch> (an earlier upgrade run made it; its pull request is reused)
todo: answer slug (...)
todo: answer review_vendor (...)
review-command: OS_HOST=<host> OS_ORG=<org> skills/_host/host.sh set-secret OS_REVIEW_KEY (it asks for the key and does not show it)
checks-on-main: <repo> [(with review-rules.md) | added review-rules.md to main | already | already: kept the check tools on main (...) | updated the check tools on main (release <old> to <new>)]
protected: <repo>
pr: <repo> <number>
auto-merge is off on <repo>: pull request <n> stays open until the admin merges it.
replaced: <repo> <branch> (an earlier upgrade run made it)
merge-by-hand: <repo> <n>: it will not merge by itself. When lint and the secret scan pass and the model review passes (or the admin overrides it, see the override: line), the admin opens it and merges it. ... If GitHub asks for a review, ...
pr: <number>
override: <repo> <n> is too large for the model review (<bytes> bytes, limit 100000). After lint and the secret scan pass, the admin comments on it: /override v1 upgrade: stock skills, too large for the model review
override: <repo> <n> if the model review fails it: read the finding. If the change is only what the pull request body says, the admin comments on it: /override <reason>
admin, on GitHub: wait until the checks pass (when the model review fails one, see its override: line). Open each pull request and merge it. When you are the only code owner, a plain merge works. If GitHub asks for a review, tick "Merge without waiting for requirements to be met (bypass rules)" and click "Bypass rules and merge".
logs-tag: could not push the logs-archive tag to <repo>. ...
teammates: in an old (v0) copy of this folder, do not run git pull. ...
teammates: 1. ... 2. ... 3. ...
admin: until the old logs branch is gone, sync push keeps logs in each folder (held) ... When every teammate has moved, delete it with: skills/_host/host.sh drop-logs <repo>; ... (one per repo whose host has the old logs branch; without a host: git push origin --delete logs)
upgrade: open pull requests: <repo> <n>, ... Merge each one when its checks pass.
```

A dry-run prints `upgrade: dry-run` and no `pr:` line. A real run prints `upgrade: ok` when nothing is left for a person to merge. When any pull request will not merge by itself, the last line is `upgrade: open pull requests: ...` instead, never `upgrade: ok`.

- `change: rules-merge` comes once per rules file: `AGENTS.md`, `CLAUDE.md`, and each `areas/<name>/AGENTS.md` and `CLAUDE.md`. `company-lines` is the count of company lines kept: the same lines the pull request body lists. Blank lines do not count, and neither does a stock v0 line (a v0 subheading that comes along with a company line under it). `chars` is the size of the merged file in bytes.
- `change: rules-spill` comes only when the merged file would be 10,000 bytes or more. In an area the file is `area-rules.md`.
- `todo: AGENTS.md is <m> characters` comes when the merged company `AGENTS.md` is over 9,000 but under 10,000. It says what to move out.
- `change: skill-moved` comes only for a company skill in a tracked copy folder.
- A changed `AGENTS.md` or `CLAUDE.md` is not a conflict. The rules merge handles it.
