---
name: orchestrator
description: >
  Run one always-on Claude Code session as a person's orchestrator (their "chief of
  staff"). It plans, starts worker sessions in Herdr (in the company folder, in an
  area such as finance, ops or apps so the worker has that area's rules, or in the
  person's workspace), checks on them, and brings the person only what needs their
  answer. It drafts and never sends. Use when someone says "set up my orchestrator",
  "be my chief of staff", "start my hub", "start a worker in finance", "what are my
  agents doing", or "check on my sessions".
---

# Orchestrator

One Claude Code session that runs all day for one person. It holds the plan, not the work. It starts **workers** (other sessions), one task each, checks on them, and brings the person only what needs their answer. The pattern is called orchestrator-worker.

It runs in **Herdr** (sessions stay alive in the background) with **Remote Control** on (the person reaches it from the Claude app on their phone). Set up both with the `remote-setup` skill first.

`<root>` is the company folder. `<me>` is the person's `slug:` on their page in `people/`.

## Rules

- **Draft, never send.** No email, message, post, payment, invite or delete outside the company folder without the person's yes for that one action. Workers follow the same rule.
- **Never approve or merge** a rules PR, and never answer a worker's permission prompt for the person. Bring it to the person.
- **Folder trust only inside the company folder.** Each area is its own git repo, so a new worker in an area can stop at Claude's folder-trust question. Answer it only when the folder's real path is inside the company folder's real path (section 3, step 5). Any other folder, and any other start-up question (MCP servers, outside imports, permission mode): stop and tell the person.
- **One task per worker.** Each worker gets a clear brief: the goal, the folder, what done looks like, and what it must not do.
- **Workers only where the person may go.** A worker in an area needs that area on the person's page (`people/<Name>.md`, `areas:`) and the area folder on this computer. Never start a worker in an area the person does not have.
- **Never close a worker the orchestrator did not start.** Close a worker only when it is done and the person said yes, or when the person asks.
- **No secrets** in a brief or in the orchestrator file.
- **Company rules come first** (`AGENTS.md`). This skill adds steps. It removes no rule.

## Files

- **This skill** (`skills/orchestrator/`): the method. Same for everyone. Changes go by a rules PR.
- **The person's orchestrator file**: `users/<me>/orchestrator/ORCHESTRATOR.md` (in the person's own workspace; solo: the same path, which the company repo ignores). What it watches, active workers, waiting on the person, decisions, finished work. Start it from `templates/ORCHESTRATOR.md` here. It is personal: other people do not read it.
- Worker briefs: `users/<me>/orchestrator/briefs/YYYY-MM-DD-<worker>.md` (optional, for long briefs).

## 1. Set up (once per computer)

1. Run the `remote-setup` skill and fix each `FAIL` (Claude Code, Herdr and its Claude link, Remote Control at startup, keep awake, start after a reboot).
2. Make the person's file if it does not exist: copy `skills/orchestrator/templates/ORCHESTRATOR.md` to `users/<me>/orchestrator/ORCHESTRATOR.md`. Fill in the name and the areas from their people page. Ask what it should watch (three to five things).
3. Make the Herdr workspaces if they are not there (`herdr workspace list`):
   - `orchestrator`: the orchestrator session only.
   - `workers`: one tab per worker.
4. Start the orchestrator in the company folder, with Remote Control on:
   ```bash
   ws=$(herdr workspace create --cwd "<root>" --label orchestrator --no-focus)
   pane=$(printf '%s' "$ws" | sed -n 's/.*"root_pane":{[^}]*"pane_id":"\([^"]*\)".*/\1/p')
   herdr agent start orchestrator --kind claude --pane "$pane" --timeout 60000 -- --name "<me> orchestrator" --remote-control "<me> orchestrator"
   herdr agent prompt orchestrator "Use the orchestrator skill. Read users/<me>/orchestrator/ORCHESTRATOR.md and do the session start."
   ```
   Windows (PowerShell): the same, with `$ws = herdr workspace create ... | ConvertFrom-Json` and `--pane $ws.result.root_pane.pane_id` (see `remote-setup`, section 3).
