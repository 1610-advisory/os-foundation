# Changes

Plain-word release notes for os-foundation. Newest first. Versions follow semver. Your folder records its version in `os_version:` in `company-profile.md`.

## v1.0.0 — unreleased

The multi-user release. A solo owner gets a simpler setup. A team gets enforced review, private workspaces and nightly sync.

### New for everyone (solo too)

- **One setup step fewer.** The `.agents/skills` and `.claude/skills` links now ship in the folder. You no longer link them by hand.
- **Logs are plain files.** Each person writes one short log per day in `memory/logs/`. There is no separate `logs` branch any more.
- **Level and switches.** `company-profile.md` says the level (`solo`, `team` or `app`) and which switches are on. Agents skip rules for a level or a switch that is not on. Every switch is off by default.
- **`privacy.md`.** A script writes it from your level and switches. It lists every place a copy of your data sits, and only the places that are on: who can read it, how long it stays, how it is removed.
- **`scale.md`.** A reference for large companies: scale switches, the projects pattern, a checklist for outside parties' computers, and the 5,000-staff case with results from a local Forgejo load check. Agents do not load it at start.
- **Versions.** `1610.sh/os` serves the latest release. `1610.sh/os@vX.Y.Z` serves a pinned one. `lint` can say in one line when a newer version exists. You choose when to run the new `upgrade` skill. The new `privacy` skill writes `privacy.md`.
- **`upgrade` brings the v1 rules to a set-up folder.** `AGENTS.md` and `CLAUDE.md` (company and areas) get the v1 rules. Every line the company added is kept as written, under the matching v1 heading, or in `company-rules.md` when the file would be too long.

### New for teams

