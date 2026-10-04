# start-claude — add-on for Claude Cowork, Claude Desktop, and Claude Code

Read `start-core.md` first. This file only adds Claude steps.

## Folder access (Cowork and Desktop)

Cowork and Desktop can only edit folders the person shares with you.

- Before you build (right after question 4 in `start-core.md`), ask them to make an empty folder named `<slug>-os` in their home folder and choose it as the folder for this task. Then build inside it.
- If you cannot run `git clone` or download the zip, read the template files one by one from `https://1610.sh/os/template/...` (the file list is in `https://github.com/1610-advisory/os-foundation/tree/main/template`) and write them into the folder.
- If `git` is not available, still build the folder. Tell them their history starts when git is installed; `add-teammate` will help later.

## First connection

After the tools question, if they use **Gmail or Google Calendar** and you have Claude's Google connectors (Settings → Connectors):

1. If the first job needs a connection, make Gmail (or Calendar) the one connection today. It unlocks "what did we say?" faster than anything else.
2. Walk them through Claude's own connect screen. **Never** ask them to paste an app password or token into chat.
3. Tell them the connector is account-wide: it works in every folder they open in Claude.

If the connector is not available in their plan or app, say so, and use a file win instead: they paste an email or notes into `inbox/`, and you run `ingest`.

## Commands for "how to start each day"

- **Cowork / Desktop:** "Start a task and choose the folder `~/<slug>-os` (or `~/<slug>-os/areas/marketing` for marketing work)."
- **Claude Code:** `cd ~/<slug>-os && claude` (or `cd ~/<slug>-os/areas/marketing && claude`).

## The paste prompt (for the landing page)

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
