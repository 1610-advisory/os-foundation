"""privacy.sh writes privacy.md from level, switches, and places.md.

Run: python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "template" / "skills" / "privacy" / "privacy.sh"
FIXTURES = ROOT / "tests" / "privacy" / "fixtures"
PLACES = FIXTURES / "places.md"

# Ticket 37 Q1. Word for word. Do not edit.
T2 = (
    "Your company folder stays on your computer and in your own GitHub. "
    "Nothing goes to 1610 unless you send it. "
    "Connections use each tool's own sign-in, and we never see your passwords."
)

TEAM_COMPUTERS = "device helper deletes the company folder"
BOTS = "until the owner deletes the bot"
TRACES = "full traces shrink to summaries after 30 days"
APP_DB = "log of every connector call"
CONNECTOR = "queue of suggestions not yet reviewed"
CLOUD = "cloud coding agent"
GIT_HOST = "rewrites it with `remove-leak`"


def run(script, root, *args, cwd=None):
    return subprocess.run(
        ["/bin/bash", str(script), *args],
        cwd=cwd,
        capture_output=True,
    )


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def make(
        self,
        level="solo",
        switches=None,
        places=None,
        profile_sh=None,
        profile_text=None,
        dirname="acme",
    ):
        root = self.base / dirname
        skill = root / "skills" / "privacy"
        skill.mkdir(parents=True)
        script = skill / "privacy.sh"
        shutil.copy(SCRIPT, script)
        script.chmod(script.stat().st_mode | stat.S_IXUSR)
        if places is None:
            shutil.copy(PLACES, skill / "places.md")
        else:
            (skill / "places.md").write_text(places)
        if profile_text is None:
            items = list(switches or [])
            if items:
                switch_line = "[" + ", ".join(items) + "]"
            else:
                switch_line = "[]"
            profile_text = (
                "---\n"
                "type: company-profile\n"
                'summary: "Acme Co makes things."\n'
                "updated: 2026-01-01\n"
                "company_slug: acme\n"
                f"level: {level}\n"
                f"switches: {switch_line}\n"
                "---\n\n"
                "# Acme Co\n"
            )
        (root / "company-profile.md").write_text(profile_text)
        if profile_sh is not None:
            host = root / "skills" / "_host"
            host.mkdir()
            path = host / "profile.sh"
            path.write_text(profile_sh)
            path.chmod(0o755)
        return root, script

    def test_solo_team_and_switch_fixtures_match_bytes(self):
        cases = (
            ("solo", "solo", [], 6),
            ("team", "team", [], 11),
            ("team-bots-traces", "team", ["bots", "traces"], 12),
        )
        for name, level, switches, count in cases:
            with self.subTest(name=name):
                root, script = self.make(level, switches, dirname=name)
                result = run(script, root, "--root", str(root))
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertEqual(
                    result.stdout.decode(),
                    f"privacy.md: {count} places\n",
                )
                actual = (root / "privacy.md").read_bytes()
                expected = (FIXTURES / name / "privacy.md").read_bytes()
                self.assertEqual(actual, expected)
                self.assertNotIn(b"2026-01-01", actual)
                self.assertTrue(actual.endswith(b"\n"))
                self.assertFalse(actual.endswith(b"\n\n"))

    def test_t2_sentence_is_unchanged_word_for_word(self):
        self.assertIn(T2, PLACES.read_text())
        self.assertIn(T2 + "\n", PLACES.read_text())
        root, script = self.make("solo")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        text = (root / "privacy.md").read_text()
        lines = text.splitlines()
        self.assertIn(T2, lines)
        self.assertLess(lines.index(T2), lines.index("## Where copies of your data sit"))
        self.assertEqual(text.count(T2), 1)
        for name in ("solo", "team", "team-bots-traces"):
            fixture = (FIXTURES / name / "privacy.md").read_text()
            self.assertIn(T2, fixture.splitlines())

    def test_fixture_sentences_follow_places(self):
        solo = (FIXTURES / "solo" / "privacy.md").read_text()
        team = (FIXTURES / "team" / "privacy.md").read_text()
        both = (FIXTURES / "team-bots-traces" / "privacy.md").read_text()
        for text in (solo, team, both):
            self.assertIn("Your computer holds the company folder", text)
            self.assertNotIn(TRACES, text)
            self.assertNotIn(APP_DB, text)
            self.assertNotIn(CONNECTOR, text)
            self.assertNotIn(CLOUD, text)
        self.assertNotIn(TEAM_COMPUTERS, solo)
        self.assertNotIn(GIT_HOST, solo)
        self.assertNotIn(BOTS, solo)
        self.assertIn(TEAM_COMPUTERS, team)
        self.assertIn(GIT_HOST, team)
        self.assertNotIn(BOTS, team)
        # places.md lists traces only when level is app and the switch is on.
        self.assertIn(BOTS, both)
        self.assertIn(TEAM_COMPUTERS, both)
        self.assertNotIn(TRACES, both)

    def test_stdout_does_not_write_and_matches_the_file(self):
        root, script = self.make("team")
        preview = run(script, root, "--root", str(root), "--stdout")
        self.assertEqual(preview.returncode, 0, preview.stderr.decode())
        self.assertFalse((root / "privacy.md").exists())
        written = run(script, root, "--root", str(root))
        self.assertEqual(written.returncode, 0, written.stderr.decode())
        self.assertEqual(preview.stdout, (root / "privacy.md").read_bytes())

    def test_check_writes_nothing(self):
        root, script = self.make("solo")
        missing = run(script, root, "--root", str(root), "--check")
        self.assertEqual(missing.returncode, 1)
        self.assertIn(b"not current", missing.stderr)
        self.assertFalse((root / "privacy.md").exists())
        run(script, root, "--root", str(root))
        path = root / "privacy.md"
        before = path.stat().st_mtime_ns
        current = run(script, root, "--root", str(root), "--check")
        self.assertEqual(current.returncode, 0, current.stderr.decode())
        self.assertEqual(current.stdout.decode(), "privacy.md: current\n")
        self.assertEqual(path.stat().st_mtime_ns, before)
        original = path.read_bytes()
        path.write_bytes(original + b"\nextra\n")
        stale = run(script, root, "--root", str(root), "--check")
        self.assertEqual(stale.returncode, 1)
        self.assertEqual(path.read_bytes(), original + b"\nextra\n")

    def test_second_write_keeps_the_same_bytes_and_mtime(self):
        root, script = self.make("team", ["bots"])
        first = run(script, root, "--root", str(root))
        self.assertEqual(first.returncode, 0, first.stderr.decode())
        path = root / "privacy.md"
        before = path.read_bytes()
        stamp = path.stat().st_mtime_ns
        second = run(script, root, "--root", str(root))
        self.assertEqual(second.returncode, 0, second.stderr.decode())
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(path.stat().st_mtime_ns, stamp)

    def test_unknown_condition_fails_and_does_not_skip(self):
        places = (
            "# title\n\n"
            "## weird\n"
            "when: level: solo\n"
            "This must not be written.\n"
        )
        root, script = self.make("solo", places=places)
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"unknown condition for weird", result.stderr)
        self.assertNotIn(b"This must not be written", result.stdout)
        self.assertFalse((root / "privacy.md").exists())

        both = (
            "# title\n\n"
            "## too-many\n"
            "when: level: app and switch: traces and switch: bots\n"
            "Nope.\n"
        )
        root, script = self.make("app", ["traces", "bots"], places=both, dirname="and")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"unknown condition for too-many", result.stderr)
        self.assertFalse((root / "privacy.md").exists())

        half = (
            "# title\n\n"
            "## half\n"
            "when: level: app and level: nope\n"
            "Nope.\n"
        )
        root, script = self.make("app", places=half, dirname="half")
        (root / "privacy.md").write_text("keep me\n")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"half", result.stderr)
        self.assertEqual((root / "privacy.md").read_text(), "keep me\n")

    def test_switch_place_is_listed_when_the_switch_is_on(self):
        places = (
            "## t2\n"
            "when: always\n"
            f"{T2}\n\n"
            "## traces-store\n"
            "when: switch: traces\n"
            "Traces sit in the store until the company deletes them.\n"
        )
        off, script = self.make("team", [], places=places, dirname="off")
        on, script_on = self.make("team", ["traces"], places=places, dirname="on")
        self.assertEqual(run(script, off, "--root", str(off)).returncode, 0)
        self.assertNotIn("Traces sit in the store", (off / "privacy.md").read_text())
        self.assertEqual(run(script_on, on, "--root", str(on)).returncode, 0)
        self.assertIn("Traces sit in the store", (on / "privacy.md").read_text())

        ordered = (
            "## t2\n"
            "when: always\n"
            f"{T2}\n\n"
            "## traces-store\n"
            "when: switch: traces and level: app\n"
            "Traces sit in the store until the company deletes them.\n"
        )
        team, team_script = self.make(
            "team", ["traces"], places=ordered, dirname="team-rev"
        )
        app, app_script = self.make(
            "app", ["traces"], places=ordered, dirname="app-rev"
        )
        self.assertEqual(run(team_script, team, "--root", str(team)).returncode, 0)
        self.assertNotIn("Traces sit in the store", (team / "privacy.md").read_text())
        self.assertEqual(run(app_script, app, "--root", str(app)).returncode, 0)
        self.assertIn("Traces sit in the store", (app / "privacy.md").read_text())

    def test_level_team_is_true_for_app(self):
        root, script = self.make("app", ["traces"])
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        text = (root / "privacy.md").read_text()
        self.assertIn(TEAM_COMPUTERS, text)
        self.assertIn(GIT_HOST, text)
        self.assertIn(TRACES, text)
        self.assertIn(APP_DB, text)
        self.assertIn(CONNECTOR, text)
        self.assertNotIn(BOTS, text)
        self.assertNotIn(CLOUD, text)
        self.assertEqual(result.stdout.decode(), "privacy.md: 14 places\n")

    def test_missing_profile_and_missing_level(self):
        root, script = self.make("solo")
        os.remove(root / "company-profile.md")
        missing = run(script, root, "--root", str(root))
        self.assertEqual(missing.returncode, 2)
        self.assertIn(b"no company-profile.md", missing.stderr)
        self.assertFalse((root / "privacy.md").exists())

        bare = "---\ntype: company-profile\nsummary: \"Acme Co\"\n---\n"
        root, script = self.make(profile_text=bare, dirname="bare")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(
            (root / "privacy.md").read_bytes(),
            (FIXTURES / "solo" / "privacy.md").read_bytes(),
        )

    def test_rules_style_frontmatter_and_block_list(self):
        text = (
            "---\n"
            "type: company-profile\n"
            'summary: "Acme Co"\n'
            "company_slug: acme\n"
            "level: team                 # solo | team | app\n"
            "switches: []                # off by default\n"
            "---\n"
        )
        root, script = self.make(profile_text=text)
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(
            (root / "privacy.md").read_bytes(),
            (FIXTURES / "team" / "privacy.md").read_bytes(),
        )

        block = (
            "---\n"
            'level: "team"\n'
            "switches:\n"
            "  - bots\n"
            "  - traces\n"
            "---\n"
        )
        root, script = self.make(profile_text=block, dirname="block")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(
            (root / "privacy.md").read_bytes(),
            (FIXTURES / "team-bots-traces" / "privacy.md").read_bytes(),
        )

        bad = "---\nlevel: solo\nswitches: nope\n---\n"
        root, script = self.make(profile_text=bad, dirname="bad-sw")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"cannot read switches", result.stderr)
        self.assertFalse((root / "privacy.md").exists())

    def test_profile_sh_is_used_when_present(self):
        stub = (
            "#!/bin/bash\n"
            '[[ -f company-profile.md ]] || exit 1\n'
            '[[ -n "${OS_PROFILE:-}" ]] || exit 1\n'
            'case "$1" in\n'
            "  level) printf '%s\\n' \"app\" ;;\n"
            "  switches) printf '%s\\n' \"bots\" ;;\n"
            "  *) exit 1 ;;\n"
            "esac\n"
        )
        # The file says solo with no switches. The stub says app + bots.
        root, script = self.make("solo", [], profile_sh=stub)
        result = run(script, root, "--root", str(root), cwd=self.base)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        text = (root / "privacy.md").read_text()
        self.assertIn(APP_DB, text)
        self.assertIn(BOTS, text)
        self.assertIn(TEAM_COMPUTERS, text)
        self.assertNotIn(TRACES, text)
        self.assertEqual(result.stdout.decode(), "privacy.md: 14 places\n")

        brackets = (
            "#!/bin/bash\n"
            'case "$1" in\n'
            "  level) printf '%s\\n' \"team\" ;;\n"
            "  switches) printf '%s\\n' \"[]\" ;;\n"
            "  *) exit 2 ;;\n"
            "esac\n"
        )
        root, script = self.make("solo", profile_sh=brackets, dirname="brackets")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(
            (root / "privacy.md").read_bytes(),
            (FIXTURES / "team" / "privacy.md").read_bytes(),
        )

        absent = (
            "#!/bin/bash\n"
            'case "$1" in\n'
            "  level) exit 2 ;;\n"
            "  switches) exit 2 ;;\n"
            "esac\n"
        )
        root, script = self.make("team", ["bots"], profile_sh=absent, dirname="absent")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(
            (root / "privacy.md").read_bytes(),
            (FIXTURES / "solo" / "privacy.md").read_bytes(),
        )

        broken = "#!/bin/bash\nprintf '%s\\n' \"team\"\nexit 1\n"
        root, script = self.make("team", profile_sh=broken, dirname="broken")
        (root / "privacy.md").write_text("old\n")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"profile.sh could not read level", result.stderr)
        self.assertEqual((root / "privacy.md").read_text(), "old\n")

        # profile.sh may print a flow list as one line. Expand it. Do not drop it.
        flow = (
            "#!/bin/bash\n"
            'case "$1" in\n'
            "  level) printf '%s\\n' \"team\" ;;\n"
            "  switches) printf '%s\\n' \"[bots, traces]\" ;;\n"
            "  *) exit 1 ;;\n"
            "esac\n"
        )
        root, script = self.make("solo", profile_sh=flow, dirname="flow")
        result = run(script, root, "--root", str(root))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(
            (root / "privacy.md").read_bytes(),
            (FIXTURES / "team-bots-traces" / "privacy.md").read_bytes(),
        )

    def test_help_usage_and_default_root(self):
        root, script = self.make("solo")
        help_result = run(script, root, "--help")
        self.assertEqual(help_result.returncode, 0)
        self.assertIn(b"--root", help_result.stdout)
        self.assertIn(b"--stdout", help_result.stdout)
        self.assertIn(b"--check", help_result.stdout)

        bad = run(script, root, "--root", str(root), "--nope")
        self.assertEqual(bad.returncode, 1)
        self.assertIn(b"unknown argument", bad.stderr)

        both = run(script, root, "--stdout", "--check", "--root", str(root))
        self.assertEqual(both.returncode, 1)
        self.assertIn(b"cannot be used together", both.stderr)

        spaced, script = self.make("solo", dirname="Acme Co")
        result = run(script, spaced, "--root", str(spaced))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(
            (spaced / "privacy.md").read_bytes(),
            (FIXTURES / "solo" / "privacy.md").read_bytes(),
        )

        own = root / "skills" / "privacy" / "privacy.sh"
        cwd_run = run(own, root, cwd=root)
        self.assertEqual(cwd_run.returncode, 0, cwd_run.stderr.decode())
        self.assertTrue((root / "privacy.md").exists())

    def test_shipped_places_match_fixture_when_present(self):
        shipped = ROOT / "template" / "skills" / "privacy" / "places.md"
        if not shipped.exists():
            self.skipTest("places.md is on the docs branch, not this one yet")
        self.assertEqual(shipped.read_bytes(), PLACES.read_bytes())


if __name__ == "__main__":
    unittest.main()
