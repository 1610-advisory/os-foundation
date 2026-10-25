---
name: company-skills
description: For chat apps with no company folder (Claude Cowork, ChatGPT, Grok). Reads {{COMPANY_NAME}}'s rules and skills from the company repo on GitHub, with the person's own read access, and follows them. When the chat makes something for the repo, writes a short task to paste into a local agent. Use for any {{COMPANY_NAME}} work in a chat app, or when someone asks "how do we do X here" or "use our company skills".
---

# Company skills

You run in a chat app. You have no company folder. The company's rules and skills live in its repo on GitHub. Read them from there each time.

Repo: `{{GITHUB_ORG}}/{{COMPANY_SLUG}}-os`, branch `main`.

## Before you start

1. Use the read-only GitHub connector of this chat app. It uses the person's own GitHub sign-in. Use nothing else.
2. No GitHub connector, or "not found" on the company repo: say so in one line. The person may be a reader with no GitHub seat. Tell them to ask the admin. Stop.

## Each task

1. Read `AGENTS.md` in the company repo. It holds the company rules. Follow them.
2. Read `level:` and `switches:` in `company-profile.md`. Skip rules for a higher level or a switch that is off.
3. List `skills/`. Find the skill that matches the task. Read its `SKILL.md`. Follow it. Company rules come before a skill's own steps.
4. Area work: read the area repo `{{GITHUB_ORG}}/{{COMPANY_SLUG}}-<area>`. Read its `AGENTS.md` and its `skills/`.
   - "Not found" means the person has no access to that area. That is correct. Do not try another way. Say so in one line.
5. The person's voice: read `profile/PROFILE.md` in their own workspace repo `{{GITHUB_ORG}}/{{COMPANY_SLUG}}-user-<person>`. Find `<person>`: the `slug:` on the page in `people/` whose `github:` matches the signed-in account. Read it only. Never read another person's workspace.

Read fresh each time. Skills change. Do not rely on an old copy in your memory.

## You cannot write to the repo

This chat app reads only. When the chat makes something for the repo (a note, a fact, a fixed skill, a file), write a **task** the person pastes into their local agent (Claude Code, the Codex app, Cursor or Pi). Use this shape:

```
Task for the {{COMPANY_NAME}} company OS.
Read AGENTS.md first.
Goal: <one line>
Repo and folder: <company root, or areas/<area>/, or users/<person>/>
Files: <paths>
Change: <the exact text to write, or the exact change>
Done when: <one line>
```

- Put the exact text in the task. The local agent should not need this chat.
- A rules or skill change: read `level:` in `company-profile.md` first.
  - `solo`: there are no pull requests. Add "Edit the file and commit it on main."
  - `team` or `app`: add "Propose it with skills/sync/sync.sh propose <topic> <file>...". Nobody writes to `main`.
- No secrets in the task. No quotes from a private source. No personal-life facts.

Tell the person in one line: "Paste this into your local agent in the company folder."

## Rules that always hold

- **One company only.** Use only this company's repos. Never mix in another company's data.
- **No secrets.** Never write a password, key or token. If you see one, stop and tell the person.
- **Private sources** (DMs, a personal mailbox, 1:1s, HR, pay) stay private. Only plain facts go to an area task.
- **No personal-life facts** anywhere.
- **Ask first** before you send, post, publish, pay or delete anything.

## For the admin: upload it once

Upload this skill once to each chat vendor account the company uses (Claude, ChatGPT, Grok). It does not change when the company's skills change, so one upload is enough.

The admin's local agent makes the upload copy. No script does it.
1. Copy this folder to a temporary folder outside the company folder. Never edit the company's own copy.
2. In the copy, fill the three names from `company-profile.md`:
   - `{{GITHUB_ORG}}`: the `org:` value (`skills/_host/profile.sh org`).
   - `{{COMPANY_SLUG}}`: the `company_slug:` value (`skills/_host/profile.sh company_slug`).
   - `{{COMPANY_NAME}}`: the title line at the top of `company-profile.md`.
3. Check that no `{{` is left in the copy. Delete the "For the admin" section from the copy.
4. Upload the copy in the vendor's skills settings. Then delete the temporary folder.
5. Each person who uses that chat app connects GitHub in it, with their own account.

GitHub only. A company on Forgejo has no chat connector: those people use a local agent.
