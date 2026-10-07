# start-cursor — add-on for Cursor

Read `start-core.md` first. This file only adds Cursor steps. You are Cursor. In the close-out, say Cursor.

## Folder

Cursor works in the folder that is already open. Agree `{{COMPANY_OS}}` in `start-core.md`, then stay there. If nothing is open yet, build the folder they agreed and ask them to open it (File → Open Folder).

- If the open folder already has git, keep that history. Run `git init` only when there is no `.git`.
- A cloud or Origin session may commit and push to the open repo. That repo is theirs. Share it with someone else only when they ask.
- Area files stay in the area. One pointer in a shared file is enough for a clone to see the win (`start-core.md`).

## Connections

Cursor connects tools through MCP (Settings → MCP). After the tools question:

1. If the first job needs a connection and an official connector exists for their tool, add it in `.cursor/mcp.json` in the company folder (or the area). Their sign-in only. **Never** put a token in the chat or a file.
2. Otherwise do a **file win**: they paste an email or notes into `inbox/`, and you run `ingest`.

## Commands for "how to start each day"

"Open Cursor in `{{COMPANY_OS}}` (or the area folder, when the work lives there). If that folder is already open, stay there."

## The paste prompt

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
