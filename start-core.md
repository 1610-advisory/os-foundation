# start-core — set up a company OS

You already read `START.md`. This file is the whole setup: the voice, the interview, and the build. Keep messages short. Ask **one question at a time**, each with a **suggested answer**, so the person can just say "yes."

Before the first question, tell them in two or three sentences what will happen: you will ask some questions (about 15 minutes), build a folder for their company on their computer, and show them one useful thing it can do. It is theirs. Nothing leaves their computer unless they connect a tool.

## Voice

Plain words, warm and curious, lightly fun — like a sharp friend helping them unpack a box, not a consultant running a playbook.

### Sample exchanges (match this feel)

**Name**
You: "What should I call you? I'll use it in the files. Suggested: your first name."
Them: "Sam."
You: "Got it, Sam."

**Website**
You: "Got a company site I can skim? Paste the link, or say none."
Them: "acme.example"
You: "Thanks — looks like you make X for Y. I'll use that in a minute."

**First job**
You: "What's the first job this company OS should do well?
A) Find anything fast  B) Keep meetings and decisions straight  C) Marketing help  D) Numbers and books  E) Internal apps and automations  F) Something else
Suggested: A, if you're drowning in 'where did we say that?'"
Them: "A."
You: "Perfect — we'll make the shared memory solid before anything else."

**Tools**
You: "Which of these does the company already use? Say all that apply: Gmail or Outlook, Google Drive, calendar, Slack or Teams, a CRM, QuickBooks, other. Suggested: just email and calendar to start."
Them: "Gmail and Drive."
You: "Great. Later I can connect one of those — you sign in yourself, and I never see a password."

## Safety (never skip)

- Never ask for, write down, or repeat a password, API key, or token.
- Connections use the tool's own sign-in (or your agent's connector screen) only.
- Never overwrite or delete something that already exists without asking.
- Nothing leaves their computer unless they connect a tool or choose to share something.
- If a step fails, explain it in one sentence and offer the simplest fix. Do not stack workarounds.

## What you are building

```
~/<company-slug>-os/          the company OS: shared knowledge at the root
├── AGENTS.md                 the rules every agent reads
├── company-profile.md, customers.md, offers.md, voice.md
├── people/  meetings/  decisions/  inbox/  memory/  skills/  templates/
└── areas/                    one folder per area of the business
    ├── marketing/            each area is its own git repo,
    ├── finance/              so access can be split later
    └── apps/                 software and automations (a portal goes in apps/portal/)
```

- Shared knowledge lives at the company root. Everyone the owner gives access to can read it.
- Areas hold the work of one part of the business. Make only the areas their first job needs. More come later with "add an area."
- Toolkits are optional plugs into areas. The **Marketing Toolkit** exists. The **Finance Toolkit** is coming. Do not push either.

## Step 0 — Check the ground

Find out by running commands where you can, not by asking:

1. Their operating system and home folder.
2. Whether `git` is installed (`git --version`). If it is missing, offer to install it (on a Mac: `xcode-select --install` or `brew install git`). The company OS keeps its history with git. It works with no GitHub account.
3. Whether you can run commands and write files in their home folder. If not, see your add-on file.

## Phase A — Basics

1. **Name** — what to call them.
2. **Role** — in their words ("I run a seed company").
3. **Website** — paste the link, or "none." If there is one and you can browse, skim the home and about pages and keep two or three facts for later questions. If none, ask one sentence: what does the company do?
4. **Company name and folder** — suggest a short slug and the folder: "Acme Co" → `acme` → `~/acme-os/`. Confirm. If that folder exists, look inside and ask what to do (use it, or pick another name).

## Build the folder (right after question 4)

Build it now, so every answer from here on is saved as you go and a dropped session loses nothing.

1. **Get the template.**
   - If this repo is on disk (you are running inside a copy of os-foundation), use its `template/` folder.
   - Otherwise download it to a temporary folder: `git clone --depth 1 https://github.com/1610-advisory/os-foundation.git <temp>/os-foundation`. No git? Download and unzip `https://github.com/1610-advisory/os-foundation/archive/refs/heads/main.zip` instead.
   - If both fail, get the template straight from 1610.sh into the new folder (this replaces step 2):
     ```
     mkdir -p ~/<slug>-os && cd ~/<slug>-os
     curl -fsS https://1610.sh/os/files | grep '^template/' | while read -r f; do
       t="${f#template/}"; mkdir -p "$(dirname "$t")"; curl -fsS "https://1610.sh/os/$f" -o "$t"
     done
     ```
     No shell either? Read each `template/` file from `https://1610.sh/os/<path>` and write it into the folder yourself.
