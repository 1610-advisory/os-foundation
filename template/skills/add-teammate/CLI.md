# add-teammate scripts

Part A is `team-on.sh` on the admin's computer. Part B is `join.sh` on the teammate's computer. `add-person.sh` adds one person after the team is already on.

All three use `bash`, `git`, `jq`. They call the host only through `skills/_host/host.sh`. They do not call `gh` or the Forgejo API.

A token, key, or secret never appears in a child process's arguments. Git uses a credential helper. The token stays in the environment. The review key never enters these scripts.

## team-on.sh

```
team-on.sh --answers <file>
team-on.sh --help
```

Turns solo into team in one run. A second run does not change git history. If origin is missing, it adds the host clone URL and fetches. If origin is set but origin/main is missing, it fetches again. It does not push to main.

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
4. Writes `CODEOWNERS` for rules paths only. The company repo names the admin. An area repo names that area's director and the admin.
5. Copies `.github/` from the company root into each area repo when that folder exists, then writes the area `CODEOWNERS`.
6. Puts `CODEOWNERS` and `review.conf` on `main` before protection. If the repo already exists and is not protected, it pushes them. If `main` is already protected and those files are missing, it stops and names `sync.sh propose`.
7. `host.sh create-repo <name> --source --push` for the company repo `<slug>-os` and each area repo `<slug>-<area>`. History is kept. The push happens before protection.
8. `host.sh protect <name> --code-owners --approvals 0` on the company repo and each area repo. Workspace repos are not protected: they push to their own `main`.
9. Creates team `company` (everyone, write on the company repo) and team `area-<area>` (that area's people, write on the area repo). The area director is on the area team.
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
| 2 | refused (synced folder, bad answers, slug still a placeholder) |
| 3 | host or tool error |
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
3. Clones each area into `areas/<area>/`. A missing repo or no access is skipped. That is correct.
4. Clones `users/<me>/` from `<slug>-user-<me>`. A missing workspace is an error: `your workspace <repo> is not reachable: ask the admin`. Join exits non-zero.
5. Writes `me` under the config dir.
6. Runs `skills/sync/sync.sh install-jobs` when that file exists.
7. Writes one profile pointer in each agent config that exists. It does not overwrite other lines. A second run does not add a second line.
   - Claude Code: `~/.claude/CLAUDE.md` gets `@<root>/users/<me>/profile/PROFILE.md` when `~/.claude` exists.
   - Codex: `~/.codex/AGENTS.md` gets one plain `Read <path>` line when `~/.codex` exists.
   - Pi: `~/.pi/agent/AGENTS.md` gets the same plain line when `~/.pi/agent` exists.
   - Cursor: one plain line only if a rules file already exists (`~/.cursor/rules.md` or `~/.cursor/User/rules.md`).
8. Records `terms_accepted: YYYY-MM-DD` on the person's people page through `skills/sync/sync.sh propose join-terms <file>` when that command exists, otherwise on branch `sync/<me>` and `host.sh open-pr`.

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

The people-page commit goes by pull request, because `main` is already protected. The workspace repo is created the same way, including `CLAUDE.md` when the workspace template has it.

Answers keys: `root` (optional), and one `person.<slug>.*` block. `area.<area>.director` when this person becomes a director.

### Exit codes

Same as `team-on.sh`. Exit 2 also means the team is not on yet.

### What it prints

```
add-person: ok
person: <slug>
workspace: <slug>-user-<slug>
pr: <number>
hand-off: <slug>
```
