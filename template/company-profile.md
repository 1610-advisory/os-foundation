---
type: company-profile
summary: "{{ONE_LINER}}"
updated: {{DATE}}
company_slug: {{COMPANY_SLUG}}
level: solo                 # solo | team | app. Setup writes solo. add-teammate sets team. The app sets app.
switches: []                # off by default. Allowed: bots, traces, cloud-handoff, mdx-reports, benchmarks, and the scale switches in scale.md.
os_version: {{OS_VERSION}}
host: none                  # none | github | forgejo (add-teammate sets it)
host_url: ""                # Forgejo base URL. Empty for github.com.
org: ""                     # host org that owns the repos (add-teammate sets it)
sync_engine: ""             # headless command for the nightly check, for example: claude -p --model haiku (add-teammate sets it)
runner: ubuntu-latest       # runs-on label for the checks workflow
---

# {{COMPANY_NAME}}

## What we do
<!-- One or two sentences. -->

## History and size
<!-- Who started it, when, how many people. -->

## How we make money
<!-- Main revenue lines. -->

## Website
<!-- URL, or "none". -->

## Tools we use
<!-- Email, calendar, docs, chat, CRM, books. "Connected" ones are listed in architecture.md. -->
