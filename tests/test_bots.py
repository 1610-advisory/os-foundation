"""Run the bots shell suite. Token values must not appear in the output."""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "tests" / "bots" / "run.sh"


def _secret_files():
    home = Path.home()
    cache = home / ".cache" / "os-foundation" / "forgejo"
    paths = [cache / "admin-token", cache / "tokens" / "acme-admin", cache / "tokens" / "acme-bot"]
    return [path for path in paths if path.is_file()]


class BotsTests(unittest.TestCase):
    def test_shell_suite(self):
        env = os.environ.copy()
        proc = subprocess.run(
            ["bash", str(RUN)],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
        )
        sys_out = proc.stdout + proc.stderr
        # Show the suite result, never a token file.
        safe = sys_out
        for path in _secret_files():
            secret = path.read_text(encoding="utf-8").strip()
            if secret and secret in safe:
                self.fail("secret appeared in bots test output")
            if secret:
                safe = safe.replace(secret, "[redacted]")
        if proc.returncode != 0:
            self.fail(safe)
        self.assertIn("PASS bots suite", proc.stdout)


if __name__ == "__main__":
    unittest.main()
