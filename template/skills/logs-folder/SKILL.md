---
name: logs-folder
description: Set up, clone, or repair the session-logs folder (memory/logs/) of a repo in this company OS. Logs live on their own `logs` branch, checked out as a folder, so they can be committed freely while `main` stays under review. Used by setup, add-area, and add-teammate; use directly when someone says "logs are missing" or "fix the logs folder".
---

# Logs folder

Every repo in the company OS (the company root, and each area) keeps its session logs in `memory/logs/`. That folder is a **git worktree**: the repo's `logs` branch, checked out inside the repo. `main` ignores it (`/memory/logs/` is in `.gitignore`).

Why: logs are written after every session. On their own branch they never need a pull request, while curated memory (`memory/MEMORY.md` and its fact files) stays on `main` under review. Same repo, so the same people can see them.

Run every command from the repo's own folder: the company root, or `areas/{{AREA_SLUG}}/`.

## Make it (new repo, after its first commit)

```
git worktree add --orphan -b logs memory/logs
```

That needs git 2.42 or newer. If it fails, use this instead (works on older git, including the one that comes with macOS):

```
git worktree add --detach memory/logs
git -C memory/logs checkout --orphan logs
git -C memory/logs rm -rfq .
```

Then, either way:

```
printf '# Session logs\n\nOne file per person per day: YYYY-MM-DD-{{PERSON_SLUG}}.md\n' > memory/logs/README.md
git -C memory/logs add README.md
git -C memory/logs commit -m "Logs: start"
```

Check: `git -C memory/logs branch --show-current` says `logs`.

## Put it on GitHub (add-teammate, after the repo is pushed)

```
git -C memory/logs push -u origin logs
```

## Clone it (a teammate's computer, after cloning the repo)

```
git fetch origin logs
git worktree add memory/logs logs
```

## Write a log

1. Append to `memory/logs/YYYY-MM-DD-{{PERSON_SLUG}}.md`: what was done, what is open.
2. `git -C memory/logs add -A && git -C memory/logs commit -m "Log: {{PERSON_SLUG}} YYYY-MM-DD"`
3. If the repo has a GitHub remote: `git -C memory/logs pull --rebase -q && git -C memory/logs push -q`.

## Repair

- Folder missing but the branch exists: `git worktree prune`, then `git worktree add memory/logs logs`.
- No git on this computer: `memory/logs/` is a plain folder. Write logs there; make it a worktree later, when git is installed (move the files into it, then commit).
