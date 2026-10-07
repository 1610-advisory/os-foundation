# Hosting choices — use with app-setup

Choose from the job and the owner's preferences. Cloudflare is the preferred starting point for a suitable new hosted web app, not mandatory. Existing suitable tools and a requested VPS remain valid choices. Verify current official documentation and pricing before committing to a stack; these are directions to investigate, not promises of compatibility or free service.

| Option | Fits when | Explain to the owner |
|---|---|---|
| Existing business software | Their current tools can solve the job through settings, built-in automation or an integration | "We may not need a new app or hosting bill." Check plan limits, data access and automation charges. |
| Local tool | One person runs it on their computer; no shared web service or unattended uptime is needed | "It works here while this computer is available." Explain local backups and any API/AI processing charges. A static file can be shared, but that alone does not provide a shared database or background service. |
| Cloudflare Workers + Static Assets | A website or app's runtime, dependencies and data requirements fit Workers | "Cloudflare runs it without us maintaining a whole server." Check framework support and service limits. Managed hosting does not remove responsibility for app security, access and updates. |
| Self-managed VPS | They want control of a rented Linux server, already have one, or need software/runtime behavior better suited to a conventional server | "You rent a computer that stays on. Someone must patch it, secure it, monitor it and restore backups." Check compute/storage capacity and availability needs. |
| Other managed hosting | Their existing framework/provider, deployment workflow or operating needs fit better elsewhere | Consider Vercel or Netlify for supported web projects; Render or Railway for supported services, containers and background work. Check each workload against current docs, not brand reputation. |
| Managed data or backend service | The app needs durable records, files or login and the chosen host does not supply the needed features | Consider Supabase or another appropriate service. This is a component, not automatically a replacement for the app host. Verify data location, authorization, backups, export and charges. |

## Cloudflare: explain the pieces, add only what is needed

Start with Workers and Static Assets for new hosted websites/apps where they fit. Explain the main benefit: Cloudflare can host the app, keep database records with D1, and store files with R2 on one platform. That can mean fewer providers and connections to manage. It does not mean every app needs all three services or that their limits and charges are identical. Preserve an existing Pages project during unrelated work; do not migrate it just to follow a preference.
- Workers runs app logic and APIs; Static Assets serves the interface files.
- D1 is an option for relational records; R2 is an option for stored files. Neither is required for a stateless calculator.
- An existing database may stay where it is if secure connectivity and performance fit. Check current storage choices before adding another copy.
- Access can put an employee sign-in gate in front of an internal app. It is not automatically customer-account management or per-record authorization. Protect alternate origins and enforce the app's own permissions as needed.
- Scheduled or background work needs a suitable execution design. Do not treat a request handler as an unlimited always-on process. If the workload needs a conventional server, compare a VPS or managed service rather than forcing it into Workers.

Read the relevant current docs before naming services in the plan:
- [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/)
- [Framework guides](https://developers.cloudflare.com/workers/framework-guides/)
- [Runtime limits](https://developers.cloudflare.com/workers/platform/limits/) and [pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [Storage choices](https://developers.cloudflare.com/workers/platform/storage-options/)
- [Access](https://developers.cloudflare.com/cloudflare-one/access-controls/)
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/) and [secrets](https://developers.cloudflare.com/workers/configuration/secrets/)

## VPS: a real option with a real operator

A VPS can run the chosen runtime or containers and serve an app behind HTTPS. Providers such as DigitalOcean, Hetzner or a provider they already use are options to compare, not required accounts. Self-hosting on a rented VPS does not mean the data stays on their own computer.
Before a release, agree who handles these and save the plan in the app repo:
- Server and application updates; restricted administrator access; a firewall and HTTPS.
- Database/file volumes that survive container replacement, backups outside the server and a tested restore.
- Monitoring, service restarts, capacity, recovery after an outage and a support contact.
- Secret storage, least-privilege service access and protection of alternate ports/origins. Cloudflare DNS, Tunnel or Access may be useful additions, but they do not replace server upkeep or app authorization.

One VPS is not automatically highly available. If nobody will operate it, recommend managed hosting or paid operations help instead. Do not create a server first and assign maintenance later.

## Other options: compare what is actually included

Read the selected provider's current official docs: [Vercel](https://vercel.com/docs), [Netlify](https://docs.netlify.com/), [Render](https://render.com/docs), [Railway](https://docs.railway.com/), [Supabase](https://supabase.com/docs), or the existing provider's documentation.
Separate the interface, runtime, database, files, identity and optional email/AI services. Avoid making the owner buy all of them by default. Name each included component, separate bill, usage limit and responsibility. Managed hosting still needs a maintenance owner, data protection, tested recovery and an exit plan.
