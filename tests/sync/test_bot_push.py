"""Bot push keeps the run commit and refuses a secret or a rules file.

Names are made up. Token values are never printed.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYNC = ROOT / "template" / "skills" / "sync"
PROFILE = ROOT / "template" / "skills" / "_host" / "profile.sh"
HELPER = ROOT / "template" / "skills" / "add-bot" / "git-credential-os-bot"
HELPER_LIB = ROOT / "template" / "skills" / "add-bot" / "lib.sh"
SECRET = "gh" + "p_" + ("ab12" * 9)
BOT_TOKEN = "bot-token-value"
PERSON_TOKEN = "person-token-value"


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
    env["GIT_AUTHOR_NAME"] = "Acme Bot"
    env["GIT_AUTHOR_EMAIL"] = "acme.bot@acme.test"
    env["GIT_COMMITTER_NAME"] = "Acme Bot"
    env["GIT_COMMITTER_EMAIL"] = "acme.bot@acme.test"
    return env


class BotPushTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="osf-bot-push-"))
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.company = self.home / "acme"
        self.company.mkdir()
        self.company.joinpath("company-profile.md").write_text(
            "\n".join(
                [
                    "---",
                    "type: company-profile",
                    'summary: "Acme Co test"',
                    "updated: 2026-10-24",
                    "company_slug: acme",
                    "level: team",
                    "switches: [bots]",
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
        people = self.company / "people"
        people.mkdir()
        (people / "Mia.md").write_text(
            "---\ntype: person\nslug: mia\ngithub: acme-member-a\nemail: mia.member@acme.test\n---\n\n# Mia Member\n"
        )
        bot = self.company / "bots" / "helper"
        bot.mkdir(parents=True)
        (bot / "BOT.md").write_text(
            "---\ntype: bot\nbot: helper\nowner: mia\nemail: acme.bot@acme.test\nbot_user: acme-bot\n---\n\n# Helper\n"
        )
        skill = self.company / "skills" / "add-bot"
        skill.mkdir(parents=True)
        shutil.copy(HELPER, skill / "git-credential-os-bot")
        shutil.copy(HELPER_LIB, skill / "lib.sh")
        (skill / "git-credential-os-bot").chmod(0o700)
        cfg = self.home / ".config" / "acme-os"
        cfg.mkdir(parents=True)
        (cfg / "me").write_text("mia\n")
        self.token_file = self.tmp / "bot-token"
        self.token_file.write_text(BOT_TOKEN + "\n")
        self.token_file.chmod(0o600)
        self.host_log = self.tmp / "host.log"
        self.host = self.tmp / "host.sh"
        self.host.write_text(
            f"""#!/bin/bash
set -euo pipefail
token_file={self.token_file}
log={self.host_log}
bot_token=$(tr -d '\r\n' < "$token_file")
cmd=${{1:-}}
for arg in "$@"; do
  if [ "$arg" = "$bot_token" ]; then
    printf '%s argv\n' "$cmd" >> "$log"
  fi
done
mark() {{
  local who=other
  if [ "${{FORGEJO_TOKEN:-}}" = "$bot_token" ]; then
    who=bot
  fi
  printf '%s %s\n' "$1" "$who" >> "$log"
}}
case "$cmd" in
  get-token)
    if [ "${{2:-}}" = "--bot" ] && [ "${{3:-}}" = "helper" ]; then
      printf 'get-token bot\n' >> "$log"
      printf '%s\n' "$bot_token"
      exit 0
    fi
    printf 'get-token other\n' >> "$log"
    exit 1
    ;;
  open-pr)
    mark open-pr
    [ "${{FORGEJO_TOKEN:-}}" = "$bot_token" ] || exit 1
    printf '%s\n' '{{"number":7,"url":"http://example.test/7"}}'
    ;;
  auto-merge)
    mark auto-merge
    [ "${{FORGEJO_TOKEN:-}}" = "$bot_token" ] || exit 1
    printf '%s\n' '{{"ok":true}}'
    ;;
  pr-status)
    mark pr-status
    [ "${{FORGEJO_TOKEN:-}}" = "$bot_token" ] || exit 1
    printf '%s\n' '{{"merged":true}}'
    ;;
  *) exit 1 ;;
