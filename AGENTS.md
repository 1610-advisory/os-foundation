# os-foundation — rules for any AI agent in this repo

This repo is **os-foundation**: the setup files and the template for a company OS. It is not anyone's company OS. A company OS is built **from** it, in its own folder: `~/<company-slug>-os/`.

`CLAUDE.md` imports this file.

## If a person asked you to set up their company

Read `START.md` and follow it. Build their company OS in `~/<company-slug>-os/`, never inside this repo. Their folder must not keep this repo's git history or remote: it is theirs.

## If you are changing os-foundation itself

| Path | What it is |
|---|---|
| `START.md` | The router every agent reads first. Short. |
| `start-core.md` | The setup interview, tone, safety rules, and build steps. Works for any agent on its own. |
| `start-<agent>.md` | Thin add-ons per agent: connectors and commands only. |
| `template/` | Copied to `~/<slug>-os/`. Placeholders: `{{COMPANY_NAME}}`, `{{COMPANY_SLUG}}`, `{{OWNER_NAME}}`, `{{OWNER_ROLE}}`, `{{ONE_LINER}}`, `{{AREAS}}`, `{{DATE}}`. |
| `template/skills/` | Company skills the OS keeps after setup. |
| `template/skills/add-area/templates/` | Area templates: `_area/` (every area), plus `marketing/`, `finance/`, `apps/` on top. Placeholders add `{{AREA_NAME}}`, `{{AREA_SLUG}}`. |

Rules:

- **This repo is public.** No real company, client, or person names, emails, prices, hosts, or account details. Examples use "Acme Co" and `acme`.
- **No secrets**, ever.
- **The company OS must work on its own** after setup: no file in `template/` may depend on this repo being present.
- **Area facts stay in areas.** Keep the shared root (`template/`) free of any rule or file that would pull area data into it.
- **Keep every `AGENTS.md` under 10,000 characters.** Put detail in skills.
- **Plain words.** Short sentences, one instruction per sentence, active voice. Setup is read by people who are not technical.
- **No telemetry.** Nothing in this repo reports back to 1610. The only count is fetches of the setup file.
- Test a change by running setup end to end in a fresh user account with at least Claude Cowork and Claude Code.
