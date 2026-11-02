#!/bin/bash
# B74 on a Windows runner, in Git Bash: MSYS rewrites a gh api path that starts with /
# into a Windows path. The old form fails; host.sh (no leading slash) reads the repo.
# Read-only. GH_TOKEN is the job's own token; this repo is public.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
owner=${GITHUB_REPOSITORY%%/*}
name=${GITHUB_REPOSITORY#*/}
err=$(mktemp)
trap 'rm -f "$err"' EXIT

# The old form: a direct call with a leading slash, as github.sh made before B74.
if gh api "/repos/${GITHUB_REPOSITORY}" > /dev/null 2> "$err"; then
  printf '%s\n' "B74 FAIL: gh api /repos/... worked here; the rewrite was not seen"
  exit 1
fi
printf 'B74 old form fails as expected: %s\n' "$(head -n 1 "$err")"

# The same path with no leading slash works.
gh api "repos/${GITHUB_REPOSITORY}" --jq .full_name > /dev/null

# The product: a real read-only host verb through Git Bash.
out=$(OS_HOST=github OS_ORG="$owner" OS_HOST_URL="" OS_SLUG="$name" \
  OS_PROFILE="$root/tests/host/fixtures/company/company-profile.md" \
  "$root/template/skills/_host/host.sh" repo-access "$name")
[ "$out" = '{"access":"ok"}' ] || { printf 'B74 FAIL: repo-access said %s\n' "$out"; exit 1; }
printf '%s\n' "B74 PASS repo-access ${GITHUB_REPOSITORY}: ${out}"