esac
"""
        )
        self.host.chmod(0o700)
        self.env = git_env(os.environ.copy())
        self.env["HOME"] = str(self.home)
        self.env["XDG_CONFIG_HOME"] = str(self.home / ".config")
        self.env["OS_COMPANY_ROOT"] = str(self.company)
        self.env["OS_PROFILE"] = str(self.company / "company-profile.md")
        self.env["OS_HOST_SH"] = str(self.host)
        self.env["OS_PROFILE_SH"] = str(PROFILE)
        self.env["OS_HOST"] = "forgejo"
        self.env["OS_SECRET_SCAN"] = "bundled"
        self.env["OS_TEST_MODE"] = "1"
        self.env["OS_BOT_MERGE_WAIT"] = "5"
        self.env["FORGEJO_TOKEN"] = PERSON_TOKEN
        self.env.pop("GH_TOKEN", None)
        self.bare = self.seed()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def seed(self):
        bare = self.tmp / "origin.git"
        run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], env=self.env, check=True)
        run(["git", "init", "-q", "-b", "main", str(self.company)], env=self.env, check=True)
        run(["git", "-C", str(self.company), "remote", "add", "origin", str(bare)], env=self.env, check=True)
        (self.company / "README.md").write_text("seed\n")
        run(["git", "-C", str(self.company), "add", "README.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "seed"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        return bare

    def commit_on_bot(self, rel, text, message="Bot note"):
        run(
            ["git", "-C", str(self.company), "checkout", "-q", "-B", "sync/helper", "origin/main"],
            env=self.env,
            check=True,
        )
        dest = self.company / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text if text.endswith("\n") else text + "\n")
        run(["git", "-C", str(self.company), "add", "--", rel], env=self.env, check=True)
        run(
            [
                "git",
                "-C",
                str(self.company),
                "commit",
                "-q",
                "-m",
                message,
                "-m",
                "Run-Id: run-1\nBot-Owner: mia",
            ],
            env=self.env,
            check=True,
        )
        return run(
            ["git", "-C", str(self.company), "rev-parse", "HEAD"],
            env=self.env,
            check=True,
        ).stdout.strip()

    def push(self):
        env = self.env.copy()
        env["OS_BOT"] = "helper"
        env["OS_ROOT"] = str(self.company)
        return run(["bash", str(SYNC / "sync.sh"), "push"], env=env, cwd=self.company)

    def heads(self):
        return run(
            ["git", "--git-dir", str(self.bare), "for-each-ref", "--format=%(refname)", "refs/heads"],
            env=self.env,
            check=True,
        ).stdout

    def assert_no_token(self, result):
        blob = result.stdout + result.stderr
        self.assertNotIn(BOT_TOKEN, blob)
        self.assertNotIn(PERSON_TOKEN, blob)
        self.assertNotIn(SECRET, blob)
        if self.host_log.exists():
            self.assertNotIn(BOT_TOKEN, self.host_log.read_text())
            self.assertNotIn(PERSON_TOKEN, self.host_log.read_text())
            self.assertNotIn("argv", self.host_log.read_text())

    def test_push_keeps_the_run_commit_and_leaves_the_person_branch(self):
        sha = self.commit_on_bot("notes/bot.md", "the bot ran")
        result = self.push()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assert_no_token(result)
        remote = run(
            ["git", "--git-dir", str(self.bare), "rev-parse", "refs/heads/sync/helper"],
            env=self.env,
            check=True,
        ).stdout.strip()
        self.assertEqual(remote, sha)
        body = run(
            ["git", "--git-dir", str(self.bare), "log", "-1", "--format=%B", "refs/heads/sync/helper"],
            env=self.env,
            check=True,
        ).stdout
        self.assertIn("Bot note", body)
        self.assertIn("Run-Id: run-1", body)
        self.assertIn("Bot-Owner: mia", body)
        email = run(
            ["git", "--git-dir", str(self.bare), "log", "-1", "--format=%ae", "refs/heads/sync/helper"],
            env=self.env,
            check=True,
        ).stdout.strip()
        self.assertEqual(email, "acme.bot@acme.test")
        heads = self.heads()
        self.assertIn("refs/heads/sync/helper", heads)
        self.assertNotIn("refs/heads/sync/mia", heads)
        log = self.host_log.read_text()
        self.assertIn("get-token bot", log)
        self.assertIn("open-pr bot", log)
        self.assertIn("auto-merge bot", log)
        self.assertIn("pr-status bot", log)
        self.assertNotIn("other", log)

    def test_secret_in_the_range_pushes_nothing(self):
        self.commit_on_bot("notes/bot.md", f"token = {SECRET}")
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("secret scan", result.stderr)
        self.assert_no_token(result)
        heads = self.heads()
        self.assertNotIn("refs/heads/sync/helper", heads)
        self.assertNotIn("refs/heads/sync/mia", heads)
        self.assertNotIn("open-pr", self.host_log.read_text())

    def test_rules_path_pushes_nothing(self):
        self.commit_on_bot("docs/AGENTS.md", "a rules change\n")
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rules file: propose it with sync.sh propose", result.stderr)
        self.assert_no_token(result)
        heads = self.heads()
        self.assertNotIn("refs/heads/sync/helper", heads)
        self.assertNotIn("refs/heads/sync/mia", heads)
        self.assertNotIn("open-pr", self.host_log.read_text())

    def test_rename_out_of_skills_pushes_nothing(self):
        (self.company / "skills" / "old.md").write_text("rule\n")
        run(["git", "-C", str(self.company), "add", "skills/old.md"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "commit", "-q", "-m", "rules"], env=self.env, check=True)
        run(["git", "-C", str(self.company), "push", "-q", "origin", "main"], env=self.env, check=True)
        run(
            ["git", "-C", str(self.company), "checkout", "-q", "-B", "sync/helper", "origin/main"],
            env=self.env,
            check=True,
        )
        (self.company / "notes").mkdir()
        run(
            ["git", "-C", str(self.company), "mv", "skills/old.md", "notes/old.md"],
            env=self.env,
            check=True,
        )
        run(
            [
                "git",
                "-C",
                str(self.company),
                "commit",
                "-q",
                "-m",
                "Bot note",
                "-m",
                "Run-Id: run-1\nBot-Owner: mia",
            ],
            env=self.env,
            check=True,
        )
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rules file: propose it with sync.sh propose", result.stderr)
        self.assert_no_token(result)
        heads = self.heads()
        self.assertNotIn("refs/heads/sync/helper", heads)
        self.assertNotIn("refs/heads/sync/mia", heads)

    def test_rules_path_with_a_space_pushes_nothing(self):
        self.commit_on_bot("skills/a b.md", "a rules file\n")
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rules file: propose it with sync.sh propose", result.stderr)
        self.assert_no_token(result)
        heads = self.heads()
        self.assertNotIn("refs/heads/sync/helper", heads)
        self.assertNotIn("refs/heads/sync/mia", heads)

    def test_credential_in_the_remote_url_pushes_nothing(self):
        self.commit_on_bot("notes/bot.md", "the bot ran")
        run(
            [
                "git",
                "-C",
                str(self.company),
                "remote",
                "set-url",
                "origin",
                "http://user:secretpass@127.0.0.1:1/repo.git",
            ],
            env=self.env,
            check=True,
        )
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing a credential in the remote URL", result.stderr)
        self.assertNotIn("secretpass", result.stderr)
        self.assertNotIn("secretpass", result.stdout)
        heads = self.heads()
        self.assertNotIn("refs/heads/sync/helper", heads)

    def test_missing_bot_token_pushes_nothing(self):
        self.commit_on_bot("notes/bot.md", "the bot ran")
        self.host.write_text("#!/bin/bash\nexit 1\n")
        self.host.chmod(0o700)
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pull request", result.stderr)
        heads = self.heads()
        self.assertNotIn("refs/heads/sync/helper", heads)
        self.assertNotIn("refs/heads/sync/mia", heads)


if __name__ == "__main__":
    unittest.main()
