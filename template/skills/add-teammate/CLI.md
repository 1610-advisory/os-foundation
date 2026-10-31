# add-teammate scripts

Part A is `team-on.sh` on the admin's computer. Part B is `join.sh` on the teammate's computer. `add-person.sh` adds one person after the team is already on.

All three use `bash`, `git`, `jq`. They call the host only through `skills/_host/host.sh`. They do not call `gh` or the Forgejo API.

A token, key, or secret never appears in a child process's arguments. Git uses a credential helper. The token stays in the environment. The review key never enters these scripts.

## team-on.sh

```
team-on.sh --answers <file>
team-on.sh --help
```

Turns solo into team in one run. A second run does not change git history. If origin is missing, it adds the host clone URL and fetches. If origin is set but origin/main is missing, it fetches again. It does not push to a main that has commits. A repo an earlier run made but left empty (its first push failed) gets that first push on the next run: `host.sh unprotect` first, then the push, then `protect` as usual. It prints `first push: <repo>`. A repo is never protected while it is empty. The "Team: turn on" commit holds only the files team-on writes (`company-profile.md`, `.github/`, `.gitea/`, `privacy.md`, the people pages; in an area `.github/`, `.gitea/`, `review-rules.md`). Untracked files in the folder stay local.

GitHub: before any change it reads the `gh` sign-in scopes (`host.sh whoami`). If `admin:org` or `workflow` is missing, it stops with exit 4: `the gh sign-in needs admin:org and workflow: run gh auth refresh -s admin:org,workflow`. A fine-grained token sends no scope list. Then the host calls show what it lacks.

GitHub, next: `host.sh plan-check` reads the org plan. A Free org stops with exit 3, before any change: `This GitHub org is on the Free plan. Team setup needs GitHub Team (rulesets for private repos). Upgrade the plan, then run this again.` Rulesets on private repos need a paid plan. Only an org owner sees the plan, and team setup needs one. A hidden plan stops it the same way, before any change: `Could not read the plan of the GitHub org <org>: sign in as an org owner, then run this again. Team setup needs an org owner.`

Every create verb is safe to run twice: an existing repo, team, member, grant or ruleset is ok.

### Flags

| Flag | Meaning |
|---|---|
| `--answers <file>` | Key=value lines. Required. |
| `--help` | Print usage and exit 0. |

### Answers file

One `key=value` per line. Blank lines and lines starting with `#` are ignored. Split on the first `=`. Values may contain spaces. Do not put a token, key, or secret in this file.

| Key | Meaning |
|---|---|
| `root` | Company folder. Default: the current directory. |
| `host` | `github` or `forgejo`. |
| `host_url` | Forgejo base URL. Empty for github.com. |
| `org` | Host org that owns the repos. |
| `sync_engine` | Headless command for the nightly check. |
| `runner` | `runs-on` label. Default `ubuntu-latest`. |
| `admin_slug` | Person slug of the admin. Default: the first `role=admin`. |
| `company_slug` | Used only when `company-profile.md` still has a placeholder slug. |
| `company_name` | Used in the hand-off and the workspace fill. Default: the profile heading. |
| `person.<slug>.name` | Page title, for example `Ada Admin`. |
| `person.<slug>.github` | Git host username. |
| `person.<slug>.email` | Work email. |
| `person.<slug>.role` | `admin`, `director`, or `writer`. |
| `person.<slug>.areas` | Comma list of area slugs. |
| `person.<slug>.manager` | Optional slug. Used later if this person leaves. |
| `area.<area>.director` | Person slug. Default: the admin. |
| `review_vendor` | `anthropic`, `openai`, or `xai`. Optional. |
| `review_kind` | `second-vendor` or `same-vendor`. Default: `second-vendor` when a vendor is set, otherwise `same-vendor`. |
| `review_model` | Optional model id. Blank means the vendor default. |

There is no review-key key. The key never goes in this file and never goes in chat.

### Review key

The script prints one command, and only that command, for the admin to run in their own terminal from the company root:

```
skills/_host/host.sh set-secret OS_REVIEW_KEY
```