- **`add-teammate` turns on the team level in one run.** The company folder, areas and one private workspace per person go to your company's GitHub (Team plan) or Forgejo, with their history.
- **Nobody writes to `main`.** Each person has one branch and one standing pull request. Notes merge by themselves when the checks pass. Rules files go by their own pull request and need their owner's approval.
- **Checks on every pull request:** a secret scan, `lint`, and a review by a second AI model against `review-rules.md`. All checks run in one job to keep host minutes low.
- **`sync` and OS jobs.** Pull every 15 minutes. Push each night, after a secret scan and a commit-or-hold check by a small model. Any failed step pushes nothing.
- **`sync pull` checks first and pulls only what changed.** One full pull runs each day. On Windows, a pull with nothing new does not start Git Bash.
- **Nightly review and reports.** On the admin's computer: clear errors fixed by pull request, one daily digest of flags per approver, a daily "to decide" list and a weekly report.
- **Joining terms and leaving.** `joining-terms.md` holds the delete promise each person accepts when they join. `remove-teammate` removes access first. A helper then deletes the company folder from that person's computer. Leave, holidays and offline days never trigger it.
- **Checks run on GitHub.** The checks job now signs in to git with the form GitHub accepts (basic auth with the job token), so every pull request gets its `checks` status. Before, it failed at checkout on GitHub and nothing merged. Forgejo accepts the same form.
- **Team setup and the v0 team upgrade work on GitHub on a second run.** An existing repo or team is reused. A repo left empty gets its first push before protection. A refused push or a missing `gh` scope says the cause in one line. A Free GitHub org stops before any change: team setup needs GitHub Team. A plan the sign-in cannot see stops too: sign in as an org owner. The upgrade puts the check tools on `main` first and never leaves `main` unprotected, even when that push is refused. It keeps every `CODEOWNERS` line the company added. Any stop while protection is lifted puts it back, or says plainly that `main` is open. On Forgejo every upgrade pull request gets auto-merge. On GitHub the admin's own rules pull requests need one bypass click, so they get no auto-merge (that would hide the bypass box), and the upgrade prints the click. It says `upgrade: ok` only when nothing is left to merge by hand. A dry run on a Free org reports the plan as a finding and still prints the full report.
- **Safer daily path for teams.** Setup and offboarding scripts commit only the files they changed, so an untracked or held file never goes up by accident. A new teammate's folder stays on `main` after joining, and `pull` moves an older folder off its own sync branch once its work is on the host. Logs and an area's shared `drafts/` folder go to the area as the rules say. The joining terms pull request merges by itself. A failed pull says why in one line, and `sync.sh status` shows it.
- **Upgrade fixes from a real v0 company.** The logs move finds `origin/logs` in a fresh clone and stops on a stale local `logs`. Other v0 clones move their old logs worktree out on `pull` or `join`, without losing a log. If that move stops part way, it says so in one line and names the folder that holds a full copy. The old logs land in `memory/logs/archive/`, so a plain `git pull` on an old copy never writes over a log there. The upgrade prints a log freeze before the run and the safe steps for teammates after it. When two people logged on the old branch, the move merges their logs first, and a real clash stops with the exact steps. Logs pushed to the old branch after the upgrade reach `main` by the next full `sync pull`. The upgrade skill gives one clear order for a team after the merge: the admin runs Part A again, then each teammate saves their logs, renames the old folder and joins in a new one (on Windows in Git Bash). The rules merge drops the setup placeholder only in the part that got company lines, keeps a blank line before each heading, carries a table row with its header, and keeps v0 lines out of the wrong subheading. A merged `AGENTS.md` over 9,000 characters gets one line on what to move. Every area gets `.gitattributes`. A profile with no host gets `host: none`, and `lint` flags a missing `host:`. The rollback steps on a host also undo the check tools commit and the v1 rules.
- **Retries and holds that keep work.** A refused switch back to `main` never stops `join`, `add-person` or `remove-teammate` before the pull request, and a second run opens it. A second `join` also opens the joining terms pull request a stopped run left out. Offline, it stops and says to run it again, instead of guessing. The accepted terms now reach `main`: `join` keeps the dated people page in the folder, so the next `sync push` sends it, and a second `join` never switches the folder to the sync branch. `remove-teammate` and `add-person` leave their change in the folder, so you see it at once; `sync push` holds it until its own pull request merges. If that pull request is closed and its branch deleted, push says so and stops holding. `pull` never swaps in a fresh copy while any local branch has a commit the host never had. A good push never clears a pull error. The daily jobs leave the temp folder as they found it: each run of `sync`, the host, team, nightly, bot and check scripts keeps its temp files in one folder that goes when the run ends or is stopped, with one sign-in helper file per run.
- **A failed model review says why.** It names the HTTP code (or the network error) and the vendor's message, never the key. A review key pasted with a space or a line break still works.
- **Who approves your own rules change, said plainly.** On GitHub the author's own approval never counts. A director's own area change needs the admin. The admin merges their own with the bypass box. On Forgejo your own change merges on green checks.
- **Area templates keep each row in its own table.** The `apps` area's skill row moved out of the approval tiers table. A test checks every rules table.
- **Windows sync works through Git Bash.** The jobs run the same `sync.sh` from Task Scheduler, with no window. Tested on a Windows runner (S15).
- **New skills:** `sync`, `remove-teammate`, `remove-leak`, `company-skills` (for chat-only agents).
- **Bots (switch).** `add-bot` gives a bot its own GitHub App and one-hour tokens. Every bot commit carries a run ID, and `undo-run` reverts one run in one step.
- **Bot runs push their own branch.** A bot run sends the commits already on `sync/<bot>`, run id included, and opens `sync: <bot>` as the bot. It does not commit that work again as the person. A secret or a rules file in that range pushes nothing.

### Not in v1

- **The dream pass.** Hidden until it has run on real knowledge long enough to trust it.
- **The connector.** Readers without a GitHub seat and the app level need the 1610 OS app, which is a separate release.
- **Projects as a feature.** The pattern is written up in `scale.md` only, until a pilot shows it helps.
