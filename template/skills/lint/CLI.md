# lint

```
lint.sh [--ci] [--root <dir>]
lint.sh --help
```

Checks the company folder. Exit 0 when nothing is wrong. Exit 1 when there is a finding. Notices do not change the exit code.

## Flags

| Flag | Meaning |
|---|---|
| `--ci` | Findings only. No version notice. No automation offer. No network. |
| `--root <dir>` | Company folder. Default: the current directory. |
| `--help` | Print usage and exit 0. |

`OS_VERSION_URL` overrides the version URL in tests. Default: `https://1610.sh/os/version`. `OS_NOW` (`YYYY-MM-DD`) overrides today for the automation offer.

## Checks

1. `.agents/skills` and `.claude/skills` exist and point at `../skills`, in the company root and in each `areas/<area>/` that has its own rules files.
2. A skill copy differs from its source. A real directory at `.agents/skills` or `.claude/skills` (not the link) is a copy. A file under `areas/<area>/skills/<name>/` that also exists under `skills/<name>/` is a copy. The bytes must match.
3. No `logs` branch check. A `logs` branch is not a finding.
4. `level` is `solo`, `team`, or `app`. Each `switches` name is a v1 switch (`automations`, `traces`, `cloud-handoff`, `mdx-reports`, `benchmarks`; `bots`, the old name of `automations`, for one release) or a name in the first column of the table in `scale.md`. `dream` is a finding.
5. Agent rules files are under 10,000 characters: `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, and `automations/*/AUTOMATION.md` (and an old `bots/*/BOT.md` at the root), at the root and in each area. Other files under `skills/` are not sized here. `skill-creator` ships a longer `SKILL.md` on purpose.
6. No `{{...}}` outside `skills/` and `library/` (the admin's private repo of copies).
7. A simple check that `users/<person>/profile/PROFILE.md` does not contain the company slug or the company name from the profile heading. The nightly check is the real one.
8. Team on GitHub, not with `--ci`: the org settings, read by `skills/_host/host.sh org-settings`. The base permission must be `none` ("No permission"). Members must not be able to make repos. Each open setting is a finding with the settings link. `OS_LINT_NO_HOST=1` skips this check.

## Notices (not findings, not with `--ci`)

- One line when `https://1610.sh/os/version` is a newer stable semver than `os_version`. Timeout 5 seconds. Offline is silent. The body is one `text/plain` line: `vX.Y.Z`, or `unreleased` (no notice). A prerelease is never newer than a stable.
- One `notice: grok:` line per folder (the company folder and each area repo) that the Grok CLI does not trust, when `grok` and `jq` are installed. Grok loads none of an untrusted folder's rules. `OS_LINT_NO_GROK=1` skips it.
- One `notice: org settings:` line when lint cannot read the org settings: the sign-in is not an org owner, or the host is offline. Team on GitHub only.
- One `notice: switches:` line when `switches:` has `bots`, the old name of `automations`. It still works for this release. The upgrade (`--refresh`) renames it. One `notice: bots/` line when the company root still has `bots/<name>/BOT.md`.
- One automation-offer sentence after 14 days of use, once, when `automations` is off. State files live under `${XDG_CONFIG_HOME:-$HOME/.config}/<slug>-os/state/`. There is no dream offer.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | one or more findings |
| 2 | usage |

## What it prints

Findings, one per line:

```
finding: link: .agents/skills is missing
finding: copy: areas/marketing/skills/lint/SKILL.md differs
finding: level: missing
finding: host: missing (add host: none to company-profile.md, or github or forgejo)
finding: switch: dream
finding: size: AGENTS.md
finding: placeholder: company-profile.md
finding: profile: users/ada/profile/PROFILE.md
finding: org settings: base permission is read, not "No permission": https://github.com/organizations/acme/settings/member_privileges
finding: org settings: members can make repos. Turn it off: https://github.com/organizations/acme/settings/member_privileges
```

Notices:

```
notice: a newer os-foundation version exists: vX.Y.Z
notice: grok: <folder> is not trusted, so Grok reads none of its rules there. Start grok in that folder once and trust it.
notice: org settings: could not read them (sign in as an org owner, or you are offline). An org owner checks them: https://github.com/organizations/acme/settings/member_privileges
offer: You have used this OS for two weeks. An automation can run jobs for you. Ask to add one.
```
