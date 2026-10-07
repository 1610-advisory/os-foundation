"""Static onboarding contracts, not an end-to-end agent setup test.

Run: python3 -m unittest discover -s tests -v
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupCopyTests(unittest.TestCase):
    def test_privacy_does_not_claim_local_only_processing(self):
        core = (ROOT / "start-core.md").read_text()
        readme = (ROOT / "README.md").read_text()
        self.assertNotIn("Nothing leaves their computer", core)
        for text in (core, readme):
            self.assertIn("AI provider", text)
            self.assertIn("processing", text)

    def test_opening_explains_destination_before_questions(self):
        core = (ROOT / "start-core.md").read_text().split("## Voice")[0]
        self.assertIn("company knowledge", core)
        self.assertIn("rules", core)
        self.assertIn("Notion", core)
        self.assertNotIn("about 15 minutes", core)

    def test_existing_sources_do_not_trigger_an_unrequested_sync(self):
        core = (ROOT / "start-core.md").read_text()
        self.assertIn("Do not propose migration, bulk export, duplicate markdown copies, or scheduled sync", core)
        self.assertIn("not proof that you can read", core)
        self.assertIn("memory/MEMORY.md", core)

    def test_source_index_is_shipped_and_discoverable(self):
        index = (ROOT / "template/memory/MEMORY.md").read_text()
        self.assertIn("[Existing sources](existing-sources.md)", index)
        sources = (ROOT / "template/memory/existing-sources.md").read_text()
        self.assertIn("type: reference", sources)
        self.assertIn("source of truth", sources)
        self.assertIn("Access status", sources)

    def test_source_policy_survives_setup(self):
        rules = (ROOT / "template/AGENTS.md").read_text()
        connector = (ROOT / "template/skills/connect-tool/SKILL.md").read_text()
        for text in (rules, connector):
            self.assertIn("memory/existing-sources.md", text)
            self.assertIn("scheduled sync", text)
        self.assertLess(len(rules), 10000)

    def test_readme_explains_where_to_paste_without_universal_support_claim(self):
        readme = (ROOT / "README.md").read_text()
        self.assertIn("file-capable", readme)
        self.assertNotIn("It works with Claude", readme)
        self.assertNotIn("about 15 minutes", readme)


if __name__ == "__main__":
    unittest.main()
