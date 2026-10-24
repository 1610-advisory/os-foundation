---
name: add-teammate
description: Turn on the team level and give teammates access to the company OS and only the areas they should see. Part A runs once on the admin's computer and turns everything on in one run. Part B runs on each teammate's computer. Also adds one more person later. Use when someone says "add a teammate", "give {{PERSON}} access", "share this with my team", "set up {{PERSON}}'s computer", or a hand-off message sends a teammate here.
---

# Add a teammate

Access works by repo. The company folder is one private repo. Each area is its own private repo. Each person gets one private workspace repo. A teammate gets the company repo, their workspace, and only the area repos they should see. Areas they do not get are never on their computer.

Two parts:
- **Part A** runs on the admin's computer. The first time, it turns on the team level. Later, it adds one person.
- **Part B** runs on the teammate's computer.

How to run each part:
- Ask one question at a time. Give a suggested answer with each question.
- Write the answers to a file. Never put a password, token or key in it.
- Run the script with that file.
- Explain the result in plain words. The person need not know git.

The flags and the answers-file keys are in `skills/add-teammate/CLI.md`. Use exactly those.

## Part A — on the admin's computer

### A1. Check first

1. Read `level:` in `company-profile.md`.
   - `solo`: this run turns on the team level. Go on.
   - `team` or `app`: the team level is on. Go to A6 (add one person).
2. Check where the company folder is. It must not be in a synced folder: iCloud Drive, Dropbox, OneDrive, Google Drive, Box. The script refuses one. If it is in one, say so and help move it first.

### A2. Questions (one at a time)

1. **Git host.** Suggest GitHub. A company that runs its own Forgejo may use that.
2. **GitHub plan.** Say this plainly:
   > The team level needs a GitHub organization on the **Team plan** (paid). The Free plan cannot enforce review on private repos. On Free, any change could go into `main` with no check.

   If they have no organization, help them make one at github.com/organizations/new and pick the Team plan. Do not go on with a Free organization.
3. **Organization name.** The repos belong to the company, not to one person.
4. **Sign-in.** GitHub: the admin runs `gh auth login` and signs in in the browser. Never handle a password or token. Forgejo: the token stays in its file outside the folder (`CLI.md` names it).
5. **The people.** For each teammate, one at a time:
   - full name, and a slug (suggest first name, lowercase),
   - git host username (they can make a free account),
   - work email,
   - role: `director` (approves rules changes in their areas) or `writer`,
   - areas. Suggest the fewest areas that let them do their job.
6. **Area directors.** For each area, who approves its rules changes? Suggest the admin.
7. **The review key.** See A3.
8. **Nightly check engine.** Which AI does the admin use most? Suggest the headless command for it, for example `claude -p --model haiku` for Claude. Codex and Pi have their own (`codex exec`, `pi -p`) with a small model.

### A3. The review key

Every pull request gets a review by a second AI model before it merges. Ask for one key from a **second AI vendor** (a vendor the company does not use for its main work). Pay-as-you-go is enough.

Tell the admin plainly how the key is used:
- Only by the review check.
- It sends only the pull request under review: its title, its body and its diff. Nothing else from the company.
- Each review is one model call. It costs what one short call to that model costs, at that vendor's normal price.
- The key is stored as an org secret on the git host. It is never written to a file in the folder.

No second-vendor key: ask for a key from the company's own AI vendor. Then say plainly:
> The review will use a different model from your own vendor. That review is weaker than one from a second vendor.

No key at all: the check fails on every pull request and says how to add a key. Say so.

Never ask for the key in the chat. The admin enters it themselves, the way `CLI.md` says (a hidden prompt or a file outside the folder). Never read it back.

### A4. Run it

1. Write the answers file (keys from `CLI.md`).
2. Run `skills/add-teammate/team-on.sh --answers <file>`.
3. If it stops, read its message. Fix the cause. Run it again. It is safe to run twice: a second run changes nothing that is already done.

### A5. Explain what turned on

