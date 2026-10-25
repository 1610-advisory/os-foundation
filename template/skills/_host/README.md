# Host layer

Other skills call the git host through `host.sh`. They do not call `gh` or the Forgejo API.

`host.sh` reads `host`, `host_url` and `org` from `company-profile.md`. It walks up from the current directory to find that file. `OS_PROFILE` points at the file instead. `OS_HOST`, `OS_HOST_URL` and `OS_ORG` override the file.

`profile.sh <key>` prints one value from that file. A list prints one item per line. `OS_SYNC_ENGINE` overrides `sync_engine`.

Output is JSON on stdout. `get-token` is the one exception: it prints a token for git over HTTPS.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | usage |
| 2 | not found or no access |
| 3 | host error |
| 4 | auth failed |
| 5 | offline |

`repo-access` prints `{"access":"ok"}` and exits 0, or `{"access":"no-access"}` and exits 2. Auth failure is exit 4. Offline is exit 5.

## Verbs

| Verb | Does |
|---|---|
| `whoami` | `{"login":...}` of the signed-in account |
| `create-repo <name> [--private] [--source <dir>] [--push]` | Make `<org>/<name>`. With `--source --push`, add remote `origin` and push every branch and tag. The repo is private. |
| `repo-access <name>` | `{"access":"ok"}` or `{"access":"no-access"}` |
| `protect <name> [--check <ctx>]... [--code-owners] [--approvals 0]` | Protect `main`. See the rules below. |
| `unprotect <name>` | Lift what `protect` set on `main`. `protect` restores it. |
| `secret-exists <name>` | `{"exists":true}` or `{"exists":false}`. Never prints the value. |
| `user-access <repo> <user>` | `{"access":"none"\|"read"\|"write"\|"admin"}`. A missing user is `none`. |
| `team-create <team>` | Create an org team |
| `team-add <team> <user>` | Add a user to a team |
| `team-remove <team> <user>` | Remove a user from a team |
| `grant <name> <user\|team:<team>> <read\|write\|admin>` | Grant repo access |
| `revoke <name> <user\|team:<team>>` | Revoke repo access |
| `org-remove <user>` | Remove a user from the org |
| `archive-repo <name>` | Archive the repo |
| `open-pr <name> --head <branch> --base main --title <text> [--body-file <file>]` | Open a pull request, or update the open one from the same head. `{"number":N,"url":...}` |
| `auto-merge <name> <number>` | Merge when required checks pass. Merge commit, not squash. A second call is success: `{"auto_merge":"already"}`. |
| `pr-status <name> <number>` | `{"state","merged","checks":[{"name","state"}],"approved"}` |
| `pr-comment <name> <number> --body-file <file>` | Comment on the pull request |
| `set-secret <name>` | Set an org Actions secret. The value is on stdin. |
| `get-token [--bot <bot>]` | Print a token for git over HTTPS |
| `purge-request <name>` | GitHub: print the support-request text. Forgejo: drop unreachable objects where the API allows it. |
| `delete-repo <name> --yes-test-only` | Tests only. Refuses unless `OS_TEST_MODE=1`. |

## Protect

GitHub writes two repository rulesets. `main` requires a pull request, zero approvals, and the check `checks`. It blocks force-push and deletion. It has no bypass. `rules-review` requires a code-owner review. The org admin role can bypass that one rule on a pull request. The admin's own rules change still needs the green check, but not a second person. A live check of that bypass is Tier B. This layer does not call GitHub.

Forgejo turns push off, requires the status check, and sets `block_on_official_review_requests`. With `CODEOWNERS` committed, Forgejo asks the owner to review a pull request that changes an owned file. The block stops the merge until that review happens. A notes change that touches no owned file can still merge on green checks. The result is `code_owners: request-block`. This is weaker than GitHub: a person who can merge can remove the review request.

## Tokens

Never print a token except from `get-token`. Never put a token in a URL. Debug output scrubs `Authorization` headers.

GitHub bot: `bots/<bot>/BOT.md` has `app_id`, `installation_id` and `key_path`. The key file stays outside the repo. The script signs a short JWT with `openssl` and exchanges it for an installation token.

Forgejo person: `FORGEJO_TOKEN`, or `${XDG_CONFIG_HOME:-$HOME/.config}/<slug>-os/forgejo-token`.

Forgejo bot: `token_path` in `BOT.md`, or `<config>/<slug>-os/bots/<bot>/token`.

## Dry run

`HOST_DRY_RUN=1` on GitHub prints each call as one JSON object per line and changes nothing. The object has `method`, `path` and `body`. A real run updates an existing ruleset or pull request of the same name. The dry run prints the create call so the output does not depend on live state.

`auto-merge` records `gh pr merge <number> --repo <org>/<name> --auto --merge`. That is the one GitHub verb that is not a `gh api` call. Dry-run records that same line every time. It does not know whether auto-merge is already on. A real second call exits 0 with `{"auto_merge":"already"}`: Forgejo when the merge response is 409 and the message says already scheduled, GitHub when `gh` says already enabled. Any other error is unchanged. `set-secret` records the org secret call with the value redacted. A real run uses `gh secret set` because the seal step is not in `openssl`.
