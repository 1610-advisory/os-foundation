---
name: add-teammate
description: Turn on the team level and give teammates access to the company OS and only the areas they should see. Part A runs on the admin's computer and turns everything on in one run, or adds one person later. Part B runs on each teammate's computer. Use when someone says "add a teammate", "give {{PERSON}} access", "share this with my team", "set up {{PERSON}}'s computer", or a hand-off message sends a teammate here.
---

# Add a teammate

Access works by repo. A teammate gets the company repo, their own private workspace, and only the area repos they should see.

- **Part A** runs on the admin's computer. The first time, it turns on the team level. Later, it adds one person.
- **Part B** runs on the teammate's computer.

For each part: ask one question at a time, with a suggested answer. Write the answers file. Run the script. Explain the result in plain words.

The flags and answers-file keys are in `skills/add-teammate/CLI.md`. Use exactly those. Never put a password, token or key in the answers file or in the chat.

## Part A — on the admin's computer

### A1. Check first

1. Read `level:` in `company-profile.md`. `solo`: go on. `team` or `app`: go to A6.
2. The script refuses a company folder in a synced folder (iCloud Drive, Dropbox, OneDrive, Google Drive, Box). Help move it first.

### A2. Questions (one at a time)

1. **Git host.** Suggest GitHub. A company that runs its own Forgejo may use that.
2. **GitHub plan.** Say this plainly:
   > The team level needs a GitHub organization on the **Team plan** (paid). The Free plan cannot enforce review on private repos. On Free, any change could go into `main` with no check.

   No organization yet: help make one at github.com/organizations/new on the Team plan. Do not go on with a Free organization.
3. **Organization name.** The repos belong to the company, not to one person.
4. **Sign-in.** GitHub: the admin runs `gh auth login` and signs in in the browser. Forgejo: the token stays in the file `CLI.md` names, outside the folder.
5. **The people.** The admin first (`role` `admin`), then each teammate: full name; slug (suggest first name, lowercase); git host username; work email; role (`director` approves rules changes in their areas, else `writer`); areas (suggest the fewest that let them do their job); manager, optional (their bots go to the manager if they leave).
6. **Area directors.** Who approves each area's rules changes? Suggest the admin.
7. **The review key.** See A3.
8. **Nightly check engine.** Which AI does the admin use most? Suggest its headless command with a small model, for example `claude -p --model haiku`.

### A3. The review key

Every pull request gets a review by a second AI model before it merges. Ask for one key from a **second AI vendor**.

Tell the admin plainly how it is used:
- Only by the review check.
- It sends only the pull request under review: its title, its body and its diff. Nothing else.
- Each review is one model call, at that vendor's normal price.
- It is stored as an org secret on the git host. Never in a file.

No second-vendor key: use a key from the company's own AI vendor. Say plainly: "The review will use a different model from your own vendor. That review is weaker." No key at all: the check fails on every pull request and says how to add one.

**The admin enters the key, never you.** `team-on.sh` prints one command. The admin runs it in their own terminal (in Claude Code: type `!` and then the command):

```
skills/_host/host.sh set-secret OS_REVIEW_KEY
```

It asks for the key in a hidden prompt. Never read the key back.

### A4. Run it

1. Write the answers file, one `key=value` per line: `host`, `host_url` (Forgejo only), `org`, `sync_engine`, `admin_slug`; for each person `person.<slug>.name`, `.github`, `.email`, `.role`, `.areas` (comma list), `.manager`; for each area `area.<area>.director`.
2. Run `skills/add-teammate/team-on.sh --answers <file>`.
3. It prints `review-command:` with the key command. The admin runs it (A3). Then run `team-on.sh` again. It checks only that the secret exists. It prints `review: key-set`, or `review: weaker` when no key is set.
4. If it stops, read its message, fix the cause, and run it again. A second run changes nothing that is already done.

### A5. Explain what turned on

