"""Rules v1.3 template contracts: dataset list per area, the apps record, record keys,
the kernel CLI skill, and areas = kernel units. Static checks only."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
T = ROOT / "template"
AREAS = T / "skills/add-area/templates"


class V13TemplateTests(unittest.TestCase):
    def test_every_area_has_a_dataset_list(self):
        text = (AREAS / "_area/datasets.md").read_text()
        for term in ["type: datasets", "| Name | Owning tool or source | File | As of | Lock | Answers | Test? |",
                     "never in this folder", "no rows and no secrets", "made up"]:
            self.assertIn(term, text)
        for agents in AREAS.glob("*/AGENTS.md"):
            self.assertIn("**Records stay in their tool.**", agents.read_text(), agents.parent.name)
            self.assertIn("`datasets.md`", agents.read_text(), agents.parent.name)

    def test_apps_record_has_version_and_address(self):
        text = (AREAS / "apps/apps.md").read_text()
        for term in ["| Tool | What it does | Owning area | Repo | Version | Address | Who may use it | Status |",
                     "1610.tools/t/<tool>/", "pinned version", "never as a copied fork", "`everyone`",
                     "stopgap"]:
            self.assertIn(term, text)

    def test_records_go_to_a_tool_and_notes_carry_keys(self):
        rules = (T / "AGENTS.md").read_text()
        self.assertIn("| Records and lists (customers, jobs) |", rules)
        self.assertIn("never markdown", rules)
        self.assertLess(len(rules), 9000)
        for path in ["templates/meeting.md", "templates/decision.md"]:
            self.assertIn("records: []", (T / path).read_text(), path)
        ingest = (T / "skills/ingest/SKILL.md").read_text()
        for term in ["`<tool>:<kind>:<key>`", '"crm:job:J-1042"', "`tool.json`", "do not invent a kind",
                     "stays plain text"]:
            self.assertIn(term, ingest)
        for path in ["README.md"]:
            self.assertNotIn("This version copies no CRM or accounting rows", (ROOT / path).read_text())

    def test_kernel_cli_skill(self):
        text = (T / "skills/kernel-cli/SKILL.md").read_text()
        for term in ["name: kernel-cli", "`ops`", "level: app", "ops commands", "ops describe",
                     "ops login", "Never ask for a token in chat", "| 2 | Waiting for approval",
                     "A refusal is the answer", "--idempotency-key", "`records:`"]:
            self.assertIn(term, text)
        self.assertIn("skills/kernel-cli/", (T / "AGENTS.md").read_text())

    def test_areas_are_kernel_units(self):
        text = (T / "skills/add-area/SKILL.md").read_text()
        for term in ["Areas and kernel units are one list", "the `admin` area too",
                     "Never make a unit with no area"]:
            self.assertIn(term, text)
        self.assertIn("kernel unit (same slug)", (T / "AGENTS.md").read_text())


if __name__ == "__main__":
    unittest.main()
