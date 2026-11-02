"""Local checks for nightly review and reports.

Names in fixtures are made up. The Forgejo scenario is tests/nightly/run.sh.
"""
from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(script, env=None):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        ["bash", str(ROOT / script)],
        cwd=ROOT,
        env=merged,
        capture_output=True,
        text=True,
    )


class NightlyLocalTests(unittest.TestCase):
    def test_local(self):
        result = run("tests/nightly/local.sh")
        if result.returncode != 0:
            self.fail(result.stdout + result.stderr)

    def test_forgejo_or_blocked(self):
        result = run("tests/nightly/run.sh")
        if result.returncode == 3:
            self.skipTest(result.stdout.strip() or result.stderr.strip() or "BLOCKED")
        if result.returncode != 0:
            self.fail(result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
