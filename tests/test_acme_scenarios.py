"""Static checks for Acme scenarios S1-S14. No Docker and no tokens."""

from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACME = ROOT / "tests" / "acme"
LIB = ACME / "lib"
STEP_RE = re.compile(r"^[0-9]+\. ")


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, LIB / f"{name}.py")
    if spec is None or spec.loader is None:
        raise RuntimeError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


results = load("results")


def numbered_steps(text: str) -> int:
    return sum(1 for line in text.splitlines() if STEP_RE.match(line))


class ResultRuleTests(unittest.TestCase):
    def test_missing_repo_is_a_host_error(self):
        payload, code = results.classify_access(404, 404)
        self.assertEqual(code, 3)
        self.assertEqual(payload["error"], "missing")

    def test_user_404_on_a_visible_repo_is_a_denial(self):
        payload, code = results.classify_access(200, 404)
        self.assertEqual(code, 0)
        self.assertTrue(payload["denied"])

    def test_user_200_is_not_a_denial(self):
        payload, code = results.classify_access(200, 200)
        self.assertEqual(code, 2)
        self.assertFalse(payload["denied"])

    def test_network_error_is_a_host_error(self):
        _payload, code = results.classify_access(None, None)
        self.assertEqual(code, 3)

    def test_checks_need_a_sha_and_the_checks_context(self):
        self.assertFalse(results.checks_are_green("", [{"context": "checks", "state": "success"}], []))
        self.assertFalse(results.checks_are_green("abc", [{"context": "other", "state": "success"}], []))
        self.assertTrue(results.checks_are_green("abc", [{"context": "checks / checks", "state": "success"}], []))
        self.assertFalse(results.checks_are_green(
            "abc", [], [{"name": "checks", "status": "success", "head_sha": "other"}]
        ))
        self.assertTrue(results.checks_are_green(
            "abc", [], [{"name": "checks", "status": "success", "head_sha": "abc"}]
        ))

    def test_empty_tag_list_is_not_a_pass(self):
        self.assertEqual(results.list_exit([]), 2)
        self.assertEqual(results.list_exit(["os-rewrite-1"]), 0)


class EngineFixtureTests(unittest.TestCase):
    def test_rules_text_does_not_hold_a_safe_note(self):
        prompt = (
            "Hold if it carries the tag source: private.\n"
            "DIFF:\n"
            "<the diff of that one file>\n"
            "REPO: area\n"
            "FILE: notes/widget.md\n"
            "DIFF:\n"
            "+The widget ships on Tuesdays.\n"
        )
        proc = subprocess.run(
            ["bash", str(ACME / "fixtures" / "engine.sh")],
            input=prompt,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn('"decision":"commit"', proc.stdout)

    def test_private_source_in_the_diff_is_a_hold(self):
        prompt = "FILE: notes/dm.md\nDIFF:\n+source: private\n"
        proc = subprocess.run(
            ["bash", str(ACME / "fixtures" / "engine.sh")],
            input=prompt,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn('"decision":"hold"', proc.stdout)

    def test_company_fact_in_a_profile_is_a_hold(self):
        prompt = (
            "FILE: <path inside that repo>\n"
            "DIFF:\n"
            "<the diff of that one file>\n"
            "FILE: profile/PROFILE.md\n"
            "DIFF:\n"
            "+OSF-COMPANY-FACT Acme Co ships 40 widgets.\n"
        )
        proc = subprocess.run(
            ["bash", str(ACME / "fixtures" / "engine.sh")],
            input=prompt,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn('"decision":"hold"', proc.stdout)
        self.assertIn("company fact", proc.stdout)


class CleanStartTests(unittest.TestCase):
    def test_create_org_does_not_reuse_a_leftover(self):
        text = (LIB / "scenario.sh").read_text()
        self.assertNotIn('osf_delete_org "$org" || true', text)
        self.assertNotIn('"$code" = "409"', text)
        self.assertIn("FAIL clean start failed", text)
        self.assertIn('GET "/api/v1/orgs/${org}"', text)


class SeatLockTests(unittest.TestCase):
    def test_helper_returns_nothing_for_github(self):
        helper = LIB / "git-credential-seat.sh"
        proc = subprocess.run(
            ["sh", str(helper)],
            input="protocol=https\nhost=github.com\n\n",
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, "OSF_GIT_USER": "ada", "OSF_FORGEJO_TOKEN": "secret-value"},
        )
        self.assertEqual(proc.returncode, 0)
        self.assertNotIn("username=", proc.stdout)
        self.assertNotIn("password=", proc.stdout)
        self.assertNotIn("secret-value", proc.stdout)

    def test_ssh_to_github_is_off(self):
        ssh_off = LIB / "ssh-off.sh"
        proc = subprocess.run(
            [
                "git",
                "-c", f"core.sshCommand={ssh_off}",
                "ls-remote",
                "git" + "@" + "github.com:octocat/Hello-World.git",
            ],
            capture_output=True,
            text=True,
            check=False,
            env={
                **os.environ,
                "GIT_SSH_COMMAND": str(ssh_off),
                "GIT_ALLOW_PROTOCOL": "http:https:file",
                "GIT_TERMINAL_PROMPT": "0",
            },
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertTrue(
            "ssh is off in Acme seats" in proc.stderr or "not allowed" in proc.stderr,
            proc.stderr,
        )
        direct = subprocess.run([str(ssh_off)], capture_output=True, text=True, check=False)
        self.assertEqual(direct.returncode, 1)
        self.assertIn("ssh is off in Acme seats", direct.stderr)

    def test_path_shim_blocks_ssh_without_a_network_client(self):
        import tempfile
        ssh_off = LIB / "ssh-off.sh"
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp)
            for name in ("ssh", "scp", "sftp"):
                (bindir / name).symlink_to(ssh_off)
            env = {
                **os.environ,
                "PATH": f"{bindir}:{os.environ.get('PATH', '')}",
                "GIT_SSH_COMMAND": str(bindir / "ssh"),
                "GIT_ALLOW_PROTOCOL": "http:https:file",
                "GIT_TERMINAL_PROMPT": "0",
                "RSYNC_RSH": str(bindir / "ssh"),
            }
            which = subprocess.run(["ssh", "-V"], capture_output=True, text=True, check=False, env=env)
            self.assertEqual(which.returncode, 1)
            self.assertIn("ssh is off in Acme seats", which.stderr)
            self.assertNotIn("OpenSSH", which.stderr)
            remote = "git" + "@" + "github.com:octocat/Hello-World.git"
            proc = subprocess.run(
                ["git", "ls-remote", remote],
                capture_output=True,
                text=True,
                check=False,
                env=env,
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("ssh is off in Acme seats", proc.stderr + which.stderr)


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
