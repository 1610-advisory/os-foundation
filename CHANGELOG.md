# Changes

Plain-word release notes for os-foundation. Newest first. Versions follow semver. Your folder records its version in `os_version:` in `company-profile.md`.

## v1.0.0 — unreleased

The multi-user release. A solo owner gets a simpler setup. A team gets enforced review, private workspaces and nightly sync.

### New for everyone (solo too)

- **One setup step fewer.** The `.agents/skills` and `.claude/skills` links now ship in the folder. You no longer link them by hand.
- **Logs are plain files.** Each person writes one short log per day in `memory/logs/`. There is no separate `logs` branch any more.
- **Level and switches.** `company-profile.md` says the level (`solo`, `team` or `app`) and which switches are on. Agents skip rules for a level or a switch that is not on. Every switch is off by default.
- **`privacy.md`.** A script writes it from your level and switches. It lists every place a copy of your data sits, and only the places that are on: who can read it, how long it stays, how it is removed.
- **`scale.md`.** A reference for large companies: scale switches, the projects pattern, a checklist for outside parties' computers, and the 5,000-staff case. Agents do not load it at start.
- **Versions.** `1610.sh/os` serves the latest release. `1610.sh/os@vX.Y.Z` serves a pinned one. `lint` can say in one line when a newer version exists. You choose when to run `upgrade`.

### New for teams

- **`add-teammate` turns on the team level in one run.** The company folder, areas and one private workspace per person go to your company's GitHub (Team plan) or Forgejo, with their history.
- **Nobody writes to `main`.** Each person has one branch and one standing pull request. Notes merge by themselves when the checks pass. Rules files go by their own pull request and need their owner's approval.
- **Checks on every pull request:** a secret scan, `lint`, and a review by a second AI model against `review-rules.md`. All checks run in one job to keep host minutes low.
- **`sync` and OS jobs.** Pull every 15 minutes. Push each night, after a secret scan and a commit-or-hold check by a small model. Any failed step pushes nothing.
- **Nightly review and reports.** On the admin's computer: clear errors fixed by pull request, one daily digest of flags per approver, a daily "to decide" list and a weekly report.
- **Joining terms and leaving.** `joining-terms.md` holds the delete promise each person accepts when they join. `remove-teammate` removes access first. A helper then deletes the company folder from that person's computer. Leave, holidays and offline days never trigger it.
- **New skills:** `sync`, `remove-teammate`, `remove-leak`, `upgrade`, `company-skills` (for chat-only agents), `privacy`.
- **Bots (switch).** `add-bot` gives a bot its own GitHub App and one-hour tokens. Every bot commit carries a run ID, and `undo-run` reverts one run in one step.

### Not in v1

- **The dream pass.** Hidden until it has run on real knowledge long enough to trust it.
- **The connector.** Readers without a GitHub seat and the app level need the 1610 OS app, which is a separate release.
- **Projects as a feature.** The pattern is written up in `scale.md` only, until a pilot shows it helps.
- **Windows jobs are written but not tested.**
