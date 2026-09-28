# START — set up an AI operating system

**You are an AI agent. A person asked you to follow this file.** Walk them through it step by step. They may not be technical. Use plain words, keep each message short, and ask **one question at a time**. Give a suggested answer with each question so they can just say "yes."

Before step 1, tell them in two or three sentences what will happen: you will make one folder on their computer (`~/os`), interview them for about 10 minutes, build a folder for their company, and help them connect one or two tools. Nothing leaves their computer unless they connect a tool.

## Rules while you do this

- Never overwrite or delete a file that already exists. If something is in the way, stop and ask.
- Never ask for, write down, or repeat a password, API key, or token. Connections use the tool's own sign-in.
- If you cannot run commands (for example, a chat app with no file access), say so and give them the manual steps instead: download the zip from `https://github.com/1610-advisory/os-starter/archive/refs/heads/main.zip`, unzip it to a folder named `os` in their home folder, then open that folder in an agent that can edit files.
- If a step fails, explain it in one sentence and offer the simplest fix. Do not stack workarounds.

## Step 1 — Check the ground

Find out (by running commands where you can, not by asking):

1. Which agent you are (Claude Code, Claude Desktop/Cowork, Codex, Cursor, other).
2. Their operating system and home folder.
3. Whether `git` is installed (`git --version`).
4. Whether `~/os` already exists.

If `~/os` exists: look inside. If it is this starter already, skip step 2 and go to step 3 below. If it holds something else, ask where to put the new OS (suggest `~/os-work`). Use that path everywhere below where this file says `~/os`.

If they already use an Obsidian vault or notes folder, ask if they want to keep it separate (simplest) or move it into `~/os/wiki/` later. Do not move anything now.

## Step 2 — Get the starter

If you are already running inside a copy of this repo, skip this step.

With git:

```
git clone https://github.com/1610-advisory/os-starter.git ~/os
```

Without git: download and unzip the zip link above into `~/os`.

## Step 3 — Make it theirs

Always run this step, even if you skipped step 2. If `~/os/.git` exists and `git -C ~/os remote get-url origin` points at `os-starter`, delete `~/os/.git` so the folder is theirs and not a copy of the starter. (Their company folders can become their own git repos later. See `system/skills/add-company/SKILL.md`.)

Some agents ask permission before deleting a folder. That is expected. Tell the person what you are deleting and why, and ask them to approve it.

## Step 4 — Continue inside the folder

From here on, read and follow the files inside `~/os`. The next steps live in `~/os/system/skills/setup/SKILL.md`. Read it now and continue there.
