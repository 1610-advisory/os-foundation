"""Host layer contracts: profile reader, GitHub dry-run fixtures, token hygiene.

Run: python3 -m unittest discover -s tests -v
"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "template" / "skills" / "_host" / "host.sh"
PROFILE = ROOT / "template" / "skills" / "_host" / "profile.sh"
LIB = ROOT / "template" / "skills" / "_host"
FIXTURES = ROOT / "tests" / "host" / "fixtures" / "github"
COMPANY = ROOT / "tests" / "host" / "fixtures" / "company" / "company-profile.md"
BODY = ROOT / "tests" / "host" / "fixtures" / "pr-body.txt"
VERBS = [
    "whoami",
    "create-repo",
    "repo-access",
    "protect",
    "unprotect",
    "secret-exists",
    "team-create",
    "team-add",
    "team-remove",
    "grant",
    "revoke",
    "org-remove",
    "archive-repo",
    "open-pr",
    "auto-merge",
    "pr-status",
    "pr-comment",
    "set-secret",
    "get-token",
    "purge-request",
    "delete-repo",
]


def run(args, env=None, stdin=None):
    merged = os.environ.copy()
    merged.update(env or {})
    return subprocess.run(
        [str(HOST), *args],
        input=stdin,
        text=True,
        capture_output=True,
        env=merged,
        check=False,
    )


def github_env(**extra):
    env = {
        "HOST_DRY_RUN": "1",
        "OS_HOST": "github",
        "OS_ORG": "acme",
        "OS_HOST_URL": "",
        "OS_SLUG": "acme",
        "OS_PROFILE": str(COMPANY),
    }
    env.update(extra)
    return env


def loads(text):
    lines = [line for line in text.splitlines() if line.strip()]
    return [json.loads(line) for line in lines]


class ProfileTests(unittest.TestCase):
    def test_walks_up_and_reads_a_value(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "company-profile.md").write_text(
                "---\ncompany_slug: acme\nhost: forgejo\nswitches:\n  - bots\n  - traces\n---\n\n"
            )
            nested = root / "areas" / "finance"
            nested.mkdir(parents=True)
            env = os.environ.copy()
            env.pop("OS_PROFILE", None)
            env.pop("OS_HOST", None)
            proc = subprocess.run(
                [str(PROFILE), "company_slug"],
                cwd=nested,
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stdout.strip(), "acme")
            listed = subprocess.run(
                [str(PROFILE), "switches"],
                cwd=nested,
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )
            self.assertEqual(listed.stdout.splitlines(), ["bots", "traces"])

    def test_env_override_and_missing_key(self):
        env = os.environ.copy()
        env["OS_HOST"] = "github"
        env["OS_PROFILE"] = str(COMPANY)
        proc = subprocess.run(
            [str(PROFILE), "host"],
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )
        self.assertEqual(proc.stdout.strip(), "github")
        missing = subprocess.run(
            [str(PROFILE), "not_a_key"],
            text=True,
            capture_output=True,
            check=False,
            env={**os.environ, "OS_PROFILE": str(COMPANY)},
        )
        self.assertEqual(missing.returncode, 2)

    def test_comment_forms_do_not_leak_into_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "company-profile.md"
            path.write_text(
                "---\n"
                "switches: [] # none yet\n"
                "areas: [bots, traces] # on\n"
                "notes: # list\n"
                "items:\n"
                "  - bots # keep\n"
                "\n"
                "  # skipped\n"
                "  - traces\n"
                "---\n"
            )
            env = os.environ.copy()
            for key in ("OS_HOST", "OS_HOST_URL", "OS_ORG", "OS_SYNC_ENGINE"):
                env.pop(key, None)
            env["OS_PROFILE"] = str(path)

            def read(key):
                proc = subprocess.run(
                    [str(PROFILE), key],
                    text=True,
                    capture_output=True,
                    env=env,
                    check=False,
                )
                self.assertEqual(proc.returncode, 0, proc.stderr)
                return proc.stdout.splitlines()

            self.assertEqual(read("switches"), [])
            self.assertEqual(read("areas"), ["bots", "traces"])
            self.assertEqual(read("notes"), [])
            self.assertEqual(read("items"), ["bots", "traces"])

    def test_strips_quotes_and_comments(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "company-profile.md"
            path.write_text(
                '---\nhost: forgejo # local\nhost_url: "http://localhost:3310"\nswitches: []\n---\n'
            )
            env = os.environ.copy()
            env.pop("OS_HOST", None)
            env.pop("OS_HOST_URL", None)
            env["OS_PROFILE"] = str(path)
            host = subprocess.run(
                [str(PROFILE), "host"], text=True, capture_output=True, env=env, check=False
            )
            url = subprocess.run(
                [str(PROFILE), "host_url"], text=True, capture_output=True, env=env, check=False
            )
            switches = subprocess.run(
                [str(PROFILE), "switches"], text=True, capture_output=True, env=env, check=False
            )
            self.assertEqual(host.stdout.strip(), "forgejo")
            self.assertEqual(url.stdout.strip(), "http://localhost:3310")
            self.assertEqual(switches.stdout, "")
            self.assertEqual(switches.returncode, 0)


class GithubDryRunTests(unittest.TestCase):
    def assert_fixture(self, name, args, env=None, stdin=None):
        proc = run(args, github_env(**(env or {})), stdin=stdin)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        got = loads(proc.stdout)
        want = loads((FIXTURES / name).read_text())
        self.assertEqual(got, want)
        return proc

    def test_every_verb_matches_its_fixture(self):
        secret = "not-a-real-secret"
        cases = [
            ("whoami.jsonl", ["whoami"], None),
            ("create-repo.jsonl", ["create-repo", "acme-os", "--private"], None),
            ("repo-access.jsonl", ["repo-access", "acme-os"], None),
            ("protect.jsonl", ["protect", "acme-os", "--approvals", "0", "--code-owners"], None),
            ("unprotect.jsonl", ["unprotect", "acme-os"], None),
            ("secret-exists.jsonl", ["secret-exists", "OS_REVIEW_KEY"], None),
            ("team-create.jsonl", ["team-create", "writers"], None),
            ("team-add.jsonl", ["team-add", "writers", "ada"], None),
            ("team-remove.jsonl", ["team-remove", "writers", "ada"], None),
            ("grant-user.jsonl", ["grant", "acme-os", "ada", "write"], None),
            ("grant-team.jsonl", ["grant", "acme-os", "team:writers", "read"], None),
            ("revoke-user.jsonl", ["revoke", "acme-os", "ada"], None),
            ("revoke-team.jsonl", ["revoke", "acme-os", "team:writers"], None),
            ("org-remove.jsonl", ["org-remove", "ada"], None),
            ("archive-repo.jsonl", ["archive-repo", "acme-os"], None),
            (
                "open-pr.jsonl",
                ["open-pr", "acme-os", "--head", "sync/ada", "--base", "main", "--title", "sync: ada", "--body-file", str(BODY)],
                None,
            ),
            ("auto-merge.jsonl", ["auto-merge", "acme-os", "12"], None),
            ("pr-status.jsonl", ["pr-status", "acme-os", "12"], None),
            ("pr-comment.jsonl", ["pr-comment", "acme-os", "12", "--body-file", str(BODY)], None),
            ("set-secret.jsonl", ["set-secret", "OS_REVIEW_KEY"], secret),
            ("get-token.jsonl", ["get-token"], None),
            ("get-token-bot.jsonl", ["get-token", "--bot", "helper"], None),
            ("delete-repo.jsonl", ["delete-repo", "acme-os", "--yes-test-only"], None),
        ]
        for name, args, stdin in cases:
            extra = {"OS_TEST_MODE": "1"} if name.startswith("delete") else {}
            proc = self.assert_fixture(name, args, extra, stdin)
            if stdin:
                self.assertNotIn(stdin, proc.stdout)
                self.assertNotIn(stdin, proc.stderr)

    def test_purge_request_text(self):
        proc = run(["purge-request", "acme-os"], github_env())
        self.assertEqual(proc.returncode, 0, proc.stderr)
        got = json.loads(proc.stdout)
        want = json.loads((FIXTURES / "purge-request.json").read_text())
        self.assertEqual(got, want)
        self.assertIn("https://github.com/acme/acme-os", got["text"])
        self.assertEqual(got["url"], "https://support.github.com/contact")

    def test_protect_ruleset_shape(self):
        calls = loads((FIXTURES / "protect.jsonl").read_text())
        self.assertEqual([call["path"] for call in calls], [
            "/repos/acme/acme-os/rulesets",
            "/repos/acme/acme-os/rulesets",
        ])
        main = calls[0]["body"]
        review = calls[1]["body"]
        main_rules = {rule["type"]: rule for rule in main["rules"]}
        self.assertEqual(main["name"], "main")
        self.assertNotIn("bypass_actors", main)
        self.assertFalse(main_rules["pull_request"]["parameters"]["require_code_owner_review"])
        self.assertEqual(main_rules["pull_request"]["parameters"]["required_approving_review_count"], 0)
        self.assertEqual(
            main_rules["required_status_checks"]["parameters"]["required_status_checks"],
            [{"context": "checks"}],
        )
        self.assertIn("non_fast_forward", main_rules)
        self.assertIn("deletion", main_rules)
        self.assertEqual(review["name"], "rules-review")
        self.assertTrue(review["rules"][0]["parameters"]["require_code_owner_review"])
        self.assertEqual(review["bypass_actors"], [
            {"actor_type": "OrganizationAdmin", "bypass_mode": "pull_request"}
        ])
        self.assertNotIn("actor_id", review["bypass_actors"][0])

    def test_check_override_replaces_the_default(self):
        proc = run(["protect", "acme-os", "--check", "lint"], github_env())
        self.assertEqual(proc.returncode, 0, proc.stderr)
        calls = loads(proc.stdout)
        checks = calls[0]["body"]["rules"][1]["parameters"]["required_status_checks"]
        self.assertEqual(checks, [{"context": "lint"}])
        self.assertEqual(calls[1]["body"]["name"], "rules-review")

    def test_ghes_hostname_is_recorded(self):
        proc = run(["whoami"], github_env(OS_HOST_URL="https://git.example.com"))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        call = loads(proc.stdout)[0]
        self.assertEqual(call["hostname"], "git.example.com")

    def test_dry_run_does_not_push(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "src"
            repo.mkdir()
            subprocess.check_call(["git", "init", "-b", "main"], cwd=repo, stdout=subprocess.DEVNULL)
            proc = run(
                ["create-repo", "acme-os", "--private", "--source", str(repo), "--push"],
                github_env(),
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertFalse((repo / ".git" / "config").read_text().find("[remote \"origin\"]") >= 0)
            self.assertEqual(loads(proc.stdout)[0]["path"], "/orgs/acme/repos")

    def test_delete_refuses_without_the_test_flag(self):
        refused = run(["delete-repo", "acme-os", "--yes-test-only"], github_env())
        self.assertEqual(refused.returncode, 1)
        self.assertIn("OS_TEST_MODE", refused.stderr)
        no_flag = run(["delete-repo", "acme-os"], github_env(OS_TEST_MODE="1"))
        self.assertEqual(no_flag.returncode, 1)


class TokenAndUsageTests(unittest.TestCase):
    def test_readme_lists_every_verb(self):
        text = (LIB / "README.md").read_text()
        for verb in VERBS:
            self.assertIn(f"`{verb}", text)

    def test_scripts_do_not_log_tokens(self):
        for path in LIB.glob("*.sh"):
            text = path.read_text()
            self.assertNotIn("set -x", text)
            self.assertNotIn("curl -v", text)
            self.assertNotIn("?token=", text)
            self.assertNotIn("token=${", text)
            self.assertNotIn("token=$token", text)

    def test_usage_and_unknown_host(self):
        help_proc = run(["--help"], {"OS_HOST": "none"})
        self.assertEqual(help_proc.returncode, 0)
        self.assertIn("whoami", help_proc.stdout)
        none = run(["whoami"], {"OS_HOST": "none", "OS_ORG": "acme"})
        self.assertEqual(none.returncode, 1)
        unknown = run(["nope"], github_env())
        self.assertEqual(unknown.returncode, 1)

    def test_forgejo_offline_hides_the_token(self):
        token = "fj-test-token-not-real"
        proc = run(
            ["repo-access", "acme-os"],
            {
                "OS_HOST": "forgejo",
                "OS_HOST_URL": "http://127.0.0.1:9",
                "OS_ORG": "acme",
                "OS_SLUG": "acme",
                "FORGEJO_TOKEN": token,
            },
        )
        self.assertEqual(proc.returncode, 5, proc.stderr)
        self.assertNotIn(token, proc.stdout)
        self.assertNotIn(token, proc.stderr)
        self.assertIn("offline", proc.stdout)

    def test_app_jwt_is_signed_and_not_printed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            key = root / "helper.pem"
            subprocess.check_call(
                ["openssl", "genrsa", "-out", str(key), "2048"],
                stderr=subprocess.DEVNULL,
            )
            (root / "company-profile.md").write_text(
                "---\ncompany_slug: acme\nhost: github\norg: acme\n---\n"
            )
            bot = root / "bots" / "helper"
            bot.mkdir(parents=True)
            (bot / "BOT.md").write_text(
                f"---\napp_id: 100\ninstallation_id: 200\nkey_path: {key}\n---\n"
            )
            log = root / "gh.log"
            envlog = root / "gh.env"
            fake = ROOT / "tests" / "host" / "fake-gh.sh"
            env = github_env(HOST_DRY_RUN="", OS_PROFILE=str(root / "company-profile.md"))
            gh = root / "gh"
            gh.write_text(fake.read_text())
            gh.chmod(0o755)
            env["PATH"] = str(root) + os.pathsep + env.get("PATH", os.environ.get("PATH", ""))
            env["FAKE_GH_LOG"] = str(log)
            env["FAKE_GH_ENV"] = str(envlog)
            proc = run(["get-token", "--bot", "helper"], env)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stdout.strip(), "test-install-token")
            self.assertNotIn("PRIVATE KEY", proc.stderr)
            self.assertNotIn(key.read_text().splitlines()[1], proc.stdout + proc.stderr)
            recorded = log.read_text()
            jwt = envlog.read_text().strip()
            self.assertNotIn(jwt, recorded)
            self.assertNotIn("Authorization:", recorded)
            self.assertEqual(jwt.count("."), 2)
            header, payload, sig = jwt.split(".")
            self.assertNotIn(jwt, proc.stdout)
            import base64

            def decode(part):
                return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))

            body = json.loads(decode(payload))
            self.assertEqual(body["iss"], 100)
            self.assertGreater(body["exp"], body["iat"])
            pub = root / "helper.pub"
            subprocess.check_call(
                ["openssl", "rsa", "-in", str(key), "-pubout", "-out", str(pub)],
                stderr=subprocess.DEVNULL,
            )
            signing = root / "signing.txt"
            signing.write_bytes(f"{header}.{payload}".encode())
            sig_file = root / "sig.bin"
            sig_file.write_bytes(decode(sig))
            verify = subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", str(pub), "-signature", str(sig_file), str(signing)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(verify.returncode, 0, verify.stderr)
            self.assertIn("Verified OK", verify.stdout)

    def test_forgejo_argv_hides_token_and_secret(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            log = root / "curl.log"
            curl = root / "curl"
            curl.write_text((ROOT / "tests" / "host" / "fake-curl.sh").read_text())
            curl.chmod(0o755)
            token = "fj-argv-token-value"
            secret = "secret-value-not-in-argv"
            env = {
                "OS_HOST": "forgejo",
                "OS_HOST_URL": "http://127.0.0.1:9",
                "OS_ORG": "acme",
                "OS_SLUG": "acme",
                "FORGEJO_TOKEN": token,
                "PATH": str(root) + os.pathsep + os.environ.get("PATH", ""),
                "FAKE_CURL_LOG": str(log),
            }
            access = run(["repo-access", "acme-os"], env)
            self.assertNotEqual(access.returncode, 0)
            argv = log.read_text()
            self.assertNotIn(token, argv)
            self.assertNotIn("Authorization", argv)
            log.write_text("")
            hidden = run(["set-secret", "OS_REVIEW_KEY"], env, stdin=secret)
            self.assertNotEqual(hidden.returncode, 0)
            argv = log.read_text()
            self.assertNotIn(secret, argv)
            self.assertNotIn(token, argv)

    def test_team_lookup_and_failed_secret_leave_no_temp_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            private = root / "tmp"
            private.mkdir()
            log = root / "argv.log"
            curl = root / "curl"
            awk = root / "awk"
            curl.write_text((ROOT / "tests" / "host" / "fake-curl.sh").read_text())
            awk.write_text((ROOT / "tests" / "host" / "fake-awk.sh").read_text())
            curl.chmod(0o755)
            awk.chmod(0o755)
            token = "fj-argv-token-value"
            secret = "secret-value-not-in-argv"
            env = {
                "OS_HOST": "forgejo",
                "OS_HOST_URL": "http://127.0.0.1:9",
                "OS_ORG": "acme",
                "OS_SLUG": "acme",
                "FORGEJO_TOKEN": token,
                "TMPDIR": str(private),
                "PATH": str(root) + os.pathsep + os.environ.get("PATH", ""),
                "FAKE_CURL_LOG": str(log),
                "FAKE_ARGV_LOG": str(log),
            }
            looked = run(["team-add", "writers", "ada"], env)
            self.assertNotEqual(looked.returncode, 0)
            hidden = run(["set-secret", "OS_REVIEW_KEY"], env, stdin=secret)
            self.assertNotEqual(hidden.returncode, 0)
            self.assertEqual(list(private.iterdir()), [])
            argv = log.read_text()
            self.assertNotIn(secret, argv)
            self.assertNotIn(token, argv)


if __name__ == "__main__":
    unittest.main()
