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


def fake_host(dir_path, login="acme-member-a"):
    dir_path.mkdir(parents=True, exist_ok=True)
    script = """#!/bin/bash
case "$1" in
  whoami) printf '%s\n' '{"login":"LOGIN"}' ;;
  get-token) printf '%s\n' local-token ;;
  open-pr) printf '%s\n' '{"number":1,"url":"http://example.test/1"}' ;;
  auto-merge) printf '%s\n' '{"ok":true}' ;;
  repo-access) printf '%s\n' '{"access":"ok"}'; exit 0 ;;
  *) exit 1 ;;
esac
"""
    (dir_path / "host.sh").write_text(script.replace("LOGIN", login))
    (dir_path / "host.sh").chmod(0o755)
    (dir_path / "profile.sh").write_text("#!/bin/bash\nprintf '%s\n' acme\n")
    (dir_path / "profile.sh").chmod(0o755)


class SyncFixTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-sync-fix-"))
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.company = self.home / "acme"
        self.company.mkdir()
        write_profile(self.company / "company-profile.md", "team", [])
        (self.company / "people").mkdir()
        (self.company / "people" / "Mia.md").write_text(
            "---\ntype: person\nslug: mia\ngithub: acme-member-a\nemail: mia.member@acme.test\n---\n\n# Mia Member\n"
        )
        cfg = self.home / ".config" / "acme-os"
        cfg.mkdir(parents=True)
        (cfg / "me").write_text("mia\n")
        self.host = self.tmp / "host"
        fake_host(self.host)
        self.env = base_env(self.home, self.company, self.host)
        self.env["OS_PROFILE_SH"] = str(self.host / "profile.sh")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def sync(self, *args, env=None):
        return run(["bash", str(SYNC / "sync.sh"), *args], env=env or self.env, cwd=self.company)

    def seed_origin(self):
        bare = self.tmp / "origin.git"
        run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], env=self.env, check=True)
        run(["git", "init", "-q", "-b", "main", str(self.company)], env=self.env, check=True)
        run(["git", "-C", str(self.company), "remote", "add", "origin", str(bare)], env=self.env, check=True)
        (self.company / "README.md").write_text("seed\n")
        run(["git", "-C", str(self.company), "add", "README.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "seed"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        return bare

    def test_secret_scan_quotes_paths_and_rejects_bad_lists(self):
        odd = self.tmp / "a file *.md"
        odd.write_text("plain\n")
        missing = self.tmp / "no-such.txt"
        result = run(
            ["bash", str(SYNC / "secret-scan.sh"), "--files", "--", str(odd)],
            env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        empty = run(["bash", str(SYNC / "secret-scan.sh"), "--files", "--"], env=self.env)
        self.assertEqual(empty.returncode, 2)
        gone = run(
            ["bash", str(SYNC / "secret-scan.sh"), "--files", "--", str(missing)],
            env=self.env,
        )
        self.assertEqual(gone.returncode, 2)

    def test_symlink_is_a_scan_error_and_pushes_nothing(self):
        self.seed_origin()
        target = self.company / "README.md"
        link = self.company / "link.md"
        link.symlink_to(target)
        result = self.sync("push")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        status = self.sync("status")
        self.assertIn("symlink: add it by hand with a pull request", status.stdout)
        heads = run(["git", "--git-dir", str(self.tmp / "origin.git"), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("sync/mia", heads.stdout)

    def test_staged_and_local_commit_are_checked(self):
        self.seed_origin()
        (self.company / "ok.md").write_text("a shop note\n")
        (self.company / "staged.md").write_text("HOLD-ME staged\n")
        run(["git", "-C", str(self.company), "add", "staged.md"], env=self.env, check=True)
        (self.company / "local.md").write_text("HOLD-ME local commit\n")
        run(["git", "-C", str(self.company), "add", "local.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "local"], env=self.env, check=True)
        result = self.sync("push")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        show = run(
            ["git", "--git-dir", str(self.tmp / "origin.git"), "ls-tree", "-r", "--name-only", "refs/heads/sync/mia"],
            env=self.env,
        )
        self.assertIn("ok.md", show.stdout)
        self.assertNotIn("staged.md", show.stdout)
        self.assertNotIn("local.md", show.stdout)

    def test_engine_must_print_one_json_line(self):
        self.seed_origin()
        engine = self.tmp / "two.sh"
        engine.write_text("#!/bin/bash\nprintf '%s\\n' '{\"decision\":\"commit\",\"reason\":\"ok\",\"message\":\"x\"}' extra\n")
        engine.chmod(0o755)
        (self.company / "note.md").write_text("a note\n")
        env = self.env.copy()
        env["OS_SYNC_ENGINE"] = str(engine)
        result = self.sync("push", env=env)
        self.assertNotEqual(result.returncode, 0)
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertIn("engine check failed", log)
        heads = run(["git", "--git-dir", str(self.tmp / "origin.git"), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("sync/mia", heads.stdout)

    def test_commit_hook_failure_does_not_push(self):
        self.seed_origin()
        hooks = self.company / ".git" / "hooks"
        hooks.mkdir(exist_ok=True)
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/bash\nexit 1\n")
        hook.chmod(0o755)
        (self.company / "note.md").write_text("a note\n")
        result = self.sync("push")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertIn("commit", log)
        heads = run(["git", "--git-dir", str(self.tmp / "origin.git"), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("sync/mia", heads.stdout)

    def test_rename_is_not_cut_and_binary_is_held(self):
        self.seed_origin()
        (self.company / "old.md").write_text("keep me\n")
        run(["git", "-C", str(self.company), "add", "old.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "old"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "mv", "old.md", "new.md"], env=self.env, check=True)
        blob = self.company / "blob.bin"
        blob.write_bytes(b"bin\0data")
        result = self.sync("push")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        show = run(
            ["git", "--git-dir", str(self.tmp / "origin.git"), "ls-tree", "-r", "--name-only", "refs/heads/sync/mia"],
            env=self.env,
        )
        self.assertIn("new.md", show.stdout)
        self.assertNotIn("blob.bin", show.stdout)
        status = self.sync("status")
        self.assertIn("binary file: add it by hand with a pull request", status.stdout)
        other = self.tmp / "incoming"
        run(["git", "clone", "-q", str(self.tmp / "origin.git"), str(other)], env=self.env, check=True)
        (other / "incoming.md").write_text("from the host\n")
        run(["git", "-C", str(other), "add", "incoming.md"], env=self.env, check=True)
        run(["git", "-C", str(other), "commit", "-q", "-m", "incoming"], env=self.env, check=True)
        run(["git", "-C", str(other), "push", "-q", "origin", "main"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "mv", "README.md", "readme-renamed.md"], env=self.env, check=True)
        pulled = self.sync("pull")
        self.assertEqual(pulled.returncode, 0, pulled.stderr + pulled.stdout)
        self.assertTrue((self.company / "incoming.md").exists())
        self.assertTrue((self.company / "readme-renamed.md").exists())
        self.assertFalse((self.company / "README.md").exists())

    def test_stale_lock_and_other_company_jobs(self):
        state = self.home / ".config" / "acme-os" / "state"
        state.mkdir(parents=True)
        lock = state / "lock"
        lock.mkdir()
        (lock / "pid").write_text("999999")
        result = self.sync("pull")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("another sync is running", result.stderr)
        jobs = self.tmp / "jobs"
        env = self.env.copy()
        env["OS_JOBS_DIR"] = str(jobs)
        env["OS_JOBS_PLATFORM"] = "linux"
        made = self.sync("install-jobs", env=env)
        self.assertEqual(made.returncode, 0, made.stderr)
        other = jobs / "osfoundation-bravo-pull.service"
        other.write_text("[Unit]\nDescription=other\n")
        removed = self.sync("uninstall-jobs", env=env)
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertTrue(other.exists())
        self.assertFalse(list(jobs.glob("osfoundation-acme-*")))

    def test_reclone_failure_puts_nested_repo_back(self):
        bare = self.seed_origin()
        area = self.company / "areas" / "shop"
        area.mkdir(parents=True)
        run(["git", "init", "-q", "-b", "main", str(area)], env=self.env, check=True)
        (area / "keep.md").write_text("area\n")
        run(["git", "-C", str(area), "add", "keep.md"], env=self.env, check=True)
        run(["git", "-C", str(area), "commit", "-q", "-m", "area"], env=self.env, check=True)
        orphan = self.tmp / "orphan"
        run(["git", "init", "-q", "-b", "main", str(orphan)], env=self.env, check=True)
        (orphan / "README.md").write_text("rewritten\n")
        run(["git", "-C", str(orphan), "add", "README.md"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "commit", "-q", "-m", "rewritten"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "remote", "add", "origin", str(bare)], env=self.env, check=True)
        run(["git", "-C", str(orphan), "push", "-q", "--force", "origin", "main"], env=self.env, check=True)
        tag = orphan / "tagmsg"
        tag.write_text("rule: github-pat\n")
        run(
            ["git", "-C", str(orphan), "tag", "-a", "os-rewrite-20261024235959", "-F", str(tag)],
            env=self.env,
            check=True,
        )
        run(
            ["git", "-C", str(orphan), "push", "-q", "origin", "refs/tags/os-rewrite-20261024235959"],
            env=self.env,
            check=True,
        )
        (self.company / "keep.md").write_text("local note\n")
        env = self.env.copy()
        env["OS_SYNC_RECLONE_FAIL"] = "nested"
        result = self.sync("pull", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((area / "keep.md").exists())
        self.assertTrue((self.company / "keep.md").exists())
        self.assertTrue((self.company / "company-profile.md").exists())

    def test_reclone_copy_failure_removes_nothing(self):
        self.seed_origin()
        (self.company / "block-copy.md").write_text("keep this\n")
        orphan = self.tmp / "orphan"
        run(["git", "init", "-q", "-b", "main", str(orphan)], env=self.env, check=True)
        (orphan / "README.md").write_text("rewritten\n")
        run(["git", "-C", str(orphan), "add", "README.md"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "commit", "-q", "-m", "rewritten"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "remote", "add", "origin", str(self.tmp / "origin.git")], env=self.env, check=True)
        run(["git", "-C", str(orphan), "push", "-q", "--force", "origin", "main"], env=self.env, check=True)
        tag = orphan / "tagmsg"
        tag.write_text("rule: none\n")
        run(
            ["git", "-C", str(orphan), "tag", "-a", "os-rewrite-20261024235958", "-F", str(tag)],
            env=self.env,
            check=True,
        )
        run(
            ["git", "-C", str(orphan), "push", "-q", "origin", "refs/tags/os-rewrite-20261024235958"],
            env=self.env,
            check=True,
        )
        bindir = self.tmp / "bin"
        bindir.mkdir()
        fake = bindir / "cp"
        fake.write_text(
            "#!/bin/bash\n"
            "for arg in \"$@\"; do\n"
            "  case \"$arg\" in\n"
            "    */block-copy.md) exit 1 ;;\n"
            "  esac\n"
            "done\n"
            "exec /bin/cp \"$@\"\n"
        )
        fake.chmod(0o755)
        env = self.env.copy()
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        result = self.sync("pull", env=env)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertIn("could not copy block-copy.md; nothing removed", log)
        self.assertEqual((self.company / "block-copy.md").read_text(), "keep this\n")
        self.assertTrue((self.company / "company-profile.md").exists())
        self.assertFalse(list(self.company.parent.glob(".sync-reclone-*")))

    def test_reclone_leaves_nested_repo_when_move_back_fails(self):
        self.seed_origin()
        area = self.company / "areas" / "shop"
        area.mkdir(parents=True)
        run(["git", "init", "-q", "-b", "main", str(area)], env=self.env, check=True)
        (area / "keep.md").write_text("uncommitted area note\n")
        run(["git", "-C", str(area), "add", "keep.md"], env=self.env, check=True)
        run(["git", "-C", str(area), "commit", "-q", "-m", "area"], env=self.env, check=True)
        (area / "keep.md").write_text("uncommitted area note\nextra\n")
        orphan = self.tmp / "orphan2"
        run(["git", "init", "-q", "-b", "main", str(orphan)], env=self.env, check=True)
        (orphan / "README.md").write_text("rewritten\n")
        run(["git", "-C", str(orphan), "add", "README.md"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "commit", "-q", "-m", "rewritten"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "remote", "add", "origin", str(self.tmp / "origin.git")], env=self.env, check=True)
        run(["git", "-C", str(orphan), "push", "-q", "--force", "origin", "main"], env=self.env, check=True)
        tag = orphan / "tagmsg"
        tag.write_text("rule: none\n")
        run(
            ["git", "-C", str(orphan), "tag", "-a", "os-rewrite-20261024235957", "-F", str(tag)],
            env=self.env,
            check=True,
        )
        run(
            ["git", "-C", str(orphan), "push", "-q", "origin", "refs/tags/os-rewrite-20261024235957"],
            env=self.env,
            check=True,
        )
        env = self.env.copy()
        env["OS_SYNC_RECLONE_FAIL"] = "after-nested"
        result = self.sync("pull", env=env)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        found = list(self.tmp.rglob("keep.md"))
        self.assertTrue(found, "nested file was deleted")
        self.assertTrue(any("uncommitted area note" in p.read_text() for p in found))
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertIn("left", log)
        status = self.sync("status")
        self.assertIn(".sync-reclone-", status.stdout)
        self.assertTrue(any(p.is_dir() for p in self.company.parent.glob(".sync-reclone-*")))

    def test_dangling_symlink_is_not_pushed_as_a_deletion(self):
        self.seed_origin()
        (self.company / "dangling.md").symlink_to("missing-target")
        result = self.sync("push")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        status = self.sync("status")
        self.assertIn("symlink: add it by hand with a pull request", status.stdout)
        heads = run(
            ["git", "--git-dir", str(self.tmp / "origin.git"), "ls-remote", "--heads"],
            env=self.env,
        )
        self.assertNotIn("sync/mia", heads.stdout)


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


class ProposeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-sync-propose-"))
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.company = self.home / "acme"
        self.company.mkdir()
        write_profile(self.company / "company-profile.md", "team", [])
        (self.company / "people").mkdir()
        (self.company / "people" / "Mia.md").write_text(
            "---\ntype: person\nslug: mia\ngithub: acme-member-a\nemail: mia.member@acme.test\n---\n\n# Mia Member\n"
        )
        (self.company / ".gitignore").write_text("areas/\nusers/\n")
        cfg = self.home / ".config" / "acme-os"
        cfg.mkdir(parents=True)
        (cfg / "me").write_text("mia\n")
        self.host = self.tmp / "host"
        fake_host(self.host)
        self.env = base_env(self.home, self.company, self.host)
        self.env["OS_PROFILE_SH"] = str(self.host / "profile.sh")
        self.company_bare = self.tmp / "company.git"
        self.area_bare = self.tmp / "area.git"
        run(["git", "init", "-q", "--bare", "-b", "main", str(self.company_bare)], env=self.env, check=True)
        run(["git", "init", "-q", "--bare", "-b", "main", str(self.area_bare)], env=self.env, check=True)
        run(["git", "init", "-q", "-b", "main", str(self.company)], env=self.env, check=True)
        run(["git", "-C", str(self.company), "remote", "add", "origin", str(self.company_bare)], env=self.env, check=True)
        (self.company / "AGENTS.md").write_text("# rules\n")
        (self.company / "README.md").write_text("seed\n")
        run(["git", "-C", str(self.company), "add", "AGENTS.md", "README.md", ".gitignore", "company-profile.md", "people"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "seed"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        self.area = self.company / "areas" / "shop"
        self.area.mkdir(parents=True)
        run(["git", "init", "-q", "-b", "main", str(self.area)], env=self.env, check=True)
        run(["git", "-C", str(self.area), "remote", "add", "origin", str(self.area_bare)], env=self.env, check=True)
        (self.area / "AGENTS.md").write_text("# area rules\n")
        run(["git", "-C", str(self.area), "add", "AGENTS.md"], env=self.env, check=True)
        run(["git", "-C", str(self.area), "commit", "-q", "-m", "seed"], env=self.env, check=True)
        run(["git", "-C", str(self.area), "push", "-q", "origin", "main"], env=self.env, check=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def propose(self, *args):
        return run(["bash", str(SYNC / "sync.sh"), "propose", *args], env=self.env, cwd=self.company)

    def branch_file(self, bare, path):
        return run(
            ["git", "--git-dir", str(bare), "show", f"refs/heads/rules/mia/topic:{path}"],
            env=self.env,
        )

    def test_company_path(self):
        (self.company / "AGENTS.md").write_text("# changed company rules\n")
        result = self.propose("topic", "AGENTS.md")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(result.stdout.strip(), "1")
        shown = self.branch_file(self.company_bare, "AGENTS.md")
        self.assertIn("changed company rules", shown.stdout)
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertIn("propose ok", log)

    def test_area_path(self):
        (self.area / "AGENTS.md").write_text("# changed area rules\n")
        result = self.propose("topic", "areas/shop/AGENTS.md")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        shown = self.branch_file(self.area_bare, "AGENTS.md")
        self.assertIn("changed area rules", shown.stdout)
        company = self.branch_file(self.company_bare, "AGENTS.md")
        self.assertNotEqual(company.returncode, 0)

    def test_company_and_area_open_two_pull_requests(self):
        (self.company / "AGENTS.md").write_text("# company change\n")
        (self.area / "skills").mkdir()
        (self.area / "skills" / "SKILL.md").write_text("# area skill\n")
        result = self.propose("topic", "AGENTS.md", "areas/shop/skills/SKILL.md")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        numbers = [line for line in result.stdout.splitlines() if line.strip()]
        self.assertEqual(len(numbers), 2)
        self.assertIn("company change", self.branch_file(self.company_bare, "AGENTS.md").stdout)
        self.assertIn("area skill", self.branch_file(self.area_bare, "skills/SKILL.md").stdout)

    def test_users_path_is_refused(self):
        user = self.company / "users" / "mia"
        user.mkdir(parents=True)
        (user / "note.md").write_text("draft\n")
        result = self.propose("topic", "users/mia/note.md")
        self.assertEqual(result.returncode, 1)
        self.assertIn("users paths stay in the workspace", result.stderr)
        heads = run(["git", "--git-dir", str(self.company_bare), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("rules/mia", heads.stdout)

    def test_nothing_staged(self):
        result = self.propose("topic", "AGENTS.md")
        self.assertEqual(result.returncode, 1)
        self.assertIn("nothing to propose: AGENTS.md", result.stderr)
        heads = run(["git", "--git-dir", str(self.company_bare), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("rules/mia", heads.stdout)

    def test_bad_paths_are_refused(self):
        outside = self.tmp / "outside.md"
        outside.write_text("outside\n")
        for path in ("areas/x/../../outside.md", "/etc/hosts", "a/../b", "bad\nname.md"):
            result = self.propose("topic", path)
            self.assertEqual(result.returncode, 1, path)
            self.assertIn("propose refused: bad path", result.stderr)
        heads = run(["git", "--git-dir", str(self.company_bare), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("rules/mia", heads.stdout)

    def test_symlink_is_refused(self):
        link = self.company / "link.md"
        link.symlink_to(self.company / "AGENTS.md")
        result = self.propose("topic", "link.md")
        self.assertEqual(result.returncode, 1)
        self.assertIn("propose refused: symlink: link.md", result.stderr)
        nested = self.company / "realnest"
        nested.mkdir()
        (nested / "file.md").write_text("via link\n")
        (self.company / "nest").symlink_to(nested)
        result = self.propose("topic", "nest/file.md")
        self.assertEqual(result.returncode, 1)
        self.assertIn("propose refused: symlink: nest/file.md", result.stderr)
        heads = run(["git", "--git-dir", str(self.company_bare), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("rules/mia", heads.stdout)

    def test_scan_stops_before_any_push(self):
        (self.company / "AGENTS.md").write_text("# company change\n")
        secret = "gh" + "p_" + ("ab12" * 9)
        (self.area / "AGENTS.md").write_text(f"token = {secret}\n")
        result = self.propose("topic", "AGENTS.md", "areas/shop/AGENTS.md")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("secret scan hit", result.stderr)
        heads = run(["git", "--git-dir", str(self.company_bare), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("rules/mia", heads.stdout)

    def test_fetch_is_checked_before_the_first_push(self):
        (self.company / "AGENTS.md").write_text("# company change\n")
        (self.area / "AGENTS.md").write_text("# area change\n")
        run(
            ["git", "-C", str(self.area), "remote", "set-url", "origin", "http://127.0.0.1:9/area.git"],
            env=self.env,
            check=True,
        )
        result = self.propose("topic", "AGENTS.md", "areas/shop/AGENTS.md")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("propose fail area: fetch", result.stderr)
        heads = run(["git", "--git-dir", str(self.company_bare), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("rules/mia", heads.stdout)

    def test_later_failure_lists_opened_pull_requests(self):
        host = self.tmp / "host-fail"
        host.mkdir()
        (host / "host.sh").write_text(
            "#!/bin/bash\n"
            "case \"$1\" in\n"
            "  whoami) printf '%s\\n' '{\"login\":\"acme-member-a\"}' ;;\n"
            "  get-token) printf '%s\\n' local-token ;;\n"
            "  open-pr)\n"
            "    n=$(wc -l < \"$COUNT\" | tr -d ' ')\n"
            "    printf 'x\\n' >> \"$COUNT\"\n"
            "    if [ \"$n\" != \"0\" ]; then exit 3; fi\n"
            "    printf '%s\\n' '{\"number\":1,\"url\":\"http://example.test/1\"}'\n"
            "    ;;\n"
            "  auto-merge) printf '%s\\n' '{\"ok\":true}' ;;\n"
            "  *) exit 1 ;;\n"
            "esac\n"
        )
        (host / "host.sh").chmod(0o755)
        (host / "profile.sh").write_text("#!/bin/bash\nprintf '%s\\n' acme\n")
        (host / "profile.sh").chmod(0o755)
        count = self.tmp / "count"
        count.write_text("")
        env = self.env.copy()
        env["OS_HOST_SH"] = str(host / "host.sh")
        env["OS_PROFILE_SH"] = str(host / "profile.sh")
        env["COUNT"] = str(count)
        (self.company / "AGENTS.md").write_text("# company change\n")
        (self.area / "AGENTS.md").write_text("# area change\n")
        result = run(
            ["bash", str(SYNC / "sync.sh"), "propose", "topic", "AGENTS.md", "areas/shop/AGENTS.md"],
            env=env,
            cwd=self.company,
        )
        self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("propose fail area: open-pr", result.stderr)
        self.assertIn("opened: company 1", result.stderr)

    def test_copy_failure_names_the_step(self):
        bindir = self.tmp / "bin"
        bindir.mkdir()
        fake = bindir / "cp"
        fake.write_text(
            "#!/bin/bash\n"
            "for arg in \"$@\"; do\n"
            "  case \"$arg\" in\n"
            "    */AGENTS.md) exit 1 ;;\n"
            "  esac\n"
            "done\n"
            "exec /bin/cp \"$@\"\n"
        )
        fake.chmod(0o755)
        env = self.env.copy()
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        (self.company / "AGENTS.md").write_text("# changed\n")
        result = run(
            ["bash", str(SYNC / "sync.sh"), "propose", "topic", "AGENTS.md"],
            env=env,
            cwd=self.company,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("propose fail company: copy AGENTS.md", result.stderr)
        self.assertNotIn("nothing to propose", result.stderr)

    def test_symlink_on_main_is_not_written_through(self):
        outside = self.tmp / "outside"
        outside.mkdir()
        skills = self.company / "skills"
        skills.mkdir()
        (skills / "x").symlink_to(outside)
        run(["git", "-C", str(self.company), "add", "skills"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "link dir"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        (skills / "x").unlink()
        (skills / "x").mkdir()
        (skills / "x" / "f.md").write_text("must not land outside\n")
        result = self.propose("t", "skills/x/f.md")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertIn("propose refused: symlink on main: skills/x/f.md", result.stderr)
        self.assertEqual(list(outside.iterdir()), [])
        target = outside / "target.md"
        target.write_text("kept\n")
        (self.company / "link.md").symlink_to(target)
        run(["git", "-C", str(self.company), "add", "link.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "file link"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        (self.company / "link.md").unlink()
        (self.company / "link.md").write_text("overwrite\n")
        result = self.propose("t", "link.md")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertIn("propose refused: symlink on main: link.md", result.stderr)
        self.assertEqual(target.read_text(), "kept\n")

    def test_gitdir_file_is_refused(self):
        git_dir = self.area / ".git"
        shutil.rmtree(git_dir)
        git_dir.write_text("gitdir: /tmp/not-this-repo\n")
        (self.area / "AGENTS.md").write_text("# changed area rules\n")
        result = self.propose("topic", "areas/shop/AGENTS.md")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("propose fail shop: repo", result.stderr)
        heads = run(["git", "--git-dir", str(self.company_bare), "ls-remote", "--heads"], env=self.env)
        self.assertNotIn("rules/mia", heads.stdout)


if __name__ == "__main__":
    unittest.main()
