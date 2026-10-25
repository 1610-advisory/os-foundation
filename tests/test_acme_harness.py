"""Static checks for the Acme harness. No Docker and no tokens required."""

from __future__ import annotations

import importlib.util
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACME = ROOT / "tests" / "acme"
LIB = ACME / "lib"


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, LIB / f"{name}.py")
    if spec is None or spec.loader is None:
        raise RuntimeError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


scrub = load("scrub")
results = load("results")


class ComposeTests(unittest.TestCase):
    def setUp(self):
        self.text = (ACME / "forgejo" / "compose.yml").read_text()

    def test_pins_forgejo_and_runner(self):
        self.assertIn("data.forgejo.org/forgejo/forgejo:17.0.0", self.text)
        self.assertIn("data.forgejo.org/forgejo/runner:13.2.0", self.text)
        self.assertIn("docker:29.9.2-dind", self.text)

    def test_publishes_port_3300(self):
        self.assertIn("3300:3000", self.text)

    def test_does_not_mount_the_host_socket(self):
        self.assertNotIn("/var/run/docker.sock", self.text)
        self.assertNotIn("docker.sock", self.text)

    def test_names_use_the_acme_prefix(self):
        for name in (
            "osf-acme-forgejo",
            "osf-acme-dind",
            "osf-acme-runner",
            "osf-acme-forgejo-data",
            "osf-acme-runner-data",
            "osf-acme-dind-certs",
            "osf-acme-dind-data",
        ):
            self.assertIn(name, self.text)
        self.assertIn("name: osf-acme", self.text)

    def test_job_image_has_the_required_tools(self):
        text = (ACME / "forgejo" / "job.Dockerfile").read_text()
        for tool in ("bash", "git", "curl", "jq"):
            self.assertIn(tool, text)

    def test_runner_label_points_at_the_job_image(self):
        text = (ACME / "forgejo" / "runner-config.template.yml").read_text()
        self.assertIn("ubuntu-latest:docker://osf-acme-job:local", text)
        self.assertNotIn("{{", text)
        self.assertIn("OS_REVIEW_FAKE: /opt/os-review-fake/verdicts.txt", text)
        self.assertIn("-v /opt/os-review-fake:/opt/os-review-fake:ro", text)
        self.assertIn("- /opt/os-review-fake", text)


class RepoHygieneTests(unittest.TestCase):
    def test_gitignore_covers_the_output_dir(self):
        text = (ROOT / ".gitignore").read_text()
        self.assertIn("tests/acme/.out/", text)

    def test_public_files_stay_generic(self):
        banned = (
            "/Use" + "rs/",
            "daw" + "son",
            "1610" + "advisory",
            "gh" + "p_",
            "docker.sock",
        )
        for path in ACME.rglob("*"):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            if path.suffix not in {".sh", ".py", ".md", ".yml", ".txt", ".Dockerfile"} and path.name != "job.Dockerfile":
                continue
            text = path.read_text(encoding="utf-8")
            for word in banned:
                self.assertNotIn(word, text, f"{path} contains {word}")

    def test_readme_names_seats_and_token_locations(self):
        text = (ACME / "README.md").read_text()
        self.assertIn("member-d", text)
        self.assertIn("~/.cache/os-foundation/forgejo/tokens/<user>", text)
        self.assertIn("~/.cache/os-foundation/forgejo/admin-token", text)
        self.assertIn("ubuntu-latest", text)
        self.assertIn("OSF_ACME_CLAUDE_MODEL", text)
        self.assertIn("OSF_ACME_PI_MODEL", text)
        self.assertIn("not limited to the sandbox folder", text)


class ScrubTests(unittest.TestCase):
    def test_redacts_known_values_and_token_shapes(self):
        secret = "abc123tokenvalue"
        shaped = "gh" + "p_" + "exampletoken"
        text = f"token={secret} and {shaped} and sha 0123456789abcdef0123456789abcdef01234567"
        cleaned = scrub.scrub_text(text, [secret])
        self.assertNotIn(secret, cleaned)
        self.assertNotIn(shaped, cleaned)
        self.assertIn("0123456789abcdef0123456789abcdef01234567", cleaned)

    def test_redacts_authorization_header(self):
        cleaned = scrub.scrub_text("Authorization: token deadbeefdeadbeef", [])
        self.assertNotIn("deadbeefdeadbeef", cleaned)
        self.assertIn("[redacted]", cleaned)


