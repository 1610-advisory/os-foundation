> v1 in progress, not released; use `1610.sh/os`.

# os-foundation

A company OS: one folder you own with company knowledge, instructions for AI agents, and saved ways of working.

Use it with a file-capable agent that can read and write the folder. Setup guides cover Claude, Codex, Cursor, and Grok; folder access and available connections differ by app and plan. Instructions are plain markdown; some skills also include scripts and review templates.

## Start

Copy the prompt below. Open a task or agent session in your file-capable AI app, such as Claude Cowork or Claude Code, and paste it into the chat. Copying alone does not start setup:

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```

The agent asks one question at a time, saves your answers in `~/{{COMPANY_SLUG}}-os/`, and helps with one real task. You leave with files the next session can read and instructions for how to work with them. Setup time depends on folder access and any connections you choose.

Already have a Notion workspace, Drive folder, or brand guide? Setup helps you choose what stays there and what, if anything, you'd like to move. It records where the authoritative material lives and how to access it. Migration and daily sync aren't required.

| Agent | How to start |
|---|---|
| Claude Cowork / Desktop | Start a task, paste the prompt. It will ask you to choose a folder. |
| Claude Code | Run `claude` in your home folder and paste the prompt. |
| Codex | Run `codex` in your home folder and paste the prompt. |
| Cursor | Open your home folder in Cursor and paste the prompt into the agent. |

Rather do it by hand? `git clone https://github.com/1610-advisory/os-foundation.git`, open the folder in your agent, and say "read START.md."

## What you get

```
~/acme-os/                    your company OS
├── AGENTS.md, CLAUDE.md      the rules every agent reads first
├── company-profile.md        what you do, plus your level and switches
├── privacy.md                every place a copy of your data sits
├── customers.md, offers.md, voice.md
├── people/  meetings/  decisions/
├── inbox/                    drop anything here; the agent files it
├── memory/                   what the agent learned about working here
│   └── logs/                 one short log per person per day
├── skills/                   your SOPs, written down for the agent
├── .agents/skills, .claude/skills   links to skills/, so every agent finds them
└── areas/                    one folder per area of the business
    ├── marketing/
    ├── finance/
    └── apps/
```

**Shared knowledge at the top, areas below.** Everyone you give access to reads the shared files. Each area is its own git repo, so when your team grows you can give the bookkeeper finance and a contractor marketing, and neither sees the other.

## Three ideas

1. **Context, tools, skills.** Context is what the agent should already know (these markdown files). Tools are the connections that let it act (email, calendar, books, CRM). Skills are your SOPs written down, so it does things your way every time.
2. **Open the folder you are working in.** Marketing work? Open your agent in `areas/marketing/`. General questions? The company folder. The agent reads the rules and starts briefed.
3. **Every time you re-explain something, make it a skill.** Say "write this down as a skill." That is how it gets better.

## Make your own skills

Anthropic's official [skill-creator](template/skills/skill-creator/SKILL.md) is included by default, with its helper scripts, references, review templates, license and notices. Say "make this a skill", "improve this skill", or "test this skill". Foundation's `write-skill` flow handles company placement and review; Anthropic's creator supplies the authoring and testing workflow.

The bundle is pinned to an upstream version, with documented company-integration/privacy changes. Drafting does not require installing a whole collection. Advanced testing needs compatible tools and your approval for data, costs and delegation; those capabilities aren't installed automatically. The [Foundation guide](template/skills/skill-creator/FOUNDATION.md) explains the limits.

Other [Anthropic skills](https://github.com/anthropics/skills) are available to explore when a job needs them, not automatically installed. Check each skill's license and requirements. New setups receive these defaults; existing company folders are not silently updated.

## Yours, not ours

- **You own it.** Your company OS is a folder you choose on your computer. It does not depend on this repo after setup. Existing knowledge can stay in Notion, Drive, or a wiki; the folder doesn't have to replace it.
- **GitHub is optional, and later.** It helps when a teammate needs a copy of these working files, or when their changes should come back to you for review. It is not a second copy of a wiki you already use.
- **Your privacy.** Your company folder stays on your computer and in your own GitHub. Nothing goes to 1610 unless you send it. Connections use each tool's own sign-in, and we never see your passwords. Your AI provider still receives prompts and files for processing under its own settings and policies: local storage does not mean local-only AI. `privacy.md` in your folder lists every place a copy sits, and only the places that are on.
- **No tracking.** Nothing in your company OS reports back. The only number we see is how many times the setup file is fetched.

## Toolkits

Folders are yours. Toolkits are ours: free, open source, and kept current by 1610. They plug into an area and add skills. They hold none of your data; their results stay in your folders.

- **[Marketing Toolkit](https://github.com/1610-advisory/mktkit)** — content plans, captions, video cuts, carousels, performance reports.
- **Finance Toolkit** — coming.

Claude installs toolkits as plugins. Other agents keep them in one folder, `~/toolkits/`, next to any other toolkits you use or build (1610's are named `1610-…`).

## Apps and hosting

Say "build an app", "automate this", or "where should this run?" The [app-setup skill](template/skills/app-setup/SKILL.md) checks your existing tools first, explains local versus hosted use, and helps choose the smallest suitable set of programs. Cloudflare is the preferred starting point when it fits: Workers can host the app, D1 can keep database records, and R2 can store files on one platform. Use only the pieces you need. A self-managed VPS or another managed service may suit you better.

You approve hosting, recurring costs, access and data handling before anything is provisioned or published. Setup does not require a hosting subscription, and installing these instructions does not create a server or grant deployment access. The skill also plans maintenance, backups and how to move your app later.

## Teams

Solo needs no GitHub. Your folder and each area are local git repos from day one.

When someone else should use it, say "add a teammate." One run turns on the team level:

- Your company folder, each area and one private workspace per person go to your company's GitHub as private repos, with their history.
- Nobody writes to `main`, the admin included. Each night, each computer pushes that person's work to their own branch and one standing pull request. Notes merge by themselves when the checks pass.
- The checks: a secret scan, `lint`, and a review by a second AI model. Rules files also need their owner's approval (`CODEOWNERS`).
- On each computer, small OS jobs pull every 15 minutes and push each night. The nightly check holds any file that breaks the rules, and the next session says why.
- On the admin's computer: a nightly review, a daily "to decide" list and a weekly report.
- `remove-teammate`, plus a helper that deletes the company folder from a computer after that person's access is removed. Each person accepts the delete promise in `joining-terms.md` when they join.

**A team needs a GitHub organization on the Team plan (paid).** That plan is what makes GitHub enforce review, checks and auto-merge on private repos. The free plan cannot. A self-run Forgejo also works.

**The review model.** `add-teammate` asks for one key from a second AI vendor, used only for the review check, on only the pull request under review (its title, body and diff). With no second-vendor key, it asks for a key from your own AI vendor; the check then uses a different model from that vendor and says plainly that the review is weaker. With no key at all, the check fails and says how to add one.

**Off until you turn them on:** bots, traces, hand-off to cloud agents, MDX reports, benchmarks. Large-company switches and the 5,000-staff case are in `scale.md`.

## Improve it

Solved something or built a useful skill? Say "suggest this." The agent removes your company's details, shows you the exact text, and only then opens an issue here. We feature the best ones.

## Want it built for you?

If nobody on your team will own this day to day, [1610 Advisory](https://1610advisory.com) installs it, connects your systems, and runs it until someone on your team can.

## License

Foundation's original files are MIT. Vendored Anthropic skill-creator files retain their Apache-2.0 license and upstream notices; local modifications are marked and listed in the source manifest. Built by [1610 Advisory](https://1610advisory.com).
