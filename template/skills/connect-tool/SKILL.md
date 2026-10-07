---
name: connect-tool
description: Connect one outside tool (email, calendar, docs, chat, books, CRM, store, email marketing) so the agent can read and act in it. Finds the official connector, puts it in the right folder, signs in with the tool's own login, and checks it with one read-only call. Use when someone says "connect my email", "hook up QuickBooks", "can you see my calendar", or setup reaches its tools step.
---

# Connect a tool

Shared files tell the agent what to know. Tools let it act. Most tools connect through **MCP** (Model Context Protocol): a standard plug that lets an agent read and act in another app.

One tool per run. Ask one question at a time.

## Rules

- **Never** ask for, type, paste, or save a password, API key, or token in chat or in any file. Use the tool's own sign-in (a browser window where they log in). If a tool only offers API keys, tell the person to put the key where the tool's docs say (an environment variable or their system keychain) themselves, and never show it to you.
- **Official first.** Use the vendor's own connector, or one listed in your agent's connector directory. Do not install community connectors without saying so and getting a yes.
- **Read-only first** when the connector offers it. Write access can come later.
- **The company's own account** (work email, not personal).
- Look up current setup steps in the vendor's docs at run time. Do not guess URLs or package names.

## 1. Which tool, which folder

Ask which tool. Then decide where it belongs:

- **Used by everyone** (email, calendar, docs, chat) → the company root.
- **Area data with restricted access** (books, bank, payroll, CRM records) → that area's folder. Connect it from inside the area, so it only works there.

Check `architecture.md` → "Connections" for what is already connected.

## 2. Find the connector

1. Your agent's built-in connectors (Claude: Settings → Connectors; Cursor: Settings → MCP; Codex: `codex mcp --help`).
2. The vendor's docs: search "{{TOOL}} MCP server".
3. Nothing official, or no internet to look? Say so. Offer a fallback: export files (CSV, PDF) into the area's `data/` folder and work from those.

## 3. Install it where it belongs

| Agent | Where connections live | How to keep it in its folder |
|---|---|---|
| Claude Desktop / Cowork | Account-wide (Settings → Connectors) | Sign in with the company account. Tell the person it is visible in every folder. |
| Claude Code | `.mcp.json` in the folder you run `claude mcp add --scope project ...` from | Run it from the company root or the area. The file holds no secrets. |
| Cursor | `.cursor/mcp.json` in the opened folder | Put it in the company root or the area. |
| Codex | One global config (`~/.codex/config.toml`) | Visible everywhere. Name it with the company slug (for example `acme-gmail`) and use it only for this company. |

Walk them through the sign-in. They click; you wait.

## 4. Check it

Make one **read-only** call and show the result: the three newest email subjects, today's calendar, the last five invoices. If it fails, read the error and fix the one thing it names.

## 5. Record it

In `architecture.md` at the company root (create it if missing, with `type: architecture` frontmatter and a "Connections" table), add a row: tool, connector, agent, folder, read-only or read-write, date. No secrets, no account numbers. Commit.

For a knowledge source such as Notion or Drive, also update `memory/existing-sources.md` (or the area's index for restricted material): what it holds, its location, the access method, and the date of the successful read-only check. Keep its entry in the corresponding `memory/MEMORY.md`. Record no credentials. The source stays authoritative; connecting it does not authorize migration, bulk copies, or a scheduled sync.

Then tell them one thing they can now ask, for example "What did customers email about this week?"
