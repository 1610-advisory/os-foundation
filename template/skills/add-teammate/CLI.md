# add-teammate scripts

Part A is `team-on.sh` on the admin's computer. Part B is `join.sh` on the teammate's computer. `add-person.sh` adds one person after the team is already on.

All three use `bash`, `git`, `jq`. They call the host only through `skills/_host/host.sh`. They do not call `gh` or the Forgejo API.

A token, key, or secret never appears in a child process's arguments. Git uses a credential helper. The token stays in the environment. The review key never enters these scripts.

## team-on.sh

```
team-on.sh --answers <file>
team-on.sh --help
```

Turns solo into team in one run. A second run does not change git history. If origin is missing, it adds the host clone URL and fetches. If origin is set but origin/main is missing, it fetches again. It does not push to a main that has commits. A repo an earlier run made but left empty (its first push failed) gets that first push on the next run: `host.sh unprotect` first, then the push, then `protect` as usual. It prints `first push: <repo>`. A repo is never protected while it is empty. The "Team: turn on" commit holds only the files team-on writes (`company-profile.md`, `.github/`, `.gitea/`, `privacy.md`, `joining-terms.md`, the people pages; in an area `.github/`, `.gitea/`, `review-rules.md`). Untracked files in the folder stay local.

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
| `review_vendor` | `anthropic`, `openai`, `xai`, or `openrouter`. Optional. |
| `review_kind` | `second-vendor` or `same-vendor`. Default: `second-vendor` when a vendor is set, otherwise `same-vendor`. |
| `review_model` | Optional model id. Blank means the vendor default (`openrouter`: `openai/gpt-4o-mini`). OpenRouter ids are `<maker>/<model>`. |

There is no review-key key. The key never goes in this file and never goes in chat.

### Review key

The script prints one command, and only that command, for the admin to run in their own terminal from the company root (Forgejo adds `OS_HOST_URL=<url>`):

```
OS_HOST=<host> OS_ORG=<org> skills/_host/host.sh set-secret OS_REVIEW_KEY
```

