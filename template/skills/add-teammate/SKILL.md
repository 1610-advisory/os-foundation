---
name: add-teammate
description: Give a teammate access to the company OS and only the areas they should see — puts the company folder and the chosen areas on the company's GitHub as private repos, invites the teammate, sets the review rule, and sets up the teammate's computer. Use when someone says "give <person> access", "share this with my team", "add a teammate", or "set up <person>'s computer".
---

# Add a teammate

Access works by repo. The company folder is one private repo; each area is its own private repo. A teammate gets the company repo plus only the area repos they should see. Areas they do not get are never on their computer.

Two parts: **A** runs on the admin's computer, **B** on the teammate's. Ask one question at a time.

## Part A — on the admin's computer

1. **Who and what.** Ask the teammate's name, GitHub username (they can make a free account), and which areas they need. Suggest the fewest areas that let them do their job.
2. **GitHub tools.** Check `git --version` and `gh --version`. Missing? Help install them (on a Mac, `brew install git gh`; otherwise the official installers). Then `gh auth login`: the admin signs in in their browser. Never handle a password or token.
3. **The company's GitHub home.** Ask where the repos go. Suggest a GitHub **organization** for the company (free to make at github.com/organizations/new), so the repos belong to the company and not to one person. Write the org name into the company `AGENTS.md` under "Admin."
4. **Put the repos on GitHub** (first time only for each repo):
   - Company folder: `gh repo create <org>/<slug>-os --private --source . --push` from the company root.
   - Each area the teammate needs: `gh repo create <org>/<slug>-<area> --private --source areas/<area> --push`.
   - Each app under `areas/apps/` is its own repo the same way: `<org>/<slug>-app-<name>`.
   Never make these repos public.
5. **Invite.** For each repo the teammate gets: `gh api -X PUT repos/<org>/<repo>/collaborators/<username> -f permission=push`. Write access lets their agent open pull requests; the review rule stops changes going in without the admin.
6. **The review rule.**
   - Add `.github/CODEOWNERS` with `* @<admin-username>` to each shared repo and commit.
   - **Paid GitHub plan (Team or higher):** protect `main` on each repo: require a pull request with one approval from code owners. GitHub then enforces the rule.
   - **Free plan:** GitHub cannot protect `main` on private repos. Tell the admin plainly: the rule is written in `AGENTS.md` and agents follow it, but GitHub does not enforce it.
   - Session logs go straight to `main`. With protection on, a teammate's log push is refused; their agent puts the log in the next pull request instead.
7. **Record it.** Add or update the teammate's note in `people/` (name, role, which areas). Commit.
8. **Hand-off message.** Write a short message the admin can send: accept the GitHub invites, then paste this into their agent: "Set up my computer for the <Company> company OS. Read `skills/add-teammate/SKILL.md` part B in the repo <org>/<slug>-os and follow it." No secrets in the message.

## Part B — on the teammate's computer

1. Check `git` and `gh`; install if missing. `gh auth login` — the teammate signs in in their browser.
2. Clone the company repo: `gh repo clone <org>/<slug>-os ~/<slug>-os`.
3. Clone only the areas they have access to: `gh repo clone <org>/<slug>-<area> ~/<slug>-os/areas/<area>`. If a clone fails with "not found," they do not have access to that area. That is correct; skip it.
4. Claude Code only: in the company root and each area, `ln -s ../skills .claude/skills` (make `.claude/` first). Skip if it fails.
5. Show them where to start: "For <area> work, open your agent in `~/<slug>-os/areas/<area>/`. General questions: `~/<slug>-os/`." Tell them: changes they ask for go to the admin as a pull request; they do not need to know git.
6. **Daily start:** `git pull` in the company root and each area. Their agent can do this at the start of each session.
