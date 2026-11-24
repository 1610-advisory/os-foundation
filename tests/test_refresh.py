"""upgrade.sh --refresh: a v1 company made from next/v1's template takes this one."""
from __future__ import annotations

import os
import shutil
import subprocess
import tarfile
import io
import json
import re
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "template"
UPGRADE = TEMPLATE / "skills" / "upgrade" / "upgrade.sh"
# A v1 company from before the redesign (next/v1 at #40). A fixed commit: once a
# branch starts from next/v1, next/v1 is no longer far behind the template.
OLD_REF = "136a0f34a5e3af971b925cbe149366cca223265e"


def run(cmd, env=None, cwd=None, check=False):
    result = subprocess.run(cmd, env=env, cwd=cwd, text=True, capture_output=True)
    if check and result.returncode != 0:
        raise AssertionError(f"{cmd} failed:\n{result.stdout}\n{result.stderr}")
    return result


def git_env(home):
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "GIT_AUTHOR_NAME": "Ada Admin",
        "GIT_AUTHOR_EMAIL": "ada@acme.test",
        "GIT_COMMITTER_NAME": "Ada Admin",
        "GIT_COMMITTER_EMAIL": "ada@acme.test",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": str(home / ".gitconfig"),
    })
    return env


FAKE_HOST = """#!/bin/bash
printf '%s\\n' "$*" >> "LOG"
case "$1" in
  whoami) printf '%s\\n' '{"login":"acme-admin"}' ;;
  get-token) printf '%s\\n' local-token ;;
  open-pr) printf '%s\\n' '{"number":7,"url":"http://example.test/7"}' ;;
  open-prs) if [ -n "${FAKE_OPEN_PRS:-}" ]; then cat "$FAKE_OPEN_PRS"; else printf '%s\\n' '{"prs":[]}'; fi ;;
  auto-merge) printf '%s\\n' '{"ok":true}' ;;
  *) printf '%s\\n' '{"ok":true}' ;;
esac
"""


def workflow_step(name):
    """The run: body of one step of the checks workflow, as a script."""
    lines = (TEMPLATE / ".github" / "workflows" / "checks.yml").read_text(encoding="utf-8").splitlines()
    start = lines.index(f"      - name: {name}")
    run_at = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: |")
    body = []
    for line in lines[run_at + 1:]:
        if line.startswith("      - name:") or line.startswith("      # "):
            break
        body.append(line[10:] if line.startswith(" " * 10) else line.strip())
    return "\n".join(body) + "\n"


