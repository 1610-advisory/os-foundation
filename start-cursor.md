# start-cursor — add-on for Cursor

Read `start-core.md` first. This file only adds Cursor steps.

## Folder

Cursor works in the folder that is open. After you build `~/{{COMPANY_SLUG}}-os/`, ask them to open it (File → Open Folder) so the company rules load. For area work they open the area folder.

## Connections

Cursor connects tools through MCP (Settings → MCP). After the tools question:

1. If the first job needs a connection and an official connector exists for their tool, add it in `.cursor/mcp.json` in the company folder (or the area). Their sign-in only. **Never** put a token in the chat or a file.
2. Otherwise do a **file win**: they paste an email or notes into `inbox/`, and you run `ingest`.

## Commands for "how to start each day"

"Open Cursor, then File → Open Folder → `~/{{COMPANY_SLUG}}-os` (or `~/{{COMPANY_SLUG}}-os/areas/marketing` for marketing work)."

## The paste prompt

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
