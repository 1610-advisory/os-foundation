---
name: add-teammate
description: Give a teammate access to the company OS and only the areas they should see — puts the company folder and the chosen areas on the company's GitHub as private repos, invites the teammate, sets the review rule, and sets up the teammate's computer. Use when someone says "give {{PERSON}} access", "share this with my team", "add a teammate", or "set up {{PERSON}}'s computer".
---

# Add a teammate

Access works by repo. The company folder is one private repo; each area is its own private repo. A teammate gets the company repo plus only the area repos they should see. Areas they do not get are never on their computer.

Two parts: **A** runs on the admin's computer, **B** on the teammate's. Ask one question at a time.

## Part A — on the admin's computer

1. **Who and what.** Ask the teammate's name, GitHub username (they can make a free account), and which areas they need. Suggest the fewest areas that let them do their job.
2. **GitHub tools.** Check `git --version` and `gh --version`. Missing? Help install them (on a Mac, `brew install git gh`; otherwise the official installers). Then `gh auth login`: the admin signs in in their browser. Never handle a password or token.
3. **The company's GitHub home.** Ask where the repos go. Suggest a GitHub **organization** for the company (free to make at github.com/organizations/new), so the repos belong to the company and not to one person. Write the org name into the company `AGENTS.md` under "Admin."
4. **Put the repos on GitHub** (first time only for each repo):
   - Company folder: `gh repo create {{GITHUB_ORG}}/{{COMPANY_SLUG}}-os --private --source . --push` from the company root.
   - Each area the teammate needs: `gh repo create {{GITHUB_ORG}}/{{COMPANY_SLUG}}-{{AREA_SLUG}} --private --source areas/{{AREA_SLUG}} --push`.
   - Each app under `areas/apps/` is its own repo the same way: `{{GITHUB_ORG}}/{{COMPANY_SLUG}}-app-{{APP}}`.
   - Then push each repo's logs branch: `skills/logs-folder/SKILL.md` → "Put it on GitHub".
   Never make these repos public.
5. **Invite.** For each repo the teammate gets: `gh api -X PUT repos/{{GITHUB_ORG}}/{{REPO}}/collaborators/{{USERNAME}} -f permission=push`. Write access lets their agent open pull requests; the review rule stops changes going in without the admin.
6. **The review rule.**
   - Add `.github/CODEOWNERS` with `* @{{ADMIN_USERNAME}}` to each shared repo and commit.
   - **Paid GitHub plan (Team or higher):** on each repo, protect both branches. GitHub then enforces the rules.
     - `main`: a pull request with one approval from code owners. The admin can still commit directly.
       ```
       gh api -X PUT repos/{{GITHUB_ORG}}/{{REPO}}/branches/main/protection --input - <<'JSON'
       {"required_status_checks": null, "enforce_admins": false,
        "required_pull_request_reviews": {"required_approving_review_count": 1, "require_code_owner_reviews": true},
        "restrictions": null}
       JSON
       ```
     - `logs`: no review, but no force-push and no deletion, so nobody can wipe the history.
       ```
       gh api -X PUT repos/{{GITHUB_ORG}}/{{REPO}}/branches/logs/protection --input - <<'JSON'
       {"required_status_checks": null, "enforce_admins": true,
        "required_pull_request_reviews": null, "restrictions": null,
        "allow_force_pushes": false, "allow_deletions": false}
       JSON
       ```
   - **Free plan:** GitHub cannot protect `main` on private repos. Tell the admin plainly: the rule is written in `AGENTS.md` and agents follow it, but GitHub does not enforce it.
   - Session logs live on the `logs` branch, so they never need a pull request.
7. **Record it.** Add or update the teammate's note in `people/` (name, role, which areas). Commit.
8. **Hand-off message.** Write a short message the admin can send: accept the GitHub invites, then paste this into their agent: "Set up my computer for the {{COMPANY_NAME}} company OS. Read `skills/add-teammate/SKILL.md` part B in the repo {{GITHUB_ORG}}/{{COMPANY_SLUG}}-os and follow it." No secrets in the message.

## Part B — on the teammate's computer

1. Check `git` and `gh`; install if missing. `gh auth login` — the teammate signs in in their browser.
2. Clone the company repo: `gh repo clone {{GITHUB_ORG}}/{{COMPANY_SLUG}}-os ~/{{COMPANY_SLUG}}-os`.
3. Clone only the areas they have access to: `gh repo clone {{GITHUB_ORG}}/{{COMPANY_SLUG}}-{{AREA_SLUG}} ~/{{COMPANY_SLUG}}-os/areas/{{AREA_SLUG}}`. If a clone fails with "not found," they do not have access to that area. That is correct; skip it.
4. In the company root and each cloned area, set up the logs folder: `skills/logs-folder/SKILL.md` → "Clone it".
5. Claude Code only: in the company root and each area, `ln -s ../skills .claude/skills` (make `.claude/` first). Skip if it fails.
6. Show them where to start: "For {{AREA_SLUG}} work, open your agent in `~/{{COMPANY_SLUG}}-os/areas/{{AREA_SLUG}}/`. General questions: `~/{{COMPANY_SLUG}}-os/`." Tell them: changes they ask for go to the admin as a pull request; they do not need to know git.
7. **Daily start:** `git pull` in the company root and each area, and in each `memory/logs/`. Their agent can do this at the start of each session.
