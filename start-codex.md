# start-codex — add-on for Codex

Read `start-core.md` first. This file only adds Codex steps. You are Codex. In the close-out, say Codex.

The first launch may ask them to update, to trust the folder, and to review hooks. They approve trust once. Copy the template as `start-core.md` describes. Do not write a build script.

## Connections

Codex may not have Gmail or Calendar connectors on their computer. After the tools question:

1. Prefer a **file win** first: they paste an email, notes, or an export into `inbox/`, and you run `ingest`.
2. If they want email or files connected next, use a connector Codex supports on their computer (`codex mcp --help`). Their sign-in only. **Never** put a token in the chat or a file.
3. If a connector fails to start, say so in one sentence and use the file win.
4. Be plain about limits: "I can build the folder and the memory now. Connecting email may be a next step on your setup."

## Commands for "how to start each day"

`cd "{{COMPANY_OS}}" && codex` (or `cd` into the area folder, then `codex`). `{{COMPANY_OS}}` is the folder you agreed in `start-core.md`.

## The paste prompt

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```