class ResultParserTests(unittest.TestCase):
    def test_trailers_come_from_the_last_block(self):
        message = "fix the note\n\nRun-Id: run-9\nBot-Owner: acme-bot\n"
        self.assertEqual(
            results.parse_trailers(message),
            {"Run-Id": "run-9", "Bot-Owner": "acme-bot"},
        )

    def test_protection_summary(self):
        rules = [{
            "branch_name": "main",
            "enable_push": False,
            "required_approvals": 0,
            "enable_status_check": True,
            "status_check_contexts": ["checks / checks (pull_request)"],
            "apply_to_admins": True,
        }]
        summary = results.normalize_protection(rules, "main")
        self.assertTrue(summary["protected"])
        self.assertTrue(summary["push_blocked"])
        self.assertEqual(summary["required_approvals"], 0)
        self.assertIn("checks / checks (pull_request)", summary["status_checks"])

    def test_pr_summary_matches_the_host_shape(self):
        pull = {"state": "open", "merged": False, "number": 4, "head": {"sha": "abc"}}
        status = {"statuses": [{"context": "checks / checks (pull_request)", "state": "success"}]}
        reviews = [{"state": "APPROVED"}]
        summary = results.normalize_pr(pull, status, [], reviews)
        self.assertEqual(summary["state"], "open")
        self.assertFalse(summary["merged"])
        self.assertTrue(summary["approved"])
        self.assertEqual(summary["checks"][0]["name"], "checks / checks (pull_request)")
        self.assertEqual(summary["checks"][0]["state"], "success")

    def test_runner_online_states(self):
        self.assertTrue(results.runner_is_online({"status": "online"}))
        self.assertTrue(results.runner_is_online({"online": True}))
        self.assertFalse(results.runner_is_online({"status": "offline"}))


class ScriptContractTests(unittest.TestCase):
    def test_run_tier_b_blocks_every_selected_scenario(self):
        proc = subprocess.run(
            ["bash", str(ACME / "run.sh"), "--tier", "b", "--only", "S0,S2"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("S0 BLOCKED: gates G1–G8", proc.stdout)
        self.assertIn("S2 BLOCKED: gates G1–G8", proc.stdout)
        self.assertIn("ACME: FAIL", proc.stdout)
        self.assertIn("BLOCKED: S0 S2", proc.stdout)
        self.assertNotIn("ACME: PASS", proc.stdout)

    def test_run_tier_a_missing_script_is_a_fail(self):
        proc = subprocess.run(
            ["bash", str(ACME / "run.sh"), "--tier", "a", "--only", "S99"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("S99 FAIL missing script", proc.stdout)
        self.assertIn("ACME: FAIL S99", proc.stdout)

    def test_director_is_blocked_when_codex_is_missing(self):
        which = subprocess.run(["bash", "-lc", "command -v codex"], capture_output=True, text=True)
        if which.returncode == 0:
            self.skipTest("codex is installed; this check is for the missing-engine path")
        prompt = ACME / ".out" / "prompt.txt"
        prompt.parent.mkdir(parents=True, exist_ok=True)
        prompt.write_text("Say hello.\n")
        proc = subprocess.run(
            ["bash", str(ACME / "seat.sh"), "director", str(prompt)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 3)
        self.assertIn("BLOCKED: director", proc.stdout)
        self.assertIn("codex", proc.stdout)

    def test_unknown_seat_exits_1(self):
        prompt = ACME / ".out" / "prompt.txt"
        prompt.parent.mkdir(parents=True, exist_ok=True)
        prompt.write_text("Say hello.\n")
        proc = subprocess.run(
            ["bash", str(ACME / "seat.sh"), "no-such", str(prompt)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 1)

    def test_help_exits_0(self):
        for rel in (
            "run.sh",
            "seat.sh",
            "forgejo/up.sh",
            "forgejo/down.sh",
            "forgejo/bootstrap.sh",
        ):
            proc = subprocess.run(
                ["bash", str(ACME / rel), "--help"],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, rel)
            self.assertIn("usage:", proc.stdout)


if __name__ == "__main__":
    unittest.main()
