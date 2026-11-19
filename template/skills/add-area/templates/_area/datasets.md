---
type: datasets
updated: {{DATE}}
---

# Datasets: {{AREA_NAME}}

Where this area's records live. One line per data file or dataset. An agent reads this first to know where to look.
Records live in a tool's SQLite file or a dataset, never in this folder. This list holds no rows and no secrets.

| Name | Owning tool or source | File | As of | Lock | Answers | Test? |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

How to fill a line:
- **Name:** a plain name ("Customers", "Jobs", "Bank lines 2025").
- **Owning tool or source:** the tool that writes it (from the Apps area), or the outside system it is copied from.
- **File:** the SQLite file and where it is (for example `crm.sqlite` on the company kernel). For a live read with no copy, write `live`.
- **As of:** `live`, or the date and time of the last copy, or the schedule (`daily 02:00`).
- **Lock:** who may read it: `area`, `area + owner` (a person also sees rows they own), named people or a group, or `owner only`.
- **Answers:** the questions it answers, in the words people use ("which jobs are late", "where did this lead come from").
- **Test?:** `test` for made-up data. Test and real data are never mixed in one answer.

Example line (made up):

| Customers | crm (tool) | `crm.sqlite` on the kernel | live | area + owner | who is this customer, where did the lead come from, what jobs do they have | no |
