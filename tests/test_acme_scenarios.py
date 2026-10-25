"""Static checks for Acme scenarios S1-S14. No Docker and no tokens."""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACME = ROOT / "tests" / "acme"
STEP_RE = re.compile(r"^[0-9]+\. ")


def numbered_steps(text: str) -> int:
    return sum(1 for line in text.splitlines() if STEP_RE.match(line))


class ScenarioScriptTests(unittest.TestCase):
    def test_s1_through_s14_exist(self):
        for number in range(1, 15):
            path = ACME / "scenarios" / f"S{number}.sh"
            self.assertTrue(path.is_file(), path.name)
            text = path.read_text(encoding="utf-8")
            self.assertIn("set -euo pipefail", text)
            self.assertIn(f"S{number}", text)

    def test_step_count_is_one_less_than_t0(self):
        new = subprocess.run(
            ["git", "show", "HEAD:start-core.md"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        old = subprocess.run(
            ["git", "show", "c2034af:start-core.md"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        new_n = numbered_steps(new.stdout)
        old_n = numbered_steps(old.stdout)
        self.assertEqual(new_n, old_n - 1, f"new={new_n} old={old_n}")

    def test_run_prints_every_result_line(self):
        proc = subprocess.run(
            ["bash", str(ACME / "run.sh"), "--tier", "a", "--only", "S99"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertIn("S99 FAIL missing script", proc.stdout)


if __name__ == "__main__":
    unittest.main()
