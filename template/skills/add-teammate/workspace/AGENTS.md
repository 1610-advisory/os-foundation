# {{FULL_NAME}} — workspace at {{COMPANY_NAME}}

This is the private workspace of **{{FULL_NAME}}** (`{{PERSON_SLUG}}`) at {{COMPANY_NAME}}. It is its own git repo, `{{COMPANY_SLUG}}-user-{{PERSON_SLUG}}`. On a computer it sits at `users/{{PERSON_SLUG}}/` in the company folder. The company repo ignores it.

The company rules (`../../AGENTS.md`) apply here too. Read them if your agent did not load them. Company rules come first.

## Who reads it

- {{FULL_NAME}}.
- Their own AI.
- The admin.

No one else. No other person, and no other person's AI.

## It belongs to the company

This workspace is the company's, like the rest of the OS. When {{FULL_NAME}} leaves, the company keeps it, archived. Only the admin can read it then.

So: **no personal-life facts** here. No health, family, home, beliefs or money troubles. Never write them anywhere.

## What goes where

| What | Where |
|---|---|
| Voice, writing samples, preferences, how the person works | `profile/` (start at `profile/PROFILE.md`) |
| Drafts and work in progress | `drafts/` |
| Sensitive work and private sources (DMs, a personal mailbox, 1:1s, HR, pay) | Here. Tag the note `source: private`. |
| How to work with this person, notes to self | `memory/` |
| What you did in this workspace today | `memory/logs/YYYY-MM-DD-{{PERSON_SLUG}}.md` |
| The person's own skills | `skills/<name>/SKILL.md` |
| Company facts others need | The area, as a plain fact (company rules, section 4). Not here. |

## Sharing is the person's choice

- Drafts and sensitive work stay here until the person shares them.
- Never move a draft, a note or a skill out of this workspace by yourself.
- You may ask once: "Share this?" If they say no, or say nothing, it stays here.
- When the person says yes, write it to the area as a plain fact. No quotes from a private source. No "X said in a DM".
- A skill they want to share goes to the company by its own PR: `../../skills/sync/sync.sh propose <topic> <file>...`.

## The profile

- `profile/PROFILE.md` is the entry file. Read it first. Open the other files in `profile/` only when the task needs them.
- Every session the person starts loads it read-only. Setup wrote one pointer line in the agent's own settings.
- You keep it current. The person never has to. When the person corrects your style, or you learn how they like to work, update it.
- No company facts in it: no company names, numbers or customer details. The nightly check holds a profile that has them.
- Notes on how to work with this one company go in `memory/`, not in the profile.

## How it is saved

- No pull request. Each night the `sync` job pushes this repo to its own `main`.
- Before the push, it runs the secret scan and the personal-facts check. A file that fails stays on the computer. The next session tells the person why.
- Rules files here are the person's own. They need no approval.

## Folder units

A unit that may grow is a folder with an entry file in capitals: `profile/PROFILE.md`, `skills/<name>/SKILL.md`. Read the entry file first. Notes stay single files.
