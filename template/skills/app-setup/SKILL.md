---
name: app-setup
description: >
  Take a business need to the smallest fix: existing software first, then a declared tool
  with its own repo, a record in the Apps area and the right approval. Use when someone says
  "build an app", "build a tool", "make a portal", "make a dashboard", "automate this",
  "where should this run", "host this", "use a VPS", "use Cloudflare", "which software
  should I use", or "deploy my app". Explains where a tool runs, the stopgap rule, data
  about a person, and who approves.
---

# App setup

You help the company get a job done with the least new software. In this skill, a **tool** is software built for the company. The **Apps** area lists every tool. Outside software (email, books, CRM) is existing software.
Follow the company and area rules. Locate the company root from those rules, not a guessed home path. Read `company-profile.md` for the existing software and the Apps area's `apps.md` before proposing anything.
Ask one question at a time, with a suggested answer. A build request alone approves nothing outside this folder.

The **kernel** is the company's OS server. It signs people in, checks every request against permissions, keeps the audit log, locks datasets, runs a tool's named requests and serves its screens. 1610 runs it for the company, or the company runs its own copy. If `level:` in `company-profile.md` is `app` (the 1610 OS app), the company has one. Otherwise assume it has none. If you are not sure, ask. Never change the kernel: a tool does not need a kernel change.

## 1. Look at what exists first

Ask what job must get easier. Check the existing software: settings, built-in automation, an integration, or a skill with a script. Custom code is an option, not the default.
If the job is a page of numbers that does not need live data, make a deliverable (section 6), not a tool. If the build replaces a working tool, write why: what the old tool cannot do, and what changes for the people who use it.
Find out: who uses it and what each person may see or change; what data it reads and writes; whether any of it is about a person (section 5); which area owns it; whether it is for the builder alone or for others.
**Check:** the job, the users, the data and the owning area are known, or marked unknown.

## 2. Declare the tool

A tool is mostly a declaration, not code. It has:
- **A data list** (required): each dataset it reads or writes, its source and its lock (the whole area, named people or a group, or the owner only). To limit rows, use a column that names who may read each row, filled from the source's own assignments. Never grant rows by hand. Do not build a second permission system.
- **Named requests** (required): one job each, with a plain name, such as "gross profit for a job". Define each one once. A named request can read and write. The screen, the chat and the command line all use the same named request, behind the same lock.
- **Screens** (optional): React pages that show what named requests return. No access rule lives only in a screen.
- **Scheduled scripts** (optional). A standing agent is a tool with a schedule. It has a named human owner and an approved data list, and never sees more than that owner. It stops when the owner leaves, until someone takes it over.
- **The shared report button** (required). Use the shared part at a pinned version; do not build your own. Ask 1610 for it if you do not have it. A person picks a kind (broken, idea or other) and writes a short text. The button adds the page, the person and the tool version. It never captures the screen or what is in a form. Each report opens an issue on the tool's repo.

Write it in TypeScript, with React for screens. The other front-end parts are the builder's choice.
Reads from outside software use the person's own connection, so that software decides what the person sees. A company-wide connection is only for a scheduled copy, and the owner approves it.
The data must pass three tests. Open format: other software can read the files (SQLite, JSON and CSV pass). The company holds it, and holds the key if it is encrypted. The owner can take a whole copy at any time with no help from 1610.
Never copy passwords, keys, payment card numbers, government ID numbers or bank login details.
Test data is made up from the real shape, never scrambled real rows, and is marked as test. Never mix test and real data in one answer. Use a general tool at a pinned version, never a copied fork.

## 3. Where it lives

- Each tool has its own repo and one owning area. The company owns the repo, in its own GitHub organisation when it has one. Never copy the tool into another repo.
- Tool code never goes in the company OS folder, not even in an ignored subfolder. The folder holds no tool code and no data.
- The folder gets one record for the tool in the Apps area's `apps.md`: name, job, owning area, repo, where it runs, who may use it and status. For a stopgap, add what must be true for it to move (section 4).
- The plan, the code and how to run it go in the tool's repo. Secrets never do.
- Test: with only its OS folder and the tool's repo, the company can run and change the tool without 1610.

