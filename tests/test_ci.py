#!/usr/bin/env python3
"""Unit tests for the checks workflow. No network. No real keys."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "template" / ".github" / "scripts"
WORKFLOW = ROOT / "template" / ".github" / "workflows" / "checks.yml"
KEY = "OSF_REVIEW_KEY_MARKER"


def run(cmd, env=None, cwd=None):
    merged = os.environ.copy()
    merged.pop("OS_REVIEW_KEY", None)
    merged.pop("OS_REVIEW_FAKE", None)
    merged.pop("OS_REVIEW_KIND", None)
    merged.pop("OS_REVIEW_VENDOR", None)
    merged.pop("OS_REVIEW_MODEL", None)
    if env:
        merged.update(env)
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=merged,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def git(repo, *args):
    env = os.environ.copy()
    env["GIT_AUTHOR_NAME"] = "Ada Admin"
    env["GIT_AUTHOR_EMAIL"] = "ada.admin@acme.test"
    env["GIT_COMMITTER_NAME"] = "Ada Admin"
    env["GIT_COMMITTER_EMAIL"] = "ada.admin@acme.test"
    subprocess.run(["git", "-C", str(repo), *args], check=True, env=env, stdout=subprocess.PIPE)


class WorkflowTests(unittest.TestCase):
    def test_one_job(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("name: checks", text)
        self.assertEqual(text.count("runs-on:"), 1)
        self.assertIn("vars.OS_RUNNER || 'ubuntu-latest'", text)
        self.assertIn("pull_request:", text)
        self.assertIn("issue_comment:", text)
        self.assertNotIn("OS_REVIEW_FAKE:", text)
        self.assertIn("OS_REVIEW_FAKE is test-only", text)

    def test_app_is_a_comment_only(self):
        text = (SCRIPTS / "model-review.sh").read_text(encoding="utf-8")
        self.assertIn("The 1610 review App is not in v1", text)
        self.assertNotIn("1610 review App" , text.split("There is no code path", 1)[-1][:40])


class ModelReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.rules = self.root / "rules.md"
        self.rules.write_text("Review rules.\n", encoding="utf-8")
        self.title = self.root / "title"
        self.title.write_text("Add a note\n", encoding="utf-8")
        self.body = self.root / "body"
        self.body.write_text("A note.\n", encoding="utf-8")
        self.diff = self.root / "diff"
        self.out = self.root / "out"

    def review(self, env):
        return run(
            [
                "bash",
                str(SCRIPTS / "model-review.sh"),
                "--rules",
                str(self.rules),
                "--title-file",
                str(self.title),
                "--body-file",
                str(self.body),
                "--diff-file",
                str(self.diff),
                "--out",
                str(self.out),
            ],
            env=env,
        )

    def test_fake_pass_and_fail(self):
        verdicts = self.root / "verdicts"
        verdicts.write_text("OSF_REVIEW_FAIL FAIL\n* PASS\n", encoding="utf-8")
        self.diff.write_text("a note\n", encoding="utf-8")
        ok = self.review({"OS_REVIEW_FAKE": str(verdicts)})
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertIn("VERDICT: PASS", self.out.read_text(encoding="utf-8"))
        self.diff.write_text("OSF_REVIEW_FAIL\n", encoding="utf-8")
        bad = self.review({"OS_REVIEW_FAKE": str(verdicts)})
        self.assertEqual(bad.returncode, 1, bad.stderr)
        self.assertIn("VERDICT: FAIL", self.out.read_text(encoding="utf-8"))

    def test_same_vendor_label(self):
        verdicts = self.root / "verdicts"
        verdicts.write_text("* PASS\n", encoding="utf-8")
        self.diff.write_text("ok\n", encoding="utf-8")
        result = self.review({"OS_REVIEW_FAKE": str(verdicts), "OS_REVIEW_KIND": "same-vendor"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("weaker review: same vendor", self.out.read_text(encoding="utf-8"))

    def test_no_key(self):
        self.diff.write_text("ok\n", encoding="utf-8")
        result = self.review({})
        self.assertEqual(result.returncode, 1)
        self.assertIn("add a review key: see add-teammate", result.stderr)
        self.assertNotIn(KEY, result.stdout + result.stderr)

    def test_key_not_in_argv(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        argv_log = self.root / "argv.txt"
        fake = bin_dir / "curl"
        fake.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os, sys
                from pathlib import Path
                argv = sys.argv[1:]
                Path(os.environ["ARGV_LOG"]).write_text("\\n".join(argv), encoding="utf-8")
                cfg = None
                args = argv[:]
                while args:
                    item = args.pop(0)
                    if item == "--config" and args:
                        cfg = args.pop(0)
                text = Path(cfg).read_text(encoding="utf-8")
                out = ""
                for line in text.splitlines():
                    if line.startswith("output = "):
                        out = line.split("=", 1)[1].strip().strip('"')
                Path(out).write_text(
                    '{"content":[{"text":"SUMMARY: ok\\\\nVERDICT: PASS"}]}',
                    encoding="utf-8",
                )
                sys.stdout.write("200")
                """
            ),
            encoding="utf-8",
        )
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        self.diff.write_text("ok\n", encoding="utf-8")
        result = self.review(
            {
                "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                "ARGV_LOG": str(argv_log),
                "OS_REVIEW_KEY": KEY,
                "OS_REVIEW_VENDOR": "anthropic",
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        recorded = argv_log.read_text(encoding="utf-8")
        self.assertNotIn(KEY, recorded)
        self.assertNotIn(KEY, result.stdout)
        self.assertNotIn(KEY, result.stderr)
        self.assertIn("VERDICT: PASS", self.out.read_text(encoding="utf-8"))


class OverrideTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        (self.repo / "CODEOWNERS").write_text(".*AGENTS\\.md @acme-admin\n", encoding="utf-8")
        (self.repo / "AGENTS.md").write_text("# Acme\n", encoding="utf-8")
        people = self.repo / "people"
        people.mkdir()
        (people / "Ada.md").write_text(
            "---\ngithub: acme-admin\nrole: admin\n---\nAda Admin\n",
            encoding="utf-8",
        )
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", "init")
        self.base = subprocess.check_output(
            ["git", "-C", str(self.repo), "rev-parse", "HEAD"], text=True
        ).strip()

    def decide(self, user, body):
        comment = Path(self.tmp.name) / "comment"
        comment.write_text(body, encoding="utf-8")
        return run(
            [
                "bash",
                str(SCRIPTS / "override.sh"),
                "--user",
                user,
                "--comment-file",
                str(comment),
                "--base",
                self.base,
            ],
            cwd=self.repo,
        )

    def test_admin_member_and_empty(self):
        admin = self.decide("acme-admin", "/override the marker is a test")
        self.assertEqual(admin.returncode, 0, admin.stderr)
        self.assertTrue(admin.stdout.startswith("valid "))
        self.assertIn("the marker is a test", admin.stdout)
        member = self.decide("acme-member-a", "/override please")
        self.assertEqual(member.stdout.strip(), "ignored not-owner")
        empty = self.decide("acme-admin", "/override")
        self.assertEqual(empty.stdout.strip(), "ignored empty")


class HostReadTests(unittest.TestCase):
    def test_pages_until_short_page(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        seen = root / "urls.txt"
        fake = bin_dir / "curl"
        fake.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json, os, sys
                from pathlib import Path
                args = sys.argv[1:]
                cfg = args[args.index("--config") + 1]
                url = ""
                out = ""
                for line in Path(cfg).read_text(encoding="utf-8").splitlines():
                    if line.startswith("url = "):
                        url = line.split("=", 1)[1].strip().strip('"')
                    if line.startswith("output = "):
                        out = line.split("=", 1)[1].strip().strip('"')
                Path(os.environ["URL_LOG"]).open("a", encoding="utf-8").write(url + "\\n")
                page = 1
                if "page=2" in url:
                    page = 2
                if page == 1:
                    rows = [{"user": {"login": "ada"}, "body": "c%s" % i} for i in range(50)]
                else:
                    rows = [{"user": {"login": "ada"}, "body": "last"}]
                Path(out).write_text(json.dumps(rows), encoding="utf-8")
                sys.stdout.write("200")
                """
            ),
            encoding="utf-8",
        )
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        result = run(
            ["bash", str(SCRIPTS / "host-read.sh"), "comments", "acme", "demo", "1"],
            env={
                "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                "URL_LOG": str(seen),
                "JOB_TOKEN": KEY,
                "GITHUB_SERVER_URL": "http://forgejo.example",
                "GITHUB_API_URL": "http://forgejo.example/api/v1",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        urls = seen.read_text(encoding="utf-8")
        self.assertIn("page=1", urls)
        self.assertIn("page=2", urls)
        self.assertNotIn(KEY, result.stdout)
        self.assertIn("last", result.stdout)


if __name__ == "__main__":
    unittest.main()