At a terminal, `set-secret` asks `OS_REVIEW_KEY: ` on stderr and reads with no echo, so the key never shows or stays in scrollback. From a pipe it reads stdin. An empty value stops with `OS_REVIEW_KEY is empty: nothing was set`. The value stays on stdin of that command. `team-on.sh` does not read it, does not store it, and does not pass it to a child.

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
3. Writes `people/<Name>.md` with `slug`, `github`, `email`, `role`, `areas`, and `manager` when set. A v0 page used `role:` for the job title ("President"): when its `role:` is not `admin`, `director` or `writer`, that value moves to `job_title:` (only when `job_title:` is blank), then `role:` takes the OS role.
4. Writes `CODEOWNERS` for rules paths only. It writes both `.github/CODEOWNERS` (GitHub globs) and `.gitea/CODEOWNERS` (Forgejo regular expressions). GitHub reads the first. Forgejo reads the second, not `.github/CODEOWNERS`. A file the host ignores does no harm. The company repo names the admin in both files. An area `.github/CODEOWNERS` names the director and the admin. An area `.gitea/CODEOWNERS` names the same owners: the director and the admin (B60). Forgejo asks every name on a line for a review and waits for each, so on Forgejo an area rules change needs both the director's and the admin's approval (a person's own change needs the other one). That is stricter than GitHub, where one owner's approval is enough.
5. Copies `.github/` workflows and scripts from the company root into each area repo when that folder exists, then writes the area `CODEOWNERS` files. If the area has no `review-rules.md`, it copies the company file. It does not replace an existing one. The area director owns that file after the copy.
6. Puts both `CODEOWNERS` files and `review.conf` on `main` before protection. If the repo already exists and is not protected, it pushes them. If `main` is already protected and any of those files is missing, it stops and names `sync.sh propose`. If `main` already has all three (a second run, or after an upgrade) and this run changed a rules file (`CODEOWNERS`, `review.conf`, `review-rules.md`; for example a new area director), it never pushes to main: it puts those files on `rules/<admin>/team-on` (built in a temporary worktree on `origin/main`) and opens one rules pull request, as `sync.sh propose` does. Its body says what changes and why: who becomes a code owner (for an area: the director, as area director), that the admin stays a code owner of every line, that both files name the same owners, and each other file (`review-rules.md`, `review.conf`). It prints `rules-pr: <repo> <n> (<files>)`, the auto-merge line, and `override: <repo> <n> if the model review fails it: ... /override team-on: ...`. A `CODEOWNERS` line the company added on main stays, after the rules lines. A second run with the same files reuses that branch and pull request. Notes it wrote (people pages, the profile) go up with the admin's next sync push. If an area main already has those files but no check tools, a second run opens a pull request on `team/scripts-tools`. That pull request also adds `review-rules.md` when main lacks it. If the tools are already on main and `review-rules.md` is still missing, it opens a pull request on `team/review-rules`. When neither the area nor the company root has a `review-rules.md` to copy, it opens no pull request and prints `review-rules: <repo> has no review-rules.md on main, and this folder has none to propose. The checks use the default rules. Run the upgrade refresh, then team-on again`. It does not push to main.
7. `host.sh create-repo <name> --source --push` for the company repo `<slug>-os` and each area repo `<slug>-<area>`. History is kept. The push happens before protection.
8. `host.sh protect <name> --code-owners --approvals 0` on the company repo and each area repo. Workspace repos are not protected: they push to their own `main`.
9. Creates team `<slug>-company` (everyone, write on the company repo) and team `<slug>-area-<area>` (that area's people, write on the area repo). The area director is on the area team. It prints `teams: <slug>-company, <slug>-area-<area>, ...`. The slug keeps two companies in one org apart: a person on one company's team never reaches the other's repos. A v1 company set up before this keeps its plain names (`company`, `area-<area>`): when team `company` already grants `<slug>-os`, the scripts use the plain names, and nothing is renamed. `add-person.sh` and `remove.sh` pick the names the same way.
   Before any write, it checks each team it will use (`host.sh team-repos`). A team may grant only its own repo. If it already grants another repo (another company's, when two companies share an org and its plain names), it stops with exit 2 and one line: `team <team> already grants <repos>. It may grant only <repo>. Two companies must not share a team: ... Use one org per company, or take those repos off team <team> on the host. Then run this again.` `add-person.sh` checks the same way.
10. Creates one workspace repo `<slug>-user-<person>` per person. The source is `add-teammate/workspace/`, copied as a whole, including `CLAUDE.md` when that file is present. The person gets write. Admins reach it through org ownership, not a second grant.
11. Runs `skills/privacy/privacy.sh --root <root>` when that file exists.
   Before that, when the folder has no `joining-terms.md` (a company upgraded before v1.0.3), it writes one from `skills/add-teammate/joining-terms.template.md`, with the company name in place of `{{COMPANY_NAME}}` (the `company_name` answer, else the first heading of `company-profile.md`), and prints `added: joining-terms.md`. A copy the company has, edited or not, is never written over. It goes in the "Team: turn on" commit. When `main` already has the rules files (a second run), it goes up with the admin's next sync push, like the people pages.
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
review-command: OS_HOST=<host> OS_ORG=<org> skills/_host/host.sh set-secret OS_REVIEW_KEY (it asks for the key and does not show it)
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
invite: <login> is not an org member; adding them to <team> sends an org invite (no new seat if they already use one as a collaborator). They accept it before join.
me: this computer signs in as <login>, which is no person in the answers; add yourself as a person, or write <config>/me by hand
could not check the review key: sign in as an org owner (gh auth refresh -s admin:org)
```

A missing key prints the no-review-key sentence. A same-vendor key prints `weaker review: same vendor`.

`invite:` (GitHub only, once per person): before the first team add, `host.sh org-membership <login>` says the person is not an org member (`none` or `pending`). GitHub then sends an org invite. Forgejo adds people at once and has no invites. `add-person.sh` prints the same line.

`me` (v1.0.2): the config `me` file names the person in the answers whose `github` (or Forgejo login) is this computer's sign-in (`host.sh whoami`), not always the admin. Another org owner, such as an outside advisor, may run team-on. When no person matches, it writes no `me` and prints the `me:` line; `sync push` would stop with `identity mismatch` until it is fixed.

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

1. Refuses a synced folder. On Windows (Git Bash), before that, it checks git's home folder (B82): the folder of git's global config (`git var GIT_CONFIG_GLOBAL`, else `$HOME`), where `gh auth setup-git` writes. git makes and removes one test file there (`git config --file`), as `gh auth setup-git` writes. When that fails, or the folder is a network (UNC) path, it stops with exit 2: `home: git uses <path> as your home folder and cannot write there; set the user environment variable HOME to %USERPROFILE% (Settings, Environment Variables, User variables), open a new terminal, then run join again`. A domain PC with `HOME` unset often maps it to a network drive (`HOMEDRIVE` and `HOMEPATH`). When it works but is not on the system drive, it prints one `home: git uses <path> as your home folder, not a folder on C:. ...` line and goes on. It never changes the variable.
   Without `joining-terms.md` in `root` it stops with exit 2: `terms: joining-terms.md is missing on main; ask the admin to run the upgrade refresh (or team-on) again, then run join again`. Part B shows that page before join (B3).
2. If `company-profile.md` is already in `root`, the company clone is done. GitHub: it runs `host.sh my-membership`. While the person's org invite is still open (`pending`), it stops with exit 2: `invite: accept the org invite first: https://github.com/orgs/<org>/invitation, then run join again`. When the check fails (for example a 403 from a token without org read), join does not stop. It prints `invite: could not check your org invite (<the host's first error line, tokens hidden>); if GitHub sent you an invite, accept it at https://github.com/orgs/<org>/invitation` and goes on.
   - A v0 clone that already pulled the upgrade can still have `memory/logs/` as a worktree of branch `logs`. Join moves it out the way `sync.sh pull` does (sync `CLI.md`): it pushes log commits the host lacks, removes the worktree, and keeps every log file as a local change. It prints `v0-logs: moved, <n> files kept as local changes`. When a file changed here and on the old branch, the old text goes beside it as `<name>.old-branch.md`, with one more `v0-logs:` line. A file in `memory/logs-archive/` with a change not committed stays as it is: the old folder's copy goes beside it, with one more `v0-logs:` line. If a kept file cannot be put back, the old folder goes back as it was and join exits 3; the next join starts over. If that fails, join exits 3 with one line. A failure before the removal removes nothing. A later one names the folder that holds a full copy.
3. Clones each area into `areas/<area>/`. A missing repo or no access is skipped. That is correct.
4. Clones `users/<me>/` from `<slug>-user-<me>`. A missing workspace is an error: `your workspace <repo> is not reachable: ask the admin`. Join exits non-zero.
5. Writes `me` under the config dir.
   Then it checks the engine, in the same order as sync: `OS_SYNC_ENGINE`, else the first line of `<config>/engine`, else `sync_engine:`. Each stop below is exit 3, before any job is installed:
   - Not on `PATH`, but `~/.local/bin/claude` (or `claude.exe`) is there: `Claude Code is in ~/.local/bin, but that folder is not on PATH.` with the step. Mac, Linux: the line to add to the shell profile (`~/.zshrc`, `~/.bash_profile` or `~/.bashrc`). Windows: add `%USERPROFILE%\.local\bin` to the user PATH. Join never changes `PATH`.
   - Not on `PATH` at all: the install line (`Claude Code CLI: ...`, or `install <tool> and put it on PATH`).
   - `claude`: one short call, the engine command with "Print the word ok and nothing else." on stdin, at most `OS_ENGINE_TIMEOUT` seconds (default 60). Unless the whole answer is `ok` (spaces and case ignored, `ok.` allowed): `sign in once: run claude, sign in, then /exit`. A program that does not stop gets TERM at the limit, then `kill -9` 5 seconds later. On Git Bash it also runs `taskkill //F //T` on the Windows process id from `/proc/<pid>/winpid`, errors ignored. Another engine is not called.
6. Runs `skills/sync/sync.sh install-jobs` when that file exists. On macOS it also starts the jobs at once (B73; `sync-jobs: started <label>`), unless `OS_JOBS_LOAD=0`. On Windows it registers them, as before.
7. Writes one profile pointer in each agent config that exists. It does not overwrite other lines. A second run does not add a second line.
   - Claude Code: `~/.claude/CLAUDE.md` gets `@<root>/users/<me>/profile/PROFILE.md` when `~/.claude` exists.
   - Codex: `~/.codex/AGENTS.md` gets one plain `Read <path>` line when `~/.codex` exists.
   - Pi: `~/.pi/agent/AGENTS.md` gets the same plain line when `~/.pi/agent` exists.
   - Cursor: one plain line only if a rules file already exists (`~/.cursor/rules.md` or `~/.cursor/User/rules.md`).
8. Records `terms_accepted: YYYY-MM-DD` on the person's people page in the company folder and commits only that page on `main`, as a sync commit by the person (git `user.name` and `user.email`, else the slug and the people page email) (`Join: accept terms`, with the line `<me> joined and accepted the terms on people/<Name>.md.` and this computer's `Sync-Seat:` trailer; `sync.sh seat` makes the seat id). Then it runs `skills/sync/sync.sh push`, which sends it to `sync/<me>/<seat>` and opens that computer's pull request with auto-merge on, like any note. A people page is not a rules file, so this does not call `sync.sh propose`. If the folder is on `sync/<me>` (an older join left it there), join switches it back to `main` first; if that is refused, it stops with exit 3 and `could not go back to main (a local change is in the way): run git checkout main, then run join again`, before it commits anything. A second run reads `origin/main` first: dated there, `terms: already`, nothing to do. Dated in the folder's own history (a run that stopped after the commit): `terms: already`, and it runs the push again. Neither: it commits them. Only a date counts: the page template has an empty `terms_accepted:` key. If the host cannot be reached, join stops with exit 3 and `could not reach the host: run join again when online; the terms pull request may not be open yet`. If the push stops, join stops with exit 3 and `sync push stopped (<the reason sync status gives>). The terms are committed in this folder: fix that, then run join again`; the commit stays and the next push sends it. One reason is not a stop: when auto-merge is off, the pull request is open, so join prints that line and goes on.
9. Looks for an old copy beside the folder (B63): each folder next to it that is a git clone of the same company repo (its `origin` ends in `<org>/<slug>-os`), such as a v0 folder renamed `<slug>-os-old`. It never fetches, writes or deletes there. It brings each item the host lacks into this folder, one line each (B69). A new file the host does not have is copied (`old-folder: <old>/<path> copied to <path>: sync sends it.`). A change to a file the host has is set aside with `sync.sh set-aside` (the person's text, and the old folder's text it was edited from as the base): `old-folder: <old>/<path> is set aside for <path>: the agent re-applies the change to the host's current text (skills/sync/sync.sh re-apply list). Nothing to copy.` It never asks for a whole-file copy, which would undo newer lines on main. The changes come from the checked-out branch or a detached HEAD (with `git status`), and from each other local branch but the old `logs` branch, beyond where it left `main`. In the old `memory/logs/`, each log not committed, or committed and never pushed on `HEAD` or the `logs` branch (both are read), is copied into `memory/logs/` here (join makes the folder); a log with the same name and other text here is set aside. It never says to push the old logs branch: that would bring back the branch the admin deleted (upgrade SKILL section 11 step 7). v0 made `memory/logs/` with `git worktree add`, which writes the full path into `memory/logs/.git`, so after the rename that link names the new folder. Join reads the old logs through the old folder's own `.git/worktrees/<name>` instead, read only (never `git worktree repair`). A stash is listed, to redo by hand; while one is there, the last line says it is still only in the old folder, and the old folder may be deleted only after each stash is redone here. join notes each one in `<config>/state/old-stash`, and `sync.sh status` prints `old folder: <old> still has stashed changes ...` while that old folder still has a stash (B71). Paths are read NUL-separated. A name with `..`, a leading `/`, a tab or a new line is not brought; it is named, and the last line says `Do not delete it yet.` Nothing is copied through a link in this folder. A link or special file in the old folder is named, not brought. A file a commit the host lacks added, then deleted from the worktree, is brought from the commit. On Windows (`core.autocrlf=true`) a worktree file is read with LF line ends when the base has LF, so only the person's edit is set aside. An area of the old copy that this folder has not joined is named, and nothing comes from it. A version set aside is noted in the sync state (`join-brought`), so join run again does not bring it twice. When any part cannot be read, it prints `... could not be checked ...` with how to check it by hand, and the last line says `Do not delete it yet.`, never "You may delete it". Then one line: `old-folder: <old> held <n> items the host lacks (listed above). join copied them here or set them aside for the agent. ...` (`1 item` and `it` for one), `old-folder: <old> has nothing else the host lacks, only the stash listed above. ...` when a stash is all that is left, or `old-folder: <old> has nothing the host lacks. You may delete it.` This never stops join.

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
pr: <url>   (sync push: this computer's pull request)
```

Stops and warnings, each one line:

```
terms: joining-terms.md is missing on main; ask the admin to run the upgrade refresh (or team-on) again, then run join again
home: git uses <path> as your home folder and cannot write there; set the user environment variable HOME to %USERPROFILE% (Settings, Environment Variables, User variables), open a new terminal, then run join again
home: git uses <path> as your home folder, not a folder on C:. Join goes on. If a later step cannot write there, set the user environment variable HOME to %USERPROFILE%, open a new terminal, then run join again
```

## add-person.sh

```
add-person.sh --answers <file>
add-person.sh --help
```

Same person steps as `team-on.sh` for one person, on a team that is already on. It does not change `level`. It does not print the review-key command. On GitHub it prints the `invite:` line when the person is not an org member.

The people-page commit goes by pull request, because `main` is already protected. It builds the branch in a temporary worktree on `origin/main` (as join does), never over the admin's folder, where notes from a sync push may sit untracked. The director's area branch is built the same way. The admin's folder stays on `main` and gets the new page with the next pull once that pull request merges: a copy left in the folder would go up with the admin's own sync pull request. A second run rebuilds the branch from `origin/main`, replaces it on the host, and opens the pull request if none is open. It turns on auto-merge right after it opens the pull request, before the workspace, like `join`, so the pull request merges by itself when its checks pass (`auto-merge: on`). If the checks are already green, GitHub will not wait: the host merges it at once (`merged: <repo> <n> (its checks were already green)`), or prints `pull request <n> is green: merge it`. If the host refuses, it prints one line that auto-merge is off and what the admin runs. The workspace repo is created the same way, including `CLAUDE.md` when the workspace template has it.

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
override: <company repo> <number> if the model review fails it: ... /override add-person: <slug>'s people page
rules-pr: <area repo> <number>   (when the person becomes an area director)
merge-by-hand: <area repo> <number>: it changes CODEOWNERS, ...   (GitHub; Forgejo: the auto-merge line)
override: <area repo> <number> if the model review fails it: ...
hand-off: <slug>
```

The area rules pull request body says who becomes a code owner and why (the area director), and that the admin stays a code owner of every line. Both `CODEOWNERS` files name the same owners. It changes `CODEOWNERS`, so on GitHub the admin merges it by hand, as with remove: the script turns auto-merge off and prints `merge-by-hand:` (it says "may merge by itself" when auto-merge could not be turned off). On Forgejo it turns on auto-merge, as team-on does.
