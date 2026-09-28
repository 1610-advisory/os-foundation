---
name: add-function
description: Add a function folder (sales, operations, HR, product, ...) to an existing company folder. Use when the person says "add sales to <company>", "I'm taking over operations", or "set up a folder for <function>".
---

# Add a function

1. Confirm which company. Work only inside `~/os/<company-slug>/`.
2. Pick a slug for the function (`sales`, `operations`, `people`, `customer-service`). If the folder exists, stop.
3. Copy `~/os/system/company-template/_function/` to `~/os/<company-slug>/<function-slug>/` (for marketing or finance, copy those template folders instead). Replace `{{COMPANY_NAME}}`, `{{COMPANY_SLUG}}`, `{{FUNCTION_NAME}}`, `{{DATE}}`.
4. Ask three questions, one at a time, and write the answers into the new `AGENTS.md`:
   - What does this job produce each week? (reports, posts, invoices, quotes, ...)
   - Which tools does it use?
   - What does "done well" look like? Anyone you learned it from?
5. Add the function to the "Functions" list in `<company>/company.md` and `<company>/AGENTS.md`.
6. For each recurring output they named, offer to write a skill for it later (`write-skill`). Do not write them all now.