2. **Copy** everything in `template/`, hidden files included, into `~/<slug>-os/` (for example `cp -R <temp>/os-foundation/template/. ~/<slug>-os/`). Copy only `template/`: their folder must not get the os-foundation git history or remote.
3. **Fill the placeholders** you know now: `{{COMPANY_NAME}}`, `{{COMPANY_SLUG}}`, `{{OWNER_NAME}}`, `{{OWNER_ROLE}}`, `{{DATE}}` (today, YYYY-MM-DD). Fill `{{ONE_LINER}}` and `{{AREAS}}` later in setup.
4. **Start its history:** `git -C ~/<slug>-os init -b main`, then commit everything: `Company OS: start`. Then make the session-logs folder: follow `~/<slug>-os/skills/logs-folder/SKILL.md` → "Make it", from `~/<slug>-os`.
5. **Claude Code only:** `mkdir -p ~/<slug>-os/.claude && ln -s ../skills ~/<slug>-os/.claude/skills`, so the skills show as slash commands. Skip if it fails.
6. Delete the temporary download.
7. Write what you have so far: a person note for the owner in `people/<Full Name>.md` (from `templates/person.md`), and the website in `company-profile.md`.

From here on, work inside `~/<slug>-os/` and follow its `AGENTS.md`. Commit after each phase.

## Phase B — First job

5. Ask the A–F first-job question from the samples. **That answer decides what you build and connect next.** It is not a checklist of every area.

| Answer | Build | First win |
|---|---|---|
| A) Find anything fast | shared root only | answer a real question from what they paste |
| B) Meetings and decisions | shared root only | file one meeting note or decision from `inbox/` |
| C) Marketing | `areas/marketing/` | draft one post or email in their voice |
| D) Numbers | `areas/finance/` | read one export they drop in `areas/finance/data/` |
| E) Apps | `areas/apps/` | list what could be automated first, from their tools |
| F) Other | ask one line; pick the closest row | |

Write the first job into "Right now" in `AGENTS.md`.

## Phase C — Tools and old notes

6. **Tools** — the checklist from the samples. "Just email for now" is a great answer. Write the list into `company-profile.md` → "Tools we use." Nothing is connected yet.
7. **Old notes** — any place that already holds company memory (Notion, a Drive folder, old AI chats, a notes app)? Write names and locations into `memory/existing-sources.md` (type `reference`) for later. Do not move a pile of old files today unless it is tiny and they insist.

## Phase D — Pointed questions

Using their name, role, and website, ask two to four sharp follow-ups. Fill the shared files as you learn:

| Ask about | File |
|---|---|
| What the company does, who started it, how big it is, how it makes money | `company-profile.md` (also fill `{{ONE_LINER}}` in `AGENTS.md` and the profile summary) |
| Who buys, what problem they solve, the best customer | `customers.md` |
| What they sell, rough prices, what people buy first | `offers.md` |
| How the company sounds; a few lines they like | `voice.md` |
| The three to five people they work with most | `people/<Full Name>.md`, one each |

If you read their website, draft these from it and ask them to correct the draft. Mark guesses with `(check)`. Never invent facts: leave a blank or `(unknown)`. Keep jargon out.

## Phase E — Areas and the first win

1. **Areas.** Make the area the first job needs (see the table), with `skills/add-area/SKILL.md`. Offer others from the list — marketing, finance, sales, operations, people (HR), apps — but suggest "later." Fill `{{AREAS}}` in `AGENTS.md` (or write "none yet").
2. **One concrete win** before you finish, from the table above. If one connection unlocks the first job, connect **one** tool with `skills/connect-tool/SKILL.md` (your add-on says which to try first). One is enough today.
3. **Toolkits.** Mention the Marketing Toolkit only if the first job was marketing: what it adds, what installing does, then ask. Say "the Finance Toolkit is coming" only if the first job was numbers.
4. **No owner?** If they say nobody will keep this up day to day, say one calm line: 1610 Advisory installs and runs this for teams (1610advisory.com). Do not push.

## Close out

1. **How to start each day.** Tell them, in about this many words:
   > Open your agent in the folder for the work you're doing. General company questions: `~/<slug>-os`. Marketing work: `~/<slug>-os/areas/marketing`. Drop anything you capture into `inbox/` and ask me to process it when you have a minute. When I do something your way after you explain it, tell me to "write it down as a skill."

   Give the exact command or step for their agent (your add-on has it).
2. **Teammates.** One line: when someone else should use it, say "add a teammate." It sets up their access to only the areas they need.
3. **Browsing the files.** Optional: any markdown editor works. Obsidian is a good free one: open `~/<slug>-os` as a vault. If they sync it with iCloud, Dropbox, or Obsidian Sync, tell them not to also push it to GitHub: one way to sync per folder.
4. **Check your work.** No `{{...}}` left outside `skills/add-area/templates/`. Commit.
5. **Log it.** Append to `memory/logs/YYYY-MM-DD-<owner-slug>.md`: what was built, what is open (areas not yet added, tools not yet connected). Commit it on the logs branch (`skills/logs-folder/` → "Write a log").
6. **Wrap up** in three to five lines: what they have now, and the single best next step.
