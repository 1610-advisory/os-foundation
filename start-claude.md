# start-claude — add-on for Claude Cowork, Claude Desktop, and Claude Code

Read `start-core.md` first. This file only adds Claude steps. You are Claude. In the close-out, say Claude.

The first time a folder opens, Claude may ask whether they trust it. They approve that once.

## Folder access (Cowork and Desktop)

Cowork and Desktop can only edit folders the person shares with you.

- `{{COMPANY_OS}}` is the folder you agreed in `start-core.md`. If they already chose a folder for this task, build there.
- If they have not chosen one yet, ask them to choose an empty folder. On their own computer, a folder in their home directory is a fine suggestion. Then build inside it.
- If you cannot run `git clone` or download the zip, get the file list from `https://1610.sh/os/files`, then read each file under `template/` from `https://1610.sh/os/{{PATH}}` and write it into the folder (without the `template/` part of the path).
- If `git` is not available, still build the folder. Tell them their history starts when git is installed; `add-teammate` will help later.

## First connection

After the tools question, if they use **Gmail or Google Calendar** and you have Claude's Google connectors (Settings → Connectors):

1. If the first job needs a connection, connect the one tool that unlocks it. Gmail or Calendar is a natural one when the job is finding what they said.
2. Walk them through Claude's own connect screen. **Never** ask them to paste an app password or token into chat.
3. Tell them the connector is account-wide: it works in every folder they open in Claude.

If the connector is not available in their plan or app, say so, and use a file win instead: they paste an email or notes into `inbox/`, and you run `ingest`.

## Commands for "how to start each day"

- **Cowork / Desktop:** "Start a task and choose the folder `{{COMPANY_OS}}` (or the area folder, when the work lives there)."
- **Claude Code:** `cd "{{COMPANY_OS}}" && claude` (or `cd` into the area folder, then `claude`).

## The paste prompt (for the landing page)

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
