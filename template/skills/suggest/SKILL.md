---
name: suggest
description: Send an improvement back to the people who make os-foundation or a 1610 toolkit — a fix, a new skill, or an idea — with all company data removed, and only after the person reads the exact text. Use when someone says "I solved this", "I made this", "suggest this", "send this to 1610", or "this should be in the toolkit".
---

# Suggest

This company OS belongs to the company. Nothing goes back to 1610 unless the person sends it. This skill is how they send something on purpose.

## 1. What and where

Ask what they want to share (a skill, a fix, an idea) and decide where it goes:

| It is about | Send it to |
|---|---|
| Setup, folders, or these company skills | `1610-advisory/os-foundation` |
| Marketing skills | `1610-advisory/mktkit` |
| Anything else | `1610-advisory/os-foundation` (say which tool in the text) |

## 2. Remove company data

Write the suggestion so it would help **any** business:

- No company name, people's names, customers, emails, addresses, prices, figures, or account details. Replace them with neutral examples ("Acme Co", "a customer").
- No file paths that name the company (`~/acme-os/` → `~/{{COMPANY_SLUG}}-os/`).
- No secrets, ever.

## 3. Show, then send

1. Show the person the **full text** exactly as it will be sent: title and body. Say plainly that it will be public.
2. Send only after a clear yes. Changes → edit and show again.
3. Send it as a GitHub issue: `gh issue create --repo {{REPO}} --title "{{TITLE}}" --body-file {{FILE}}`. No `gh`, or no GitHub account? Give them the text and the link `https://github.com/{{REPO}}/issues/new` to paste it themselves.
4. For a skill they want to give, put the clean skill text in the issue. 1610 picks what becomes a featured skill or plugin.

## 4. Record it

Add one line to the session log: what was suggested, where, and the issue link. No company data in the line either.
