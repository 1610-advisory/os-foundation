"""os_codeowners writes a GitHub file and a Forgejo file."""

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "template" / "skills" / "add-teammate" / "lib.sh"


class CodeownersTests(unittest.TestCase):
    def write(self, users):
        dest = tempfile.TemporaryDirectory()
        self.addCleanup(dest.cleanup)
        result = subprocess.run(
            [
                "bash",
                "-c",
                'set -euo pipefail; . "$1"; os_codeowners "$2" "$3"',
                "owners",
                str(LIB),
                dest.name,
                users,
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

    def test_area_owners_match_on_both_hosts(self):
        github, forgejo = self.write("@acme-director @acme-admin")
        self.assertIn("/skills/ @acme-director @acme-admin\n", github)
        self.assertIn("/.github/ @acme-director @acme-admin\n", github)
        self.assertIn("/.gitea/ @acme-director @acme-admin\n", github)
        self.assertIn("^skills/.* @acme-director @acme-admin\n", forgejo)
        self.assertIn("^bots/[^/]+/BOT\\.md$ @acme-director @acme-admin\n", forgejo)
        self.assertIn("^\\.github/.* @acme-director @acme-admin\n", forgejo)
        self.assertIn("^\\.gitea/.* @acme-director @acme-admin\n", forgejo)
        self.assertNotIn("/skills/", forgejo)
        self.assertNotIn("^skills/", github)

    def test_company_names_only_the_admin(self):
        github, forgejo = self.write("@acme-admin")
        self.assertIn("^AGENTS\\.md$ @acme-admin\n", forgejo)
        self.assertNotIn("@acme-director", github)
        self.assertNotIn("@acme-director", forgejo)
