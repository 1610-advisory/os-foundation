---
name: app-setup
description: >
  Take a business need to the smallest fix: existing software first, then a declared tool
  with its own repo, its own SQLite file, a record in the Apps area and the right approval.
  Use when someone says "build an app", "build a tool", "make a portal", "make a dashboard",
  "automate this", "where should this run", "host this", "which software should I use",
  "add a CRM", or "deploy my app". Explains the tool format, where a tool runs, row locks,
  data about a person, and who approves.
---

# App setup

You help the company get a job done with the least new software. In this skill, a **tool** is software built for the company. The **Apps** area lists every tool. Outside software (email, books, a vendor's CRM) is existing software.
Follow the company and area rules. Find the company root from those rules, not from a guessed home path. Read `company-profile.md` for the existing software, and the Apps area's `apps.md`, before you propose anything.
Ask one question at a time, with a suggested answer. A build request alone approves nothing outside this folder.

The **kernel** is the company's one door: sign-in, permissions, the audit log, the connector and dataset locks. It checks each request to a tool, logs it, and forwards it with the person's id, email, role and areas. **The kernel never runs a tool's requests itself.** If `level:` in `company-profile.md` is `app`, the company has one. Otherwise assume it has none. If you are not sure, ask. Never change the kernel. A tool never needs a kernel change; if it seems to, stop (last section).

How a tool gets built into the kernel: the Tool Build Standard (ops-app `docs/tool-build-standard.md` once the kernel trunk merges; until then ask the 1610 dev team) and ops-app `docs/tool-door.md`. Kernel modules are closed: tools are TypeScript, own repo, served at `/t/<tool>/` behind the kernel.

## 1. Look at what exists first

Ask what job must get easier. Check the existing software: settings, built-in automation, an integration, or a skill with a script. Custom code is an option, not the default.
If a general 1610 tool already does the job (for example the CRM), use it at a pinned version. Never copy it into a fork.
If the job is a page of numbers that does not need live data, make a deliverable (section 7), not a tool. If the build replaces a working tool, write why: what the old tool cannot do, and what changes for the people who use it.
Find out: who uses it and what each person may see or change; what data it reads and writes; whether any of it is about a person (section 6); which area owns it; whether it is for the builder alone or for others.
**Check:** the job, the users, the data and the owning area are known, or marked unknown.

## 2. Declare the tool

A tool is mostly a declaration, not code. Its repo has a `tool.json` that the kernel reads. It holds:
- **The data list** (required): each table the tool owns, its label, a one-line description, its **row lock**, its key columns, and its personal columns. The tool's data is **one plain SQLite file**, `data.sqlite`. That file is the live source.
- **Named requests** (required): one job each, with a plain name and an input schema, such as "gross profit for a job". Define each one once. Each has a kind: `read`, `write`, or `risky` (archive, merge, bulk change, or anything that sends a message outside). The screen, the chat and the command line all use the same named request, behind the same lock.
- **On the connector:** a request is off the connector until `tool.json` lists it as on. A `risky` request is never on the connector.
- **Timers** (optional): scheduled scripts. A standing agent is a timer with a named human owner and an approved data list. It never sees more than its owner, and stops when the owner leaves, until someone takes it over.
- **Outbound hosts** (optional): each outside address the tool may call. Nothing else is allowed. The tool logs each outbound call in its own file.
- **Screens** (optional): React pages that show what named requests return. No access rule lives only in a screen.
- **Nav, hooks, model and OAuth** (optional): the tool's entries in the kernel's menu (`nav`), web form hooks that a website posts to (`hooks`), the kernel's model door (`model`), and sign-in to an outside app (`oauth`, not on every kernel yet). The keys and their limits are in ops-app `docs/tool-door.md`. The kernel refuses any other top-level key.
- **The shared report button** (required). Use the shared part at a pinned version. Do not build your own. A person picks a kind (broken, idea or other) and writes a short text. The button adds the page, the person and the tool version. It never captures the screen or what is in a form. Each report opens an issue on the tool's repo.

Write it in TypeScript, with React for screens. Generate `tool.json` from the code (for example `pnpm tool-json`) and commit it.

**Worked example: the 1610 CRM.** `tool.json` names `data.sqlite` and 18 tables. `party` (customers) has `lock: { kind: "area", column: "area_id", owner_column: "owner_user_id" }`, keys `external_ref`, personal columns name, email and phone. `job_member` has `lock: { kind: "parent", table: "job", column: "job_id" }`. Company settings have `lock: { kind: "company" }`. Labor hours have `lock: { kind: "admin" }`. About 120 named requests, such as `list_parties` (read, on the connector) and `merge_party` (risky, off the connector). Timers such as `follow_through` (every 15 minutes) run as a standing agent.

## 3. Row locks and the data file

- **Declare the lock, never code it.** Each table has one lock `kind`: `area` (`column` names the row's area; one area per row), `area` with `owner_column` (a person always sees the rows they own), `parent` (`table` and `column`: a link table follows its parent row), `company` (every person the kernel lets in), or `admin` (owners and admins only). The 1610 tool kit builds locked views from the data list. Requests read only those views and write only through the kit. A builder never writes a filter by hand.
- Fill the lock column from the source's own assignments, in the same sync as the rows. Never grant rows by hand. Do not build a second permission system.
- A tool that only shows data from other tools has no file and no lock of its own. It calls the owning tools through the kernel, as the person.
- **One tool owns each file** and is the only tool that writes it. Other tools read it through the owner's named requests, never through their own copy.
- The file is plain SQLite (not encrypted inside), on an encrypted disk, so other software can open it. It keeps its own change log by triggers: who, when, which row, the old and the new value. Changes through the kernel are also in the kernel's log.
- Data changes ship as numbered migration files with the code and run on deploy. Never edit an old migration.
- Direct work on the file (a fix, a bulk load, the command line) is for the owner and admins only. The change log records it. The tool checks data when it reads it, so an edit made outside the tool cannot break it.
- The data passes three tests. Open format: other software can read the file. The company holds it, and the key if the disk is encrypted. The owner can take a whole copy at any time with no help from 1610.
- Never store passwords, keys, payment card numbers, government ID numbers or bank login details.
- Test data is made up from the real shape, never scrambled real rows, and is marked as test. Never mix test and real data in one answer.

## 4. Where it lives

- Each tool has its own repo and one owning area. A tool for the whole company is owned by the `everyone` area. The company owns the repo, in its own GitHub organisation. Never copy the tool into another repo.
- An owner's agent makes the tool repo, when an owner asks. Members do not make repos (the org turns that off). A member who wants a tool asks an owner.
- Code goes in the tool's own repo, never in the company OS folder or an area repo.
- Tool code and data never go in the company OS folder, not even in an ignored subfolder.
- The folder gets one record for the tool in the Apps area's `apps.md`: name, job, owning area, repo, pinned version, address, who may use it, status. Add each data file to the owning area's dataset list.
- The plan, the code and how to run it go in the tool's repo. Secrets never do.
- Test: with only its OS folder and the tool's repo, the company can run and change the tool without 1610.

## 5. Where it runs

**Behind the kernel (the normal shape).** The tool is its own TypeScript process with its own SQLite file. The kernel is in front, at `<company>.1610.tools/t/<tool>/`. The kernel signs people in, checks and logs each request, and forwards it. The tool has no sign-in of its own. Its screens show in the middle of the kernel's app shell, so a person sees all their tools in one place. Reports from the button go to the kernel.
Screen rules under `/t/<tool>/`: every response has a sandbox header; the screen gets a short token that works only for its own `/t/<tool>/` paths; it calls only those paths; it has no cookies and no local storage.
Unreviewed screens run only on a **local preview server** (a stub kernel with the same screen rules and made-up data). Only reviewed screens go live. Deploy on merge is not built yet: an operator deploys by hand until it ships.
Data at rest: disk encryption, backups with a restore test, and a scheduled copy to storage the company owns.

**With no kernel (a stopgap).** The tool may run on its own, with its own sign-in, only while all of these are true:
1. Business records only (accounting, jobs, the customer list, shared files, shared inboxes). Nothing about a person.
2. Sign-in with the company's office account (Microsoft or Google), through a standard sign-in library. No passwords. Never write your own sign-in code.
3. A security review before go-live.
4. Its data passes the three tests (section 3).
5. Backups, plus a scheduled copy of the data to storage the company owns.
6. A written plan says why it is a stopgap and what must be true for it to move behind the kernel.
7. It moves when the kernel can host it.
8. A second stopgap tool for the same company needs 1610's approval. Stop and ask.

In a stopgap, the tool's own server saves the reports from the button. Show the costs, recurring charges and upkeep before you create anything. Unknown costs stay unknown, not zero.

**Build it so it can move behind the kernel.** Hosting choices for a stopgap: agree them with the owner and with 1610, and use the shape below so the move is small.
- One Node and TypeScript process with one `data.sqlite` file on disk. Named requests at `POST /.ops/requests/<name>`. Answers are `{ok: true, data}` or `{ok: false, error: {code}}`. Health at `GET /.ops/health`.
- Read identity in ONE adapter file: today the hosting sign-in, later the kernel's `X-Ops-User-Id`, `X-Ops-Role` and `X-Ops-Areas`. Match people by a stable id, never by email.
- Screens follow the `/t/<tool>/` rules now: relative URLs, no cookies or local storage, no redirects, no inline script or style, never write `location.hash`, built files under `/assets/`.
- Declare locks in `tool.json`. Run timers in the tool's own process. List outside hosts in `outbound`.
- Cloudflare Workers with their hosted database are not a clean lift: that database is not a file, and Workers do not run a long-lived Node process. Use a small Node and SQLite server, published through a Cloudflare Tunnel behind an Access rule (for example `tool.acme.com`). The server checks the Access token (signature, audience, issuer). Lock the origin to the tunnel.

## 6. Approval and data about a person

- A person may build a tool for themselves with no review. It runs as that person and sees only what they may already see.
- Publishing it for others needs the manager of the area it is published into. If the builder is that manager, or the tool is company-wide, the owner approves. The owner may approve their own tool; it is logged. In the kernel today, only the company owner approves a `tool.json`. The kernel uses only the approved file, so a changed `tool.json` needs a new version and a new approval.
- Before it is published, run the cross-read test: a person in one area tries to read another area's rows, through each named request. Each must refuse or return nothing.
- Sharing is a grant to a group. A person sees only what they may read. The one exception is a summary: the tool writes a small dataset with a wider lock, and the manager approves it and who sees it. The approver checks that two summaries together do not reveal a locked number.
- A published tool that changes what data it touches (its data list) needs a new approval. A change to screens only does not.
- `risky` requests: the tool does not build its own approval. Kernel approvals for `risky` requests are not live yet. Until they ship, the kernel refuses a `risky` request on the connector.
- A builder with no access of their own works on made-up test data.
- Data about a person: a named person's mailbox, chat, texts, recordings, personal calendars and drives, HR and pay, location and activity, a person's own AI chat history, photos of customers' homes. It is never in a tool without the kernel in front. A company copy of it needs the owner to turn it on; staff are told, and it is logged. Never touch a mailbox the company does not own.

## 7. Deliverables

Markdown is the truth. No fact lives only in a deliverable. A deliverable is a single HTML file made from the markdown. It holds its numbers and an "as of" date. It reads no live data. It may link to a live screen. A page that reads live data is a tool screen: build it as a tool.

## 8. Build and release

Show the plan and get approval (section 6) before go-live. Get an explicit yes before you create an account or a hosted resource, start a charge, upload company data, change DNS or access, or publish.
Check that this agent can run the tools, sign in and deploy. If it cannot, save the next steps and do the safe local work. Do not claim it is live.
Never ask for a secret in chat, write it in a file, or put it in a command or a log. Keys for outside services go in the kernel's key store when it has one, else the provider's secret storage or the system keychain.
Before real data goes in: the typecheck and tests pass; the cross-read test passes; an allowed person and a refused person are tested on each named request directly, not only through the screen; one test report is sent from the button. For a stopgap, also check HTTPS, the office sign-in, a restore from backup with test data, the scheduled copy, and that the security review passed.
**Registration order (behind the kernel):** an owner or admin, signed in to the app (not an agent), adds the tool, then adds a standing agent for each timer and hook, then submits `tool.json`. The owner approves it. The tool is dark until approval. After approval, the owner sets each hook secret and the model endpoint. Detail: ops-app `docs/tool-door.md`.
Update the tool's record in `apps.md` and the dataset list. Log the work in the area.
**Check:** each check passed, or is marked "not tested" with what that means. Say "local preview" for local work, not "live". End with what works and the single next step.

## When to stop and ask a human

- The tool would copy data about a person for the company, or touch a mailbox the company does not own.
- The tool would touch health records. These rules do not cover health data yet.
- The tool seems to need a change to the kernel.
- You cannot tell whether the company has a kernel, or which area owns the tool.
- A row would need more than one area, or a lock the data list cannot declare.
- The build replaces a working tool and nobody has said why.
- It needs a new account, a charge, a DNS or access change, or real data before approval.
- A rule here conflicts with the company or area rules. The stricter rule wins until a person decides.