## 4. Where it runs

**With a kernel,** the tool has no server and no sign-in of its own. The kernel signs people in, checks and logs each request, holds the locks, runs the named requests and serves the screens. Reports from the button go to the kernel. No tool code runs on the server.
If the kernel cannot yet run the tool's named requests, the tool may run as its own TypeScript process "behind the kernel": the kernel stays in front for sign-in and locks. This is a stopgap. It still needs a security review before go-live, backups plus a scheduled copy of its data to storage the company owns, and a written plan to move. It moves onto the kernel when the kernel can run it.

**With no kernel that can host it,** the stopgap rule applies. The tool may run on its own, with its own sign-in, only while all of these are true:
1. Business records only (accounting, jobs, the customer list, shared files, shared inboxes). Nothing about a person.
2. Sign-in with the company's office account (Microsoft or Google), through a standard sign-in library. No passwords. Never write your own sign-in code.
3. A security review before go-live.
4. Its data passes the three tests (section 2).
5. Backups, plus a scheduled copy of the data to storage the company owns.
6. The plan states why it is a stopgap and what must be true for it to move onto the kernel.
7. It moves when the kernel can host it.
8. A second stopgap tool for the same company needs approval from 1610. Stop and ask.

In a stopgap, the tool's own server saves the reports from the button. Show the costs, recurring charges and upkeep before you create anything. Unknown costs stay unknown, not zero.

## 5. Approval and data about a person

- A person may build a tool for themselves with no review. It runs as that person and sees only what they may already see.
- Publishing it for others needs the manager of the area it is published into (the area director). If the builder is that manager, or the tool is company-wide, the owner approves. The owner may approve their own tool; log it.
- Sharing is a grant to a group. A person sees only what they may read. The one exception is a summary: the tool writes a small dataset with a wider lock, and the manager approves it and who sees it. The approver checks that two summaries together do not reveal a locked number.
- A published tool that changes what data it touches needs a new approval. A change to screens only does not.
- A builder with no access of their own works on made-up test data.
- Data about a person: a named person's mailbox, chat, texts, recordings, personal calendars and drives, HR and pay, location and activity, a person's own AI chat history, photos of customers' homes. It is never in a tool that runs without the kernel in front.
- On the kernel, a person may read their own things live, with their own sign-in, for their own use. A company copy of any of that data needs the owner to turn it on. Staff are told, and it is logged. Never touch a mailbox the company does not own.

## 6. Deliverables and screens

Markdown is the truth. No fact lives only in a deliverable. A deliverable is a single HTML file made from the markdown. It holds its numbers and an "as of" date. It reads no live data. It may link to a live screen. A page that reads live data is a tool screen. Build it as a tool (sections 2 to 4).

## 7. Build and release

Show the plan and get approval (section 5) before go-live. Get an explicit yes before you create an account or a hosted resource, start a charge, upload company data, change DNS or access, or publish.
Check that this agent can run the tools, sign in and deploy. If it cannot, save the next steps and do the safe local work. Do not claim it is live.
Never ask for a secret in chat, write it in a file, or put it in a command or a log. Use the provider's secret storage or the system keychain.
Before real data goes in, test an allowed person and a refused person. Call the named request directly, not only through the screen. Send one test report from the button. For a stopgap, also check HTTPS, the office sign-in, a restore from backup with test data, the scheduled copy, and that the security review passed.
Update the tool's record in `apps.md`. Log the work in the area.
**Check:** each check passed, or is marked "not tested" with what that means. Say "local prototype" for local work, not "live". End with what works and the single next step.

## When to stop and ask a human

- The tool would copy data about a person for the company, or touch a mailbox the company does not own.
- The tool would touch health records. These rules do not cover health data yet.
- The tool seems to need a change to the kernel.
- You cannot tell whether the company has a kernel, or which area owns the tool.
- The build replaces a working tool and nobody has said why.
- It needs a new account, a charge, a DNS or access change, or real data before approval.
- A rule here conflicts with the company or area rules. The stricter rule wins until a person decides.
