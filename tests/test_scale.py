"""Scale-check contracts. No Docker required.

Run: python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "tests" / "scale" / "lib"
os.sys.path.insert(0, str(LIB))

import assign  # noqa: E402
import api  # noqa: E402
import gitauth  # noqa: E402
import proc  # noqa: E402
import push_window  # noqa: E402
import render  # noqa: E402

CANARY = "scale-canary-secret-value"


class AssignTests(unittest.TestCase):
    def test_spread_is_fixed_and_mostly_one_area(self):
        first = assign.assignments(5000, 200, 1610)
        second = assign.assignments(5000, 200, 1610)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 5000)
        counts = assign.area_counts(first)
        self.assertGreater(counts[1] / 5000, 0.7)
        self.assertGreater(counts[2], 0)
        self.assertGreater(counts[3], 0)
        used = {repo for repos in first.values() for repo in repos}
        self.assertEqual(len(used), 200)
        for repos in first.values():
            self.assertEqual(len(repos), len(set(repos)))
            self.assertLessEqual(len(repos), 3)

    def test_denial_sample_is_half_and_half(self):
        rows = assign.assignments(5000, 200, 1610)
        sample = assign.denial_sample(rows, 200, 200, 1610)
        self.assertEqual(len(sample), 200)
        self.assertEqual(sum(1 for item in sample if item["allow"]), 100)
        self.assertEqual(assign.denial_sample(rows, 200, 200, 1610), sample)
        seen = set()
        for item in sample:
            key = (item["user"], item["repo"])
            self.assertNotIn(key, seen)
            seen.add(key)
            member = item["repo"] in rows[item["user"]]
            self.assertEqual(member, item["allow"])

    def test_schedule_stays_inside_the_window(self):
        rows = assign.assignments(20, 5, 1610)
        names = assign.push_users(rows, 10, 1610)
        jobs = assign.schedule(names, rows, 180, 120, 1610)
        self.assertEqual(len(jobs), 10)
        self.assertEqual(jobs, assign.schedule(names, rows, 180, 120, 1610))
        for job in jobs:
            self.assertGreaterEqual(job["offset_min"], 0)
            self.assertLess(job["offset_min"], 180)
            self.assertAlmostEqual(job["wall_s"], job["offset_min"] * 60 / 120)


class PageTests(unittest.TestCase):
    def test_list_follows_pages_until_a_short_page(self):
        seen = []

        def transport(method, url, headers, body):
            self.assertNotIn(CANARY, url)
            self.assertNotIn("Authorization", url)
            page = int(url.rsplit("page=", 1)[1])
            seen.append(page)
            if page < 3:
                payload = [{"login": f"user-{page}-{i}"} for i in range(50)]
            else:
                payload = [{"login": "user-last"}]
            return 200, json.dumps(payload).encode()

        client = api.Client(token_file=None, transport=transport)
        client._token = lambda: CANARY  # noqa: SLF001
        rows = client.list_all("/api/v1/admin/users")
        self.assertEqual(seen, [1, 2, 3])
        self.assertEqual(len(rows), 101)

    def test_find_stops_when_the_item_is_found(self):
        seen = []

        def transport(method, url, headers, body):
            page = int(url.rsplit("page=", 1)[1])
            seen.append(page)
            payload = [{"login": "user-0001" if page == 1 else "other"}]
            if page == 1:
                payload = [{"login": f"user-{i:04d}"} for i in range(1, 51)]
            return 200, json.dumps(payload).encode()

        client = api.Client(token_file=None, transport=transport)
        client._token = lambda: "x"  # noqa: SLF001
        found = client.find("/api/v1/admin/users", lambda item: item.get("login") == "user-0007")
        self.assertEqual(found["login"], "user-0007")
        self.assertEqual(seen, [1])


class ArgvTests(unittest.TestCase):
    def write_fake(self, folder: Path, name: str) -> None:
        dest = folder / name
        dest.write_text((LIB / "fake-argv.sh").read_text(encoding="utf-8"), encoding="utf-8")
        dest.chmod(0o755)

    def test_git_clone_argv_has_no_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fake(root, "git")
            token = root / "token"
            token.write_text(CANARY + "\n", encoding="utf-8")
            token.chmod(0o600)
            log = root / "argv.log"
            env = os.environ.copy()
            env["PATH"] = str(root) + os.pathsep + env.get("PATH", "")
            env["FAKE_ARGV_LOG"] = str(log)
            work = root / "work"
            proc = gitauth.git(
                ["git", "clone", "--depth", "1", "http://localhost:3400/scale/area-001.git", str(root / "dest")],
                token_file=token,
                username="user-0001",
                work=work,
                secrets=[CANARY],
                env_base=env,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            recorded = log.read_text(encoding="utf-8")
            self.assertNotIn(CANARY, recorded)
            self.assertNotIn("Authorization", recorded)
            self.assertNotIn("@", recorded.split("clone", 1)[-1])

    def test_create_users_script_discards_the_password_and_keeps_it_off_argv(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fake(root, "forgejo")
            log = root / "argv.log"
            env = os.environ.copy()
            env["PATH"] = str(root) + os.pathsep + env.get("PATH", "")
            env["FAKE_ARGV_LOG"] = str(log)
            env["FAKE_ARGV_STDOUT"] = "generated password " + CANARY
            env["OSF_MUST_CHANGE"] = "0"
            proc = subprocess.run(
                ["sh", str(LIB / "create-users.sh")],
                input="user-0001\n",
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertNotIn(CANARY, proc.stdout)
            self.assertNotIn(CANARY, proc.stderr)
            recorded = log.read_text(encoding="utf-8")
            self.assertNotIn(CANARY, recorded)
            self.assertNotIn("--password ", recorded)
            self.assertIn("--random-password", recorded)

    def test_create_users_failure_does_not_print_the_password(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fake(root, "forgejo")
            env = os.environ.copy()
            env["PATH"] = str(root) + os.pathsep + env.get("PATH", "")
            env["FAKE_ARGV_STDOUT"] = CANARY
            env["FAKE_ARGV_EXIT"] = "1"
            proc = subprocess.run(
                ["sh", str(LIB / "create-users.sh")],
                input="user-0001\n",
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertNotIn(CANARY, proc.stdout)
            self.assertNotIn(CANARY, proc.stderr)
            self.assertIn("FAIL: create user-0001", proc.stderr)

    def test_guard_refuses_a_secret_in_argv(self):
        with self.assertRaises(proc.SecretInArgv):
            proc.assert_clean_argv(["curl", "-H", "Authorization: token " + CANARY], [CANARY])

    def test_shell_scripts_do_not_put_auth_on_a_command_line(self):
        for path in (ROOT / "tests" / "scale").rglob("*.sh"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("Authorization", text, path.name)
            self.assertNotIn("--password ", text, path.name)
            self.assertNotIn("token@", text, path.name)


class ScriptTests(unittest.TestCase):
    def test_help_exits_zero(self):
        for name in ("up.sh", "down.sh", "bootstrap.sh", "read-denial.sh", "push-window.sh"):
            proc = subprocess.run(
                ["bash", str(ROOT / "tests" / "scale" / name), "--help"],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, name)
            self.assertIn("usage:", proc.stdout)

    def test_compose_is_a_second_stack(self):
        text = (ROOT / "tests" / "scale" / "compose.yml").read_text(encoding="utf-8")
        self.assertIn("3400:3000", text)
        self.assertIn("osf-scale-forgejo", text)
        self.assertIn("osf-scale-forgejo-data", text)
        self.assertNotIn("3300:3000", text)
        self.assertNotIn("osf-acme", text)
        self.assertNotIn("runner:", text.lower())

    def test_non_ff_and_percentile(self):
        self.assertTrue(gitauth.is_non_ff("! [rejected] sync/user-0001 -> sync/user-0001 (non-fast-forward)"))
        self.assertFalse(gitauth.is_non_ff("everything up to date"))
        self.assertEqual(push_window.percentile([1, 2, 3, 4], 50), 2)

    def test_render_has_no_home_path(self):
        text = render.render(
            {"cpu": "test", "docker_cpus": 12, "docker_memory_bytes": 8000000000, "container_cpus": 2, "container_memory_bytes": 2147483648, "forgejo_image": "example", "forgejo_version": "17", "port": 3400},
            {"users": 5000, "areas": 200, "company_repos": 1, "teams": 200, "memberships": 6250, "seed": 1610, "one": 4000, "two": 750, "three": 250, "phases": [{"name": "users", "count": 5000, "seconds": 1}]},
            {"pairs": 200, "allowed": 100, "denied": 100, "wrong": 0, "incomplete": 0, "seconds": 1, "seed": 1610},
            {"users": 10, "pushes_ok": 12, "pushes_fail": 0, "window_min": 180, "factor": 120, "wall_seconds": 3, "pushes_per_min_wall": 4, "pushes_per_min_window": 0.06, "p50_s": 0.2, "p95_s": 0.4, "non_ff": 0, "merges_ok": 1, "merges_tried": 1, "concurrency": 4, "api_status": {"201": 1}, "api_errors": {}, "kinds": {}},
            "No hard stop.",
        )
        self.assertIn("Forgejo is not GitHub", text)
        self.assertIn("Wrong answers", text)
        self.assertNotIn("/Users/", text)
        self.assertNotIn(CANARY, text)

    def test_token_file_mode_helper(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "token"
            path.write_text("x", encoding="utf-8")
            path.chmod(0o600)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
