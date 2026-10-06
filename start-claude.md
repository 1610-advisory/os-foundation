# start-claude — add-on for Claude Cowork, Claude Desktop, and Claude Code

Read `start-core.md` first. This file only adds Claude steps. You are Claude. In the close-out, say Claude.

The first time a folder opens, Claude may ask whether they trust it. They approve that once.

## Folder access (Cowork and Desktop)

Cowork and Desktop can only edit folders the person shares with you.

- `{{COMPANY_OS}}` is the path you agreed in `start-core.md`. If they already chose a folder for this task and it is empty, build there.
- If they have not chosen one yet, ask them to make an empty folder and choose it. On their own computer, `~/{{COMPANY_SLUG}}-os` in their home folder is the usual place. Then build inside it.
- If you cannot run `git clone` or download the zip, get the file list from `https://1610.sh/os/files`, then read each file under `template/` from `https://1610.sh/os/{{PATH}}` and write it into the folder (without the `template/` part of the path).
- If `git` is not available, still build the folder. Tell them their history starts when git is installed; `add-teammate` will help later.

## First connection

After the tools question, if they use **Gmail or Google Calendar** and you have Claude's Google connectors (Settings → Connectors):

1. If the first job needs a connection, make Gmail (or Calendar) the one connection today. It unlocks "what did we say?" faster than anything else.
2. Walk them through Claude's own connect screen. **Never** ask them to paste an app password or token into chat.
3. Tell them the connector is account-wide: it works in every folder they open in Claude.

If the connector is not available in their plan or app, say so, and use a file win instead: they paste an email or notes into `inbox/`, and you run `ingest`.

## Commands for "how to start each day"

- **Cowork / Desktop:** "Start a task and choose the folder `{{COMPANY_OS}}` (or `{{COMPANY_OS}}/areas/marketing` for marketing work)."
- **Claude Code:** `cd "{{COMPANY_OS}}" && claude` (or `cd "{{COMPANY_OS}}/areas/marketing" && claude`).

## The paste prompt (for the landing page)

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
