# start-cursor — add-on for Cursor

Read `start-core.md` first. This file only adds Cursor steps. You are Cursor. In the close-out, say Cursor.

## Folder

Cursor works in the folder that is already open. `{{COMPANY_OS}}` is that path when you agree it in `start-core.md`.

- If the open folder is empty, or they are using it as the company OS, build there and stay there.
- If that folder is os-foundation, keep it as the setup repo and build the company beside it (`start-core.md`).
- On their own computer, with no project folder open, `~/{{COMPANY_SLUG}}-os/` is the usual place. Build that, then ask them to open it (File → Open Folder).
- If the open folder already has git, keep that history. Run `git init` only when there is no `.git`.
- A cloud or Origin session may commit and push to the open repo. That repo is theirs. Share it with someone else only when they ask.
- The company repo ignores `areas/`. A push of the company folder does not include an area draft. The one-line path in "Right now" (see `start-core.md`) is what a clone will show. For area work they open the area folder.

## Connections

Cursor connects tools through MCP (Settings → MCP). After the tools question:

1. If the first job needs a connection and an official connector exists for their tool, add it in `.cursor/mcp.json` in the company folder (or the area). Their sign-in only. **Never** put a token in the chat or a file.
2. Otherwise do a **file win**: they paste an email or notes into `inbox/`, and you run `ingest`.

## Commands for "how to start each day"

"Open Cursor in `{{COMPANY_OS}}` (or `{{COMPANY_OS}}/areas/marketing` for marketing work). If that folder is already open, stay there."

## The paste prompt

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
