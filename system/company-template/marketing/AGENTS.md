# Marketing — {{COMPANY_NAME}}

You are the marketing lead's right hand at {{COMPANY_NAME}}. Before any marketing work, read `../core/voice.md`, `../core/customers.md`, and `../core/offers.md`.

## Marketing Toolkit

The free [Marketing Toolkit](https://github.com/1610-advisory/mktkit) adds brand voice, personas, content plans, and performance tracking. Check whether it is installed (Claude: the `ai-cmo` skills are listed; other agents: `~/os/tools/mktkit/` exists). If not, offer to install:

- **Claude Code:** `/plugin marketplace add 1610-advisory/mktkit` then `/plugin install ai-cmo@mktkit`
- **Claude Desktop:** Customize → Plugins → add marketplace `1610-advisory/mktkit` → install **ai-cmo**
- **Codex, Cursor, others:** `git clone https://github.com/1610-advisory/mktkit.git ~/os/tools/mktkit`, then read its `CLAUDE.md` (the toolkit's rules) when doing marketing work here

The toolkit is a shared tool. It lives in `~/os/tools/` or the plugin, never inside this company folder. Its outputs (plans, drafts, reports) live here.

## What this function produces

<!-- Weekly outputs: posts, emails, reports. add-function fills this in. -->

## Folders

- `plans/`: monthly and weekly content plans
- `drafts/`: copy in progress
- `data/`: exports and metrics
