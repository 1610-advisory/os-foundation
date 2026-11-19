---
type: apps
updated: {{DATE}}
---

# Apps

One record per tool. Tool code and data live in each tool's own repo and data file, never in this folder.
Each data file a tool owns also has a line in its owning area's `datasets.md`.

| Tool | What it does | Owning area | Repo | Version | Address | Who may use it | Status |
|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |

How to fill a record:
- **Owning area:** the area whose manager approves it. A tool everyone in the company uses is owned by `everyone`.
- **Version:** the pinned version that runs (for example `crm 0.1.0`). A general tool is used at a pinned version, never as a copied fork.
- **Address:** behind the kernel, `{{COMPANY_SLUG}}.1610.tools/t/<tool>/`. A local preview: `local preview`. A stopgap: its own address.
- **Who may use it:** the group the area manager approved, or `builder only` for a personal tool.
- **Status:** `building`, `local preview`, `live`, `stopgap` or `retired`.
- **Stopgap only:** add one line under the table: why it is a stopgap, and what must be true for it to move behind the kernel.

Example record (made up):

| crm | Customers, leads, bids, jobs and the timeline | sales | `<org>/crm` (1610 general tool) | 0.1.0 | `acme.1610.tools/t/crm/` | sales, ops | live |
