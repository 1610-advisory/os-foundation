# Security

## Report a security problem in private

Do not open a public issue for a security problem. A public issue tells everyone before there is a fix.

Use GitHub's private vulnerability reporting:

1. Open the **Security** tab of this repo.
2. Click **Report a vulnerability**.
3. Say what the problem is, which file or step, which version (`os_version:` in `company-profile.md`, or the tag), and how to see it happen.

Do not put real company data, real names or working secrets in the report. Use made-up examples.

## What happens next

- We answer within 5 working days.
- We tell you if we can see the problem, and what we plan to do.
- We fix it in a new release. We announce the problem in `CHANGELOG.md` after the release that fixes it, so companies can upgrade first.
- If you want, we name you in that note.

## Versions

We fix the newest release. A company folder gets the fix with `skills/upgrade/upgrade.sh`.