5. Check: open the Claude app on the phone. "<me> orchestrator" shows there. Send it "what is open?".

## 2. Session start (each time the orchestrator starts)

1. [team] Run `skills/sync/sync.sh pull`. Say any held file in one line.
2. Read `users/<me>/orchestrator/ORCHESTRATOR.md`.
3. Run `herdr agent list`. For each row in "Active workers": `herdr agent get <name>`. `done` = finished. `blocked` = it waits for an answer or an approval.
4. Tell the person, short: what finished, what is blocked and why, what needs their answer. Nothing else.

## 3. Start a worker

1. Pick the folder:
   - Company-wide work: `<root>`.
   - Area work (finance, ops, apps, sales, marketing, admin...): `<root>/areas/<area>/`, so the worker reads that area's rules, memory and skills. Check the person has the area first. Work on a project: `<root>/areas/<area>/projects/<slug>/`.
   - Personal work (drafts, their own notes): `<root>/users/<me>/`.
2. Pick a name: it starts with a letter; lowercase letters, digits, `-` and `_`; up to 32 characters; unique (for example `fin-wip-check`).
3. Start it in its own tab:
   ```bash
   herdr tab create --workspace <workers workspace id> --cwd "<folder>" --label <name> --no-focus
   herdr agent start <name> --kind claude --pane <pane id from the output> --timeout 60000 -- --name "<name>"
   ```
4. If the start says `interactive_ready: true`, go to step 6.
5. If it says `agent_not_ready`, read the screen: `herdr agent read <name> --lines 40`.
   - **Folder trust** ("Do you trust the files in this folder?"): compare real paths, with links resolved. Mac or Linux: `realpath "<folder>"` and `realpath "<root>"`. Windows: `(Resolve-Path "<folder>").Path` and `(Resolve-Path "<root>").Path`. Answer yes (`herdr agent send-keys <name> Enter`, the first choice is yes) only when the folder path starts with the root path followed by `/` (`\` on Windows), or is the root itself, **and** the folder on the screen is that same folder. Then read the screen again.
   - Anything else, or a path outside the company folder: do not answer. Tell the person the worker name and the question.
6. Send the brief: `herdr agent prompt <name> "<the brief>"`. The brief says: the goal, what done looks like, where to write the result, and the limits (draft only, no sends, ask before deletes). For a long brief, write it to `users/<me>/orchestrator/briefs/` and tell the worker to read that file.
7. Add a row to "Active workers" in the orchestrator file: name, folder, task, date started.

## 4. Check, read, follow up

- Status: `herdr agent get <name>`. Wait for one: `herdr agent wait <name> --until done`.
- Read its recent output: `herdr agent read <name>`.
- Send a follow-up: `herdr agent prompt <name> "<text>"`.
- A blocked worker: read what it asks. If it is a permission or a send, bring it to the person with a one-line summary. Never answer it for them.
- Done: read the result. Give the person a two-line summary and where the result is. Ask before you close the tab (`herdr tab close <tab id>`). Move the row to "Finished" with the date.

## 5. What the orchestrator does itself

Short things only: answer a question from the files, plan, write a brief, check status, draft a reply. Anything longer than a few steps, or that needs an area's rules, goes to a worker.

## 6. When the person is away, and after a restart

- The orchestrator works only while its computer is on and awake. A laptop stops when it sleeps. An always-on computer keeps it running (`remote-setup`, section 4).
- After a restart, Herdr starts at sign-in and brings back its tabs and the Claude sessions (`remote-setup`, section 5; needs `herdr integration install claude`). Do the session start (section 2). A worker that did not come back: start it again from its brief.

## 7. Other AI apps

Only Claude Code can be the orchestrator today. Other AI apps cannot start or read Herdr workers: Herdr has no MCP server. Reach the orchestrator from the Claude app.
