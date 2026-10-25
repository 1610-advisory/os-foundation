"""os_codeowners writes a GitHub file and a Forgejo file."""

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
        self.assertIn("/skills/ @acme-director @acme-admin\n", github)
        self.assertIn("/.github/ @acme-director @acme-admin\n", github)
        self.assertIn("/.gitea/ @acme-director @acme-admin\n", github)
        self.assertIn("^skills/.* @acme-director\n", forgejo)
        self.assertIn("^CODEOWNERS$ @acme-director\n", forgejo)
        self.assertIn("^docs/CODEOWNERS$ @acme-director\n", forgejo)
        self.assertIn("^\\.forgejo/.* @acme-director\n", forgejo)
        self.assertIn("^\\.claude/.* @acme-director\n", forgejo)
        self.assertIn("/CODEOWNERS @acme-director @acme-admin\n", github)
        self.assertIn("/.claude/ @acme-director @acme-admin\n", github)
        self.assertNotIn("@acme-admin", forgejo)
        self.assertNotIn("/skills/", forgejo)
        self.assertNotIn("^skills/", github)

    def test_company_names_only_the_admin(self):
        github, forgejo = self.write("@acme-admin")
        self.assertIn("^AGENTS\\.md$ @acme-admin\n", forgejo)
        self.assertNotIn("@acme-director", github)
        self.assertNotIn("@acme-director", forgejo)
