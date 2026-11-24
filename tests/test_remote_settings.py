"""remote-setup sets the Claude Code defaults in ~/.claude/settings.json and keeps every other key."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "template/skills/remote-setup"


def defaults():
    out = {}
    for line in (SKILL / "defaults.txt").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, val = line.split("=", 1)
            out[key] = json.loads(val)
    return out


def tools():
    found = []
    if shutil.which("jq"):
        found.append("jq")
    if shutil.which("python3"):
        found.append("python3")
    if os.uname().sysname == "Darwin" and shutil.which("plutil"):
        found.append("plutil")
    return found


class RemoteSettingsTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home)
        self.file = self.home / ".claude/settings.json"

    def run_set(self, tool):
        env = dict(os.environ, HOME=str(self.home), REMOTE_SETUP_JSON=tool)
        return subprocess.run(["bash", str(SKILL / "set-settings.sh")], env=env,
                              capture_output=True, text=True)

    def write(self, data):
        self.file.parent.mkdir(parents=True, exist_ok=True)
        self.file.write_text(data)

    def test_one_default_autocompact_window(self):
        self.assertEqual(defaults().get("autoCompactWindow"), 400000)
        for name in ["check.sh", "check.ps1", "set-settings.sh", "set-settings.ps1"]:
            text = (SKILL / name).read_text()
            self.assertIn("defaults.txt", text, name)
            self.assertNotIn("400000", text, name)
        self.assertIn("set-settings", (SKILL / "SKILL.md").read_text())

    def test_missing_file_is_made(self):
        for tool in tools():
            with self.subTest(tool=tool):
                if self.file.exists():
                    self.file.unlink()
                r = self.run_set(tool)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn("was not set", r.stdout)
                self.assertEqual(json.loads(self.file.read_text()), defaults())

    def test_other_keys_are_kept(self):
        start = {"remoteControlAtStartup": True, "permissions": {"allow": ["Bash(ls)"], "deny": []},
                 "env": {"A": "b"}, "model": "x"}
        for tool in tools():
            with self.subTest(tool=tool):
                self.write(json.dumps(start, indent=2))
                r = self.run_set(tool)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(json.loads(self.file.read_text()), {**start, **defaults()})

    def test_already_set_changes_nothing(self):
        want = defaults()["autoCompactWindow"]
        text = '{ "autoCompactWindow": %d, "model": "x" }\n' % want
        for tool in tools():
            with self.subTest(tool=tool):
                self.write(text)
                r = self.run_set(tool)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn(f"already {want}", r.stdout)
                self.assertEqual(self.file.read_text(), text)

    def test_other_value_is_replaced_and_both_shown(self):
        want = defaults()["autoCompactWindow"]
        for tool in tools():
            with self.subTest(tool=tool):
                self.write('{"autoCompactWindow": 123, "model": "x"}')
                r = self.run_set(tool)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn(f"set to {want} (was 123)", r.stdout)
                self.assertEqual(json.loads(self.file.read_text()), {"autoCompactWindow": want, "model": "x"})

    def test_bad_json_is_left_alone(self):
        for tool in tools():
            with self.subTest(tool=tool):
                self.write('{"model": "x",')
                r = self.run_set(tool)
                self.assertEqual(r.returncode, 1)
                self.assertIn("not a valid JSON object", r.stderr)
                self.assertEqual(self.file.read_text(), '{"model": "x",')

    def test_symlink_stays_a_symlink(self):
        real = self.home / "dotfiles-settings.json"
        real.write_text('{"model": "x"}')
        self.file.parent.mkdir(parents=True, exist_ok=True)
        self.file.symlink_to(real)
        r = self.run_set(tools()[0])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.file.is_symlink())
        self.assertEqual(json.loads(real.read_text())["model"], "x")

    def test_check_reports_the_value(self):
        want = defaults()["autoCompactWindow"]
        env = dict(os.environ, HOME=str(self.home), PATH="/usr/bin:/bin")
        self.write('{"autoCompactWindow": 123}')
        out = subprocess.run(["bash", str(SKILL / "check.sh")], env=env, capture_output=True, text=True).stdout
        self.assertIn(f"autoCompactWindow is 123 (the default is {want})", out)
        self.assertIn("set-settings.sh", out)
        self.write('{"autoCompactWindow": %d}' % want)
        out = subprocess.run(["bash", str(SKILL / "check.sh")], env=env, capture_output=True, text=True).stdout
        self.assertIn(f"PASS  Claude Code setting autoCompactWindow is {want}.", out)


if __name__ == "__main__":
    unittest.main()
