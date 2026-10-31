"""upgrade.sh --refresh: a v1 company made from next/v1's template takes this one."""
from __future__ import annotations

import os
import shutil
import subprocess
import tarfile
import io
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "template"
UPGRADE = TEMPLATE / "skills" / "upgrade" / "upgrade.sh"
OLD_REF = "origin/next/v1"


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
  auto-merge) printf '%s\\n' '{"ok":true}' ;;
  *) printf '%s\\n' '{"ok":true}' ;;
esac
"""


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
        # Only skills/ and .github/ change.
        changed = run(["git", "--git-dir", str(self.bare), "diff", "--name-only", "main", ref],
                      env=self.env).stdout.split()
        self.assertTrue(changed)
        self.assertTrue(all(p.startswith(("skills/", ".github/")) for p in changed), changed)
        # main is untouched, and a second run is current.
        self.assertEqual(run(["git", "-C", str(self.company), "status", "--porcelain"], env=self.env).stdout, "")
        run(["git", "--git-dir", str(self.bare), "update-ref", "refs/heads/main", ref], env=self.env, check=True)
        again = self.refresh()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertIn("refresh: the company folder is current (1 kept)", again.stdout)

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


if __name__ == "__main__":
    unittest.main()
