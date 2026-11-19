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
        self.assertLess(len(text.splitlines()), 130)
        for private_path in ["/Users/", "/home/", "~/"]:
            self.assertNotIn(private_path, text)

    def test_existing_software_comes_first(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["existing software", "Custom code is an option, not the default",
                     "replaces a working tool", "write why"]:
            self.assertIn(term, text)

    def test_a_tool_is_declared(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["data list", "Named requests", "Define each one once", "tool.json", "row lock",
                     "one plain SQLite file", "Screens", "scheduled scripts", "TypeScript", "React",
                     "off the connector"]:
            self.assertIn(term, text)

    def test_tool_code_stays_out_of_the_company_folder(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["its own repo", "never go in the company OS folder", "apps.md", "owning area",
                     "pinned version", "dataset list", "`everyone` area"]:
            self.assertIn(term, text)
        apps = (ROOT / "template/skills/add-area/templates/apps").resolve()
        self.assertNotIn("portal/`", (apps / "AGENTS.md").read_text())
        self.assertIn("Owning area", (apps / "apps.md").read_text())
        add_area = (ROOT / "template/skills/add-area/SKILL.md").read_text()
        self.assertNotIn("areas/apps/portal/", add_area)
        self.assertIn("own repo", add_area)

    def test_kernel_first_and_the_stopgap_rule(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["never runs a tool's requests itself", "no sign-in of its own", "Behind the kernel",
                     "local preview server", "1610.tools/t/<tool>/",
                     "Business records only", "office account", "No passwords",
                     "security review before go-live", "three tests", "Backups",
                     "storage the company owns", "why it is a stopgap",
                     "what must be true for it to move", "second stopgap tool", "1610"]:
            self.assertIn(term, text)

    def test_no_per_app_hosting_choice(self):
        self.assertFalse((SKILL / "hosting-options.md").exists())
        for path in [SKILL / "SKILL.md", ROOT / "README.md", ROOT / "start-core.md",
                     ROOT / "template/skills/add-area/templates/apps/AGENTS.md"]:
            text = path.read_text()
            for term in ["hosting-options.md", "D1", "R2", "Prefer Cloudflare",
                         "self-managed VPS"]:
                self.assertNotIn(term, text, f"{path.name}: {term}")

    def test_shared_report_button_and_locks(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["shared report button", "pinned version", "Do not build your own",
                     "broken, idea or other", "never captures the screen", "opens an issue",
                     "assignments", "Never grant rows by hand", "second permission system",
                     "as the person", "Declare the lock, never code it"]:
            self.assertIn(term, text)

    def test_kernel_is_not_changed_and_health_data_stops(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["Never change the kernel", "`app`", "change to the kernel",
                     "health records", "Never write your own sign-in code"]:
            self.assertIn(term, text)

    def test_approval_and_data_about_a_person(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["for themselves with no review", "manager of the area", "the owner approves",
                     "new approval", "without the kernel in front", "mailbox", "HR and pay",
                     "owner to turn it on"]:
            self.assertIn(term, text)

    def test_deliverables_hold_no_live_data(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["Markdown is the truth", "single HTML file", '"as of" date',
                     "reads no live data", "tool screen"]:
            self.assertIn(term, text)

    def test_external_changes_need_approval_and_verification(self):
        text = (SKILL / "SKILL.md").read_text()
        for term in ["one question at a time", "approval", "account", "publish", "recurring",
                     "secret", "Unknown", "refused", "restore", "not tested", "HTTPS",
                     "real data", "local preview", "stop and ask a human"]:
            self.assertIn(term, text)
        self.assertLess(text.index("## 6. Approval"), text.index("## 8. Build and release"))

    def test_copied_template_keeps_skill_and_area_links(self):
        with tempfile.TemporaryDirectory(prefix="os-app-setup-") as tmp:
            company = Path(tmp) / "acme-os"
            shutil.copytree(ROOT / "template", company)
            area = company / "areas/apps"
            templates = company / "skills/add-area/templates"
            shutil.copytree(templates / "_area", area)
            shutil.copytree(templates / "apps", area, dirs_exist_ok=True)
            self.assertTrue((area / "../../skills/app-setup/SKILL.md").resolve().is_file())
            for file in company.rglob("AGENTS.md"):
                self.assertLess(len(file.read_text()), 10000, str(file))


if __name__ == "__main__":
    unittest.main()
