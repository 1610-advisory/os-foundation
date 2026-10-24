---
name: privacy
description: Write privacy.md, the plain list of every place a copy of the company's data sits, built from the level and switches in company-profile.md. Use at the end of setup, after add-teammate, after any switch changes, or when someone asks "where does our data go", "who can see this", or "update the privacy page".
---

# Privacy

`privacy.md` at the company root lists where copies of the company's data sit. It lists only the places that are on now. Each place has one sentence: who can read it, how long it stays, how it is removed.

Never edit `privacy.md` by hand. The script writes it from `places.md` and `company-profile.md`.

## When to run it

Run `skills/privacy/privacy.sh` from the company root:

1. At the end of setup (solo).
2. At the end of `add-teammate` Part A (the level changes to `team`).
3. After each change to `level:` or `switches:` in `company-profile.md`.

If the script is missing, say so in one line and go on. Do not write `privacy.md` yourself.

## What to tell the person

One line, then stop:

> I updated `privacy.md`. It lists every place a copy of your company's data sits.

If the person asks, read `privacy.md` to them. Do not add places it does not list.

## Change a place

Edit `places.md`, not `privacy.md`. This is a rules change: open it by its own pull request. Keep the `t2` text word for word.

## Script contract (`privacy.sh`)

- Usage: `privacy.sh [--root <dir>] [--check]`. Default root: the current folder. `--help` prints usage.
- Reads `level:` and `switches:` from `<root>/company-profile.md` (with `skills/_host/profile.sh` if present). A missing level counts as `solo`.
- Reads `places.md` next to the script. Lines before the first `## ` are ignored. Each entry is:
  ```
  ## <place-id>
  when: <condition>
  <one sentence>
  ```
- `<condition>` is `always`, `level: team` (true for `team` and `app`), `level: app`, `switch: <name>` (true if `<name>` is in `switches:`), or two of these joined by ` and `. Anything else: exit 1 with the place id. Never guess.
- Writes `<root>/privacy.md`:
  ```
  # Privacy

  Made by `skills/privacy/privacy.sh` from the level and switches in `company-profile.md`. Do not edit by hand.

  <t2 sentence>

  ## Where copies of your data sit

  - <sentence of each other place that is on, in places.md order>
  ```
- `--check`: write nothing; exit 0 if `privacy.md` is current, 1 if it differs.
- Prints one line, for example `privacy.md: 7 places`. Exit 0 ok, 1 usage or bad `places.md`, 2 no `company-profile.md`.
