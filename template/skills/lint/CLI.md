# lint

```
lint.sh [--ci] [--root <dir>]
lint.sh --help
```

Checks the company folder. Exit 0 when nothing is wrong. Exit 1 when there is a finding. Notices do not change the exit code.

## Flags

| Flag | Meaning |
|---|---|
| `--ci` | Findings only. No version notice. No bot offer. No network. |
| `--root <dir>` | Company folder. Default: the current directory. |
| `--help` | Print usage and exit 0. |

`OS_VERSION_URL` overrides the version URL in tests. Default: `https://1610.sh/os/version`. `OS_NOW` (`YYYY-MM-DD`) overrides today for the bot offer.

## Checks

1. `.agents/skills` and `.claude/skills` exist and point at `../skills`, in the company root and in each `areas/<area>/` that has its own rules files.
2. A skill copy differs from its source. A real directory at `.agents/skills` or `.claude/skills` (not the link) is a copy. A file under `areas/<area>/skills/<name>/` that also exists under `skills/<name>/` is a copy. The bytes must match.
3. No `logs` branch check. A `logs` branch is not a finding.
4. `level` is `solo`, `team`, or `app`. Each `switches` name is a v1 switch (`bots`, `traces`, `cloud-handoff`, `mdx-reports`, `benchmarks`) or a name in the first column of the table in `scale.md`. `dream` is a finding.
5. Agent rules files are under 10,000 characters: `AGENTS.md`, `CLAUDE.md`, `review-rules.md`, and `bots/*/BOT.md`, at the root and in each area. Other files under `skills/` are not sized here. `skill-creator` ships a longer `SKILL.md` on purpose.
6. No `{{...}}` outside `skills/`.
7. A simple check that `users/<person>/profile/PROFILE.md` does not contain the company slug or the company name from the profile heading. The nightly check is the real one.

## Notices (not findings, not with `--ci`)

- One line when `https://1610.sh/os/version` is a newer stable semver than `os_version`. Timeout 5 seconds. Offline is silent. The body is one `text/plain` line: `vX.Y.Z`, or `unreleased` (no notice). A prerelease is never newer than a stable.
- One bot-offer sentence after 14 days of use, once, when `bots` is off. State files live under `${XDG_CONFIG_HOME:-$HOME/.config}/<slug>-os/state/`. There is no dream offer.

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
finding: switch: dream
finding: size: AGENTS.md
finding: placeholder: company-profile.md
finding: profile: users/ada/profile/PROFILE.md
```

Notices:

```
notice: a newer os-foundation version exists: vX.Y.Z
offer: You have used this OS for two weeks. A bot can run jobs for you. Ask to add one.
```
