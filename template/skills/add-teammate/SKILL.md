---
name: add-teammate
description: Turn on the team level and give teammates access to the company OS and only the areas they should see. Part A on the admin's computer, Part B on each teammate's. Use when someone says "add a teammate", "give {{PERSON}} access", "share this with my team", "set up {{PERSON}}'s computer", or a hand-off message sends a teammate here.
---

# Add a teammate

Access works by repo. A teammate gets the company repo, their own private workspace, and only the area repos they should see. **Part A** runs on the admin's computer: the first time it turns on the team level; later it adds one person. **Part B** runs on the teammate's computer.

For each part: ask one question at a time, with a suggested answer. Write the answers file (flags and keys: `skills/add-teammate/CLI.md`). Run the script. Explain the result in plain words. Never put a password, token or key in the answers file or in the chat.

## Part A — on the admin's computer

### A1. Check first

1. Read `level:` in `company-profile.md`. `solo`: go on. `team` or `app`: go to A6.
2. The script refuses a synced folder (iCloud Drive, Dropbox, OneDrive, Google Drive). Help move it first.

### A2. Questions (one at a time)

1. **Git host.** Suggest GitHub. A company may use its own Forgejo. Say plainly: there the code-owner review is weaker; a person who can merge can remove the review request.
2. **GitHub plan.** Say this plainly:
   > The team level needs a GitHub organization on the **Team plan** (paid). The Free plan cannot enforce review on private repos. On Free, any change could go into `main` with no check.

   No organization yet: help make one at github.com/organizations/new on the Team plan. Do not go on with a Free organization.
3. **Organization name.** The repos belong to the company, not to one person.
4. **Sign-in.** GitHub: the admin runs `gh auth login` in the browser. Forgejo: the admin puts their token in `~/.config/{{COMPANY_SLUG}}-os/forgejo-token` (mode 600). Never you.
5. **The people.** The admin first (`role` `admin`), then each teammate: full name; slug (suggest first name, lowercase); git host username; work email; role (`director` approves rules changes in their areas, else `writer`); areas (suggest the fewest that let them do their job); manager, optional (their bots go to the manager if they leave).
6. **Area directors.** Who approves each area's rules changes? Suggest the admin.
7. **Nightly check engine.** Which AI does the admin use most? Suggest its headless command with a small model, for example `claude -p --model haiku`.

### A3. The review key

Every pull request gets a review by a second AI model before it merges. Ask for one key from a **second AI vendor**.

Tell the admin plainly: only the review check uses it. It sends only the pull request under review (title, body, diff), nothing else. Each review is one model call, at that vendor's normal price. It is an org secret on the git host, never a file. Anyone who can push a branch can read it: the git host works that way. So use a key made only for this review, with a spend cap, and rotate it when someone leaves.

Ask, one at a time:
1. **Which vendor is the key from?** `anthropic`, `openai` or `xai`.
2. **Is that the company's own AI vendor?** No: `second-vendor` (suggested). Yes: `same-vendor`; say plainly: "Weaker review: same vendor."

No key at all: say plainly: "No review key: every pull request fails the model review until you add one." Nothing merges until then.

**The admin sets the key, never you.** Best before `team-on.sh` runs. In their own terminal window, in the company folder, they run this line. It runs `skills/_host/host.sh set-secret OS_REVIEW_KEY` and hides the key. Fill `<host>` and `<org>` (Forgejo: add `OS_HOST_URL=<url>`):

```
printf 'Review key: '; read -rs k; echo; printf '%s' "$k" | OS_HOST=<host> OS_ORG=<org> skills/_host/host.sh set-secret OS_REVIEW_KEY; unset k
```

Never run it for them, ask for the key in the chat, or read it back.

### A4. Run it

1. Write the answers file from A2 and A3, with `review_vendor` and `review_kind` (`review_model` only if the admin names one). Never the key.
2. Run `skills/add-teammate/team-on.sh --answers <file>`. It writes `.github/review.conf` (vendor, model, kind) for the review check.
3. It checks that the key exists (`host.sh secret-exists`). Read its review line to the admin as printed:
   - `no review key: every pull request fails the model review until you add one`: the admin sets the key (A3), then run `team-on.sh` again.
   - `weaker review: same vendor`: say it plainly. The key works.
