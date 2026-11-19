#!/usr/bin/env python3
"""v1.0.4: private by default. Root paths, the sweep before access, area names, rules text."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "template"
PUSH = TEMPLATE / "skills" / "sync" / "push.sh"
SWEEP = TEMPLATE / "skills" / "add-teammate" / "sweep.sh"
LIB = TEMPLATE / "skills" / "add-teammate" / "lib.sh"
ROUTE = "goes in `areas/admin/` only, never the shared root."


def git(repo, *args):
    env = os.environ.copy()
    env.update(GIT_AUTHOR_NAME="Ada Admin", GIT_AUTHOR_EMAIL="ada@acme.test",
               GIT_COMMITTER_NAME="Ada Admin", GIT_COMMITTER_EMAIL="ada@acme.test")
    subprocess.run(["git", "-C", str(repo), *args], check=True, env=env, stdout=subprocess.PIPE)


class RootPathTests(unittest.TestCase):
    """The push holds root content, except the map, company memory and company facts (D163)."""

    def allowed(self, path):
        text = PUSH.read_text()
        funcs = []
        for name in ("sync_root_map_file", "sync_root_allowed"):
            start = text.index(name + "() {")
            funcs.append(text[start:text.index("\n}\n", start) + 3])
        script = "\n".join(funcs) + '\nsync_root_allowed "$1"\n'
        return subprocess.run(["bash", "-c", script, "x", path]).returncode == 0

    def test_allowed(self):
        for path in ("people/Ada Admin.md", "company-profile.md", "privacy.md", "templates/meeting.md",
                     "memory/MEMORY.md", "memory/how-we-quote.md", "memory/sub/x.md", "customers.md", "offers.md"):
            self.assertTrue(self.allowed(path), path)

    def test_held(self):
        for path in ("meetings/2026-11-17 Leadership.md", "notes/x.md", "decisions/2026-11-17 Plan.md",
                     "memory/logs/2026-11-17-ada.md", "inbox/a.md", "data.csv"):
            self.assertFalse(self.allowed(path), path)


class SweepTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.co = Path(tmp.name) / "acme-os"
        self.co.mkdir()
        git(self.co, "init", "-q", "-b", "main")
        (self.co / "company-profile.md").write_text("level: team\n")
        (self.co / "customers.md").write_text("Customers like calls.\n")
        (self.co / "old.md").write_text("The GitHub org and billing plan.\n")
        git(self.co, "add", ".")
        git(self.co, "commit", "-q", "-m", "init")
        git(self.co, "rm", "-q", "old.md")
        git(self.co, "commit", "-q", "-m", "remove")
        area = self.co / "areas" / "sales"
        area.mkdir(parents=True)
        git(area, "init", "-q", "-b", "main")
        (area / "access.md").write_text("Who has access: the admins.\n")
        git(area, "add", ".")
        git(area, "commit", "-q", "-m", "init")

    def sweep(self, *args):
        return subprocess.run(["bash", str(SWEEP), *args], cwd=self.co, text=True, capture_output=True)

    def test_lists_files_hints_and_history(self):
        result = self.sweep("--areas", "sales", "--person", "noa")
        self.assertEqual(result.returncode, 0, result.stderr)
        out = result.stdout
        self.assertIn("what noa will be able to read", out)
        self.assertIn("  customers.md", out)
        self.assertIn("look: area sales: access.md", out)
        self.assertNotIn("look: company repo (everyone): customers.md", out)
        self.assertIn("history: company repo (everyone)", out)
        self.assertIn("  old.md", out)
        self.assertIn("Wait for a clear yes before the invite.", out)

    def test_missing_area_and_wrong_folder_fail(self):
        self.assertEqual(self.sweep("--areas", "finance").returncode, 1)
        outside = subprocess.run(["bash", str(SWEEP), "--areas", ""], cwd=self.co / "areas",
                                 text=True, capture_output=True)
        self.assertEqual(outside.returncode, 1)


class AreaNameTests(unittest.TestCase):
    def check(self, name):
        script = f'. "{LIB}"; os_area_name_ok "$1"'
        return subprocess.run(["bash", "-c", script, "x", name], text=True, capture_output=True)

    def test_names(self):
        for bad in ("os", "library", "user-ada"):
            result = self.check(bad)
            self.assertEqual(result.returncode, 2, bad)
            self.assertIn("is not allowed", result.stderr)
        for good in ("sales", "admin", "os-team", "everyone"):
            self.assertEqual(self.check(good).returncode, 0, good)


class RulesTextTests(unittest.TestCase):
    def test_routing_rule_in_every_rules_file(self):
        files = [TEMPLATE / "CLAUDE.md", TEMPLATE / "skills/add-area/templates/_area/CLAUDE.md"]
        files += sorted((TEMPLATE / "skills/add-area/templates").glob("*/AGENTS.md"))
        for path in files:
            text = path.read_text()
            self.assertIn("Leadership and access material", text, path)
            self.assertIn(ROUTE, text, path)
            self.assertIn("/approve", text, path)
            self.assertIn("secret", text.lower(), path)
        agents = (TEMPLATE / "AGENTS.md").read_text()
        self.assertIn("`areas/admin/` only. Never the shared root.", agents)
        self.assertIn("Never type `/approve` or `/override` yourself.", agents)
        self.assertLess(len(agents), 9000)
        self.assertTrue((TEMPLATE / "skills/add-area/templates/admin/AGENTS.md").is_file())

    def test_review_rules_copies_match_and_name_the_root_check(self):
        a = (TEMPLATE / "review-rules.md").read_text()
        b = (TEMPLATE / ".github/scripts/review-rules.default.md").read_text()
        self.assertEqual(a, b)
        self.assertIn("**Content at the shared root.**", a)
        self.assertIn("belongs in an area (admin?)", a)
        check = (TEMPLATE / "skills/sync/push-check.md").read_text()
        self.assertIn("`belongs in an area (admin?)`", check)

    def test_propose_never_turns_on_auto_merge(self):
        text = PUSH.read_text()
        start = text.index("sync_propose_repo() {")
        body = text[start:text.index("\n}\n", start)]
        self.assertNotIn('"$HOST_SH" auto-merge "', body)
        self.assertIn('"$HOST_SH" auto-merge-off', body)


if __name__ == "__main__":
    unittest.main()