One line each:
- **Repos.** The company folder and each area are private repos on the host, with their history. Each person has a private workspace: only that person, their own AI and the admin can read it.
- **Review.** Nobody writes to `main`, the admin included. Each change goes by pull request. It merges when the checks pass: secret scan, `lint`, model review.
- **Rules files** (`AGENTS.md`, `CLAUDE.md`, `skills/`) also need their code owner: the area director, or the admin at the root. When the code owner is the author, the model review alone is enough, as for the admin's own rules change.
- **Level.** `company-profile.md` says `level: team`. The team rules in `AGENTS.md` now apply.
- **OS jobs here.** Pull every 15 minutes. Push at about 2 am after the nightly check. Then the nightly review, the daily "to decide" list and the weekly report.
- **Leaving.** `remove-teammate` and the device helper. Each person accepts `joining-terms.md` when they join.
- **Chat apps.** Cowork, ChatGPT and Grok users get `company-skills`, uploaded once per vendor account (see its `SKILL.md`).
- **Privacy.** `privacy.md` now lists the team places.

Then show the **hand-off message** the script printed for each teammate. The admin sends it. It holds no secrets.

### A6. Add one more person later

Ask A2 item 5 for the new person, and item 6 if they direct an area. Write the `person.<slug>.*` lines (and `area.<area>.director`). Run `skills/add-teammate/add-person.sh --answers <file>`. Their people page goes in by pull request. Show the hand-off message.

A new area later: run `add-area`.

## Part B — on the teammate's computer

### B1. Tools and sign-in

1. Check `git --version`. GitHub: also `gh --version`. Missing? Help install them (Mac: `brew install git gh`).
2. GitHub: the teammate runs `gh auth login` and signs in in the browser.
3. Accept the company's invites on the host.

### B2. Folder and clone

1. Ask for the folder. Suggest `~/{{COMPANY_SLUG}}-os`. Refuse a synced folder (iCloud Drive, Dropbox, OneDrive, Google Drive, Box).
2. Clone the company repo with their own sign-in. The org and repo name are in the hand-off message:
   ```
   git clone https://github.com/{{GITHUB_ORG}}/{{COMPANY_SLUG}}-os.git ~/{{COMPANY_SLUG}}-os
   ```
   Forgejo: use the host address from the hand-off message instead of `https://github.com`.

### B3. The joining terms

1. Show `joining-terms.md` from the clone. Show the whole page.
2. Name the two main points:
   - When they leave, a helper deletes the company folder from this computer. Only the company removing their access counts. Leave, holiday or an offline laptop never does.
   - They delete the copies outside the folder themselves: agent transcripts, backups, hand copies.
3. Point to `privacy.md`: every place a copy of company data sits.
4. Ask: "Do you accept these terms?" Yes: go on. They accept once, now. No: stop, and tell them to talk to the admin.

### B4. Run it

Only after a yes in B3.
1. **Slug.** It is in the hand-off message. Confirm it.
2. Write the answers file: `me=<slug>`.
3. From inside the clone, run `skills/add-teammate/join.sh --answers <file>`. It keeps the clone and goes on.
4. If it stops, read its message, fix the cause, and run it again.

### B5. Explain the result

One line each:
- **Folders.** The company folder, their workspace at `users/<slug>/`, and their areas. A `skipped:` area is one they have no access to. That is correct.
- **Who they are.** One small file, `~/.config/{{COMPANY_SLUG}}-os/me`, names them. The nightly push checks it against their git sign-in.
- **OS jobs.** Pull every 15 minutes. Push at about 2 am. A held file stays on this computer, and the next session says why.
- **Profile.** Their voice and preferences live in `users/<slug>/profile/PROFILE.md`. Claude Code, Codex and Pi (and Cursor, if it has a rules file) now load it in every session, read-only. Their AI keeps it current. They never have to.
- **Terms.** `terms: proposed` means their yes is recorded on their people page, by pull request.
- **Where to start.** "For {{AREA_SLUG}} work, open your agent in `~/{{COMPANY_SLUG}}-os/areas/{{AREA_SLUG}}/`. General work: `~/{{COMPANY_SLUG}}-os/`."
- **Changes.** Notes go up each night by themselves. They need not know git.

## Rules for this skill

- Nobody writes to `main`, the admin included. Never write or say otherwise.
- No step after setup needs a person in the daily path.
