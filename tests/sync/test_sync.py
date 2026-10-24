"""Tests for the sync skill.

Names are made up. Token values are never printed.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYNC = ROOT / "template" / "skills" / "sync"
HOST = ROOT / "template" / "skills" / "_host"
ENGINE = ROOT / "tests" / "fakes" / "engine.sh"
SECRET = "gh" + "p_" + ("ab12" * 9)


def run(cmd, env=None, cwd=None, check=False):
    return subprocess.run(
        cmd,
        cwd=cwd or ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=check,
    )


def git_env(base):
    env = base.copy()
    env["GIT_AUTHOR_NAME"] = "Mia Member"
    env["GIT_AUTHOR_EMAIL"] = "mia.member@acme.test"
    env["GIT_COMMITTER_NAME"] = "Mia Member"
    env["GIT_COMMITTER_EMAIL"] = "mia.member@acme.test"
    return env


def write_profile(path, level, switches, slug="acme"):
    items = ", ".join(switches)
    path.write_text(
        "\n".join(
            [
                "---",
                "type: company-profile",
                'summary: "Acme Co test"',
                "updated: 2026-10-24",
                f"company_slug: {slug}",
                f"level: {level}",
                f"switches: [{items}]",
                "os_version: 0.0.0-test",
                "host: forgejo",
                'host_url: "http://localhost:3300"',
                "org: acme",
                'sync_engine: ""',
                "runner: ubuntu-latest",
                "---",
                "",
                "# Acme Co",
                "",
            ]
        )
    )


def base_env(home, company, host_dir):
    env = git_env(os.environ.copy())
    env["HOME"] = str(home)
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    env["OS_COMPANY_ROOT"] = str(company)
    env["OS_PROFILE"] = str(company / "company-profile.md")
    env["OS_HOST_SH"] = str(host_dir / "host.sh")
    env["OS_PROFILE_SH"] = str(host_dir / "profile.sh")
    env["OS_TEST_MODE"] = "1"
    env["OS_SECRET_SCAN"] = "bundled"
    env["OS_SYNC_ENGINE"] = str(ENGINE)
    env["OS_ENGINE_TIMEOUT"] = "5"
    return env


class SyncLocalTests(unittest.TestCase):
    @classmethod
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-sync-"))
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.company = self.home / "acme"
        self.company.mkdir()
        write_profile(self.company / "company-profile.md", "team", [])
        (self.company / "people").mkdir()
        (self.company / "people" / "Mia.md").write_text(
            "\n".join(
                [
                    "---",
                    "type: person",
                    "slug: mia",
                    "github: acme-member-a",
                    "email: mia.member@acme.test",
                    "role: writer",
                    "---",
                    "",
                    "# Mia Member",
                    "",
                ]
            )
        )
        cfg = self.home / ".config" / "acme-os"
        cfg.mkdir(parents=True)
        (cfg / "me").write_text("mia\n")
        self.env = base_env(self.home, self.company, HOST)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def sync(self, *args, env=None):
        return run(["bash", str(SYNC / "sync.sh"), *args], env=env or self.env, cwd=self.company)

    def test_secret_scan_holds_the_rule_not_the_value(self):
        path = self.tmp / "note.md"
        path.write_text(f"token = {SECRET}\n")
        result = run(
            ["bash", str(SYNC / "secret-scan.sh"), "--files", str(path)],
            env={**self.env, "OS_SECRET_SCAN": "bundled"},
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("github-pat", result.stdout)
        self.assertNotIn(SECRET, result.stdout)
        self.assertNotIn(SECRET, result.stderr)

    def test_jobs_refuse_solo_and_render(self):
        write_profile(self.company / "company-profile.md", "solo", [])
        jobs = self.tmp / "jobs"
        env = self.env.copy()
        env["OS_JOBS_DIR"] = str(jobs)
        env["OS_JOBS_PLATFORM"] = "macos"
        refused = self.sync("install-jobs", env=env)
        self.assertNotEqual(refused.returncode, 0)
        self.assertFalse(jobs.exists())

        write_profile(self.company / "company-profile.md", "team", [])
        env["OS_JOBS_PLATFORM"] = "macos"
        made = self.sync("install-jobs", "--admin", env=env)
        self.assertEqual(made.returncode, 0, made.stderr + made.stdout)
        plists = sorted(jobs.glob("*.plist"))
        self.assertGreaterEqual(len(plists), 4)
        for plist in plists:
            lint = run(["plutil", "-lint", str(plist)])
            self.assertEqual(lint.returncode, 0, lint.stdout + lint.stderr)
        text = "\n".join(p.read_text() for p in plists)
        self.assertIn("<integer>900</integer>", text)
        self.assertIn("<integer>2</integer>", text)
        self.assertIn("<integer>3</integer>", text)
        self.assertIn("<integer>30</integer>", text)

        linux = self.tmp / "linux-jobs"
        env["OS_JOBS_DIR"] = str(linux)
        env["OS_JOBS_PLATFORM"] = "linux"
        made = self.sync("install-jobs", "--admin", env=env)
        self.assertEqual(made.returncode, 0, made.stderr)
        names = sorted(p.name for p in linux.iterdir())
        self.assertTrue(any(n.endswith(".service") for n in names))
        self.assertTrue(any(n.endswith(".timer") for n in names))
        push_timer = next(p for p in linux.glob("*push*.timer"))
        self.assertIn("Persistent=true", push_timer.read_text())
        self.assertIn("RandomizedDelaySec=1800", push_timer.read_text())

        windows = self.tmp / "win-jobs"
        env["OS_JOBS_DIR"] = str(windows)
        env["OS_JOBS_PLATFORM"] = "windows"
        made = self.sync("install-jobs", env=env)
        self.assertEqual(made.returncode, 0, made.stderr)
        xml = "\n".join(p.read_text() for p in windows.glob("*.xml"))
        self.assertIn("Not tested", xml)

    def test_helper_day_count(self):
        host = self.tmp / "fake-host"
        host.mkdir()
        (host / "host.sh").write_text(
            "\n".join(
                [
                    "#!/bin/bash",
                    "case \"$1\" in",
                    "  repo-access)",
                    "    case \"$OS_FAKE_ACCESS\" in",
                    "      ok) printf '%s\\n' '{\"access\":\"ok\"}'; exit 0 ;;",
                    "      no-access) printf '%s\\n' '{\"access\":\"no-access\"}'; exit 2 ;;",
                    "      expired) printf '%s\\n' '{\"error\":\"auth\"}'; exit 4 ;;",
                    "      offline) printf '%s\\n' '{\"error\":\"offline\"}'; exit 5 ;;",
                    "    esac",
                    "    ;;",
                    "esac",
                    "exit 1",
                    "",
                ]
            )
        )
        (host / "host.sh").chmod(0o755)
        (host / "profile.sh").write_text(
            "#!/bin/bash\nprintf '%s\\n' acme\n"
        )
        (host / "profile.sh").chmod(0o755)
        env = self.env.copy()
        env["OS_HOST_SH"] = str(host / "host.sh")
        env["OS_PROFILE_SH"] = str(host / "profile.sh")
        env["OS_FAKE_ACCESS"] = "ok"
        env["OS_NOW"] = "2026-10-01"
        result = self.sync("helper", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads((self.home / ".config" / "acme-os" / "state" / "helper.json").read_text())
        self.assertEqual(state["days"], [])

        env["OS_FAKE_ACCESS"] = "expired"
        result = self.sync("helper", env=env)
        self.assertIn("sign in again", result.stdout)
        state = json.loads((self.home / ".config" / "acme-os" / "state" / "helper.json").read_text())
        self.assertEqual(state["days"], [])

        env["OS_FAKE_ACCESS"] = "offline"
        result = self.sync("helper", env=env)
        self.assertNotIn("sign in again", result.stdout)
        state = json.loads((self.home / ".config" / "acme-os" / "state" / "helper.json").read_text())
        self.assertEqual(state["days"], [])

        env["OS_FAKE_ACCESS"] = "no-access"
        for day in range(1, 8):
            env["OS_NOW"] = f"2026-10-{day:02d}"
            result = self.sync("helper", env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no access", result.stdout)
        self.assertTrue(self.company.exists())
        state = json.loads((self.home / ".config" / "acme-os" / "state" / "helper.json").read_text())
        self.assertEqual(len(state["days"]), 7)

        env["OS_NOW"] = "2026-10-07"
        self.sync("helper", env=env)
        state = json.loads((self.home / ".config" / "acme-os" / "state" / "helper.json").read_text())
        self.assertEqual(len(state["days"]), 7)

        for day in range(8, 15):
            env["OS_NOW"] = f"2026-10-{day:02d}"
            result = self.sync("helper", env=env)
        self.assertFalse(self.company.exists(), result.stdout + result.stderr)

    def test_helper_refuses_path_outside_home(self):
        outside = self.tmp / "outside"
        outside.mkdir()
        write_profile(outside / "company-profile.md", "team", [])
        host = self.tmp / "fake-host2"
        host.mkdir()
        (host / "host.sh").write_text(
            "#!/bin/bash\nprintf '%s\\n' '{\"access\":\"no-access\"}'\nexit 2\n"
        )
        (host / "host.sh").chmod(0o755)
        (host / "profile.sh").write_text("#!/bin/bash\nprintf '%s\\n' acme\n")
        (host / "profile.sh").chmod(0o755)
        state = self.home / ".config" / "acme-os" / "state"
        state.mkdir(parents=True)
        days = [f"2026-10-{day:02d}" for day in range(1, 14)]
        (state / "helper.json").write_text(json.dumps({"days": days, "warned": True}))
        env = self.env.copy()
        env["OS_HOST_SH"] = str(host / "host.sh")
        env["OS_PROFILE_SH"] = str(host / "profile.sh")
        env["OS_COMPANY_ROOT"] = str(outside)
        env["OS_PROFILE"] = str(outside / "company-profile.md")
        env["OS_NOW"] = "2026-10-14"
        result = self.sync("helper", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((outside / "company-profile.md").exists())

    def test_collect_cases(self):
        write_profile(self.company / "company-profile.md", "app", ["traces"])
        bravo = self.home / "bravo"
        bravo.mkdir()
        write_profile(bravo / "company-profile.md", "app", ["traces"], slug="bravo")
        shared = self.home / "shared" / "tools.md"
        shared.parent.mkdir()
        shared.write_text("a method\n")
        cfg = self.home / ".config"
        cfg.mkdir(exist_ok=True)
        (cfg / "os-shared-list").write_text(str(self.home / "shared") + "\n")
        projects = self.home / ".claude" / "projects" / "acme"
        projects.mkdir(parents=True)
        acme = str(self.company)
        bravo_file = str(bravo / "note.md")

        def session(name, cwd, tool_path, extra=""):
            line = {
                "type": "user",
                "cwd": cwd,
                "sessionId": name,
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "name": "Read",
                            "input": {"file_path": tool_path},
                        }
                    ]
                },
            }
            text = json.dumps(line) + "\n" + extra
            (projects / f"{name}.jsonl").write_text(text)

        session("inside", acme, str(self.company / "notes.md"))
        session("other", acme, bravo_file)
        session("root", str(self.home), str(self.company / "notes.md"))
        session("shared", acme, str(shared))
        session("secret", acme, str(self.company / "notes.md"), extra=f"token = {SECRET}\n")

        pi = self.home / ".pi" / "agent" / "sessions"
        pi.mkdir(parents=True)
        (pi / "parent.jsonl").write_text(
            json.dumps({"type": "session", "id": "parent", "cwd": acme}) + "\n"
        )
        sub = pi / "parent" / "sub"
        sub.mkdir(parents=True)
        (sub / "session.jsonl").write_text(
            json.dumps(
                {
                    "type": "message",
                    "message": {
                        "role": "assistant",
                        "content": [
                            {
                                "type": "toolCall",
                                "name": "read",
                                "arguments": {"path": bravo_file},
                            }
                        ],
                    },
                }
            )
            + "\n"
        )
        target = self.tmp / "traces"
        env = self.env.copy()
        env["OS_TRACES_TARGET"] = str(target)
        result = self.sync("collect", env=env)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        names = sorted(p.name for p in target.glob("*.jsonl"))
        self.assertIn("inside.jsonl", names)
        self.assertIn("shared.jsonl", names)
        self.assertIn("secret.jsonl", names)
        self.assertNotIn("other.jsonl", names)
        self.assertNotIn("root.jsonl", names)
        self.assertNotIn("parent.jsonl", names)
        uploaded = (target / "secret.jsonl").read_text()
        self.assertNotIn(SECRET, uploaded)
        self.assertIn("[redacted]", uploaded)
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertIn("collect hold other", log)
        self.assertIn("collect skip root", log)
        self.assertIn("collect hold parent", log)

    def test_collect_off_without_switch(self):
        env = self.env.copy()
        env["OS_TRACES_TARGET"] = str(self.tmp / "traces")
        result = self.sync("collect", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertIn("collect off", log)
        self.assertFalse((self.tmp / "traces").exists())

    def test_lock_blocks_a_second_run(self):
        state = self.home / ".config" / "acme-os" / "state"
        state.mkdir(parents=True)
        lock = state / "lock"
        lock.mkdir()
        (lock / "pid").write_text(str(os.getpid()))
        result = self.sync("pull")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another sync is running", result.stderr)

    def test_no_secret_in_argv(self):
        marker = "ARGVTOKENsyncmarker0123456789abcdef"
        spy = self.tmp / "spy"
        spy.mkdir()
        log = self.tmp / "argv.log"
        token_file = self.tmp / "token"
        token_file.write_text(marker + "\n")
        token_file.chmod(0o600)
        (spy / "git").write_text(
            "\n".join(
                [
                    "#!/bin/bash",
                    "printf '%s\\n' \"$*\" >> \"$ARGV_LOG\"",
                    "exec /usr/bin/git \"$@\"",
                    "",
                ]
            )
        )
        (spy / "curl").write_text(
            "\n".join(
                [
                    "#!/bin/bash",
                    "printf '%s\\n' \"$*\" >> \"$ARGV_LOG\"",
                    "exit 0",
                    "",
                ]
            )
        )
        (spy / "host.sh").write_text(
            "\n".join(
                [
                    "#!/bin/bash",
                    "printf '%s\\n' \"$*\" >> \"$ARGV_LOG\"",
                    "case \"$1\" in",
                    "  whoami) printf '%s\\n' '{\"login\":\"acme-member-a\"}' ;;",
                    "  get-token) tr -d '\\r\\n' < \"$OS_FAKE_TOKEN_FILE\"; printf '\\n' ;;",
                    "  open-pr) printf '%s\\n' '{\"number\":1,\"url\":\"http://example.test/1\"}' ;;",
                    "  auto-merge) printf '%s\\n' '{\"ok\":true}' ;;",
                    "  repo-access) printf '%s\\n' '{\"access\":\"ok\"}'; exit 0 ;;",
                    "  *) exit 1 ;;",
                    "esac",
                    "",
                ]
            )
        )
        for name in ("git", "curl", "host.sh"):
            (spy / name).chmod(0o755)
        (spy / "profile.sh").write_text("#!/bin/bash\nexec \"$1\" \"$@\"\n")
        # Use the real profile reader.
        shutil.copy(HOST / "profile.sh", spy / "profile.sh")
        shutil.copy(HOST / "lib.sh", spy / "lib.sh")
        (spy / "profile.sh").chmod(0o755)
        bare = self.tmp / "origin.git"
        run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], env=self.env, check=True)
        run(["git", "init", "-q", "-b", "main", str(self.company)], env=self.env, check=True)
        run(["git", "-C", str(self.company), "remote", "add", "origin", str(bare)], env=self.env, check=True)
        (self.company / "README.md").write_text("seed\n")
        run(["git", "-C", str(self.company), "add", "README.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "seed"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        (self.company / "notes.md").write_text("a company fact\n")
        env = self.env.copy()
        env["PATH"] = str(spy) + os.pathsep + env.get("PATH", "")
        env["ARGV_LOG"] = str(log)
        env["OS_FAKE_TOKEN_FILE"] = str(token_file)
        env["OS_HOST_SH"] = str(spy / "host.sh")
        env["OS_TRACES_TARGET"] = str(self.tmp / "traces")
        env["OS_TRACES_UPLOAD_URL"] = "http://127.0.0.1:9/traces"
        env["OS_TRACES_UPLOAD_TOKEN_FILE"] = str(token_file)
        write_profile(self.company / "company-profile.md", "app", ["traces"])
        projects = self.home / ".claude" / "projects" / "acme"
        projects.mkdir(parents=True)
        (projects / "one.jsonl").write_text(
            json.dumps(
                {
                    "type": "user",
                    "cwd": str(self.company),
                    "sessionId": "one",
                    "message": {
                        "content": [
                            {
                                "type": "tool_use",
                                "name": "Read",
                                "input": {"file_path": str(self.company / "notes.md")},
                            }
                        ]
                    },
                }
            )
            + "\n"
        )
        pushed = self.sync("push", env=env)
        collected = self.sync("collect", env=env)
        text = log.read_text() if log.exists() else ""
        self.assertNotIn(marker, text, pushed.stderr + collected.stderr)
        self.assertNotIn(marker, pushed.stdout + pushed.stderr)
        self.assertNotIn(marker, collected.stdout + collected.stderr)


class SyncForgejoTests(unittest.TestCase):
    def test_forgejo_cases(self):
        cache = Path.home() / ".cache" / "os-foundation" / "forgejo"
        env = os.environ.copy()
        env["OSF_ACME_CACHE"] = str(cache)
        result = run(["bash", str(ROOT / "tests" / "sync" / "forgejo.sh")], env=env)
        text = result.stdout + result.stderr
        if "BLOCKED: Forgejo" in text:
            self.fail(text)
        self.assertEqual(result.returncode, 0, text)
        self.assertIn("PASS forgejo", text)


if __name__ == "__main__":
    unittest.main()
