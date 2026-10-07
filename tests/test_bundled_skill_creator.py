"""Packaging/integration contracts; these do not run model evaluations."""
import ast
import hashlib
import json
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CREATOR = ROOT / "template/skills/skill-creator"
INTEGRATION = "## os-foundation integration"


class BundledSkillCreatorTests(unittest.TestCase):
    def test_complete_pinned_upstream_package_and_license(self):
        manifest = json.loads((CREATOR / "UPSTREAM.json").read_text())
        self.assertEqual(manifest["revision"], "683bc88e56f3e09ba94f7055977f3d3aa499f202")
        self.assertEqual(len(manifest["files"]), 19)
        self.assertIn("Apache License", (CREATOR / "LICENSE.txt").read_text())
        self.assertTrue((CREATOR / "UPSTREAM_NOTICES.md").is_file())
        for item in manifest["files"]:
            raw = (CREATOR / item["path"]).read_bytes()
            expected = item.get("installed_sha256", item["sha256"])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), expected, item["path"])
            if "installed_sha256" in item:
                self.assertIn(item["path"], manifest["changes"])
                self.assertIn("os-foundation change" if item["path"] != "SKILL.md" else "Modified by os-foundation", raw.decode())

    def test_official_name_and_visible_integration_notice(self):
        text = (CREATOR / "SKILL.md").read_text()
        self.assertIn("name: skill-creator", text)
        self.assertIn(INTEGRATION, text)
        self.assertIn("FOUNDATION.md", text)
        self.assertIn("Anthropic", text)

    def test_placement_and_authorization_rules_survive_vendor_instructions(self):
        text = (CREATOR / "FOUNDATION.md").read_text()
        for term in ["area", "synthetic", "approval", "delegation", "cost", "claude",
                     "Python", "PyYAML", "not installed", "not tested", "company rules"]:
            self.assertIn(term, text)

    def test_creator_is_routed_during_and_after_setup(self):
        for path in ["start-core.md", "template/AGENTS.md", "template/skills/write-skill/SKILL.md"]:
            self.assertIn("skills/skill-creator/", (ROOT / path).read_text())
        self.assertIn("skills/skill-creator/", (ROOT / "README.md").read_text())

    def test_knowledge_note_distinguishes_bundled_and_linked_tools(self):
        note = (ROOT / "template/memory/skill-resources.md").read_text()
        for term in ["type: reference", "Anthropic", "skill-creator", "not bundled", "license",
                     "company knowledge"]:
            self.assertIn(term, note)
        self.assertNotIn("grill", note)
        self.assertIn("skill-resources.md", (ROOT / "template/memory/MEMORY.md").read_text())

    def test_python_helpers_parse_without_running_external_models(self):
        paths = list(CREATOR.rglob("*.py"))
        self.assertGreater(len(paths), 5)
        for path in paths:
            ast.parse(path.read_text(), filename=str(path))

    def test_review_templates_have_no_remote_asset_requests(self):
        for relative in ["assets/eval_review.html", "eval-viewer/viewer.html", "scripts/generate_report.py"]:
            text = (CREATOR / relative).read_text()
            self.assertNotRegex(text, r'(?:src|href)=[\"\']https?://')
        self.assertIn("Spreadsheet preview is disabled", (CREATOR / "eval-viewer/viewer.html").read_text())

    def test_live_viewer_does_not_kill_an_existing_port_owner(self):
        module = ast.parse((CREATOR / "eval-viewer/generate_review.py").read_text())
        calls = [node for node in ast.walk(module) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == "_kill_port"]
        self.assertEqual(calls, [])

    @unittest.skipUnless(importlib.util.find_spec("yaml"), "Local packaging smoke test needs PyYAML")
    def test_local_validator_and_package_without_model_calls(self):
        with tempfile.TemporaryDirectory(prefix="os-creator-package-") as tmp:
            good = subprocess.run([sys.executable, "-B", str(CREATOR / "scripts/quick_validate.py"), str(CREATOR)], capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            bad = Path(tmp) / "invalid-skill"
            bad.mkdir()
            (bad / "SKILL.md").write_text("---\nname: Bad_Name\ndescription: Synthetic example\n---\n")
            result = subprocess.run([sys.executable, "-B", str(CREATOR / "scripts/quick_validate.py"), str(bad)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            packed = subprocess.run([sys.executable, "-B", "-m", "scripts.package_skill", str(CREATOR), tmp], cwd=CREATOR, capture_output=True, text=True)
            self.assertEqual(packed.returncode, 0, packed.stderr)
            with zipfile.ZipFile(Path(tmp) / "skill-creator.skill") as archive:
                self.assertIn("skill-creator/LICENSE.txt", archive.namelist())
                self.assertIn("skill-creator/FOUNDATION.md", archive.namelist())
                self.assertEqual(archive.read("skill-creator/SKILL.md"), (CREATOR / "SKILL.md").read_bytes())

    def test_static_review_embeds_synthetic_outputs_safely(self):
        with tempfile.TemporaryDirectory(prefix="os-creator-review-") as tmp:
            workspace = Path(tmp) / "workspace"
            run = workspace / "eval-0/with_skill"
            (run / "outputs").mkdir(parents=True)
            payload = "synthetic </script><p>output</p>"
            (run / "outputs/example.txt").write_text(payload)
            (run / "eval_metadata.json").write_text(json.dumps({"prompt": "Review a synthetic skill", "eval_id": 0}))
            output = Path(tmp) / "review.html"
            result = subprocess.run([sys.executable, "-B", str(CREATOR / "eval-viewer/generate_review.py"), str(workspace), "--static", str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            html = output.read_text()
            self.assertNotIn(payload, html)
            self.assertNotRegex(html, r'(?:src|href)=[\"\']https?://')
            data = json.loads(re.search(r"const EMBEDDED_DATA = (.*?);\n", html).group(1))
            self.assertEqual(data["runs"][0]["outputs"][0]["content"], payload)

    def test_copied_company_has_complete_local_references(self):
        with tempfile.TemporaryDirectory(prefix="os-skill-creator-") as tmp:
            company = Path(tmp) / "acme-os"
            shutil.copytree(ROOT / "template", company)
            for rel in ["agents/grader.md", "agents/comparator.md", "agents/analyzer.md",
                        "references/schemas.md", "assets/eval_review.html",
                        "eval-viewer/generate_review.py", "eval-viewer/viewer.html",
                        "scripts/quick_validate.py", "scripts/package_skill.py", "FOUNDATION.md"]:
                self.assertTrue((company / "skills/skill-creator" / rel).is_file(), rel)
            for path in company.rglob("AGENTS.md"):
                self.assertLess(len(path.read_text()), 10000)


if __name__ == "__main__":
    unittest.main()
