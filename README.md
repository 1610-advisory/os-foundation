# OS Starter

One folder for your work and your company, set up so an AI agent already knows how you work when you open it.

It works with Claude (Code, Desktop, Cowork), Codex, Cursor, or any agent that can read files. Everything is plain markdown on your own computer.

## Start

Paste this into your agent:

```
Set up my AI operating system. Read https://raw.githubusercontent.com/1610-advisory/os-starter/main/START.md and follow it step by step. Ask me one question at a time.
```

Or clone it yourself:

```
git clone https://github.com/1610-advisory/os-starter.git ~/os
cd ~/os
claude        # or: codex, or open the folder in Cursor
```

Then say "run setup."

Setup takes about 15 minutes. The agent interviews you, builds your company folder, and helps you connect the tools you already use.

## What you end up with

```
~/os/
├── AGENTS.md          the rules every agent reads first
├── inbox/             drop anything here; the agent files it
├── wiki/              people, notes, ideas (your personal knowledge)
├── calendar/          meetings, reviews
├── efforts/           personal projects
├── tools/             shared toolkits (like the Marketing Toolkit)
├── system/            agent memory and skills
└── your-company/      one folder per company you work in
    ├── AGENTS.md      what the company is, who you are there
    ├── core/          shared knowledge: about, customers, offers, voice, people, meetings
    ├── marketing/     one folder per function you work in
    ├── finance/
    └── memory/        what the agent learned about working here
```

## The three ideas

1. **Context, tools, skills.** Context is what the agent should already know (markdown files). Tools are the connections that let it act (email, calendar, books, CRM). Skills are your SOPs written down, so it does things your way every time.
2. **One company, one folder.** Everything about a company lives in its folder. If you work in more than one, each is its own silo and the agent never mixes them.
3. **Open the folder you are working in.** Doing marketing? Open `your-company/marketing/`. The agent reads the rules for your OS, then the company, then the function, and starts briefed.

## Add more later

- "Add a company" builds another company folder.
- "Add a function" adds sales, operations, HR, or anything else to a company.
- "Connect a tool" walks you through one connection.
- "Process my inbox" and "lint the vault" keep it tidy.

## License

MIT. Built by [1610 Advisory](https://1610advisory.com).