The value is typed at a hidden prompt and stays on stdin of that command. `team-on.sh` does not read it, does not store it, and does not pass it to a child.

Then `team-on.sh` checks only that the secret exists:

```
skills/_host/host.sh secret-exists OS_REVIEW_KEY
```

That verb prints `{"exists":true}` or `{"exists":false}` and exits 0. It never prints the value. If the secret is missing, the script prints:

```
no review key: every pull request fails the model review until you add one
```

It does not say weaker. If the secret exists and `review_kind` is `same-vendor`, it prints `weaker review: same vendor`. It still does not read the value.

If the check itself fails (GitHub answers 403 without `admin:org`), it prints `could not check the review key: sign in as an org owner (gh auth refresh -s admin:org)`, not the no-key sentence.

Before the first push it writes `.github/review.conf`:

```
vendor=anthropic
model=
kind=second-vendor
```

`model` is blank unless `review_model` is set. The file is copied into each area repo with `.github/`. It is not a line in `company-profile.md`.

### What it does

1. Refuses a company folder in a synced folder. The message names the reason: iCloud Drive, iCloud Desktop, iCloud Documents, a cloud storage folder, Dropbox (any suffix), OneDrive, Google Drive, or a Google Drive volume.
2. Sets `level: team` and writes `host`, `host_url`, `org`, `sync_engine`, `runner`, and `review` in `company-profile.md`.
3. Writes `people/<Name>.md` with `slug`, `github`, `email`, `role`, `areas`, and `manager` when set.
4. Writes `CODEOWNERS` for rules paths only. It writes both `.github/CODEOWNERS` (GitHub globs) and `.gitea/CODEOWNERS` (Forgejo regular expressions). GitHub reads the first. Forgejo reads the second, not `.github/CODEOWNERS`. A file the host ignores does no harm. The company repo names the admin in both files. An area `.github/CODEOWNERS` names the director and the admin. An area `.gitea/CODEOWNERS` names only the director, or the admin when the area has no director, so on Forgejo the director's own area rules change has no review request and merges on green checks, the same as the admin's own change on the company repo.
5. Copies `.github/` workflows and scripts from the company root into each area repo when that folder exists, then writes the area `CODEOWNERS` files. If the area has no `review-rules.md`, it copies the company file. It does not replace an existing one. The area director owns that file after the copy.
6. Puts both `CODEOWNERS` files and `review.conf` on `main` before protection. If the repo already exists and is not protected, it pushes them. If `main` is already protected and any of those files is missing, it stops and names `sync.sh propose`. If an area main already has those files but no check tools, a second run opens a pull request on `team/scripts-tools`. That pull request also adds `review-rules.md` when main lacks it. If the tools are already on main and `review-rules.md` is still missing, it opens a pull request on `team/review-rules`. It does not push to main.
7. `host.sh create-repo <name> --source --push` for the company repo `<slug>-os` and each area repo `<slug>-<area>`. History is kept. The push happens before protection.
8. `host.sh protect <name> --code-owners --approvals 0` on the company repo and each area repo. Workspace repos are not protected: they push to their own `main`.
9. Creates team `<slug>-company` (everyone, write on the company repo) and team `<slug>-area-<area>` (that area's people, write on the area repo). The area director is on the area team. It prints `teams: <slug>-company, <slug>-area-<area>, ...`. The slug keeps two companies in one org apart: a person on one company's team never reaches the other's repos. A v1 company set up before this keeps its plain names (`company`, `area-<area>`): when team `company` already grants `<slug>-os`, the scripts use the plain names, and nothing is renamed. `add-person.sh` and `remove.sh` pick the names the same way.
   Before any write, it checks each team it will use (`host.sh team-repos`). A team may grant only its own repo. If it already grants another repo (another company's, when two companies share an org and its plain names), it stops with exit 2 and one line: `team <team> already grants <repos>. It may grant only <repo>. Two companies must not share a team: ... Use one org per company, or take those repos off team <team> on the host. Then run this again.` `add-person.sh` checks the same way.
10. Creates one workspace repo `<slug>-user-<person>` per person. The source is `add-teammate/workspace/`, copied as a whole, including `CLAUDE.md` when that file is present. The person gets write. Admins reach it through org ownership, not a second grant.
11. Runs `skills/privacy/privacy.sh --root <root>` when that file exists.
12. Writes the admin's `me` file and runs `skills/sync/sync.sh install-jobs --admin` when that file exists.
13. Prints one hand-off message per teammate. No secrets.

`OS_HOST_SH` may point at `host.sh` in tests. Otherwise the script uses `skills/_host/host.sh`.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | usage |
| 2 | refused (synced folder, bad answers, slug still a placeholder, a team that already grants another repo) |
| 3 | host or tool error, a Free GitHub org, or a refused push: `push refused for <repo>: ...` names the likely cause, for example the missing `workflow` scope |
| 4 | auth failed |

### What it prints

```
team-on: ok
level: team
review-command: skills/_host/host.sh set-secret OS_REVIEW_KEY
no review key: every pull request fails the model review until you add one
repo: <slug>-os
repo: <slug>-<area>
workspace: <slug>-user-<person>
protected: <slug>-os
hand-off: <person-slug>
Hand-off for <Name>. Company repo: <host_url>/<org>/<slug>-os. Host: <host_url>. Areas: <areas>. Workspace: <host_url>/<org>/<slug>-user-<person>.
```

On github.com the host part is `github.com/<org>`, for example `Host: github.com/acme.`

```
first push: <slug>-os
could not check the review key: sign in as an org owner (gh auth refresh -s admin:org)
```

A missing key prints the no-review-key sentence. A same-vendor key prints `weaker review: same vendor`.

## join.sh

```
join.sh --answers <file>
join.sh --help
```

Part B clones the company repo first, with git and the person's own sign-in, then runs this script from inside that clone. An existing company clone is done. This script does not clone it again.

### Flags

| Flag | Meaning |
|---|---|
| `--answers <file>` | Required. |
| `--help` | Print usage and exit 0. |

### Answers file

| Key | Meaning |
|---|---|
| `me` | Person slug. Required. |
| `root` | Company clone. Default: the current directory. |
| `areas` | Optional comma list. Default: `areas` on the person's page. |

`host`, `host_url`, `org`, and `company_slug` come from `company-profile.md`.

The person's sign-in is `FORGEJO_TOKEN` or `<config>/<slug>-os/forgejo-token`. It is never an answers-file value and never part of a URL.

### What it does

1. Refuses a synced folder.
2. If `company-profile.md` is already in `root`, the company clone is done.
   - A v0 clone that already pulled the upgrade can still have `memory/logs/` as a worktree of branch `logs`. Join moves it out the way `sync.sh pull` does (sync `CLI.md`): it pushes log commits the host lacks, removes the worktree, and keeps every log file as a local change. It prints `v0-logs: moved, <n> files kept as local changes`. When a file changed here and on the old branch, the old text goes beside it as `<name>.old-branch.md`, with one more `v0-logs:` line. A file in `memory/logs-archive/` with a change not committed stays as it is: the old folder's copy goes beside it, with one more `v0-logs:` line. If a kept file cannot be put back, the old folder goes back as it was and join exits 3; the next join starts over. If that fails, join exits 3 with one line. A failure before the removal removes nothing. A later one names the folder that holds a full copy.
3. Clones each area into `areas/<area>/`. A missing repo or no access is skipped. That is correct.
4. Clones `users/<me>/` from `<slug>-user-<me>`. A missing workspace is an error: `your workspace <repo> is not reachable: ask the admin`. Join exits non-zero.
5. Writes `me` under the config dir.
   Then it checks the engine (`OS_SYNC_ENGINE`, else `sync_engine:`). Each stop below is exit 3, before any job is installed:
   - Not on `PATH`, but `~/.local/bin/claude` (or `claude.exe`) is there: `Claude Code is in ~/.local/bin, but that folder is not on PATH.` with the step. Mac, Linux: the line to add to the shell profile (`~/.zshrc`, `~/.bash_profile` or `~/.bashrc`). Windows: add `%USERPROFILE%\.local\bin` to the user PATH. Join never changes `PATH`.
   - Not on `PATH` at all: the install line (`Claude Code CLI: ...`, or `install <tool> and put it on PATH`).
   - `claude`: one short call, the engine command with "Print the word ok and nothing else." on stdin, at most `OS_ENGINE_TIMEOUT` seconds (default 60). No `ok` in the answer: `sign in once: run claude, sign in, then /exit`. Another engine is not called.
6. Runs `skills/sync/sync.sh install-jobs` when that file exists.
7. Writes one profile pointer in each agent config that exists. It does not overwrite other lines. A second run does not add a second line.
   - Claude Code: `~/.claude/CLAUDE.md` gets `@<root>/users/<me>/profile/PROFILE.md` when `~/.claude` exists.
   - Codex: `~/.codex/AGENTS.md` gets one plain `Read <path>` line when `~/.codex` exists.
   - Pi: `~/.pi/agent/AGENTS.md` gets the same plain line when `~/.pi/agent` exists.
   - Cursor: one plain line only if a rules file already exists (`~/.cursor/rules.md` or `~/.cursor/User/rules.md`).
8. Records `terms_accepted: YYYY-MM-DD` on the person's people page, on branch `sync/<me>`, then `host.sh open-pr` and `host.sh auto-merge`, like push and propose. The pull request merges by itself when the checks pass. If auto-merge is refused, it prints one plain line and the pull request stays open. A people page is not a rules file, so this does not call `sync.sh propose`. It commits only that page, in a temporary worktree: it never checks out `sync/<me>` over the company folder, where the same files may sit untracked. The company folder stays on `main`. The dated `terms_accepted:` is also written to the people page there, as a local change. `sync.sh push` rebuilds `sync/<me>` from `main` and the local changes each time, so every push carries the terms until the pull request merges. If the folder is on `sync/<me>` (an older join left it there), join switches it back to `main`. If that switch is refused (a local change in the way), it prints `main: could not go back to main ...` and still opens the pull request. A second run reads where the terms stand on the host. On `origin/main`: `terms: already`, nothing to do. On `origin/sync/<me>` only: `terms: already`, then it switches back to `main`, writes that date to the local page, and opens the pull request if none is open (an earlier run stopped before `open-pr`). Neither: it proposes them again, on top of `origin/sync/<me>` when that exists (an earlier run stopped before the push). Only a date counts: the page template has an empty `terms_accepted:` key. If the host cannot be reached, join stops with exit 3 and `could not reach the host: run join again when online; the terms pull request may not be open yet`. It never guesses from the page in the folder.

Tests must point `HOME`, `XDG_CONFIG_HOME`, and `OS_JOBS_DIR` at a sandbox.

### Exit codes

Same as `team-on.sh`. Exit 2 also means this folder is not a company clone.

### What it prints

```
join: ok
me: <slug>
company-clone: done
cloned: <slug>-<area>
skipped: <slug>-<area>
cloned: <slug>-user-<slug>
terms: proposed
```

## add-person.sh

```
add-person.sh --answers <file>
add-person.sh --help
```

Same person steps as `team-on.sh` for one person, on a team that is already on. It does not change `level`. It does not print the review-key command.

The people-page commit goes by pull request, because `main` is already protected. After the push it switches the folder back to `main` and leaves the new page there as a local edit. It reaches `main` only by that pull request: `sync push` holds it until it merges. If that switch is refused, it prints one plain line and still opens the pull request. A second run rebuilds the branch from `origin/main`, replaces it on the host, and opens the pull request if none is open. It turns on auto-merge, like `join`, so the pull request merges by itself when its checks pass (`auto-merge: on`). If the host refuses, it prints one line that auto-merge is off and what the admin runs. The workspace repo is created the same way, including `CLAUDE.md` when the workspace template has it.

Answers keys: `root` (optional), and one `person.<slug>.*` block. `area.<area>.director` when this person becomes a director.

### Exit codes

Same as `team-on.sh`. Exit 2 also means the team is not on yet.

### What it prints

```
add-person: ok
person: <slug>
workspace: <slug>-user-<slug>
pr: <number>
auto-merge: on
hand-off: <slug>
```
