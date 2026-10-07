"""Static app-planning contracts, not proof of an agent run or a deployment."""
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "template/skills/app-setup"


class AppSetupTests(unittest.TestCase):
    def test_skill_is_discoverable_during_and_after_setup(self):
        for path in ["start-core.md", "template/AGENTS.md",
                     "template/skills/add-area/templates/apps/AGENTS.md"]:
            self.assertIn("skills/app-setup/", (ROOT / path).read_text())
        self.assertIn("only when", (ROOT / "start-core.md").read_text())

    def test_skill_is_portable_and_has_trigger_frontmatter(self):
        text = (SKILL / "SKILL.md").read_text()
        self.assertIn("name: app-setup", text)
        self.assertIn("Use when", text)
        self.assertIn("hosting-options.md", text)
        self.assertLess(len(text.splitlines()), 100)
        for private_path in ["/Users/", "/home/", "~/"]:
            self.assertNotIn(private_path, text)

    def test_local_and_shared_hosting_are_distinguished(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["local", "computer is off", "GitHub", "not hosting", "existing tools"]:
            self.assertIn(term, text)

    def test_provider_choices_are_explicit_and_not_mandatory(self):
        text = (SKILL / "hosting-options.md").read_text()
        for term in ["Cloudflare", "Workers", "VPS", "Vercel", "Render", "Supabase",
                     "not mandatory", "patch", "backups", "runtime", "pricing"]:
            self.assertIn(term, text)

    def test_cloudflare_one_platform_benefit_is_explicit(self):
        for path in [SKILL / "SKILL.md", SKILL / "hosting-options.md", ROOT / "README.md"]:
            text = path.read_text()
            for term in ["Workers", "D1", "R2", "platform"]:
                self.assertIn(term, text)

    def test_requirements_and_costs_precede_external_changes(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["one question at a time", "budget", "data", "maintenance",
                     "approval", "account", "publish", "recurring", "secret", "Unknown"]:
            self.assertIn(term, text)
        self.assertLess(text.index("## 3. Save the decision"), text.index("## 4. Build and release"))

    def test_live_verification_covers_access_and_persistence(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["unauthorized", "restart", "rollback", "restore", "not tested",
                     "HTTPS", "real data", "export", "approved audience"]:
            self.assertIn(term, text)

    def test_copied_template_keeps_skill_and_area_links(self):
        with tempfile.TemporaryDirectory(prefix="os-app-setup-") as tmp:
            company = Path(tmp) / "acme-os"
            shutil.copytree(ROOT / "template", company)
            area = company / "areas/apps"
            templates = company / "skills/add-area/templates"
            shutil.copytree(templates / "_area", area)
            shutil.copytree(templates / "apps", area, dirs_exist_ok=True)
            self.assertTrue((area / "../../skills/app-setup/SKILL.md").resolve().is_file())
            self.assertTrue((company / "skills/app-setup/hosting-options.md").is_file())
            for file in company.rglob("AGENTS.md"):
                self.assertLess(len(file.read_text()), 10000, str(file))


if __name__ == "__main__":
    unittest.main()
