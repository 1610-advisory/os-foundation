---
name: kernel-cli
description: >
  Use the company kernel from the terminal with the `ops` command: find a named request,
  read its input, run it as yourself, behind the same locks and audit log as the app and
  the connector. Use when a git user in Claude Code (or a similar agent) asks to "look up a
  customer", "add a job", "what is on my day", "run <request>", "check the CRM", or any
  question about live records, and `level:` in company-profile.md is `app`.
---

# Kernel CLI

The kernel is the company's one door to live records (customers, jobs, datasets). The `ops` command talks to it as **you**: same sign-in, same locks, same audit log as the app screens and the AI connector. It sees nothing more than you may see.
Use it for records. Notes, SOPs and decisions stay in this folder (markdown). Never copy records from `ops` into notes; add its key to the note's `records:` list (for example `"crm:job:J-1042"`) instead.

## 1. Check it is there

1. `company-profile.md` says `level: app` (the company has a kernel). If not, the company has no kernel: stop and say so.
2. `ops --help` runs. If not, ask the admin how to install it for this computer. Do not install it from another source.
3. Signed in: `ops commands` lists requests. If it says you are not signed in, the person runs `ops login` in their own terminal. Never ask for a token in chat, and never put a token in a file, a command line or a log.

## 2. Find, read, run

1. **Find:** `ops commands` lists every request your sign-in may call. Search it for the job (`ops commands | grep -i job`).
2. **Read:** `ops describe <name>` shows the input, the output and an example. Read it before the first call of a request in this session.
3. **Run:** `ops <name> --flag value` (flags come from the input), or `ops <name> --input '<json>'` for the whole input. Add `--output json` when you will read the answer in code.

Kinds of request:
- **read:** run it.
- **write:** say in one line what will change, then run it. Use `--dry-run` first when the change is large or you are not sure.
- **risky** (archive, merge, bulk change, sends something outside): ask the person first. The kernel may answer "waiting for approval" (exit 2). Give the person the link. Do not run it again to get around it. A `risky` request of a built tool is refused until kernel approvals ship.

## 3. Exit codes

| Code | Means | Do |
|---|---|---|
| 0 | Done, or a preview | Report the result. |
| 2 | Waiting for approval | Give the link. Stop. |
| 3 | Bad input | Read `ops describe <name>` and fix the input. |
| 4 | Not signed in, or not allowed | Sign-in: the person runs `ops login`. Not allowed: say so. Never try another way in. |
| 5 | Conflict (someone changed the record) | Read the record again, then ask. |
| 1 | Other | Show the error line. Do not retry in a loop. |

## 4. Rules

- A refusal is the answer. Do not look for the record another way (a copy, an export, another person's sign-in).
- Never paste record lists, personal details or exports into notes, chat logs or commits. Quote only what the person needs, and give the "as of" time.
- For one request that changes many records, ask first, even if it is not marked risky.
- Retry a write only with the same `--idempotency-key`, so it does not run twice.
- A request you need is missing: say so, and say which tool should own it. Do not work around it with direct file access.
