# os-foundation

A company OS: one folder on your computer that holds your company's memory, set up so any AI agent you open there already knows how your business works.

It works with Claude (Cowork, Desktop, Code), Codex, Cursor, and Grok. Everything is plain markdown, in a folder that is yours.

## Start

Paste this into your agent:

```
Set up my company OS. Read https://1610.sh/os and follow it. Ask me one question at a time.
```

The agent asks you some questions (about 15 minutes), builds `~/{{COMPANY_SLUG}}-os/`, and shows you one useful thing it can do.

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
├── AGENTS.md                 the rules every agent reads first
├── company-profile.md        what you do
├── customers.md, offers.md, voice.md
├── people/  meetings/  decisions/
├── inbox/                    drop anything here; the agent files it
├── memory/                   what the agent learned about working here (session logs on their own branch)
├── skills/                   your SOPs, written down for the agent
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

## Yours, not ours

- **You own it.** Your company OS is your folder, on your computer and in your own GitHub if you add one. It does not depend on this repo after setup.
- **Your privacy.** Your company folder stays on your computer and in your own GitHub. Nothing goes to 1610 unless you send it. Connections use each tool's own sign-in, and we never see your passwords.
- **No tracking.** Nothing in your company OS reports back. The only number we see is how many times the setup file is fetched.

## Toolkits

Folders are yours. Toolkits are ours: free, open source, and kept current by 1610. They plug into an area and add skills. They hold none of your data; their results stay in your folders.

- **[Marketing Toolkit](https://github.com/1610-advisory/mktkit)** — content plans, captions, video cuts, carousels, performance reports.
- **Finance Toolkit** — coming.

Claude installs toolkits as plugins. Other agents keep them in one folder, `~/toolkits/`, next to any other toolkits you use or build (1610's are named `1610-…`).

## Teams

When someone else should use it, say "add a teammate." The agent puts the company folder and only the areas they need on your company's GitHub as private repos, invites them, and sets up their computer. Changes they ask for come to you, the admin, as a pull request.

The admin approval rule is enforced by GitHub on paid plans (GitHub Team). On the free plan it is a written rule that agents follow.

## Improve it

Solved something or built a useful skill? Say "suggest this." The agent removes your company's details, shows you the exact text, and only then opens an issue here. We feature the best ones.

## Want it built for you?

If nobody on your team will own this day to day, [1610 Advisory](https://1610advisory.com) installs it, connects your systems, and runs it until someone on your team can.

## License

MIT. Built by [1610 Advisory](https://1610advisory.com).
