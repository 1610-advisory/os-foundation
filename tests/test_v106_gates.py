"""v1.0.6 part 1: sign-off sync, "tell 1610", SECURITY.md, tool repo wording.

Run: python3 -m unittest tests.test_v106_gates -v
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "template"
TELL = TEMPLATE / "skills" / "suggest" / "tell.sh"

FAKE_CURL = """#!/bin/bash
# Records the call; answers with the code in $FAKE_CODE.
printf '%s\\n' "$*" >> "$FAKE_LOG"
for a in "$@"; do
  case "$a" in @*) cat "${a#@}" >> "$FAKE_BODY" ;; esac
done
printf '%s' "${FAKE_CODE:-200}"
"""


class TellTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-tell-"))
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        (bin_dir / "curl").write_text(FAKE_CURL)
        (bin_dir / "curl").chmod(0o755)
        self.log = self.tmp / "curl.log"
        self.body = self.tmp / "body.txt"
        self.env = os.environ.copy()
        self.env.update(
            PATH=f"{bin_dir}:{self.env['PATH']}",
            FAKE_LOG=str(self.log),
            FAKE_BODY=str(self.body),
            OS_SECRET_SCAN="bundled",
        )
        self.note = self.tmp / "note.txt"
        self.note.write_text("Step: add-area. The second question was not clear. OS v1.0.6.\n")

    def tearDown(self):
        subprocess.run(["rm", "-rf", str(self.tmp)])

    def tell(self, *args, code="200"):
        env = dict(self.env, FAKE_CODE=code)
        return subprocess.run(["bash", str(TELL), *args], env=env, capture_output=True, text=True)

    def test_no_yes_sends_nothing(self):
        r = self.tell("--file", str(self.note))
        self.assertEqual(r.returncode, 1)
        self.assertIn("wait for a clear yes", r.stderr)
        self.assertFalse(self.log.exists())

    def test_sent_as_plain_text_to_the_address(self):
        r = self.tell("--file", str(self.note), "--yes")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("tell: sent.", r.stdout)
        call = self.log.read_text()
        self.assertIn("https://1610.sh/os/feedback", call)
        self.assertIn("content-type: text/plain", call)
        self.assertEqual(self.body.read_text(), self.note.read_text())

    def test_no_address_prints_the_note_and_where_to_paste(self):
        r = self.tell("--file", str(self.note), "--yes", code="404")
        self.assertEqual(r.returncode, 3)
        self.assertIn("tell: not sent:", r.stdout)
        self.assertIn("https://github.com/1610-advisory/os-foundation/issues/new", r.stdout)
        self.assertIn("The second question was not clear.", r.stdout)

    def test_too_long_or_empty_is_refused(self):
        self.note.write_text("x" * 2001)
        r = self.tell("--file", str(self.note), "--yes")
        self.assertEqual(r.returncode, 1)
        self.assertIn("2,000 or fewer", r.stderr)
        self.note.write_text("  \n")
        self.assertEqual(self.tell("--file", str(self.note), "--yes").returncode, 1)
        self.assertFalse(self.log.exists())

    def test_a_secret_sends_nothing(self):
        token = "gh" + "p_" + "A1b2" * 9
        self.note.write_text(f"It failed with token {token}\n")
        r = self.tell("--file", str(self.note), "--yes")
        self.assertEqual(r.returncode, 2)
        self.assertNotIn(token, r.stdout + r.stderr)
        self.assertFalse(self.log.exists())

    def test_a_missing_scan_sends_nothing(self):
        # A copy of tell.sh with no skills/sync/secret-scan.sh next to it.
        lone = self.tmp / "skills" / "suggest"
        lone.mkdir(parents=True)
        (lone / "tell.sh").write_text(TELL.read_text())
        r = subprocess.run(["bash", str(lone / "tell.sh"), "--file", str(self.note), "--yes"],
                           env=dict(self.env, FAKE_CODE="200"), capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("secret scan", r.stderr)
        self.assertFalse(self.log.exists())

    def test_a_scan_error_sends_nothing(self):
        r = subprocess.run(["bash", str(TELL), "--file", str(self.note), "--yes"],
                           env=dict(self.env, FAKE_CODE="200", OS_SECRET_SCAN="gitleaks",
                                    PATH=str(self.tmp / "bin") + ":/usr/bin:/bin"),
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertFalse(self.log.exists())


class WordingTests(unittest.TestCase):
    def test_sign_off_sync(self):
        agents = (TEMPLATE / "AGENTS.md").read_text()
        self.assertIn('At sign-off, or on "sync now", run `skills/sync/sync.sh push`', agents)
        self.assertLess(len(agents), 9000)
        skill = (TEMPLATE / "skills" / "sync" / "SKILL.md").read_text()
        self.assertIn('## Sign-off and "sync now"', skill)
        self.assertIn("Do not push after every turn", skill)
        self.assertNotIn("by hand only when the person asks", skill)

    def test_hold_reasons_have_a_fix(self):
        skill = (TEMPLATE / "skills" / "sync" / "SKILL.md").read_text()
        self.assertIn("| `person note: belongs in admin` |", skill)
        self.assertIn("| `extra hold: <heading>` |", skill)
        cli = (TEMPLATE / "skills" / "sync" / "CLI.md").read_text()
        self.assertIn("~/.config/os-brain/push-holds.md", cli)

    def test_tell_step(self):
        skill = (TEMPLATE / "skills" / "suggest" / "SKILL.md").read_text()
        self.assertIn('## Quick note: "tell 1610 X"', skill)
        self.assertIn("Never pass `--yes` before that yes.", skill)

    def test_security_md(self):
        text = (ROOT / "SECURITY.md").read_text()
        self.assertIn("Do not open a public issue", text)
        self.assertIn("Report a vulnerability", text)
        self.assertIn("within 5 working days", text)
        self.assertIn("after the release that fixes it", text)

    def test_tool_repo_wording(self):
        text = (TEMPLATE / "skills" / "app-setup" / "SKILL.md").read_text()
        self.assertIn("An owner's agent makes the tool repo, when an owner asks. Members do not make repos", text)
        self.assertIn("Code goes in the tool's own repo, never in the company OS folder", text)


if __name__ == "__main__":
    unittest.main()
