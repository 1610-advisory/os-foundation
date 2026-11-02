# Scale check results

Forgejo is not GitHub. These numbers are from one local Forgejo. They do not prove a GitHub limit. At 5,000 staff the first limits are GitHub's own API rate and push rate.

This is not a live run with 5,000 people. Most staff at that size are connector readers. They do not clone. This check is the git-user load.

## Machine

| Item | Value |
| --- | --- |
| CPU | Apple M2 Max |
| Docker CPUs | 12 |
| Memory given to Docker | 7.65 GiB |
| Cap on this container | 2 CPUs, 2.00 GiB |
| Forgejo image | data.forgejo.org/forgejo/forgejo:17.0.0 |
| Forgejo version | 17.0.0+gitea-1.22.0 |
| Port | 3400 |

The container cap is there so the Acme stack on the same Docker keeps running. It is not a Forgejo limit.

## Bootstrap

| Piece | Size |
| --- | --- |
| Users | 5000 |
| Area repos | 200 |
| Company repo | 1 |
| Teams | 200 |
| Memberships | 6248 |
| Seed | 1610 |
| Users in one area | 4007 |
| Users in two areas | 738 |
| Users in three areas | 255 |

Most users are in one area. Some are in two. Some are in three. The seed is fixed, so a later run repeats the same spread.

### Phase times

| Phase | Count | Seconds |
| --- | --- | --- |
| admin | 1 | 0.8 |
| users | 5000 | 711.2 |
| org | 1 | 0.0 |
| repos | 201 | 38.5 |
| teams | 200 | 1.2 |
| grants | 200 | 1.1 |
| members | 6248 | 37.2 |

## Read denial

| Check | Result |
| --- | --- |
| Pairs | 400 |
| Allowed | 200 |
| Denied | 200 |
| Wrong answers | 0 |
| Incomplete | 0 |
| Seconds | 71.7 |
| Seed | 1610 |

Pass rule: zero wrong answers. Allowed means the user's team can write that area repo. Denied means the user is not on that team. The company repo is owner-only and is not in this sample.

## Push window

| Item | Value |
| --- | --- |
| Users | 5000 |
| Pushes that worked | 6247 |
| Pushes that failed | 1 |
| Simulated window (minutes) | 180.0 |
| Compression factor | 120.0 |
| Wall time (seconds) | 1316.6 |
| Pushes per minute, wall clock | 284.69 |
| Pushes per minute, if spread over the real window | 34.71 |
| p50 push time (seconds) | 0.282 |
| p95 push time (seconds) | 0.379 |
| Non-fast-forward conflicts | 0 |
| Standing PRs merged | 50 of 50 |
| Git concurrency | 4 |

Each person pushes one small log file on branch `sync/<person>` in each area they belong to. The start time is a random offset inside the window. Time is compressed by the factor above. The wall-clock rate is what this Forgejo handled. The window rate is what the same pushes would be if they were spread over the real hours.

Percentiles use nearest rank on pushes that worked.

### API status codes (pull request create and merge)

| Status | Count |
| --- | --- |
| 200 | 50 |
| 201 | 50 |

### API errors

None.

### Push failures

| Kind | Count |
| --- | --- |
| git-failed | 1 |

## First limit

No Forgejo error limit at this size. 5,000 users, 200 area repos, 6,248 grants, and 6,248 push attempts all completed.

The slow step was creating users: 711 seconds for 4,992 new users (about 7 a second) through the admin command. Eight users already existed, so the phase size is 5,000. Repo create, measured on the first pass of the same 201 repos, took 38.5 seconds. The idempotent second pass skipped those repos in 0.1 seconds. Adding the 6,248 memberships took 37.2 seconds. Giving each team write on its repo took about 1 second.

The container was capped at 2 CPUs and 2 GB, and git calls at 4 at once, so the Acme stack on the same Docker kept working. Peak memory for this container during the push was 346 MB of that 2 GB. Docker reported 7.65 GiB of memory (the run brief said 8 GB) and 12 CPUs.

A first push attempt was stopped by an outside signal after 3,309 pushes. That was not a Forgejo limit. Those branches were deleted and the window was run again. The push table is the completed run.

One push failed. The other 6,247 worked. There were 0 non-fast-forward conflicts, because each person pushes only their own branch. 50 standing pull requests were created and merged, with no API error. Push time stayed under half a second (p95 0.38 seconds). The wall rate of 285 pushes a minute is the 4-at-a-time cap, not a refusal from Forgejo. Spread over the real 180-minute window, the same pushes are about 35 a minute.

Degrade order item 4 was not used. The load was not cut below 5,000 users. The read-denial check was not cut.

## What this does not prove

- Forgejo is not GitHub. A number here is not a GitHub number.
- GitHub's API rate (about 5,000 requests an hour per user, about 15,000 for an Enterprise Cloud app) and GitHub's push rate are the first limits at this size. This run did not measure those. Check the current GitHub numbers before you rely on them.
- One SQLite container is not GitHub Enterprise Cloud, and it is not a multi-node Forgejo.
- The check did not create a year of log files (about 1.25 million small files). It created one small file per push.
- Connector readers, SSO, SCIM, and audit streaming were not running. Those are switches, not this load.
- Ask GitHub, in writing, whether a connector reader is an End User before a 5,000-staff rollout. The terms do not say.
