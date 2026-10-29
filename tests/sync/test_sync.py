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
        env["OS_JOBS_LOAD"] = "0"
        made = self.sync("install-jobs", env=env)
        self.assertEqual(made.returncode, 0, made.stderr)
        xml = "\n".join(p.read_text() for p in windows.glob("*.xml"))
        self.assertNotIn("Not tested", xml)
        self.assertIn("StartWhenAvailable>true", xml)
        self.assertIn("ExecutionTimeLimit>PT1H", xml)
        self.assertIn("DisallowStartIfOnBatteries>false", xml)
        self.assertIn("StopIfGoingOnBatteries>false", xml)
        self.assertIn("MultipleInstancesPolicy>IgnoreNew", xml)
        self.assertIn("InteractiveToken", xml)
        self.assertIn("LeastPrivilege", xml)

    def test_render_escapes_ampersand_in_the_root_path(self):
        root = self.tmp / "acme & co"
        root.mkdir()
        write_profile(root / "company-profile.md", "team", [])
        jobs = self.tmp / "amp-jobs"
        env = self.env.copy()
        env["OS_COMPANY_ROOT"] = str(root)
        env["OS_PROFILE"] = str(root / "company-profile.md")
        env["OS_JOBS_DIR"] = str(jobs)
        env["OS_JOBS_LOAD"] = "0"
        env["OS_JOBS_PLATFORM"] = "macos"
        made = self.sync("install-jobs", env=env)
        self.assertEqual(made.returncode, 0, made.stderr + made.stdout)
        plist = "\n".join(p.read_text() for p in jobs.glob("*.plist"))
        self.assertIn("acme &amp; co", plist)
        self.assertNotIn("acme & co", plist)
        windows = self.tmp / "amp-win"
        env["OS_JOBS_DIR"] = str(windows)
        env["OS_JOBS_PLATFORM"] = "windows"
        made = self.sync("install-jobs", env=env)
        self.assertEqual(made.returncode, 0, made.stderr + made.stdout)
        xml = "\n".join(p.read_text() for p in windows.glob("*.xml"))
        self.assertIn("acme &amp; co", xml)
        self.assertNotIn("acme & co", xml)

    def test_skill_copy_fold_keeps_local_edits(self):
        script = ROOT / "tests" / "sync" / "test_links_copy.sh"
        result = run(["bash", str(script)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS links-copy", result.stdout)

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

    def test_auto_merge_failure_is_held(self):
        self.seed_origin()
        host = self.host / "host.sh"
        text = host.read_text()
        start = text.index("  auto-merge)")
        end = text.index(";;", start) + 2
        host.write_text(text[:start] + "  auto-merge) echo 'Auto merge is not allowed' >&2; exit 3 ;;" + text[end:])
        (self.company / "note.md").write_text("a note\n")
        result = self.sync("push")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        status = self.sync("status")
        self.assertIn("last error: auto-merge is off on", status.stdout)
        self.assertIn("pull request 1 is open but will not merge by itself", status.stdout)

    def git(self, *args, check=True):
        return run(["git", "-C", str(self.company), *args], env=self.env, check=check)

    def sync_log(self):
        return (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()

    def tree(self, ref):
        return run(
            ["git", "--git-dir", str(self.tmp / "origin.git"), "ls-tree", "-r", "--name-only", ref],
            env=self.env,
        ).stdout.splitlines()

    def test_logs_are_never_held_as_workspace_only(self):
        # B13: rule 5 is a path rule. A log is Auto tier, even when the model says otherwise.
        self.seed_origin()
        logs = self.company / "memory" / "logs"
        logs.mkdir(parents=True)
        (logs / "2026-10-28-mia.md").write_text("WORKSPACE-ME wrote the newsletter\n")
        (logs / "2026-10-27-mia.md").write_text("PERSONAL-FACT\n")
        (self.company / "habits.md").write_text("WORKSPACE-ME how I like to work\n")
        result = self.sync("push")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        tree = self.tree("refs/heads/sync/mia")
        self.assertIn("memory/logs/2026-10-28-mia.md", tree)
        self.assertNotIn("habits.md", tree)
        self.assertNotIn("memory/logs/2026-10-27-mia.md", tree)
        status = self.sync("status").stdout
        self.assertIn("habits.md: belongs in the workspace", status)
        self.assertIn("2026-10-27-mia.md: personal-life fact", status)
        self.assertIn("push path-rule root memory/logs/2026-10-28-mia.md", self.sync_log())

    def test_a_file_waiting_on_its_own_pull_request_is_held(self):
        # Round 3 (42): remove-teammate leaves the offboard change in the folder so the
        # person sees it. Its pull request stays the only path to main.
        self.seed_origin()
        page = self.company / "people" / "Mia.md"
        self.git("add", "people/Mia.md")
        self.git("commit", "-q", "-m", "page")
        self.git("push", "-q", "origin", "main")
        self.git("checkout", "-q", "-b", "rules/ada/offboard-mia")
        page.write_text(page.read_text().replace("---\n\n#", "left: 2026-10-28\n---\n\n#"))
        self.git("commit", "-q", "-am", "Offboard: mia")
        self.git("push", "-q", "origin", "rules/ada/offboard-mia")
        self.git("checkout", "-q", "main")
        self.git("show", "rules/ada/offboard-mia:people/Mia.md")
        page.write_text(self.git("show", "rules/ada/offboard-mia:people/Mia.md").stdout)
        (self.company / "note.md").write_text("a shop note\n")
        result = self.sync("push")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        tree = self.tree("refs/heads/sync/mia")
        self.assertIn("note.md", tree)
        diff = run(
            ["git", "--git-dir", str(self.tmp / "origin.git"), "diff", "--name-only", "main", "sync/mia"],
            env=self.env,
        ).stdout.splitlines()
        self.assertNotIn("people/Mia.md", diff)
        status = self.sync("status").stdout
        self.assertIn("people/Mia.md: waits for its own pull request (rules/ada/offboard-mia)", status)
        self.assertIn("left: 2026-10-28", page.read_text())

        # Round 4 (47): the pull request is closed and the host deletes its branch. The
        # local origin/rules/* ref is stale; push prunes it, says so, and stops holding.
        run(["git", "--git-dir", str(self.tmp / "origin.git"), "branch", "-D", "rules/ada/offboard-mia"], env=self.env)
        self.assertEqual(self.git("rev-parse", "-q", "--verify", "origin/rules/ada/offboard-mia", check=False).returncode, 0)
        result = self.sync("push")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(
            "people/Mia.md: its own pull request (rules/ada/offboard-mia) was closed and its branch is gone, "
            "so push no longer waits for it",
            result.stderr,
        )
        self.assertNotEqual(self.git("rev-parse", "-q", "--verify", "origin/rules/ada/offboard-mia", check=False).returncode, 0)
        diff = run(
            ["git", "--git-dir", str(self.tmp / "origin.git"), "diff", "--name-only", "main", "sync/mia"],
            env=self.env,
        ).stdout.splitlines()
        self.assertIn("people/Mia.md", diff)
        self.assertNotIn("waits for its own pull request", self.sync("status").stdout)

    def test_pull_prunes_a_branch_the_host_deleted(self):
        # Round 4 (47): pull fetches with --prune, so a stale origin/rules/* ref goes.
        self.seed_origin()
        self.git("update-ref", "refs/remotes/origin/rules/ada/offboard-mia", "HEAD")
        result = self.sync("pull")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotEqual(
            self.git("rev-parse", "-q", "--verify", "origin/rules/ada/offboard-mia", check=False).returncode, 0
        )

    def join_ready(self):
        # A joining teammate's clone: the people page on main, an own workspace repo.
        bare = self.seed_origin()
        (self.company / ".gitignore").write_text("users/\n")
        self.git("add", "people/Mia.md", ".gitignore")
        self.git("commit", "-q", "-m", "people")
        self.git("push", "-q", "origin", "main")
        ws = self.company / "users" / "mia"
        ws.mkdir(parents=True)
        run(["git", "-C", str(ws), "init", "-q", "-b", "main"], env=self.env, check=True)
        answers = self.tmp / "join-answers"
        answers.write_text(f"root={self.company}\nme=mia\nareas=\n")
        return bare, answers

    def join(self, answers):
        env = self.env.copy()
        env["OS_JOBS_DIR"] = str(self.tmp / "jobs")
        return run(["bash", str(ROOT / "template" / "skills" / "add-teammate" / "join.sh"), "--answers", str(answers)],
                   env=env, cwd=self.company)

    def host_page(self, bare, ref):
        return run(["git", "--git-dir", str(bare), "show", f"{ref}:people/Mia.md"], env=self.env).stdout

    def test_join_terms_survive_the_next_push(self):
        # logsfix (54, B25): push rebuilds sync/<me> from main plus local changes. The
        # join's terms must be a local change too, or the next push drops them.
        bare, answers = self.join_ready()
        result = self.join(answers)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("terms: proposed", result.stdout)
        self.assertRegex(self.host_page(bare, "sync/mia"), r"(?m)^terms_accepted: \"?\d{4}-")
        self.assertRegex((self.company / "people" / "Mia.md").read_text(), r"(?m)^terms_accepted: \"?\d{4}-")
        self.assertEqual(self.git("symbolic-ref", "--short", "HEAD").stdout.strip(), "main")
        (self.company / "note.md").write_text("a shop note\n")
        result = self.sync("push")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        page = self.host_page(bare, "sync/mia")
        self.assertRegex(page, r"(?m)^terms_accepted: \"?\d{4}-", "the push dropped the terms")
        self.assertIn("note.md", self.tree("refs/heads/sync/mia"))
        # The pull request merges: main has the terms. The local page is clean again.
        run(["git", "--git-dir", str(bare), "update-ref", "refs/heads/main", "refs/heads/sync/mia"], env=self.env, check=True)
        self.assertEqual(self.sync("pull", "--full").returncode, 0)
        self.assertRegex(self.host_page(bare, "main"), r"(?m)^terms_accepted: \"?\d{4}-")
        self.assertEqual(self.git("status", "--porcelain", "people").stdout, "")

    def test_rejoin_after_a_push_never_checks_out_over_the_folder(self):
        # logsfix (55, B29): the host's sync/<me> holds a pushed note, and the same note is
        # untracked here on main. A join that must propose the terms again still works.
        bare, answers = self.join_ready()
        (self.company / "note.md").write_text("a shop note\n")
        self.assertEqual(self.sync("push").returncode, 0)
        self.assertIn("note.md", self.tree("refs/heads/sync/mia"))
        self.assertNotRegex(self.host_page(bare, "sync/mia"), r"(?m)^terms_accepted: \"?\d")
        result = self.join(answers)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("would be overwritten", result.stderr)
        self.assertIn("terms: proposed", result.stdout)
        self.assertEqual(self.git("symbolic-ref", "--short", "HEAD").stdout.strip(), "main")
        self.assertEqual((self.company / "note.md").read_text(), "a shop note\n")
        tree = self.tree("refs/heads/sync/mia")
        self.assertIn("note.md", tree)
        self.assertRegex(self.host_page(bare, "sync/mia"), r"(?m)^terms_accepted: \"?\d{4}-")

    def test_a_push_clears_only_a_push_error(self):
        # Round 3 (41): a good push never clears an error a pull left in another run.
        script = (
            'source "$1/lib.sh"; source "$1/push.sh"; SYNC_HELD="$2"; '
            'sync_mktemp() { mktemp; }; sync_push_clear_error; jq -r .last_error "$2"'
        )
        held = self.tmp / "held.json"
        pull_err = "pull failed for root: could not reach the host. Check the internet connection and sign-in, then run it again."
        for before, after in [
            (pull_err, pull_err),
            ("auto-merge is off on acme-os: pull request 1 is open but will not merge by itself", ""),
            ("", ""),
        ]:
            held.write_text(json.dumps({"files": [], "last_error": before}))
            out = run(["bash", "-c", script, "x", str(SYNC), str(held)], env=self.env)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertEqual(out.stdout.strip(), after)

    def test_area_drafts_and_logs_are_area_work(self):
        script = 'source "$1/lib.sh"; source "$1/push.sh"; sync_not_workspace_only "$2" "$3"'

        def exempt(kind, path):
            return run(["bash", "-c", script, "x", str(SYNC), kind, path], env=self.env).returncode == 0

        self.assertTrue(exempt("area", "drafts/spring-post.md"))
        self.assertTrue(exempt("area", "memory/logs/2026-10-28-mia.md"))
        self.assertTrue(exempt("root", "memory/logs/2026-10-28-mia.md"))
        self.assertFalse(exempt("root", "drafts/spring-post.md"))
        self.assertFalse(exempt("area", "notes/habits.md"))
        self.assertFalse(exempt("workspace", "memory/logs/2026-10-28-mia.md"))

    def test_pull_leaves_own_sync_branch_once_pushed(self):
        # B14: join left the clone on sync/mia. Push rebuilt that branch on the host.
        bare = self.seed_origin()
        self.git("checkout", "-q", "-b", "sync/mia")
        (self.company / "README.md").write_text("seed\nterms accepted\n")
        self.git("commit", "-q", "-am", "Join: accept terms")
        self.git("push", "-q", "origin", "sync/mia")
        other = self.tmp / "other"
        run(["git", "clone", "-q", str(bare), str(other)], env=self.env, check=True)
        (other / "README.md").write_text("seed\nterms accepted\n")
        run(["git", "-C", str(other), "commit", "-q", "-am", "rebuilt"], env=self.env, check=True)
        run(["git", "-C", str(other), "push", "-q", "-f", "origin", "HEAD:sync/mia"], env=self.env, check=True)
        run(["git", "-C", str(other), "reset", "-q", "--hard", "origin/main"], env=self.env, check=True)
        (other / "news.md").write_text("from main\n")
        run(["git", "-C", str(other), "add", "news.md"], env=self.env, check=True)
        run(["git", "-C", str(other), "commit", "-q", "-m", "news"], env=self.env, check=True)
        run(["git", "-C", str(other), "push", "-q", "origin", "HEAD:main"], env=self.env, check=True)
        (self.company / "scratch.md").write_text("not committed yet\n")
        result = self.sync("pull")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("symbolic-ref", "--short", "HEAD").stdout.strip(), "main")
        self.assertTrue((self.company / "news.md").exists())
        self.assertEqual((self.company / "scratch.md").read_text(), "not committed yet\n")
        log = self.sync_log()
        self.assertIn("back on main from sync/mia", log)
        self.assertNotIn("not fast-forward", log)

    def test_pull_keeps_unpushed_work_on_sync_branch(self):
        self.seed_origin()
        self.git("checkout", "-q", "-b", "sync/mia")
        (self.company / "draft.md").write_text("only here\n")
        self.git("add", "draft.md")
        self.git("commit", "-q", "-m", "local only")
        self.sync("pull")
        self.assertEqual(self.git("symbolic-ref", "--short", "HEAD").stdout.strip(), "sync/mia")
        self.assertEqual((self.company / "draft.md").read_text(), "only here\n")
        self.assertIn("on sync/mia: draft.md is not pushed yet", self.sync_log())

    def test_failed_pull_says_why_and_status_shows_it(self):
        # B19: a pull that cannot fetch was silent. Now it is one plain line and last_error.
        bare = self.seed_origin()
        moved = self.tmp / "away.git"
        bare.rename(moved)
        result = self.sync("pull", "--full")
        self.assertNotEqual(result.returncode, 0)
        lines = [l for l in result.stderr.splitlines() if l.startswith("pull failed for ")]
        self.assertEqual(
            lines,
            ["pull failed for root: could not reach the host. Check the internet connection and sign-in, then run it again."],
            result.stderr,
        )
        status = self.sync("status").stdout
        self.assertIn("last error: pull failed for root: could not reach the host", status)
        self.assertIn("pull fail root could not reach origin", self.sync_log())
        # The next clean pull clears it.
        moved.rename(bare)
        result = self.sync("pull", "--full")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("last error: none", self.sync("status").stdout)

    def test_clean_pull_keeps_a_push_error(self):
        self.seed_origin()
        script = 'source "$1/lib.sh"; sync_bind; sync_held_error "auto-merge is off on acme-os"'
        run(["bash", "-c", script, "x", str(SYNC)], env=self.env, cwd=self.company, check=True)
        self.assertEqual(self.sync("pull", "--full").returncode, 0)
        self.assertIn("last error: auto-merge is off on acme-os", self.sync("status").stdout)

    def v0_clone_after_upgrade(self, archive=False):
        # v0: logs on branch logs, checked out at memory/logs/, ignored by main.
        # archive=True: the upgrade layout since logsfix (51): memory/logs/archive/ plus
        # the logs-archive tag on the host.
        bare = self.seed_origin()
        (self.company / ".gitignore").write_text("/memory/logs/\n")
        self.git("add", ".gitignore")
        self.git("commit", "-q", "-m", "v0 ignore")
        self.git("push", "-q", "origin", "main")
        self.git("worktree", "add", "-q", "--detach", "memory/logs")
        logs = self.company / "memory" / "logs"
        run(["git", "-C", str(logs), "checkout", "-q", "--orphan", "logs"], env=self.env, check=True)
        run(["git", "-C", str(logs), "rm", "-rfq", "."], env=self.env, check=True)
        (logs / "2026-10-01-mia.md").write_text("day one\n")
        run(["git", "-C", str(logs), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(logs), "commit", "-q", "-m", "Logs: day one"], env=self.env, check=True)
        run(["git", "-C", str(logs), "push", "-q", "origin", "logs"], env=self.env, check=True)
        # The upgrade ran elsewhere: main now tracks memory/logs/ and no longer ignores it.
        other = self.tmp / "upgrader"
        run(["git", "clone", "-q", str(bare), str(other)], env=self.env, check=True)
        (other / ".gitignore").write_text("")
        moved = other / "memory" / "logs" / ("archive" if archive else "")
        moved.mkdir(parents=True)
        (moved / "2026-10-01-mia.md").write_text("day one\n")
        run(["git", "-C", str(other), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(other), "commit", "-q", "-m", "Upgrade to v1"], env=self.env, check=True)
        run(["git", "-C", str(other), "push", "-q", "origin", "main"], env=self.env, check=True)
        if archive:
            run(["git", "-C", str(other), "tag", "-a", "logs-archive-2026-10-01", "origin/logs", "-m", "snapshot"],
                env=self.env, check=True)
            run(["git", "-C", str(other), "push", "-q", "origin", "logs-archive-2026-10-01"], env=self.env, check=True)
        # On this clone, after the upgrade: a log commit not pushed yet, an edit, a new file.
        (logs / "2026-10-02-mia.md").write_text("day two, committed only here\n")
        run(["git", "-C", str(logs), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(logs), "commit", "-q", "-m", "Logs: day two"], env=self.env, check=True)
        (logs / "2026-10-01-mia.md").write_text("day one\nand a later line\n")
        (logs / "2026-10-03-mia.md").write_text("day three, untracked\n")
        return bare, logs

    def test_pull_moves_a_v0_logs_worktree_without_losing_a_log(self):
        # Round 3 (30): the upgrade removed the worktree only where it ran.
        bare, logs = self.v0_clone_after_upgrade()
        result = self.sync("pull", "--full")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((logs / ".git").exists())
        self.assertNotIn(str(logs), self.git("worktree", "list").stdout)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout, self.git("rev-parse", "origin/main").stdout)
        self.assertEqual((logs / "2026-10-01-mia.md").read_text(), "day one\nand a later line\n")
        self.assertEqual((logs / "2026-10-02-mia.md").read_text(), "day two, committed only here\n")
        self.assertEqual((logs / "2026-10-03-mia.md").read_text(), "day three, untracked\n")
        # The unpushed log commit went to the host first.
        log = run(["git", "--git-dir", str(bare), "log", "--format=%s", "logs"], env=self.env).stdout
        self.assertIn("Logs: day two", log)
        self.assertIn("pull v0-logs root worktree removed, 3 files kept as local changes", self.sync_log())
        # The files are local changes now, so the next push sends them.
        status = self.git("status", "--porcelain").stdout
        self.assertIn("memory/logs/2026-10-01-mia.md", status)
        self.assertIn("memory/logs/2026-10-03-mia.md", status)

    def logs_clone(self, name):
        # Another v0 teammate: a clone of the logs branch only.
        path = self.tmp / name
        run(["git", "clone", "-q", "--branch", "logs", str(self.tmp / "origin.git"), str(path)], env=self.env, check=True)
        return path

    def test_v0_logs_merge_when_the_host_logs_moved(self):
        # logsfix (52, 53): someone else pushed to logs after the upgrade. The park merges
        # the host's logs before its push. The catch-up brings the other log into
        # memory/logs/archive/ as a local change and says so; a second pull does not repeat it.
        bare, logs = self.v0_clone_after_upgrade(archive=True)
        noa = self.logs_clone("noa")
        (noa / "2026-10-05-noa.md").write_text("noa, after the upgrade\n")
        run(["git", "-C", str(noa), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(noa), "commit", "-q", "-m", "Logs: noa"], env=self.env, check=True)
        run(["git", "-C", str(noa), "push", "-q", "origin", "logs"], env=self.env, check=True)
        result = self.sync("pull", "--full")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((logs / ".git").exists())
        host = run(["git", "--git-dir", str(bare), "log", "--format=%s", "logs"], env=self.env).stdout
        self.assertIn("Logs: day two", host)
        self.assertIn("Logs: noa", host)
        arc = logs / "archive"
        self.assertEqual((arc / "2026-10-01-mia.md").read_text(), "day one\nand a later line\n")
        self.assertEqual((arc / "2026-10-02-mia.md").read_text(), "day two, committed only here\n")
        self.assertEqual((arc / "2026-10-03-mia.md").read_text(), "day three, untracked\n")
        self.assertEqual((arc / "2026-10-05-noa.md").read_text(), "noa, after the upgrade\n")
        self.assertEqual(sorted(p.name for p in logs.iterdir()), ["archive"])
        self.assertIn(
            "logs: 1 files written to the old logs branch after the upgrade are now in memory/logs/archive/ in root. "
            "The next push sends them.",
            result.stdout,
        )
        self.assertIn("pull logs-catch-up root 1 files", self.sync_log())
        again = self.sync("pull", "--full")
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertNotIn("logs: ", again.stdout)

    def test_catch_up_keeps_a_change_made_here(self):
        # logsfix (53): an archived log edited here (not pushed) is not replaced by the
        # host's logs branch copy.
        bare, logs = self.v0_clone_after_upgrade(archive=True)
        self.assertEqual(self.sync("pull", "--full").returncode, 0)
        mine = logs / "archive" / "2026-10-01-mia.md"
        mine.write_text("my fix, here only\n")
        noa = self.logs_clone("noa")
        (noa / "2026-10-01-mia.md").write_text("changed on the old branch\n")
        run(["git", "-C", str(noa), "commit", "-q", "-am", "Logs: late edit"], env=self.env, check=True)
        run(["git", "-C", str(noa), "push", "-q", "origin", "logs"], env=self.env, check=True)
        result = self.sync("pull", "--full")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(mine.read_text(), "my fix, here only\n")

    def test_v0_logs_conflict_says_what_to_do(self):
        # logsfix (52): both sides changed the same log. Nothing is removed, and the line
        # gives the steps. Following them, the next pull moves the folder.
        bare, logs = self.v0_clone_after_upgrade()
        run(["git", "-C", str(logs), "commit", "-q", "-am", "Logs: day one, more"], env=self.env, check=True)
        noa = self.logs_clone("noa")
        (noa / "2026-10-01-mia.md").write_text("day one\nnoa added this\n")
        run(["git", "-C", str(noa), "commit", "-q", "-am", "Logs: noa on day one"], env=self.env, check=True)
        run(["git", "-C", str(noa), "push", "-q", "origin", "logs"], env=self.env, check=True)
        result = self.sync("pull", "--full")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(
            "the old logs folder memory/logs could not be moved: the logs branch here and on the host both changed "
            "2026-10-01-mia.md. Nothing was removed. In memory/logs run: git pull --no-rebase origin logs, keep both "
            'texts in each of those files, git commit -am "Logs: merge", git push origin logs. Then run this again.',
            result.stderr,
        )
        self.assertNotIn("Ask the admin", result.stderr)
        self.assertTrue((logs / ".git").exists())
        self.assertEqual((logs / "2026-10-03-mia.md").read_text(), "day three, untracked\n")
        self.assertEqual(run(["git", "-C", str(logs), "status", "--porcelain", "--untracked-files=no"], env=self.env).stdout, "")
        # The steps in the line work.
        run(["git", "-C", str(logs), "pull", "-q", "--no-rebase", "origin", "logs"], env=self.env)
        (logs / "2026-10-01-mia.md").write_text("day one\nand a later line\nnoa added this\n")
        run(["git", "-C", str(logs), "commit", "-q", "-am", "Logs: merge"], env=self.env, check=True)
        run(["git", "-C", str(logs), "push", "-q", "origin", "logs"], env=self.env, check=True)
        result = self.sync("pull", "--full")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((logs / "2026-10-01-mia.md").read_text(), "day one\nand a later line\nnoa added this\n")

    def test_v0_logs_worktree_stays_when_the_push_fails(self):
        bare, logs = self.v0_clone_after_upgrade()
        hook = bare / "hooks" / "pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        result = self.sync("pull", "--full")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pull failed for root: the old logs folder memory/logs could not be moved", result.stderr)
        self.assertTrue((logs / ".git").exists())
        self.assertEqual((logs / "2026-10-03-mia.md").read_text(), "day three, untracked\n")

    def test_v0_logs_put_back_failure_keeps_the_copy(self):
        # Round 4 (45): a copy back fails after the worktree is gone (a file lock on
        # Windows). The saved folder stays, one plain line names it, and no success is
        # logged. Run with bash 3.2 when the system has it.
        bare, logs = self.v0_clone_after_upgrade()
        bindir = self.tmp / "bin"
        bindir.mkdir()
        fake = bindir / "cp"
        fake.write_text(
            "#!/bin/bash\n"
            "case \" $* \" in\n"
            "  *' -R'*) ;;\n"
            "  *memory/logs/2026-10-03-mia.md*) exit 1 ;;\n"
            "esac\n"
            "exec /bin/cp \"$@\"\n"
        )
        fake.chmod(0o755)
        env = self.env.copy()
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        shell = "/bin/bash" if Path("/bin/bash").exists() else "bash"
        result = run([shell, str(SYNC / "sync.sh"), "pull", "--full"], env=env, cwd=self.company)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("could not copy 1 logs back into memory/logs. A full copy is in ", result.stderr)
        save = Path(result.stderr.split("A full copy is in ", 1)[1].split()[0].rstrip("."))
        self.assertEqual((save / "2026-10-03-mia.md").read_text(), "day three, untracked\n")
        self.assertNotIn("worktree removed", self.sync_log())
        self.assertIn("last error: pull failed for root: the old logs folder", self.sync("status").stdout)
        shutil.rmtree(save, ignore_errors=True)

    def test_partial_worktree_remove_says_where_the_copy_is(self):
        # Round 4 (48): a remove that deletes some files, then stops.
        bare, logs = self.v0_clone_after_upgrade()
        real_git = shutil.which("git")
        bindir = self.tmp / "bin"
        bindir.mkdir()
        shim = bindir / "git"
        shim.write_text(
            "#!/bin/bash\n"
            "case \" $* \" in\n"
            f"  *' worktree remove '*) rm -f '{logs}/2026-10-03-mia.md'; exit 1 ;;\n"
            "esac\n"
            f"exec '{real_git}' \"$@\"\n"
        )
        shim.chmod(0o755)
        env = self.env.copy()
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        result = self.sync("pull", "--full", env=env)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("some files may be gone from memory/logs. A full copy is in ", result.stderr)
        self.assertNotIn("Nothing was removed", result.stderr)
        save = Path(result.stderr.split("A full copy is in ", 1)[1].split()[0].rstrip("."))
        self.assertEqual((save / "2026-10-03-mia.md").read_text(), "day three, untracked\n")
        shutil.rmtree(save, ignore_errors=True)

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

    def rewrite_origin(self, stamp):
        orphan = self.tmp / ("orphan-" + stamp)
        run(["git", "init", "-q", "-b", "main", str(orphan)], env=self.env, check=True)
        (orphan / "README.md").write_text("rewritten\n")
        run(["git", "-C", str(orphan), "add", "README.md"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "commit", "-q", "-m", "rewritten"], env=self.env, check=True)
        run(["git", "-C", str(orphan), "remote", "add", "origin", str(self.tmp / "origin.git")], env=self.env, check=True)
        run(["git", "-C", str(orphan), "push", "-q", "--force", "origin", "main"], env=self.env, check=True)
        tag = orphan / "tagmsg"
        tag.write_text("rule: none\n")
        run(["git", "-C", str(orphan), "tag", "-a", "os-rewrite-" + stamp, "-F", str(tag)], env=self.env, check=True)
        run(["git", "-C", str(orphan), "push", "-q", "origin", "refs/tags/os-rewrite-" + stamp], env=self.env, check=True)

    def test_reclone_holds_while_a_commit_is_not_on_the_host(self):
        # Round 3 (38): a reclone copies only changed files. A commit the host never had stays.
        self.seed_origin()
        (self.company / "mine.md").write_text("not pushed\n")
        run(["git", "-C", str(self.company), "add", "mine.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "mine"], env=self.env, check=True)
        head = run(["git", "-C", str(self.company), "rev-parse", "HEAD"], env=self.env, check=True).stdout.strip()
        self.rewrite_origin("20261024235956")
        result = self.sync("pull")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(
            "pull failed for root: this copy has 1 commits (on any local branch) that are not on the host, so it was not swapped",
            result.stderr,
        )
        after = run(["git", "-C", str(self.company), "rev-parse", "HEAD"], env=self.env, check=True).stdout.strip()
        self.assertEqual(after, head)
        self.assertEqual((self.company / "mine.md").read_text(), "not pushed\n")
        self.assertFalse(list(self.company.parent.glob(".sync-reclone-*")))
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertNotIn("pull reclone root", log)

    def test_reclone_holds_while_another_local_branch_has_unpushed_work(self):
        # Round 4 (44): HEAD is clean, but a local branch the host never had would be lost.
        self.seed_origin()
        self.git("checkout", "-q", "-b", "draft-ideas")
        (self.company / "idea.md").write_text("not pushed\n")
        self.git("add", "idea.md")
        self.git("commit", "-q", "-m", "idea")
        self.git("checkout", "-q", "main")
        self.rewrite_origin("20261024235954")
        result = self.sync("pull")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("this copy has 1 commits (on any local branch) that are not on the host", result.stderr)
        self.assertEqual(self.git("show", "draft-ideas:idea.md").stdout, "not pushed\n")
        self.assertNotIn("pull reclone root", self.sync_log())

    def test_reclone_runs_when_every_commit_was_on_the_host(self):
        # The old main tip was on the host before the rewrite: that is not unpushed work.
        self.seed_origin()
        self.rewrite_origin("20261024235955")
        result = self.sync("pull")
        log = (self.home / ".config" / "acme-os" / "state" / "sync.log").read_text()
        self.assertNotIn("commits that are not on the host", result.stderr)
        self.assertIn("pull reclone root", log, result.stdout + result.stderr)
        self.assertEqual((self.company / "README.md").read_text(), "rewritten\n")

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

    def test_opened_lines_before_refuse(self):
        (self.company / "AGENTS.md").write_text("# company change\n")
        result = self.propose("topic", "AGENTS.md", "areas/shop/AGENTS.md")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertIn("nothing to propose: areas/shop/AGENTS.md", result.stderr)
        self.assertIn("opened: company 1", result.stderr)
        outside = self.tmp / "outside-link"
        outside.mkdir()
        skills = self.area / "skills"
        skills.mkdir()
        (skills / "x").symlink_to(outside)
        run(["git", "-C", str(self.area), "add", "skills"], env=self.env, check=True)
        run(["git", "-C", str(self.area), "commit", "-q", "-m", "link"], env=self.env, check=True)
        run(["git", "-C", str(self.area), "push", "-q", "origin", "main"], env=self.env, check=True)
        (skills / "x").unlink()
        (skills / "x").mkdir()
        (skills / "x" / "f.md").write_text("no\n")
        (self.company / "AGENTS.md").write_text("# company change again\n")
        result = self.propose("topic2", "AGENTS.md", "areas/shop/skills/x/f.md")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertIn("propose refused: symlink on main: areas/shop/skills/x/f.md", result.stderr)
        self.assertIn("opened: company 1", result.stderr)
        self.assertEqual(list(outside.iterdir()), [])

    def test_symlink_walk_does_not_glob(self):
        # Glob is a later component. The only cwd match is a decoy, not the symlink.
        outside = self.tmp / "outside-glob"
        outside.mkdir()
        target = outside / "target.md"
        target.write_text("kept\n")
        (self.company / "x-only").write_text("decoy\n")
        skills = self.company / "skills"
        skills.mkdir()
        (skills / "x*").symlink_to(target)
        run(["git", "-C", str(self.company), "add", "--", "skills/x*"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "glob link"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        (skills / "x*").unlink()
        (skills / "x*").write_text("overwrite\n")
        result = self.propose("topic", "skills/x*")
        self.assertEqual(target.read_text(), "kept\n")
        self.assertEqual(list(outside.iterdir()), [target])
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertIn("propose refused: symlink on main: skills/x*", result.stderr)

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


class SecretScanAwkTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-scan-"))
        self.env = os.environ.copy()
        self.env["OS_SECRET_SCAN"] = "bundled"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def scan(self, text, env=None):
        path = self.tmp / "note.txt"
        path.write_text(text if text.endswith("\n") else text + "\n")
        return run(
            ["bash", str(SYNC / "secret-scan.sh"), "--files", "--", str(path)],
            env=env or self.env,
        )

    def test_known_bad_fixtures_hit_and_hide_the_value(self):
        cases = [
            ("gh" + "p_" + ("ab12" * 9), "github-pat"),
            ("github" + "_pat_" + "abcdefghij1234567890ab", "github-pat"),
            ("xo" + "xb-" + "1234567890abcdef", "slack-bot-token"),
            ("xo" + "xp-" + "1234567890abcdef", "slack-bot-token"),
            ("AK" + "IA" + "0123456789ABCDEF", "aws-access-key"),
            ("token = abcdefghijklmnop", "generic-api-key"),
            ("api_key=abcdefghijklmnop", "generic-api-key"),
            ('token = "' + ("e" * 16), "generic-api-key"),
            ("token = " + ("d" * 16) + " secret = x", "generic-api-key"),
            ("token = no token = " + ("d" * 16), "generic-api-key"),
            ("password = aB3xQ9mZ2kL8pR4sT6uV1wY5nC7dE0fG2hJ4", "high-entropy"),
            ("-----BE" + "GIN OPENSSH PRIVATE KEY-----", "private-key"),
            ("-----BE" + "GIN RSA PRIVATE KEY-----", "private-key"),
        ]
        for text, rule in cases:
            result = self.scan(text)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(rule, result.stdout)
            self.assertNotIn(text, result.stdout)
            self.assertNotIn(text, result.stderr)

    def test_clean_lines_stay_clean(self):
        for text in ("notes: no secret here", "password = short", "-----BE" + "GIN OPENSSH"):
            result = self.scan(text)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout, "")

    def test_self_test_fails_closed_when_awk_does_not_flag(self):
        bindir = self.tmp / "bin"
        bindir.mkdir()
        stub = bindir / "awk"
        stub.write_text("#!/bin/sh\nexit 0\n")
        stub.chmod(0o755)
        env = self.env.copy()
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        result = self.scan("hello\n", env=env)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("secret scan error: self-test failed", result.stderr)
        self.assertNotIn("hello", result.stdout)
        self.assertNotIn("self-test ok", result.stdout)

    def test_empty_staged_self_test_fails_closed(self):
        bindir = self.tmp / "bin"
        bindir.mkdir()
        stub = bindir / "awk"
        stub.write_text("#!/bin/sh\nexit 0\n")
        stub.chmod(0o755)
        env = self.env.copy()
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        repo = self.tmp / "repo"
        repo.mkdir()
        run(["git", "init", "-q", "-b", "main", str(repo)], env=env, check=True)
        result = run(
            ["bash", str(SYNC / "secret-scan.sh"), "--staged"],
            env=env,
            cwd=repo,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("secret scan error: self-test failed", result.stderr)

    def test_same_fixtures_under_bsd_mawk_and_gawk(self):
        result = run(["bash", str(ROOT / "tests" / "sync" / "scan-awks.sh")])
        text = result.stdout + result.stderr
        if "BLOCKED: docker" in text:
            self.fail(text)
        self.assertEqual(result.returncode, 0, text)
        for label in ("bsd", "bookworm-mawk", "stable-mawk", "gawk"):
            self.assertIn(f"PASS {label}", text)


class QuickPullTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-sync-quick-"))
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

    def clock(self, now, mid, base=None):
        env = (base or self.env).copy()
        env["OS_SYNC_CLOCK"] = f"{now} {mid}"
        return env

    def make_repo(self, path, bare, name="README.md", text="seed\n"):
        path.mkdir(parents=True, exist_ok=True)
        run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], env=self.env, check=True)
        run(["git", "init", "-q", "-b", "main", str(path)], env=self.env, check=True)
        target = path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        run(["git", "-C", str(path), "add", "-A"], env=self.env, check=True)
        run(["git", "-C", str(path), "commit", "-q", "-m", "seed"], env=self.env, check=True)
        run(["git", "-C", str(path), "remote", "add", "origin", str(bare)], env=self.env, check=True)
        run(["git", "-C", str(path), "push", "-q", "origin", "main"], env=self.env, check=True)
        return bare

    def commit_push(self, path, rel, text, message="more"):
        target = path / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        run(["git", "-C", str(path), "add", rel], env=self.env, check=True)
        run(["git", "-C", str(path), "commit", "-q", "-m", message], env=self.env, check=True)
        run(["git", "-C", str(path), "push", "-q", "origin", "main"], env=self.env, check=True)

    def stamp(self, repo):
        fetch = Path(repo) / ".git" / "FETCH_HEAD"
        if not fetch.exists():
            return None
        return fetch.stat().st_mtime_ns

    def state_path(self):
        return self.company / ".git" / "os-foundation" / "pull-state"

    def state_lines(self):
        raw = self.state_path().read_bytes()
        self.assertNotIn(b"\r", raw)
        self.assertTrue(raw.endswith(b"\n"))
        text = raw.decode("ascii")
        lines = text.split("\n")
        self.assertEqual(lines[-1], "")
        return lines[:-1]

    def log_text(self):
        path = self.home / ".config" / "acme-os" / "state" / "sync.log"
        if not path.exists():
            return ""
        return path.read_text()

    def line_for(self, rel):
        for line in self.state_lines():
            if line.startswith("repo ") and line.endswith(" " + rel):
                return line
        return ""

    def test_no_state_is_a_full_pull_and_status_names_it(self):
        never = self.sync("status")
        self.assertEqual(never.returncode, 0, never.stderr)
        self.assertIn("last full pull: never", never.stdout)
        self.make_repo(self.company, self.tmp / "root.git")
        area = self.company / "areas" / "lab"
        self.make_repo(area, self.tmp / "lab.git")
        workspace = self.company / "users" / "mia"
        self.make_repo(workspace, self.tmp / "mia.git")
        env = self.clock(1700000000, 72000)
        result = self.sync("pull", env=env)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        lines = self.state_lines()
        self.assertEqual(lines[0], "os-sync-state 1")
        self.assertEqual(lines[1], "full 1700000000")
        self.assertEqual(lines[2], "me mia")
        self.assertEqual(lines[3], "bot 0")
        self.assertTrue(self.line_for(".").startswith("repo ok "))
        self.assertTrue(self.line_for("areas/lab").startswith("repo ok "))
        self.assertTrue(self.line_for("users/mia").startswith("repo ok "))
        self.assertEqual(
            [line.split()[-1] for line in lines if line.startswith("repo ")],
            [".", "areas/lab", "users/mia"],
        )
        status = self.sync("status", env=env)
        self.assertIn("last full pull: 2023-11-14T22:13:20Z", status.stdout)
        self.assertNotIn("pull-state", run(["git", "-C", str(self.company), "status", "--porcelain"], env=self.env).stdout)

    def test_nothing_changed_does_not_fetch_or_log(self):
        self.make_repo(self.company, self.tmp / "root.git")
        area = self.company / "areas" / "lab"
        self.make_repo(area, self.tmp / "lab.git")
        (self.company / "skills" / "lint").mkdir(parents=True)
        (self.company / "skills" / "lint" / "SKILL.md").write_text("base\n")
        (self.company / ".agents" / "skills").mkdir(parents=True)
        (self.company / ".claude" / "skills").mkdir(parents=True)
        first = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(first.returncode, 0, first.stderr)
        copied = self.company / ".agents" / "skills" / "lint" / "SKILL.md"
        self.assertEqual(copied.read_text(), "base\n")
        copied.unlink()
        root_stamp = self.stamp(self.company)
        area_stamp = self.stamp(area)
        before = self.log_text()
        quiet = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(quiet.returncode, 0, quiet.stderr + quiet.stdout)
        self.assertEqual(self.stamp(self.company), root_stamp)
        self.assertEqual(self.stamp(area), area_stamp)
        self.assertEqual(self.log_text(), before)
        self.assertFalse(copied.exists())
        self.assertEqual(self.state_lines()[1], "full 100000")

    def test_full_flag_still_fetches_and_copies(self):
        self.make_repo(self.company, self.tmp / "root.git")
        (self.company / "skills" / "lint").mkdir(parents=True)
        (self.company / "skills" / "lint" / "SKILL.md").write_text("base\n")
        (self.company / ".agents" / "skills").mkdir(parents=True)
        (self.company / ".claude" / "skills").mkdir(parents=True)
        run(["git", "-C", str(self.company), "add", "skills"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "skill"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        (self.company / ".agents" / "skills" / "lint" / "SKILL.md").unlink()
        before = self.stamp(self.company)
        full = self.sync("pull", "--full", env=self.clock(100100, 18000))
        self.assertEqual(full.returncode, 0, full.stderr + full.stdout)
        self.assertNotEqual(self.stamp(self.company), before)
        self.assertEqual((self.company / ".agents" / "skills" / "lint" / "SKILL.md").read_text(), "base\n")
        self.assertEqual(self.state_lines()[1], "full 100100")

    def test_one_area_changed_leaves_the_others(self):
        self.make_repo(self.company, self.tmp / "root.git")
        lab = self.company / "areas" / "lab"
        shop = self.company / "areas" / "shop"
        self.make_repo(lab, self.tmp / "lab.git")
        self.make_repo(shop, self.tmp / "shop.git")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        root_line = self.line_for(".")
        lab_line = self.line_for("areas/lab")
        root_stamp = self.stamp(self.company)
        lab_stamp = self.stamp(lab)
        side = self.tmp / "shop-side"
        run(["git", "clone", "-q", str(self.tmp / "shop.git"), str(side)], env=self.env, check=True)
        self.commit_push(side, "notes/new.md", "from the host\n")
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(pulled.returncode, 0, pulled.stderr + pulled.stdout)
        self.assertTrue((shop / "notes" / "new.md").exists())
        self.assertEqual(self.stamp(self.company), root_stamp)
        self.assertEqual(self.stamp(lab), lab_stamp)
        self.assertNotEqual(self.stamp(shop), None)
        self.assertEqual(self.line_for("."), root_line)
        self.assertEqual(self.line_for("areas/lab"), lab_line)
        self.assertNotEqual(self.line_for("areas/shop"), "")
        self.assertTrue(self.line_for("areas/shop").startswith("repo ok "))
        self.assertEqual(self.state_lines()[1], "full 100000")

    def test_retry_line_is_pulled(self):
        self.make_repo(self.company, self.tmp / "root.git")
        area = self.company / "areas" / "lab"
        self.make_repo(area, self.tmp / "lab.git")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        lines = self.state_lines()
        swapped = []
        for line in lines:
            if line.endswith(" areas/lab") and line.startswith("repo ok "):
                swapped.append("repo retry " + line[len("repo ok ") :])
            else:
                swapped.append(line)
        self.state_path().write_text("\n".join(swapped) + "\n")
        before = self.stamp(self.company)
        area_before = self.stamp(area)
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(pulled.returncode, 0, pulled.stderr)
        self.assertEqual(self.stamp(self.company), before)
        self.assertNotEqual(self.stamp(area), area_before)
        self.assertTrue(self.line_for("areas/lab").startswith("repo ok "))

    def test_new_area_is_pulled_with_its_copy_pass(self):
        self.make_repo(self.company, self.tmp / "root.git")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        root_stamp = self.stamp(self.company)
        area = self.company / "areas" / "shop"
        self.make_repo(area, self.tmp / "shop.git")
        (area / "skills" / "lint").mkdir(parents=True)
        (area / "skills" / "lint" / "SKILL.md").write_text("base\n")
        (area / ".agents" / "skills").mkdir(parents=True)
        (area / ".claude" / "skills").mkdir(parents=True)
        run(["git", "-C", str(area), "add", "skills"], env=self.env, check=True)
        run(["git", "-C", str(area), "commit", "-q", "-m", "skill"], env=self.env, check=True)
        run(["git", "-C", str(area), "push", "-q", "origin", "main"], env=self.env, check=True)
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(pulled.returncode, 0, pulled.stderr + pulled.stdout)
        self.assertEqual(self.stamp(self.company), root_stamp)
        self.assertIsNotNone(self.stamp(area))
        self.assertEqual((area / ".agents" / "skills" / "lint" / "SKILL.md").read_text(), "base\n")
        self.assertEqual((area / ".claude" / "skills" / "lint" / "SKILL.md").read_text(), "base\n")
        self.assertTrue(self.line_for("areas/shop").startswith("repo ok "))

    def test_new_area_without_origin_still_gets_the_copy_pass(self):
        self.make_repo(self.company, self.tmp / "root.git")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        area = self.company / "areas" / "shop"
        area.mkdir(parents=True)
        run(["git", "init", "-q", "-b", "main", str(area)], env=self.env, check=True)
        (area / "skills" / "lint").mkdir(parents=True)
        (area / "skills" / "lint" / "SKILL.md").write_text("base\n")
        (area / ".agents" / "skills").mkdir(parents=True)
        (area / ".claude" / "skills").mkdir(parents=True)
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(pulled.returncode, 0, pulled.stderr + pulled.stdout)
        copied = area / ".agents" / "skills" / "lint" / "SKILL.md"
        self.assertEqual(copied.read_text(), "base\n")
        self.assertEqual(self.line_for("areas/shop"), "repo ok none areas/shop")
        copied.unlink()
        before = self.log_text()
        quiet = self.sync("pull", env=self.clock(100200, 18000))
        self.assertEqual(quiet.returncode, 0, quiet.stderr + quiet.stdout)
        self.assertFalse(copied.exists())
        self.assertEqual(self.log_text(), before)
        self.assertEqual(self.line_for("areas/shop"), "repo ok none areas/shop")
        run(["git", "-C", str(area), "add", "skills"], env=self.env, check=True)
        run(["git", "-C", str(area), "commit", "-q", "-m", "skill"], env=self.env, check=True)
        bare = self.tmp / "shop.git"
        run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], env=self.env, check=True)
        run(["git", "-C", str(area), "remote", "add", "origin", str(bare)], env=self.env, check=True)
        run(["git", "-C", str(area), "push", "-q", "origin", "main"], env=self.env, check=True)
        side = self.tmp / "shop-side"
        run(["git", "clone", "-q", str(bare), str(side)], env=self.env, check=True)
        self.commit_push(side, "notes/from-host.md", "from the host\n")
        gained = self.sync("pull", env=self.clock(100300, 18000))
        self.assertEqual(gained.returncode, 0, gained.stderr + gained.stdout)
        self.assertTrue((area / "notes" / "from-host.md").exists())
        self.assertTrue(self.line_for("areas/shop").startswith("repo ok "))
        self.assertNotIn("none", self.line_for("areas/shop"))

    def test_ls_remote_failure_uses_the_normal_fail_line(self):
        self.make_repo(self.company, self.tmp / "root.git")
        area = self.company / "areas" / "lab"
        self.make_repo(area, self.tmp / "lab.git")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        run(
            ["git", "-C", str(area), "remote", "set-url", "origin", str(self.tmp / "missing.git")],
            env=self.env,
            check=True,
        )
        before = self.stamp(self.company)
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertNotEqual(pulled.returncode, 0)
        self.assertEqual(self.stamp(self.company), before)
        self.assertIn("pull fail area:lab could not reach origin", self.log_text())
        self.assertTrue(self.line_for("areas/lab").startswith("repo retry "))

    def test_daily_due_is_full_and_not_due_is_quick(self):
        self.make_repo(self.company, self.tmp / "root.git")
        area = self.company / "areas" / "lab"
        self.make_repo(area, self.tmp / "lab.git")
        seeded = self.sync("pull", env=self.clock(100000, 10800))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        quiet_root = self.stamp(self.company)
        quiet = self.sync("pull", env=self.clock(100100, 10800))
        self.assertEqual(quiet.returncode, 0, quiet.stderr)
        self.assertEqual(self.stamp(self.company), quiet_root)
        self.assertEqual(self.state_lines()[1], "full 100000")
        due = self.sync("pull", env=self.clock(200000, 10800))
        self.assertEqual(due.returncode, 0, due.stderr)
        self.assertNotEqual(self.stamp(self.company), quiet_root)
        self.assertNotEqual(self.stamp(area), None)
        self.assertEqual(self.state_lines()[1], "full 200000")

    def test_local_changes_that_block_fast_forward_are_retry(self):
        bare = self.make_repo(self.company, self.tmp / "root.git")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        side = self.tmp / "side"
        run(["git", "clone", "-q", str(bare), str(side)], env=self.env, check=True)
        self.commit_push(side, "README.md", "from the host\n")
        (self.company / "README.md").write_text("local edit\n")
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertNotEqual(pulled.returncode, 0)
        self.assertIn("pull fail root local changes", self.log_text())
        line = self.line_for(".")
        self.assertTrue(line.startswith("repo retry "), line)
        self.assertNotIn("repo ok ", line)
        head = run(["git", "-C", str(self.company), "rev-parse", "HEAD"], env=self.env, check=True).stdout.strip()
        origin = run(
            ["git", "-C", str(self.company), "rev-parse", "refs/remotes/origin/main"],
            env=self.env,
            check=True,
        ).stdout.strip()
        self.assertNotEqual(head, origin)
        ancestor = run(
            ["git", "-C", str(self.company), "merge-base", "--is-ancestor", "refs/remotes/origin/main", "HEAD"],
            env=self.env,
        )
        self.assertNotEqual(ancestor.returncode, 0)

    def test_bad_flag_and_broken_state(self):
        self.make_repo(self.company, self.tmp / "root.git")
        bad = self.sync("pull", "--nope")
        self.assertEqual(bad.returncode, 1)
        self.assertIn("unknown flag", bad.stderr)
        extra = self.sync("pull", "--full", "--extra")
        self.assertEqual(extra.returncode, 1)
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        self.state_path().write_text("not a state\n")
        before = self.stamp(self.company)
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(pulled.returncode, 0, pulled.stderr)
        self.assertNotEqual(self.stamp(self.company), before)
        self.assertEqual(self.state_lines()[0], "os-sync-state 1")
        self.assertEqual(self.state_lines()[1], "full 100100")

    def test_quick_path_does_not_put_the_token_in_argv(self):
        marker = "ARGVTOKENquickmarker0123456789abcdef"
        spy = self.tmp / "spy"
        spy.mkdir()
        log = self.tmp / "argv.log"
        token_file = self.tmp / "token"
        token_file.write_text(marker + "\n")
        token_file.chmod(0o600)
        (spy / "git").write_text(
            "#!/bin/bash\n"
            "printf '%s\\n' \"$*\" >> \"$ARGV_LOG\"\n"
            "if [ -n \"${GIT_ASKPASS:-}\" ] && [ -f \"$GIT_ASKPASS\" ]; then\n"
            "  printf '%s\\n' ASKPASS >> \"$ARGV_LOG\"\n"
            "  cat \"$GIT_ASKPASS\" >> \"$ARGV_LOG\"\n"
            "fi\n"
            "exec /usr/bin/git \"$@\"\n"
        )
        (spy / "git").chmod(0o755)
        (spy / "host.sh").write_text(
            "#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$ARGV_LOG\"\n"
            "case \"$1\" in\n"
            "  get-token) tr -d '\\r\\n' < \"$OS_FAKE_TOKEN_FILE\" ;;\n"
            "  *) exit 1 ;;\n"
            "esac\n"
        )
        (spy / "host.sh").chmod(0o755)
        shutil.copy(self.host / "profile.sh", spy / "profile.sh")
        self.make_repo(self.company, self.tmp / "root.git")
        env = self.clock(100000, 18000)
        env["PATH"] = str(spy) + os.pathsep + env.get("PATH", "")
        env["ARGV_LOG"] = str(log)
        env["OS_FAKE_TOKEN_FILE"] = str(token_file)
        env["OS_HOST_SH"] = str(spy / "host.sh")
        first = self.sync("pull", env=env)
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        log.write_text("")
        second = self.sync("pull", env=self.clock(100100, 18000, env))
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        text = log.read_text() if log.exists() else ""
        self.assertNotIn(marker, text)
        self.assertNotIn(marker, second.stdout + second.stderr)
        self.assertNotIn(marker, self.log_text())
        self.assertIn("ASKPASS", text)

    def test_reset_behind_is_pulled_back(self):
        self.make_repo(self.company, self.tmp / "root.git")
        area = self.company / "areas" / "lab"
        self.make_repo(area, self.tmp / "lab.git")
        self.commit_push(area, "notes/second.md", "second\n", "second")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        run(["git", "-C", str(area), "reset", "--hard", "HEAD~1"], env=self.env, check=True)
        self.assertFalse((area / "notes" / "second.md").exists())
        root_stamp = self.stamp(self.company)
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(pulled.returncode, 0, pulled.stderr + pulled.stdout)
        self.assertTrue((area / "notes" / "second.md").exists())
        self.assertEqual(self.stamp(self.company), root_stamp)

    def test_symlinked_area_behind_is_pulled(self):
        self.make_repo(self.company, self.tmp / "root.git")
        seeded = self.sync("pull", env=self.clock(100000, 18000))
        self.assertEqual(seeded.returncode, 0, seeded.stderr)
        outside = self.tmp / "outside-lab"
        self.make_repo(outside, self.tmp / "lab.git")
        side = self.tmp / "lab-side"
        run(["git", "clone", "-q", str(self.tmp / "lab.git"), str(side)], env=self.env, check=True)
        self.commit_push(side, "notes/linked.md", "linked\n")
        (self.company / "areas").mkdir()
        (self.company / "areas" / "lab").symlink_to(outside)
        root_stamp = self.stamp(self.company)
        pulled = self.sync("pull", env=self.clock(100100, 18000))
        self.assertEqual(pulled.returncode, 0, pulled.stderr + pulled.stdout)
        self.assertTrue((outside / "notes" / "linked.md").exists())
        self.assertEqual(self.stamp(self.company), root_stamp)
        self.assertTrue(self.line_for("areas/lab").startswith("repo ok "))

    def test_four_am_is_the_boundary_and_a_future_stamp_is_due(self):
        self.make_repo(self.company, self.tmp / "root.git")
        first = self.sync("pull", env=self.clock(100000, 1800))
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(self.state_lines()[1], "full 100000")
        stamp = self.stamp(self.company)
        quiet = self.sync("pull", env=self.clock(110800, 12600))
        self.assertEqual(quiet.returncode, 0, quiet.stderr)
        self.assertEqual(self.stamp(self.company), stamp)
        self.assertEqual(self.state_lines()[1], "full 100000")
        due = self.sync("pull", env=self.clock(114400, 16200))
        self.assertEqual(due.returncode, 0, due.stderr)
        self.assertNotEqual(self.stamp(self.company), stamp)
        self.assertEqual(self.state_lines()[1], "full 114400")
        lines = self.state_lines()
        lines[1] = "full 300000"
        self.state_path().write_text("\n".join(lines) + "\n")
        before = self.stamp(self.company)
        forced = self.sync("pull", env=self.clock(114500, 16200))
        self.assertEqual(forced.returncode, 0, forced.stderr)
        self.assertNotEqual(self.stamp(self.company), before)
        self.assertEqual(self.state_lines()[1], "full 114500")


if __name__ == "__main__":
    unittest.main()
