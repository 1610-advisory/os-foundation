# <Project name>

A project in the **<area>** area: one piece of work with an end and a done test, that takes many agent sessions. This folder holds its planning and memory. Tool code lives in its own tool repo (`skills/app-setup/` in the company folder), never here.

The area rules (`../../AGENTS.md`) and the company rules (`../../../../AGENTS.md`) apply here. Read them if your agent did not load them. Company rules come first.

## What it is

- **Goal:** <one or two lines>
- **Owner:** <person slug>. **Owning area:** <area>. **Other areas touched:** <none, or the list>
- **Done test:** <how anyone can check that it is finished>
- **Tool repo(s):** <none, or the repo names>
- **State:** open <!-- open, paused or closed -->

## How to work here

1. Read this file, then the top of `LOG.md` (where the last session stopped), then `status.json`.
2. Do the next open item. In `status.json`, mark an item only `pass` or `fail`, with the date.
3. Before you stop, add an entry at the top of `LOG.md`: what you did, what is open, the next step.
4. A choice that later sessions must not undo goes in `decisions/` (one file each, see `decisions/README.md`). A comparison of options goes in `compare/`.
5. When the done test passes, set **State** to closed, and update the project's line in `../README.md`.

<!-- Add project-specific rules below: data sources, who reviews, what not to touch. Rules here may only tighten the area and company rules, never loosen them. -->

## Project rules

- (none yet)
