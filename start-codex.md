# start-codex — add-on for Codex

Read `start-core.md` first. This file only adds Codex steps.

## Connections

Codex may not have Gmail or Calendar connectors on their computer. After the tools question:

1. Prefer a **file win** first: they paste an email, notes, or an export into `inbox/`, and you run `ingest`.
2. If they want email or files connected next, use a connector Codex supports on their computer (`codex mcp --help`). Their sign-in only. **Never** put a token in the chat or a file.
3. Be plain about limits: "I can build the folder and the memory now. Connecting email may be a next step on your setup."

## Commands for "how to start each day"

`cd ~/{{COMPANY_SLUG}}-os && codex` (or `cd ~/{{COMPANY_SLUG}}-os/areas/marketing && codex` for marketing work).

## The paste prompt

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