Tell the admin, one line each:
- **Repos.** The company folder and each area are now private repos on the host, with their full history. Each person has one private workspace repo. Only that person, their own AI and the admin can read it.
- **Review rule.** On every repo, nobody writes to `main`. The admin is included. Each change goes by pull request. It merges when the checks pass: the secret scan, `lint` and the model review.
- **Rules files.** Changes to `AGENTS.md`, `CLAUDE.md`, `skills/` and the like need their code owner (`CODEOWNERS`). Area: the area director. Company root: the admin. When the code owner is the author, the model review alone is enough. So the admin's own rules change merges on the model review.
- **Level.** `company-profile.md` now says `level: team`. The team rules in `AGENTS.md` now apply (approval tiers, the standing pull request).
- **OS jobs on this computer.** Pull every 15 minutes. Push each night at about 2 am, after the nightly check. Then the nightly review, the daily "to decide" list and the weekly report.
- **Teammates.** `remove-teammate` and the device helper. Each person accepts `joining-terms.md` when they join.
- **Chat apps.** People who use Claude Cowork, ChatGPT or Grok in a chat app get `company-skills`. Upload it once per vendor account (see `skills/company-skills/SKILL.md`).
- **Privacy.** `privacy.md` now lists the team places. Run `skills/privacy/privacy.sh` if the script did not.

Then show the **hand-off message** the script printed for each teammate. The admin sends it. It holds no secrets.

### A6. Add one more person later

1. Ask the questions in A2, item 5, for the new person.
2. Run `skills/add-teammate/add-person.sh --answers <file>`.
3. Show the hand-off message.

A new area later: run `add-area`. At the team level it also gets its repo, its team, its `CODEOWNERS` and its place in the ruleset.

## Part B — on the teammate's computer

The hand-off message sent the teammate here.

### B1. Tools and sign-in

1. Check `git --version`. GitHub companies: also `gh --version`. Missing? Help install them (on a Mac, `brew install git gh`; otherwise the official installers).
2. GitHub: the teammate runs `gh auth login` and signs in in the browser. Never handle a password or token.
3. Accept the invites from the company on the host.

### B2. The joining terms

1. Read `joining-terms.md` from the company repo on the host. Show the whole page.
2. Name the two main points:
   - When they leave, a helper deletes the company folder from this computer. Only the company removing their access counts. Leave, holiday or a dead laptop never does.
   - They delete the copies outside the folder themselves: agent transcripts, backups, hand copies.
3. Give the link to `privacy.md`: the list of every place a copy of company data sits.
4. Ask: "Do you accept these terms?"
   - Yes: go on. They accept once, now. Nothing is asked when they leave.
   - No: stop. Tell them to talk to the admin.

### B3. Questions (one at a time)

1. **Your slug.** It is in the hand-off message. Confirm it.
2. **Folder.** Suggest `~/{{COMPANY_SLUG}}-os`. Refuse a synced folder (iCloud Drive, Dropbox, OneDrive, Google Drive, Box).
3. **Agents.** Which AI tools do you use here: Claude Code, Codex, Cursor, Pi?

### B4. Run it

1. Write the answers file (keys from `CLI.md`). It records that they accepted the terms.
2. Run `skills/add-teammate/join.sh --answers <file>`. Before the clone, the script is not on this computer yet: run it from the copy `CLI.md` names.
3. If it stops, read its message, fix the cause, run it again.

### B5. Explain the result

One line each:
- **Folders.** The company folder, your workspace at `users/<you>/`, and your areas. An area that said "not found" is one you have no access to. That is correct.
- **Who you are.** One small file on this computer (`~/.config/{{COMPANY_SLUG}}-os/me`) names you. The nightly push checks it against your git sign-in.
- **OS jobs.** Pull every 15 minutes. Push each night at about 2 am. A file the nightly check holds stays on this computer. Your next session says why.
- **Your profile.** Your voice and preferences live in `users/<you>/profile/PROFILE.md`. Each agent you named now loads it in every session, read-only. Your AI keeps it current. You never have to.
- **Where to start.** "For {{AREA_SLUG}} work, open your agent in `~/{{COMPANY_SLUG}}-os/areas/{{AREA_SLUG}}/`. General work: `~/{{COMPANY_SLUG}}-os/`."
- **Changes.** Your notes go up each night by themselves. A rules change goes to its owner for approval. You need not know git.

## Rules for this skill

- Nobody writes to `main`, the admin included. Never write or say otherwise.
- Never handle a password, token or key in the chat or in a file in the folder.
- Never make a repo public.
- No step after setup needs a person in the daily path.
