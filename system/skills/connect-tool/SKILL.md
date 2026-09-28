---
name: connect-tool
description: Connect one outside tool (email, calendar, docs, chat, books, CRM, store, email marketing) to one company so the agent can read and act in it. Finds the official connector, scopes it to the company, signs in with the tool's own login, and verifies with one read-only call. Use when the person says "connect my email", "hook up QuickBooks", "can you see my calendar", or setup reaches its tools step.
---

# Connect a tool

Context tells the agent what to know. Tools let it act. Most tools connect through **MCP** (Model Context Protocol): a standard plug that lets an agent read and act in another app.

One tool, one company, per run. Ask one question at a time.

## Rules

- **Never** ask for, type, paste, or save a password, API key, or token in chat or in any file. Use the tool's own sign-in (OAuth: a browser window where they log in). If a tool only offers API keys, tell the person to put the key in the place the tool's docs name (an environment variable or their system keychain) themselves, and never show it to you.
- **Official first.** Use the connector made by the tool's vendor, or the one listed in your agent's own connector directory. Do not install random community servers without saying so and getting a yes.
- **Read-only first.** If the connector offers scopes or a read-only mode, start there. Write access can come later.
- **Scope to the company.** Set up from inside `~/os/<company-slug>/` and use the company's own account (their work email, not personal).
- Look up current setup steps from the vendor's docs at run time. Do not guess URLs or package names from memory.

## 1. Which tool, which company

Ask which tool and confirm the company. Check `<company>/company.md` → "Tools" for what is already connected.

## 2. Find the connector

Search, in this order:

1. Your agent's built-in connector list (Claude: Settings → Connectors; Cursor: Settings → MCP; Codex: `codex mcp --help`).
2. The vendor's own docs: search "<tool> MCP server".
3. If nothing official exists, say so. Offer a fallback: export files (CSV, PDF) into `<company>/<function>/data/` and work from those.

Common ones by function:

| Function | Tools people usually connect |
|---|---|
| Everyone | Email + calendar + docs (Google Workspace or Microsoft 365), chat (Slack or Teams) |
| Marketing | Email marketing (Mailchimp, Klaviyo, beehiiv), social scheduling, analytics (GA4), ads |
| Sales | CRM (HubSpot, Salesforce, Pipedrive) |
| Finance | Books (QuickBooks, Xero), bank or card exports, spreadsheets |
| Operations | Project tool (Notion, Asana, Monday), store (Shopify) |

## 3. Install it where it belongs

Where the connection lives depends on the agent:

| Agent | Where connections live | How to scope to one company |
|---|---|---|
| Claude Desktop / Cowork / claude.ai | Account-wide connectors (Settings → Connectors) | Sign in with this company's account. If they work in more than one company, tell them which account the connector uses. |
| Claude Code | `.mcp.json` in the folder you run `claude mcp add --scope project ...` from | Run it from `~/os/<company-slug>/`. The file holds no secrets; sign-in happens in the browser. |
| Cursor | `.cursor/mcp.json` in the project folder | Put it in `~/os/<company-slug>/`. |
| Codex | One global config (`~/.codex/config.toml`) | It is visible everywhere. Name it with the company slug (for example `prairie-seed-gmail`) and only use it inside that company. |

Walk them through the sign-in. They click; you wait.

## 4. Verify

Make one **read-only** call and show the result: list the three newest emails (subjects only), today's calendar, the last five invoices, and so on. If it fails, read the error and fix the one thing it names.

## 5. Record it

In `<company>/company.md` → "Tools", add a line: tool, connector name, agent, read-only or read-write, date connected. No secrets. Then tell them one thing they can now ask, for example "What did customers email about this week?"
