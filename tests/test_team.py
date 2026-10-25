"""Team script tests. Shell scripts print PASS or BLOCKED."""

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEAM = ROOT / "tests" / "team"


def run_script(name):
    proc = subprocess.run(
        ["bash", str(TEAM / name)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=900,
    )
    out = (proc.stdout or "") + (proc.stderr or "")
    if "BLOCKED" in out and proc.returncode == 0:
        raise unittest.SkipTest(out.strip())
    if proc.returncode != 0:
        raise AssertionError(out[-4000:])
    if "PASS" not in out:
        raise AssertionError(out[-4000:])


class TeamScripts(unittest.TestCase):
    def test_lint(self):
        run_script("test_lint.sh")

    def test_argv(self):
        run_script("test_argv.sh")

    def test_upgrade(self):
        run_script("test_upgrade.sh")

    def test_p1(self):
        run_script("test_p1.sh")

    def test_forgejo(self):
        run_script("test_forgejo.sh")


if __name__ == "__main__":
    unittest.main()
