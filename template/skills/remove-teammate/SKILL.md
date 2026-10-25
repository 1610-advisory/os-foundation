---
name: remove-teammate
description: Remove a person who is leaving the company (or an outside party whose work ends). Revokes their access first, archives their workspace, marks their people page, gives their bots a new owner, and lists the AI vendor seats to remove. The device helper then deletes the company folder from their computer. Team level only. Use when someone says "remove {{PERSON}}", "{{PERSON}} is leaving", "offboard {{PERSON}}", or "end access for the agency".
---

# Remove a teammate

Team level only. Read `level:` in `company-profile.md`. At `solo` there is no one to remove: say so and stop.

Only the admin runs this. It runs on the admin's computer.

How to run it:
- Ask one question at a time. Give a suggested answer with each question.
- Run the script.
- Explain the result in plain words.

The flags are in `skills/remove-teammate/CLI.md`. Use exactly those.

## 1. Questions (one at a time)

1. **Who is leaving?** Find their page in `people/`. Say their full name and slug back. Ask the admin to confirm.
2. **Their bots.** Look in `bots/*/BOT.md` for bots this person owns. None: skip this question. Bots keep running when an owner leaves: they are company infrastructure. Ask who owns them now. Suggest the `manager:` on the person's page. No manager: suggest the admin.

The script refuses to remove the last admin. If this person is the last admin, help name a new admin first.

## 2. Run it

Run `skills/remove-teammate/remove.sh --person <slug>`. Add `--new-bot-owner <slug>` when the admin named someone other than the manager. With no flag, the script uses the manager, else the admin.

The script prints `revoked:` only when every revoke worked. If any revoke fails, it does not remove the person from the org, prints what is left, and exits with an error.

If it exits with an error, tell the admin the exact message and what is left. Never say access is gone unless the script printed `revoked:`. Fix the cause it names and run it once more. If it stops again, stop.

## 3. What it does, in this order

1. **Revoke first.** It removes the person from their teams, from each repo grant and from the org. Their sign-in no longer reaches any company repo.
2. **Workspace.** It archives their workspace repo. Only the admin can read it. The company keeps it. The admin may turn on deletion.
3. **People page.** It sets `left:` to today on their page in `people/`. The page stays.
4. **Bots.** Each bot they owned gets the new `owner:` in its `BOT.md`.
5. **By pull request.** The changes to `people/` and `bots/` go on one branch and one pull request. `bots/` holds rules files, so the model review runs. The admin is the author and the code owner, so the model review alone is enough. Nobody writes to `main`.
6. **Vendor seats.** It prints one `seat:` line per AI vendor seat listed under Connections in `architecture.md`.

Their notes and action logs stay in the areas. They are company knowledge.

## 4. Tell the admin

One line each:
- Access is gone now.
- The workspace is archived. Only you can read it.
- `people/` is marked. Bots have a new owner (name them). Give the `pr:` link.
- **Rotate the review key.** Anyone who could push a branch could read it. Make a new key at the vendor, set it with `skills/_host/host.sh set-secret OS_REVIEW_KEY` (the hidden-input line in `add-teammate` A3), then delete the old key.
- **Remove these vendor seats now.** Read the printed list. The admin removes each seat in that vendor's admin page. This is the only lever on vendor memory and chat history. What a vendor keeps after that is the vendor's rule.
- **Their computer.** The device helper deletes the company folder by itself. Explain the signal below.

## The device helper

The person accepted this when they joined (`joining-terms.md`). No step is needed from them or from the admin.

- A day counts only when all three are true: the helper ran, their sign-in works, and the company repo says "no access".
- Days with the computer off or offline do not count. An expired sign-in does not count.
- After 14 counted days, the helper deletes the company folder. It warns on that computer first.
- So leave, holiday or a dead laptop never deletes anything. Only removed access does.
- If it ever deletes by mistake: everything pushed is on the host. Run Part B of `add-teammate` again. It takes minutes.

Copies outside the folder (agent transcripts, backups, hand copies) are the person's to delete. They agreed to that when they joined.

## Outside parties

A firm, agency or bookkeeper is removed the same way, one company at a time. They delete every copy of company data. They may keep anonymized notes on methods: no names, numbers or detail that points to the company, unless a special agreement says otherwise.

## Not in v1

App level (the 1610 OS app): the app removes the person and drives the same steps. PHI installs delete the workspace by the company's record policy. Neither is in this script yet: it prints `phi: app-level-not-in-v1`.
