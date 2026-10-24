# People

One page per teammate, customer contact or partner, named `Full Name.md`, made from `templates/person.md`. Pages are shared: everyone with the company folder reads them. Pay, reviews and HR notes never go here; they belong in an area with restricted access.

Teammates fill these fields. Customer contacts and partners leave them empty.

| Field | What it holds |
|---|---|
| `slug:` | Short lowercase id. Used in log file names (`memory/logs/YYYY-MM-DD-<slug>.md`) and the person's `sync/<slug>` branch. |
| `github:` | Git host username. `sync` checks it against the signed-in account (team level). |
| `email:` | Work email. |
| `role:` | `admin`, `director` or `writer`. A director approves rules changes in their areas. |
| `areas:` | The areas this person may read and write. |
| `kernel_id:` | App level only: the person's id in the 1610 OS app. |
| `left:` | The date they left. `remove-teammate` sets it. The page stays. |

A person's voice and preferences are private. They live in their workspace (`users/<slug>/profile/PROFILE.md`), not here.
