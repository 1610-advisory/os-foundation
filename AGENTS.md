# os-foundation — rules for any AI agent in this repo

This repo is **os-foundation**: the setup files and the template for a company OS. It is not anyone's company OS. A company OS is built **from** it, in its own folder. The path is `{{COMPANY_OS}}` from `start-core.md`: usually `~/{{COMPANY_SLUG}}-os/`, or the empty folder already open.

`CLAUDE.md` imports this file.

## If a person asked you to set up their company

Read `START.md` and follow it. Build their company OS in its own folder (`{{COMPANY_OS}}` in `start-core.md`), never inside this repo. Their folder must not keep this repo's git history or remote: it is theirs.

## If you are changing os-foundation itself

| Path | What it is |
|---|---|
| `START.md` | The router every agent reads first. Short. |
| `start-core.md` | The setup interview, tone, safety rules, and build steps. Works for any agent on its own. |
| `start-{{AGENT}}.md` | Thin add-ons per agent: connectors and commands only. |
| `template/` | Copied into `{{COMPANY_OS}}/` (see `start-core.md`). Placeholders: `{{COMPANY_NAME}}`, `{{COMPANY_SLUG}}`, `{{OWNER_NAME}}`, `{{OWNER_ROLE}}`, `{{ONE_LINER}}`, `{{AREAS}}`, `{{DATE}}`. |
| `template/skills/` | Company skills the OS keeps after setup. |
| `template/skills/add-area/templates/` | Area templates: `_area/` (every area), plus `marketing/`, `finance/`, `apps/` on top. Placeholders add `{{AREA_NAME}}`, `{{AREA_SLUG}}`. |

Rules:

- **This repo is public.** No real company, client, or person names, emails, prices, hosts, or account details. Examples use "Acme Co" and `acme`.
- **No secrets**, ever.
- **The company OS must work on its own** after setup: no file in `template/` may depend on this repo being present.
- **Sharing is the person's choice.** Agents never move area facts into shared files on their own; a person may share anything, and a teammate's share goes through the admin's pull-request review. Keep the template consistent with that rule.
- **Keep every `AGENTS.md` under 10,000 characters.** Put detail in skills.
- **Plain words.** Short sentences, one instruction per sentence, active voice. Setup is read by people who are not technical.
- **No telemetry.** Nothing in this repo reports back to 1610. The only count is fetches of the setup file.
- Test a change by running setup end to end in a fresh user account with at least Claude Cowork and Claude Code.
