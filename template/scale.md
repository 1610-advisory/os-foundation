# Scale — switches, projects, outside parties, and the 5,000-staff case

Agents do not load this file at session start. Read it only when someone asks about a large company, a switch named here, projects, or outside-party devices.

A small company needs none of this. The design stays the same at every size: the same folder, the same areas, the same rules. A larger company turns on switches. A switch changes how a rule is enforced, never where knowledge lives.

## Scale switches

All are off by default. v1 ships them as a written plan: turning one on is host or device setup that the admin does. No v1 script reads them yet. When one is on, add its name to `switches:` in `company-profile.md` and run `skills/privacy/privacy.sh`.

| Switch | What it does | Needs |
|---|---|---|
| `managed-device-clone` | Git users clone only from company-managed computers. On personal computers they use the connector. | GitHub Enterprise Cloud (IP allow list or managed users, plus SSH certificates). Forgejo: only an IP limit at the proxy. The app level, for the connector. |
| `connector-only-areas` | In a sensitive area (finance, HR), only its approvers get git read. Everyone else reads through the connector. | The app level. Per-repo read already enforces it, so it works at 10 staff. |
| `mdm-wipe` | Device management deletes the company folder on managed computers when a person leaves. | A device management (MDM) tool. |
| `clone-audit-stream` | Clone and fetch events go to the company's own log store. GitHub keeps them only 7 days. | GitHub Enterprise Cloud. |
| `merge-queue` | Merges on a busy repo wait in a queue and run checks in order. | GitHub Enterprise Cloud. |
| `two-person-rule` | The admin loses the review bypass. A second person approves company-root rules changes. | A second approver. |
| `sso-scim` | The company's identity provider adds and removes people. Leaving runs `remove-teammate` by itself. | GitHub Enterprise Cloud with SAML and SCIM. |
| `enterprise-cloud` | The host is GitHub Enterprise Cloud: SSO, managed users, org-wide rulesets, audit log streaming. | The Enterprise Cloud plan. A company that must keep data on its own servers uses GitHub Enterprise Server instead. |
| `company-app` | One GitHub App for the whole company. The app gives each bot a one-hour token cut to that bot's repos. The key never sits on a bot's computer. | The app level and the `bots` switch. |

Phone access to your own computer (an always-on session on a computer that already holds the copy) adds no copy. It is allowed at every size and needs no switch.

## Projects (not in v1)

A project is one piece of work with an end and a done test that takes many agent sessions. Examples: "move the company to the team level", "build the year-end report pack".

The shape, when it ships:

- A folder `projects/<slug>/` inside the area that owns the work.
- `PROJECT.md` is the entry file: goal, owner, areas touched, done test. It may carry an `authority:` field. That field may only tighten the approval tiers, never loosen them.
- `status.json`: a list of items. Agents only mark an item pass or fail.
- `progress.md`: where the last session stopped.
- Any other files the work needs.
- A cross-area project has one owning area. The company root keeps only one index line: name, owning area, state.

A new session reads these files and goes on, with no "where was I" questions. When the done test passes, the project closes.

A project never changes who can read. A client of an outside firm is not a project: a client is a company with its own folder.

Why not in v1: the pattern is not proven yet. It is piloted for two weeks in one area first. It passes if long agent runs finish with fewer restarts and fewer "where was I" questions, judged from the run logs.

## Outside-party device checklist

For anyone who works inside many companies' OS from one computer: an advisory firm, a vendor, an agency, a bookkeeper.

- [ ] One named account per person in each company. It is marked "outside party". The company can see and remove it. No shared login.
- [ ] One folder per company. Never put two companies in one folder.
- [ ] Open each agent session inside one company's folder only.
- [ ] No rules file, setting, skill or memory loads across companies. Keep agent config per folder.
- [ ] Chat-app memory is off, or kept per company (one project or workspace per company).
- [ ] Your home profile holds no company facts: no names, numbers or details.
- [ ] Your firm's floor rules sit in the agent's managed settings on firm computers.
- [ ] Disk encryption and screen lock are on.
- [ ] No company folder in a synced folder (iCloud Drive, Dropbox, OneDrive, Google Drive).
- [ ] Clone only the areas you are granted. Health data (PHI) installs: no clones; use the app and the connector only.
- [ ] Firm skills come as a versioned package. Never copy them into a company's own `skills/`.
- [ ] When the work ends: delete every copy (the folder, agent transcripts, backups, hand copies). Keep only anonymized notes on methods, unless a special agreement says otherwise.

## The 5,000-staff case

The same design works for a company of 5,000. The argument:

- **Same layout, more areas.** One company repo, one repo per area, one workspace per person. Read access is per repo, so a large company adds areas, not new kinds of storage.
- **Most staff are connector readers.** They use the connector in their chat app: no GitHub seat, no clone. Only people who write or approve need a seat. The connector is the app level (the 1610 OS app); it is not in this public release.
- **GitHub Enterprise Cloud switches.** SSO, SCIM for joiners and leavers, org-wide rulesets, audit log streaming (see the table above). Forgejo is the lower-cost choice. A company that picks it gives up built-in audit, SSO and a multi-node design, and must add proxy logs, an approver allowlist and a multi-node plan.
- **One company App.** Bots get one-hour tokens cut to their repos. No long-lived bot keys on computers.
- **A spread nightly push window.** Each computer pushes at a random offset over some hours, so the host never gets 5,000 pushes at once. Each person has their own branch, so pushes do not conflict.
- **One digest per approver.** The nightly review fixes clear errors itself and sends each approver team one daily digest of flags, grouped and capped. People gate only rules files, which change rarely.
- **Log volume.** One short log file per person per day per area: about 1.25 million small files a year across all area repos. The nightly review folds logs older than 30 days into one monthly summary per area. Raw files stay in history.
- **First limits: API and push rates, not storage.** Host limits seen so far (check again before you rely on them): about 5,000 API requests an hour per user, 15,000 for Enterprise Cloud apps; about 100,000 repos per org; 10 GB per repo; 100 MB per file; 5,000 members per team.
- **Ask GitHub first.** GitHub's terms define an "End User" as any person or machine account the customer lets use the product or reach its content. Connector readers may fall under that. Get GitHub's view in writing before a 5,000-staff rollout.

## Load and permission check

Numbers: see `tests/scale/RESULTS.md` in the os-foundation repo (https://github.com/1610-advisory/os-foundation). The numbers come here before release.

The check runs on a local Forgejo: 5,000 users, 200 area repos, team grants by area. It proves read denial per repo for a sample of users, and simulates a spread nightly push window (rate, conflicts, time). It is not a live run with 5,000 people.