4. If it stops with an error, tell the admin the exact message. Fix the cause it names (if it names `sync.sh propose`, propose those files), then run it again once. A second run changes nothing already done. If it stops again, stop. Do not say the team level is on.

### A5. Explain what turned on

One line each:
- **Repos.** Company and areas are private repos on the host, with history. Each person has a private workspace (that person, their AI, the admin).
- **Review.** Nobody writes to `main`, the admin included. Changes go by pull request and merge when the checks pass: secret scan, `lint`, model review. Rules files also need their code owner (area director; admin at the root). When the code owner is the author, as with the admin's own rules change, the model review alone is enough.
- **OS jobs here.** Pull every 15 minutes, push at about 2 am, then the nightly review and reports. `level: team`.
- **Leaving.** `remove-teammate` and the device helper; `joining-terms.md` at join. `privacy.md` lists the team places.
- **Chat apps.** GitHub only: upload `company-skills` once per chat vendor account (its `SKILL.md`). Forgejo: people use a local agent.

Then show the **hand-off message** the script printed for each teammate. The admin sends it. It holds no secrets.

### A6. Add one more person later

Ask A2 items 5 and 6 for the new person. Run `skills/add-teammate/add-person.sh --answers <file>`. Their people page goes in by pull request. Show the hand-off message.

A new area later: run `add-area`.

## Part B — on the teammate's computer

### B1. Tools and sign-in

1. Check `git --version` (GitHub: also `gh --version`). Missing? Help install them (Mac: `brew install git gh`).
2. GitHub: the teammate runs `gh auth login` in the browser. Then they accept the company's invites.

### B2. Folder and clone

1. Ask for the folder. Suggest `~/{{COMPANY_SLUG}}-os`. Refuse a synced folder.
2. Clone the company repo with their own sign-in. Take the URL from `Company repo:` in the hand-off message. Never guess it:
   ```
   git clone <company repo URL> ~/{{COMPANY_SLUG}}-os
   ```
   Forgejo: `Host:` in the hand-off is the host address (`host_url`). The teammate puts their token in `~/.config/{{COMPANY_SLUG}}-os/forgejo-token` (mode 600) first.

### B3. The joining terms

1. Show `joining-terms.md` from the clone. Show the whole page.
2. Name the two main points: when they leave, a helper deletes the company folder (only removed access counts, never leave or an offline laptop); and they delete copies outside the folder themselves (agent transcripts, backups, hand copies).
3. Point to `privacy.md`: every place a copy of company data sits.
4. Ask: "Do you accept these terms?" Yes: go on. They accept once, now. No: stop, and tell them to talk to the admin.

### B4. Run it

Only after a yes in B3.
1. **Slug.** It is in the hand-off message. Confirm it. `host`, `host_url` and `org` come from `company-profile.md` in the clone: do not ask.
2. Write the answers file: `me=<slug>`.
3. From inside the clone, run `skills/add-teammate/join.sh --answers <file>`. It keeps the clone and goes on.
4. On an error, tell them the exact message. `your workspace <repo> is not reachable: ask the admin`: stop; the join is not done; the admin checks that repo and its grant. Any other error: fix the cause it names and run it once more. If it stops again, stop and send the message to the admin.

### B5. Explain the result

One line each:
- **Folders.** The company folder, `users/<slug>/` (their workspace) and their areas. A `skipped:` area is one they cannot read. That is correct.
- **Who they are.** `~/.config/{{COMPANY_SLUG}}-os/me` names them. The nightly push checks it against their git sign-in.
- **OS jobs.** Pull every 15 minutes, push at about 2 am. Notes go up by themselves. A held file stays here; the next session says why.
- **Profile.** `users/<slug>/profile/PROFILE.md` holds their voice and preferences. Claude Code, Codex, Pi (and Cursor, with a rules file) load it in every session, read-only. Their AI keeps it current.
- **Terms.** `terms: proposed`: their yes goes on their people page by pull request.
- **Where to start.** "For {{AREA_SLUG}} work, open your agent in `~/{{COMPANY_SLUG}}-os/areas/{{AREA_SLUG}}/`. General work: `~/{{COMPANY_SLUG}}-os/`."

## Rules for this skill

- Nobody writes to `main`, the admin included. Never write or say otherwise.
- No step after setup needs a person in the daily path.
