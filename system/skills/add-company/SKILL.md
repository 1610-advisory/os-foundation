---
name: add-company
description: Build a new company folder (a silo) from system/company-template — interview about the company, pick functions, fill core knowledge, optionally make it a git repo the team can share. Use when the person says "add a company", "I also work at ...", "set up a folder for my side business", or during setup.
---

# Add a company

Each company gets one folder at `~/os/<company-slug>/`, copied from `system/company-template/`. It is a silo: nothing in it references another company, and nothing from another company comes in.

Ask one question at a time, with a suggested answer.

## 1. Name and slug

Ask for the company name. Suggest a short slug: lowercase, hyphens, no punctuation ("Prairie Seed Co." → `prairie-seed`). If `~/os/<slug>/` exists, stop and ask.

## 2. Functions

Ask which parts of the business they work in. Offer a list: marketing, finance, sales, operations, HR/people, product, customer service, leadership. Suggest only the ones they touch every week. More can be added later with `add-function`.

## 3. Build the folder

1. Copy `system/company-template/` to `~/os/<slug>/`.
2. Keep `core/` and `memory/` always. Keep `marketing/` and `finance/` only if chosen. For every other chosen function, copy `_function/` to `<function-slug>/`. Then delete `_function/` and any unchosen function folders from the new company.
3. Replace placeholders in every file: `{{COMPANY_NAME}}`, `{{COMPANY_SLUG}}`, `{{FUNCTION_NAME}}`, `{{PERSON_NAME}}`, `{{ROLE}}`, `{{DATE}}` (today, YYYY-MM-DD).
4. Add the company to the "Companies" line in `~/os/AGENTS.md`.

## 4. Fill core knowledge (the interview)

This is the part that makes the agent useful. Ask these, one at a time, and write the answers into `core/` as you go. Short answers are fine; the files grow over time.

| Question | File |
|---|---|
| What does the company do, in one or two sentences? Who started it, how big is it? | `core/about.md` |
| Who buys from you? What problem are they trying to solve? Who is your best customer? | `core/customers.md` |
| What do you sell? Main products or services, rough prices, what people buy first. | `core/offers.md` |
| How should the company sound when it writes? Any words you never use? Paste a few lines you like. | `core/voice.md` |
| Who are the three to five people you work with most? Their role. | `core/people/<Name>.md` (one each, from `templates/Person.md`) |
| What are you working on this quarter? | `AGENTS.md` → "Right now" |

Offer shortcuts: "If there is a website, I can read it and draft these for you to check." If the agent can browse, read the company website and draft `about.md`, `offers.md`, and `voice.md` from it, then ask them to correct it. Mark anything you guessed with `(check)`.

Never invent facts. Leave a blank or `(unknown)` instead.

## 5. Git (optional — ask only if they have a team or want backups)

A company folder can be its own private git repo, so teammates share the same context. Offer this only if they use git or have a technical teammate. If yes:

```
cd ~/os/<slug>
git init
git add -A
git commit -m "Company OS: initial"
```

Then they create an empty **private** repo on GitHub (or their company's host) and push. Remind them: files here should be fine for anyone with repo access to read, so keep personal notes in `~/os/wiki/`, not here. Never commit a `.env` or credential file; `.gitignore` in the template already blocks the common ones.

## 6. Finish

Tell them the path to open for each function (`~/os/<slug>/marketing`, ...). Log the new company in `system/memory/logs/YYYY-MM-DD.md`.
