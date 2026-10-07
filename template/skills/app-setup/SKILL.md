---
name: app-setup
description: >
  Guide an app from a business need to a suitable tool, hosting choice and approved release.
  Use when someone says "build an app", "make a portal", "automate this", "where should
  this run", "host this", "use a VPS", "use Cloudflare", "which software should I use",
  or "deploy my app". Compare existing tools, local use, Cloudflare, a self-managed VPS
  and other managed options. Explain costs and upkeep before creating resources.
---

# App setup

You are helping a business owner choose the smallest workable solution, not selling a stack.
Follow the company and area rules. Locate the company root from those rules, not a guessed home path.
Read `company-profile.md` for existing tools and relevant approved source pointers. Read the apps area's `apps.md` and any existing app instructions before proposing changes.
Use this flow only for app or automation work. General company setup does not require hosting.
Ask one question at a time, with a suggested answer based on what they have told you.

## 1. Find the job and explain where it runs

Ask what job needs to get easier. Check whether their existing tools already do it, or can do it with a small automation. Custom code is an option, not the default.
Establish each unanswered requirement; reuse confirmed answers instead of repeating questions:
- Who uses it: one person, employees, customers, or the public? What should each person see or change?
- Must it work when their computer is off, run on a schedule, or serve several people at once?
- What data does it save, what tools does it connect, and are there privacy or location requirements?
- What monthly budget is comfortable, and who will own maintenance and support?
- What hosting or software accounts do they already have and want to keep? Ask before inspecting accounts.

Explain only the distinction their job needs:
> The folder holds the code and instructions. A local tool runs on your computer. If others need a web link, or it must work while your computer is off, it needs somewhere to run. That can be a managed service or a server you rent and look after.

GitHub keeps source history; a repository alone is not hosting for a running app. An AI subscription does not automatically include production hosting. Some platforms bundle hosting; verify what their actual plan includes. A local prototype does not require paid hosting. A rented VPS is still a third party handling hosted data, not local-only storage.
**Check:** the job, audience, runtime needs, data, budget and maintenance owner are known, or explicitly marked unknown. With unresolved safety or hosting requirements, offer a local prototype with synthetic data or save the questions; do not guess a production setup.

## 2. Recommend the smallest suitable stack

Read [hosting-options.md](hosting-options.md). Start with existing tools or local use if sufficient. Prefer Cloudflare for a suitable new hosted web app; honor a requested VPS or existing suitable provider. Preference is not a mandate.
Give one recommendation and at most two relevant alternatives. When Cloudflare fits, explain the one-platform benefit: Workers for hosting/app logic, D1 for database records, and R2 for files, using only the pieces needed. Explain each program's job in plain words: interface, place it runs, data storage, login, integrations. Add only the pieces the job needs. Name concrete products after checking runtime and data requirements, not before.
Check current official docs for runtime/framework support, pricing, limits, data handling and export options. Record links and the date checked. If you cannot verify a material requirement, say so and keep the choice provisional. Do not invent free-tier promises or quote old prices as current.
Include recurring hosting, database/storage, domain, email or AI API charges where relevant. Explain usage-based costs, any spending-alert/cap limitations, and the maintenance work; a budget alert is not necessarily a spending cap. Unknown costs remain unknown, not zero.
**Check:** they can explain why the recommendation fits, what it costs, and who looks after it.

## 3. Save the decision and get approval

Save `app-plan.md` in the app's own repo, or a planning note in the apps area until the app has one. Follow the apps area's one-repo-per-app rules. Keep restricted details in that area/app, not shared company files.
Record:
- Job, acceptance checks, approved audience and each role's allowed actions.
- Chosen programs and hosting, alternatives rejected and why, docs/date checked.
- Data stored or sent to each service; login, authorization and required permissions.
- Account/billing owner, cost estimate/unknowns, recurring charges and agreed budget.
- Maintenance owner, updates, monitoring, backups and a restore procedure where data persists.
- How to export data and code, move providers, and roll back a release; name any limitations.
- Status: proposed, approved, local prototype, or deployed; blockers and exact approvals received.

Show the plan and get explicit approval before creating an account or hosted resource, starting a subscription, uploading company data, changing DNS/access, or publishing. A build request alone does not approve those steps. Approval for one scope does not approve unrelated infrastructure changes.
Use company-owned accounts; the user signs in through the provider's own flow. Use provider secret storage or the operating-system keychain for credentials. Never ask for a secret in chat, write it in company files, or put it in command arguments or logs. If secure authentication is unavailable, explain the missing step and stop there.
**Check:** the chosen services, audience, external changes and costs are approved, or the work stays local with synthetic data.

## 4. Build and release within that approval

Check that this agent can run the required tools, authenticate securely and deploy to the selected account. An instruction file does not grant those capabilities. If something is unavailable, save exact next steps and do the safe local work; do not claim it is deployed.
Use the chosen provider's current official setup and deployment guide. Preserve existing frameworks, versions and working deployments unless a change is approved. Build the smallest complete version and demonstrate the acceptance checks locally before release.
Publish only app code and approved assets, never the company OS, inbox, memory, credentials or private source data. Check build output before uploading it. Use synthetic test data until the data/access plan is approved and verified.
Before real data goes live, verify HTTPS, login where required and server-side authorization. Test both an authorized user and an unauthorized user; cover direct API/file URLs and alternate origin URLs, not just a hidden menu. A private git repo does not make the deployed app private.
For persistent data, verify it survives the expected restart/redeploy and exercise backup restore using test data in a safe environment. Code rollback does not necessarily restore database contents; plan migrations separately. Verify the app from its deployed address, not just a successful build or HTTP status.
Record the live URL, deployed revision, approved audience, tests actually run, costs and owner in the app's notes. Update the apps area's `apps.md`; shared `architecture.md` gets only the app name and job, not host/account details. Log in the area under its existing rules.
**Check:** each acceptance, access and recovery check is passed or explicitly "not tested" with its consequence. Do not call it production-ready while a required check is unresolved. For local work say "local prototype", not "live". End with what works and the single next step.
