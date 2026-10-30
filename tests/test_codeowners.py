"""os_codeowners writes a GitHub file and a Forgejo file."""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "template" / "skills" / "add-teammate" / "lib.sh"


class CodeownersTests(unittest.TestCase):
    def write(self, github_users, forgejo_users=""):
        dest = tempfile.TemporaryDirectory()
        self.addCleanup(dest.cleanup)
        result = subprocess.run(
            [
                "bash",
                "-c",
                'set -euo pipefail; . "$1"; os_codeowners "$2" "$3" "$4"',
                "owners",
                str(LIB),
                dest.name,
                github_users,
                forgejo_users,
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        root = Path(dest.name)
        return (root / ".github" / "CODEOWNERS").read_text(encoding="utf-8"), (
            root / ".gitea" / "CODEOWNERS"
        ).read_text(encoding="utf-8")

    def test_area_forgejo_names_only_the_director(self):
        github, forgejo = self.write("@acme-director @acme-admin", "@acme-director")
        self.assertIn("**/skills/ @acme-director @acme-admin\n", github)
        self.assertIn("**/.github/ @acme-director @acme-admin\n", github)
        self.assertIn("**/.gitea/ @acme-director @acme-admin\n", github)
        self.assertIn("^(.*/)?skills/.* @acme-director\n", forgejo)
        self.assertIn("^(.*/)?CODEOWNERS$ @acme-director\n", forgejo)
        self.assertIn("^(.*/)?\\.forgejo/.* @acme-director\n", forgejo)
        self.assertIn("^(.*/)?\\.claude/.* @acme-director\n", forgejo)
        self.assertIn("**/CODEOWNERS @acme-director @acme-admin\n", github)
        self.assertIn("**/.claude/ @acme-director @acme-admin\n", github)
        self.assertNotIn("@acme-admin", forgejo)
        self.assertNotIn("/skills/", forgejo)
        self.assertNotIn("^skills/", github)

    def test_company_names_only_the_admin(self):
        github, forgejo = self.write("@acme-admin")
        self.assertIn("^(.*/)?AGENTS\\.md$ @acme-admin\n", forgejo)
        self.assertNotIn("@acme-director", github)
        self.assertNotIn("@acme-director", forgejo)

    def test_every_rules_file_sync_holds_has_an_owner(self):
        """Item 9: a nested AGENTS.md or CLAUDE.md is held as a rules file, so it needs an owner."""
        github, forgejo = self.write("@acme-admin")
        sync_lib = ROOT / "template" / "skills" / "sync" / "lib.sh"
        ci_lib = ROOT / "template" / ".github" / "scripts" / "lib.sh"
        rules = [
            "AGENTS.md", "CLAUDE.md", "review-rules.md", "company-rules.md", "area-rules.md",
            "projects/launch/AGENTS.md", "docs/guides/CLAUDE.md", "projects/launch/review-rules.md",
            "skills/ingest/SKILL.md", "projects/launch/skills/x/SKILL.md", "bots/digest/BOT.md",
            "CODEOWNERS", "docs/CODEOWNERS", ".github/workflows/checks.yml", "projects/launch/.github/x.yml",
            ".gitea/CODEOWNERS", ".forgejo/x.yml", ".claude/settings.json", "projects/launch/.claude/settings.json",
        ]
        notes = ["notes/plan.md", "meetings/2026-10-29 Kickoff.md", "projects/launch/notes.md", "AGENTS.md.bak"]

        def held(path):
            proc = subprocess.run(
                ["bash", "-c", '. "$1"; sync_is_rules "$2"', "held", str(sync_lib), path],
                check=False, text=True, capture_output=True,
            )
            return proc.returncode == 0

        def lines(text):
            return [line.split()[0] for line in text.splitlines() if line and not line.startswith("#")]

        def gh_owned(path):
            for pattern in lines(github):
                proc = subprocess.run(
                    ["bash", "-c", '. "$1"; trap ci_cleanup EXIT; ci_path_match glob "$2" "$3"',
                     "m", str(ci_lib), pattern, path],
                    check=False, text=True, capture_output=True,
                )
                if proc.returncode == 0:
                    return True
            return False

        def fj_owned(path):
            # Forgejo puts ^ and $ around each pattern.
            return any(re.match("^" + p + "$", path) for p in lines(forgejo))

        for path in rules:
            self.assertTrue(held(path), path)
            self.assertTrue(gh_owned(path), "GitHub: " + path)
            self.assertTrue(fj_owned(path), "Forgejo: " + path)
        for path in notes:
            self.assertFalse(held(path), path)
            self.assertFalse(gh_owned(path), "GitHub: " + path)
            self.assertFalse(fj_owned(path), "Forgejo: " + path)
