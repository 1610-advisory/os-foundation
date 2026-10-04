@AGENTS.md

## Rules that hold in every session in this company (inline on purpose)

A session opened in an area (`areas/<area>/`) loads this file but not the `AGENTS.md` import above. So the must-have rules are written here too:

- **One company only.** Use only files inside this company folder. Never read or copy from another company's folder (another `~/*-os/`).
- **No secrets.** No passwords, API keys, or tokens in any file. Connections use each tool's own sign-in.
- **Area facts stay in their area.** Never copy pay, raw numbers, HR notes, or customer records from an area into a shared file at the company root.
- **Git only in the repo you mean.** Never run destructive git (`git clean -x`, `git reset --hard`, `git rm -r` across `areas/`) at the company root.
- **Ask first** before you send, post, publish, pay, or delete anything outside this folder.