class RefreshTests(unittest.TestCase):
    def setUp(self):
        if run(["git", "-C", str(ROOT), "rev-parse", "--verify", "-q", OLD_REF]).returncode != 0:
            self.skipTest(f"{OLD_REF} is not fetched")
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-refresh-"))
        self.home = self.tmp / "home"
        self.home.mkdir()
        (self.home / ".gitconfig").write_text("[init]\n\tdefaultBranch = main\n")
        self.env = git_env(self.home)
        self.company = self.tmp / "acme"
        self.bare = self.tmp / "acme-os.git"
        # The company as next/v1's setup left it: the template copied, profile filled.
        archive = subprocess.run(["git", "-C", str(ROOT), "archive", "--format=tar", OLD_REF, "template"],
                                 capture_output=True, check=True).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(self.tmp / "old", filter="tar")
        shutil.copytree(self.tmp / "old" / "template", self.company, symlinks=True)
        profile = self.company / "company-profile.md"
        text = profile.read_text().replace("{{COMPANY_SLUG}}", "acme").replace("{{COMPANY_NAME}}", "Acme Co")
        self.solo_text = text
        text = text.replace("level: solo", "level: team").replace("host: none", "host: github")
        text = text.replace('org: ""', "org: acme-os-test")
        profile.write_text(text)
        # Setup filled every other placeholder (lint fails on one).
        for path in self.company.rglob("*.md"):
            rel = path.relative_to(self.company).as_posix()
            if path.is_symlink() or rel.startswith(("skills/", ".github/", ".agents/", ".claude/")):
                continue
            text = path.read_text()
            if "{{" in text:
                path.write_text(re.sub(r"\{\{[A-Z_]+\}\}", "Acme", text))
        # The company changed one stock skill, wrote one of its own, and still has a
        # stock file a later release dropped.
        ingest = self.company / "skills" / "ingest" / "SKILL.md"
        ingest.write_text(ingest.read_text() + "\nAcme: file invoices under finance.\n")
        own = self.company / "skills" / "acme-quotes" / "SKILL.md"
        own.parent.mkdir(parents=True)
        own.write_text("---\nname: acme-quotes\n---\n\nQuotes the Acme way.\n")
        gone = run(["git", "-C", str(ROOT), "log", "-1", "--format=%H", "--diff-filter=D", "--",
                    "template/skills/logs-folder/SKILL.md"], check=True).stdout.strip()
        dropped = self.company / "skills" / "logs-folder" / "SKILL.md"
        dropped.parent.mkdir(parents=True, exist_ok=True)
        dropped.write_text(run(["git", "-C", str(ROOT), "show",
                                f"{gone}^:template/skills/logs-folder/SKILL.md"], check=True).stdout)
        run(["git", "init", "-q", "-b", "main", str(self.company)], env=self.env, check=True)
        run(["git", "-C", str(self.company), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "Company OS: start"], env=self.env, check=True)
        run(["git", "init", "-q", "--bare", "-b", "main", str(self.bare)], env=self.env, check=True)
        run(["git", "-C", str(self.company), "remote", "add", "origin", str(self.bare)], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        cfg = self.home / ".config" / "acme-os"
        cfg.mkdir(parents=True)
        (cfg / "me").write_text("ada\n")
        host = self.tmp / "host"
        host.mkdir()
        self.log = host / "calls.log"
        (host / "host.sh").write_text(FAKE_HOST.replace("LOG", str(self.log)))
        (host / "host.sh").chmod(0o755)
        self.env["OS_HOST_SH"] = str(host / "host.sh")

    def tearDown(self):
        shutil.rmtree(getattr(self, "tmp", ""), ignore_errors=True)

    def refresh(self, *extra):
        return run(["bash", str(UPGRADE), "--refresh", "--root", str(self.company),
                    "--template", str(TEMPLATE), *extra], env=self.env, cwd=self.company)

    def host_blob(self, ref, path):
        return run(["git", "--git-dir", str(self.bare), "rev-parse", "-q", "--verify", f"{ref}:{path}"],
                   env=self.env).stdout.strip()

    def test_without_refresh_a_v1_company_is_told_how(self):
        result = run(["bash", str(UPGRADE), "--root", str(self.company), "--template", str(TEMPLATE)],
                     env=self.env, cwd=self.company)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already v1. To bring stock skills and checks to this template, run it with --refresh",
                      result.stdout)

    def test_dry_run_changes_nothing(self):
        result = self.refresh("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("refresh: the company folder:", result.stdout)
        self.assertIn("kept: the company folder skills/ingest/SKILL.md", result.stdout)
        heads = run(["git", "ls-remote", "--heads", str(self.bare)], env=self.env).stdout
        self.assertNotIn("rules/", heads)

    def test_dry_run_never_keeps_the_generated_lists_and_names_drop_logs(self):
        # Round 6: the stock lists are generated, never "changed by the company", and an old
        # v0 logs branch still on the host gets the admin's drop-logs line.
        scripts = self.company / ".github" / "scripts"
        scripts.mkdir(parents=True, exist_ok=True)
        for name in ("stock-current.txt", "stock-hashes.txt"):
            path = scripts / name
            path.write_text((path.read_text() if path.exists() else "") + "0000000000000000000000000000000000000000 skills/old/SKILL.md\n")
        run(["git", "-C", str(self.company), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "older lists"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main", "main:logs"], env=self.env, check=True)
        result = self.refresh("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("stock-current.txt (changed by the company", result.stdout)
        self.assertNotIn("stock-hashes.txt (changed by the company", result.stdout)
        self.assertIn("kept: the company folder skills/ingest/SKILL.md", result.stdout)
        self.assertIn("delete it with: skills/_host/host.sh drop-logs acme-os", result.stdout)

    def test_refresh_opens_one_rules_pull_request_with_only_stock_files(self):
        release = (TEMPLATE / ".github" / "scripts" / "tools-release").read_text().strip()
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        branch = f"rules/ada/refresh-{release}"
        self.assertIn("opened: acme-os 7", result.stdout)
        self.assertIn(f"open-pr acme-os --head {branch} --base main", self.log.read_text())
        ref = f"refs/heads/{branch}"
        # Every stock file now matches this template.
        for rel in ("skills/sync/push.sh", "skills/sync/pull.sh", ".github/workflows/checks.yml",
                    ".github/scripts/checkout.sh", "skills/sync/re-apply.md"):
            want = run(["git", "hash-object", str(TEMPLATE / rel)], env=self.env).stdout.strip()
            self.assertEqual(self.host_blob(ref, rel), want, rel)
        # Scripts keep their mode.
        mode = run(["git", "--git-dir", str(self.bare), "ls-tree", ref, "skills/sync/sync.sh"],
                   env=self.env).stdout.split()[0]
        self.assertEqual(mode, "100755")
        # The company's own work is untouched; the changed stock file is kept and named.
        self.assertEqual(self.host_blob(ref, "skills/ingest/SKILL.md"), self.host_blob("main", "skills/ingest/SKILL.md"))
        self.assertEqual(self.host_blob(ref, "skills/acme-quotes/SKILL.md"),
                         self.host_blob("main", "skills/acme-quotes/SKILL.md"))
        self.assertIn("kept: the company folder skills/ingest/SKILL.md", result.stdout)
        # A stock file a later release dropped goes.
        self.assertEqual(self.host_blob(ref, "skills/logs-folder/SKILL.md"), "")
        # Only skills/ and .github/ change, and the stock bots names in the rules files and
        # the profile (v1.0.8 rename).
        changed = run(["git", "--git-dir", str(self.bare), "diff", "--name-only", "main", ref],
                      env=self.env).stdout.split()
        self.assertTrue(changed)
        renamed = ("AGENTS.md", "review-rules.md", "company-profile.md")
        self.assertTrue(all(p.startswith(("skills/", ".github/")) or p in renamed for p in changed), changed)
        for rel in renamed:
            if rel in changed:
                diff = run(["git", "--git-dir", str(self.bare), "diff", "-U0", "main", ref, "--", rel],
                           env=self.env).stdout
                gone = [l for l in diff.splitlines() if l.startswith("-") and not l.startswith("---")]
                self.assertTrue(all("bots" in l for l in gone), diff)
        # main is untouched, and a second run is current.
        self.assertEqual(run(["git", "-C", str(self.company), "status", "--porcelain"], env=self.env).stdout, "")
        run(["git", "--git-dir", str(self.bare), "update-ref", "refs/heads/main", ref], env=self.env, check=True)
        again = self.refresh()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertIn("refresh: the company folder is current (1 kept)", again.stdout)

    def test_refresh_pull_request_passes_the_checks_with_the_fake_review(self):
        # B57: the stock skills alone are far over the review's limit. The refresh puts this
        # release's tools and stock list on main first, so the review leaves the stock texts
        # out and the pull request passes on its own, with no /override.
        release = (TEMPLATE / ".github" / "scripts" / "tools-release").read_text().strip()
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"(?m)^checks-on-main: acme-os")
        self.assertNotIn("too large for the model review", result.stdout)
        # B58: the step still prints the exact comment for a review that fails it.
        self.assertIn("override: acme-os 7 if the model review fails it: read the finding. If the change is only "
                      "what the pull request body says, the admin comments on it: /override", result.stdout)
        calls = self.log.read_text()
        self.assertLess(calls.index("unprotect acme-os"), calls.index("protect acme-os --code-owners"))
        self.assertLess(calls.index("protect acme-os --code-owners"), calls.index("open-pr acme-os"))
        branch = f"rules/ada/refresh-{release}"
        for name in ("stock-hashes.txt", "stock-current.txt"):
            self.assertEqual(self.host_blob("main", ".github/scripts/" + name),
                             run(["git", "hash-object", str(TEMPLATE / ".github/scripts" / name)],
                                 env=self.env).stdout.strip())
        whole = run(["git", "--git-dir", str(self.bare), "diff", "main..." + branch], env=self.env).stdout
        self.assertGreater(len(whole.encode()), 100000)
        # The checks job, as the workflow runs it, on a runner with this pull request.
        work = self.tmp / "work"
        run(["git", "clone", "-q", "--no-checkout", str(self.bare), str(work)], env=self.env, check=True)
        head = run(["git", "-C", str(work), "rev-parse", f"origin/{branch}"], env=self.env, check=True).stdout.strip()
        base = run(["git", "-C", str(work), "rev-parse", "origin/main"], env=self.env, check=True).stdout.strip()
        run(["git", "-C", str(work), "checkout", "-q", "--detach", head], env=self.env, check=True)
        event = self.tmp / "event.json"
        event.write_text(json.dumps({"pull_request": {
            "number": 7, "title": "Refresh", "body": "Refresh of the stock skills.",
            "head": {"ref": branch, "sha": head}, "base": {"ref": "main", "sha": base}}}))
        verdicts = self.tmp / "verdicts.txt"
        verdicts.write_text("* PASS\n")
        bin_dir = self.tmp / "ci-bin"
        bin_dir.mkdir()
        (bin_dir / "curl").write_text(textwrap.dedent("""\
            #!/bin/bash
            cfg=$2
            out=$(sed -n 's/^output = "\\(.*\\)"$/\\1/p' "$cfg")
            data=$(sed -n 's/^data-binary = "@\\(.*\\)"$/\\1/p' "$cfg")
            [ -z "$data" ] || cat "$data" >> "$FAKE_DIR/posted"
            printf '%s' '{"id":1}' > "$out"
            printf '201'
            """))
        (bin_dir / "curl").chmod(0o755)
        (self.tmp / "runner").mkdir()
        ci_env = dict(self.env)
        ci_env.pop("OS_HOST_SH", None)
        ci_env.update({
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "FAKE_DIR": str(self.tmp),
            "JOB_TOKEN": "job-token-test-value",
            "GITHUB_WORKSPACE": str(work),
            "GITHUB_SERVER_URL": "http://forgejo.test",
            "GITHUB_API_URL": "http://forgejo.test/api/v1",
            "GITHUB_REPOSITORY": "acme/acme-os",
            "GITHUB_EVENT_NAME": "pull_request",
            "GITHUB_EVENT_PATH": str(event),
            "RUNNER_TEMP": str(self.tmp / "runner"),
            "OS_REVIEW_FAKE": str(verdicts),
        })
        for name in ("base tools", "run checks"):
            script = self.tmp / f"{name.replace(' ', '-')}.sh"
            script.write_text(workflow_step(name))
            proc = run(["bash", str(script)], env=ci_env, cwd=work)
            if name == "run checks":
                # v1.0.4 (B89): the review passes, but a rules change waits for an owner's /approve.
                self.assertEqual(proc.returncode, 1, f"{name}:\n{proc.stdout}\n{proc.stderr}")
                self.assertIn("waiting for owner: an owner comments /approve", proc.stdout + proc.stderr)
            else:
                self.assertEqual(proc.returncode, 0, f"{name}:\n{proc.stdout}\n{proc.stderr}")
        posted = (self.tmp / "posted").read_text()
        self.assertIn("VERDICT: PASS", posted)
        self.assertIn("WAITING FOR OWNER", posted)
        self.assertNotIn("too large", proc.stdout + proc.stderr)

    def test_refresh_closes_its_own_older_refresh_pull_request(self):
        """Round 4: an open refresh for an older release is closed, with a comment naming the new one."""
        release = (TEMPLATE / ".github" / "scripts" / "tools-release").read_text().strip()
        older = str(int(release) - 1)
        prs = self.tmp / "prs.json"
        prs.write_text(json.dumps({"prs": [
            {"number": 3, "head": f"rules/ada/refresh-{older}", "body": ""},
            {"number": 4, "head": f"rules/bea/refresh-{older}", "body": ""},
            {"number": 5, "head": "sync/ada/laptop", "body": ""},
        ]}))
        self.env["FAKE_OPEN_PRS"] = str(prs)
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"closed: acme-os 3 (refresh for release {older}; replaced by 7)", result.stdout)
        calls = self.log.read_text().splitlines()
        self.assertIn("pr-comment acme-os 3 --body-file", "\n".join(calls))
        self.assertIn("close-pr acme-os 3", calls)
        # Only the admin's own refresh goes: not another person's, not a sync pull request.
        self.assertNotIn("close-pr acme-os 4", calls)
        self.assertNotIn("close-pr acme-os 5", calls)

    def test_refresh_fetch_prunes_a_stale_ref(self):
        """B59: an old sync/<me> ref beside sync/<me>/<seat> on the host does not stop the fetch."""
        run(["git", "-C", str(self.company), "update-ref", "refs/remotes/origin/sync/ada", "HEAD"],
            env=self.env, check=True)
        run(["git", "--git-dir", str(self.bare), "update-ref", "refs/heads/sync/ada/laptop", "main"],
            env=self.env, check=True)
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("refresh: could not reach", result.stdout)
        self.assertIn("opened: acme-os 7", result.stdout)

    def test_refresh_fetch_error_says_what_the_host_answered(self):
        """B59: a fetch the host answered is not 'could not reach'."""
        run(["git", "-C", str(self.company), "remote", "set-url", "origin", str(self.tmp / "no-such-repo.git")],
            env=self.env, check=True)
        result = self.refresh()
        self.assertNotIn("could not reach", result.stdout)
        self.assertRegex(result.stdout, r"refresh: the host (answered, but the fetch for the company folder failed|"
                                        r"refused the sign-in or the repo for the company folder) \(git: ")

    def drop_root_files(self):
        """A company upgraded from v0 before v1.0.3: no joining-terms.md, no scale.md."""
        run(["git", "-C", str(self.company), "rm", "-q", "joining-terms.md", "scale.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "as an old upgrade left it"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)

    def test_refresh_adds_missing_root_files_with_the_name(self):
        # B81: join needs joining-terms.md. The refresh adds each company-root file v1
        # ships that main lacks, with the company name filled, in its pull request.
        self.drop_root_files()
        release = (TEMPLATE / ".github" / "scripts" / "tools-release").read_text().strip()
        dry = self.refresh("--dry-run")
        self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ref = f"refs/heads/rules/ada/refresh-{release}"
        terms = run(["git", "--git-dir", str(self.bare), "show", f"{ref}:joining-terms.md"], env=self.env).stdout
        want = (TEMPLATE / "joining-terms.md").read_text().replace("{{COMPANY_NAME}}", "Acme Co")
        self.assertEqual(terms, want)
        self.assertNotIn("{{", terms)
        scale = run(["git", "hash-object", str(TEMPLATE / "scale.md")], env=self.env).stdout.strip()
        self.assertEqual(self.host_blob(ref, "scale.md"), scale)
        mode = run(["git", "--git-dir", str(self.bare), "ls-tree", ref, "joining-terms.md"], env=self.env).stdout.split()[0]
        self.assertEqual(mode, "100644")
        # Once it merges, a second run changes nothing.
        run(["git", "--git-dir", str(self.bare), "update-ref", "refs/heads/main", ref], env=self.env, check=True)
        again = self.refresh()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertIn("refresh: the company folder is current (1 kept)", again.stdout)

    def test_refresh_never_touches_the_company_terms(self):
        # A copy the company edited is its own: not replaced, not listed as kept.
        terms = self.company / "joining-terms.md"
        terms.write_text(terms.read_text() + "\nAcme: laptops go back to the office.\n")
        run(["git", "-C", str(self.company), "commit", "-q", "-am", "our terms"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        release = (TEMPLATE / ".github" / "scripts" / "tools-release").read_text().strip()
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ref = f"refs/heads/rules/ada/refresh-{release}"
        self.assertEqual(self.host_blob(ref, "joining-terms.md"), self.host_blob("main", "joining-terms.md"))
        self.assertNotIn("joining-terms.md", result.stdout)

    def test_solo_refresh_commits_the_missing_terms(self):
        (self.company / "company-profile.md").write_text(self.solo_text)
        run(["git", "-C", str(self.company), "commit", "-q", "-am", "solo"], env=self.env, check=True)
        self.drop_root_files()
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        head = run(["git", "-C", str(self.company), "show", "HEAD:joining-terms.md"], env=self.env).stdout
        self.assertTrue(head.startswith("# Joining terms — Acme Co\n"), head[:80])
        self.assertEqual(run(["git", "-C", str(self.company), "status", "--porcelain"], env=self.env).stdout, "")
        again = self.refresh()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertIn("refresh: the company folder is current", again.stdout)

    def test_solo_commits_on_main(self):
        # No host: everything at solo is a commit on main.
        (self.company / "company-profile.md").write_text(self.solo_text)
        run(["git", "-C", str(self.company), "commit", "-q", "-am", "solo"], env=self.env, check=True)
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("committed: the company folder", result.stdout)
        self.assertFalse(self.log.exists())
        want = run(["git", "hash-object", str(TEMPLATE / "skills/sync/push.sh")], env=self.env).stdout.strip()
        have = run(["git", "-C", str(self.company), "rev-parse", "HEAD:skills/sync/push.sh"], env=self.env).stdout.strip()
        self.assertEqual(have, want)
        self.assertIn("Acme: file invoices", (self.company / "skills/ingest/SKILL.md").read_text())

    # v1.0.8: bots becomes automations (skills/upgrade/rename.sh).
    BOT_PAGE = textwrap.dedent("""\
        ---
        type: bot
        summary: "Files the inbox"
        name: "Helper"
        bot: helper
        kind: company
        owner: ada
        bot_user: helper
        email: "helper@acme.test"
        repos:
          - acme-os
        ---

        # Helper
        """)

    def add_bots(self, root, switches="[bots, traces]"):
        page = root / "bots" / "helper" / "BOT.md"
        page.parent.mkdir(parents=True)
        page.write_text(self.BOT_PAGE)
        routine = root / "bots" / "helper" / "routines" / "daily.md"
        routine.parent.mkdir()
        routine.write_text("Each weekday at 6 am, file the shared inbox.\n")
        if switches is not None:
            profile = root / "company-profile.md"
            text = profile.read_text()
            if switches.startswith("\n"):
                text = re.sub(r"(?m)^switches: \[\][^\n]*", "switches:" + switches, text)
            else:
                text = re.sub(r"(?m)^switches: \[\]", f"switches: {switches}", text)
            profile.write_text(text)
        for rel, line in ((".github/CODEOWNERS", "/bots/*/BOT.md @acme-admin"),
                          (".gitea/CODEOWNERS", "^bots/[^/]+/BOT\\.md$ @acme-admin")):
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# Rules files only. Notes have no code owner.\n**/AGENTS.md @acme-admin\n" + line + "\n")
        run(["git", "-C", str(root), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(root), "commit", "-q", "-m", "a bot"], env=self.env, check=True)

    def show(self, ref, rel, git_dir=None):
        return run(["git", "--git-dir", str(git_dir or self.bare), "show", f"{ref}:{rel}"], env=self.env).stdout

    def test_refresh_renames_bots_to_automations(self):
        self.add_bots(self.company)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        # A person's own bots in their workspace: never touched.
        mine = self.company / "users" / "ada" / "bots" / "mine" / "BOT.md"
        mine.parent.mkdir(parents=True)
        mine.write_text("my own bot\n")
        dry = self.refresh("--dry-run")
        self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
        self.assertIn("rename: the company folder bots/ to automations/ (1 folders; each BOT.md becomes AUTOMATION.md)",
                      dry.stdout)
        self.assertIn("rename: the company folder company-profile.md: bots becomes automations", dry.stdout)
        self.assertIn("rename: the company folder .github/CODEOWNERS:", dry.stdout)
        self.assertIn("rename: the company folder .gitea/CODEOWNERS:", dry.stdout)
        self.assertEqual(run(["git", "ls-remote", "--heads", str(self.bare), "rules/*"], env=self.env).stdout, "")
        release = (TEMPLATE / ".github" / "scripts" / "tools-release").read_text().strip()
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ref = f"refs/heads/rules/ada/refresh-{release}"
        page = self.show(ref, "automations/helper/AUTOMATION.md")
        self.assertIn("type: automation\n", page)
        self.assertIn("automation: helper\n", page)
        self.assertIn("host_user: helper\n", page)
        self.assertIn("# Helper\n", page)
        self.assertEqual(self.show(ref, "automations/helper/routines/daily.md"),
                         "Each weekday at 6 am, file the shared inbox.\n")
        self.assertEqual(self.host_blob(ref, "bots/helper/BOT.md"), "")
        self.assertRegex(self.show(ref, "company-profile.md"), r"(?m)^switches: \[automations, traces\]")
        self.assertIn("Allowed: automations, traces", self.show(ref, "company-profile.md"))
        self.assertIn("\n/automations/*/AUTOMATION.md @acme-admin\n", self.show(ref, ".github/CODEOWNERS"))
        self.assertIn("\n^automations/[^/]+/AUTOMATION\\.md$ @acme-admin\n", self.show(ref, ".gitea/CODEOWNERS"))
        self.assertIn("**/AGENTS.md @acme-admin", self.show(ref, ".github/CODEOWNERS"))
        self.assertNotIn("bots/*/BOT.md", self.show(ref, "AGENTS.md"))
        # git sees a rename, with the history.
        moved = run(["git", "--git-dir", str(self.bare), "diff", "-M", "--name-status", "main", ref, "--",
                     "bots", "automations"], env=self.env).stdout
        self.assertIn("automations/helper/routines/daily.md", moved)
        self.assertRegex(moved, r"(?m)^R\d+\tbots/helper/routines/daily.md\tautomations/helper/routines/daily.md$")
        # The body says what the rename does, for the review.
        body_call = [l for l in self.log.read_text().splitlines() if l.startswith("open-pr ")]
        self.assertTrue(body_call)
        self.assertEqual(mine.read_text(), "my own bot\n")
        # Once it merges, a second run has no rename left.
        run(["git", "--git-dir", str(self.bare), "update-ref", "refs/heads/main", ref], env=self.env, check=True)
        again = self.refresh()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertNotIn("rename:", again.stdout)
        self.assertIn("refresh: the company folder is current", again.stdout)

    def test_refresh_stops_a_repo_with_both_folders(self):
        self.add_bots(self.company)
        both = self.company / "automations" / "other" / "AUTOMATION.md"
        both.parent.mkdir(parents=True)
        both.write_text("---\ntype: automation\n---\n")
        run(["git", "-C", str(self.company), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "both"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        result = self.refresh()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("refresh: stopped in the company folder: it has both bots/ and automations/.", result.stdout)
        self.assertNotIn("opened:", result.stdout)
        self.assertEqual(run(["git", "ls-remote", "--heads", str(self.bare), "rules/*"], env=self.env).stdout, "")

    def test_solo_refresh_renames_bots_on_main(self):
        (self.company / "company-profile.md").write_text(self.solo_text)
        run(["git", "-C", str(self.company), "commit", "-q", "-am", "solo"], env=self.env, check=True)
        self.add_bots(self.company, switches="\n  - bots")
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("committed: the company folder", result.stdout)
        self.assertTrue((self.company / "automations" / "helper" / "AUTOMATION.md").is_file())
        self.assertFalse((self.company / "bots").exists())
        profile = (self.company / "company-profile.md").read_text()
        self.assertRegex(profile, r"(?m)^switches:\s*\n  - automations$")
        self.assertEqual(run(["git", "-C", str(self.company), "status", "--porcelain"], env=self.env).stdout, "")
        again = self.refresh()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertNotIn("rename:", again.stdout)


class RenameFilterTests(unittest.TestCase):
    """skills/upgrade/rename.sh filters, one text at a time (v1.0.8)."""

    def filt(self, name, text):
        lib = TEMPLATE / "skills" / "upgrade" / "rename.sh"
        proc = subprocess.run(["bash", "-c", '. "$1"; "$2"', "f", str(lib), name], input=text,
                              text=True, capture_output=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout

    def test_switch_inline_block_and_bare(self):
        inline = "---\nswitches: [bots, traces]   # off by default. Allowed: bots, traces\n---\n\nbots stay here\n"
        self.assertEqual(self.filt("rename_switch_filter", inline),
                         "---\nswitches: [automations, traces]   # off by default. Allowed: automations, traces\n---\n\nbots stay here\n")
        block = "---\nswitches:\n  - traces\n  - bots\nhost: none\n---\n"
        self.assertEqual(self.filt("rename_switch_filter", block),
                         "---\nswitches:\n  - traces\n  - automations\nhost: none\n---\n")
        bare = "---\nswitches: bots\n---\n"
        self.assertEqual(self.filt("rename_switch_filter", bare), "---\nswitches: automations\n---\n")
        # A switch that only starts with bots is another switch.
        other = "---\nswitches: [bots-extra, traces]\n---\n"
        self.assertEqual(self.filt("rename_switch_filter", other), other)

    def test_keys_only_in_the_frontmatter(self):
        page = "---\ntype: bot\nbot: helper\nbot_user: acme-helper\nowner: ada\n---\n\nbot: in the body stays\n"
        self.assertEqual(self.filt("rename_keys_filter", page),
                         "---\ntype: automation\nautomation: helper\nhost_user: acme-helper\nowner: ada\n---\n\nbot: in the body stays\n")

    def test_owners_keep_the_owners_and_other_lines(self):
        github = "# Rules\n**/AGENTS.md @acme-admin\n/bots/*/BOT.md @acme-director @acme-admin\n"
        self.assertEqual(self.filt("rename_owners_filter", github),
                         "# Rules\n**/AGENTS.md @acme-admin\n/automations/*/AUTOMATION.md @acme-director @acme-admin\n")
        forgejo = "^bots/[^/]+/BOT\\.md$ @acme-admin\n^(.*/)?skills/.* @acme-admin\n"
        self.assertEqual(self.filt("rename_owners_filter", forgejo),
                         "^automations/[^/]+/AUTOMATION\\.md$ @acme-admin\n^(.*/)?skills/.* @acme-admin\n")

    def test_text_changes_only_the_stock_names(self):
        text = ("- Rules files (`skills/**`, `bots/*/BOT.md`, `CODEOWNERS`).\n"
                "- Units: `bots/<bot>/BOT.md`.\n  - [bots]: `add-bot`, `undo-run`.\n"
                "Our own line about bots stays.\n")
        self.assertEqual(self.filt("rename_text_filter", text),
                         "- Rules files (`skills/**`, `automations/*/AUTOMATION.md`, `CODEOWNERS`).\n"
                         "- Units: `automations/<automation>/AUTOMATION.md`.\n  - [automations]: `add-automation`, `undo-run`.\n"
                         "Our own line about bots stays.\n")


if __name__ == "__main__":
    unittest.main()
