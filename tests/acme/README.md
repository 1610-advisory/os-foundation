# Acme test harness

Acme Co is a made-up company. These scripts prove the team flows on a local Forgejo. They do not use a real company.

## Run

```bash
tests/acme/forgejo/up.sh
tests/acme/forgejo/bootstrap.sh
tests/acme/run.sh --tier a --only S0
```

`up.sh` is safe to run again. `bootstrap.sh` is safe to run again. `down.sh` stops the containers. `down.sh --wipe` also removes the Acme volumes. It does not touch other Docker projects.

Tier B is not available in this phase. `run.sh --tier b` prints `BLOCKED: gates G1–G8` for each scenario.

## What is running

| Piece | Image |
|---|---|
| Forgejo | `data.forgejo.org/forgejo/forgejo:17.0.0` |
| Actions runner | `data.forgejo.org/forgejo/runner:13.2.0` |
| Job Docker | `docker:29.9.2-dind` |

Forgejo listens on `http://localhost:3300`. Job containers run in the DinD sidecar. The host Docker socket is not mounted.

The job image is built from `tests/acme/forgejo/job.Dockerfile` and loaded into DinD as `osf-acme-job:local`. The runner label `ubuntu-latest` points at that image. The image has bash, git, curl, and jq.

## Seats

| Seat | Engine | Forgejo user | Git name |
|---|---|---|---|
| admin | `claude -p` | acme-admin | Ada Admin |
| director | `codex exec` | acme-director | Dana Director |
| member-a | `claude -p` | acme-member-a | Mia Member |
| member-b | `codex exec` | acme-member-b | Max Member |
| member-c | `cursor-agent -p` | acme-member-c | Noa Member |
| member-d | `pi -p` | acme-member-d | Sam Member |
| bot | `pi -p` | acme-bot | Acme Bot |

```bash
tests/acme/seat.sh member-d prompt.txt --cwd <clone>
```

A missing engine or sign-in prints `BLOCKED: <seat> <reason>` and exits 3. The vendor login stays the one already on the computer. Each seat gets its own git name, host token, and `XDG_CONFIG_HOME`.

## Tokens

Tokens are not in this repo and are not printed. The site admin login is `osf-admin`. It is not an Acme seat.

| What | Where |
|---|---|
| Site admin token | `~/.cache/os-foundation/forgejo/admin-token` |
| Seat tokens | `~/.cache/os-foundation/forgejo/tokens/<user>` |

Files are mode 0600. The folder is mode 0700.

## Results

`tests/acme/lib/results.py` reads git and the Forgejo API only. It does not read agent chat.

```bash
tests/acme/lib/results.py repo-exists acme <repo>
tests/acme/lib/results.py protection acme <repo>
tests/acme/lib/results.py access acme <repo>
tests/acme/lib/results.py pr acme <repo> <number>
tests/acme/lib/results.py file acme <repo> <path>
tests/acme/lib/results.py trailers acme <repo> <sha>
tests/acme/lib/results.py clone-denied <user> <owner> <repo>
```
