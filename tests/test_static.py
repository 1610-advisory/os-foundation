"""Unit tests for the static checks.

Fixtures are built in a temp directory. Names in fixtures are made up.
Run: python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "tests" / "static"


def run(script, args=None, env=None, cwd=None):
    return subprocess.run(
        ["bash", str(STATIC / script), *(args or [])],
        cwd=cwd or ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


def git_env(base=None):
    env = os.environ.copy() if base is None else base.copy()
    env["GIT_AUTHOR_NAME"] = "Ada Admin"
    env["GIT_AUTHOR_EMAIL"] = "ada@example.com"
    env["GIT_COMMITTER_NAME"] = "Ada Admin"
    env["GIT_COMMITTER_EMAIL"] = "ada@example.com"
    return env


def init_repo(path, env):
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=path, check=True, env=env)
    subprocess.run(["git", "add", "-A"], cwd=path, check=True, env=env)


def commit_all(path, env, message):
    subprocess.run(["git", "add", "-A"], cwd=path, check=True, env=env)
    subprocess.run(["git", "commit", "-q", "-m", message], cwd=path, check=True, env=env)


def clear_pii(env):
    for key in ("PII_SLUG_DIR", "PII_TERMS_FILE", "PII_ALLOW"):
        env.pop(key, None)
    return env


def pii_env(slug_dir, terms_file, allow=""):
    env = clear_pii(git_env())
    env["PII_SLUG_DIR"] = str(slug_dir)
    env["PII_TERMS_FILE"] = str(terms_file)
    env["PII_ALLOW"] = allow
    return env


def slug_fixture(tmp):
    slug_dir = tmp / "slugs"
    slug_dir.mkdir()
    (slug_dir / "zebra-co").mkdir()
    terms = tmp / "terms.txt"
    terms.write_text("quill-bird\n")
    return slug_dir, terms


class RulesSizeTests(unittest.TestCase):
    def test_oversize_agents_fails(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            init_repo(tmp, env)
            (tmp / "AGENTS.md").write_text("a" * 10001)
            subprocess.run(["git", "add", "-A"], cwd=tmp, check=True, env=env)
            result = run("rules-size.sh", ["--root", str(tmp)], env=env)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("AGENTS.md 10001", result.stdout)
        self.assertNotIn("OK ", result.stdout)

    def test_under_limit_passes(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            init_repo(tmp, env)
            (tmp / "AGENTS.md").write_text("a" * 9999)
            subprocess.run(["git", "add", "-A"], cwd=tmp, check=True, env=env)
            result = run("rules-size.sh", ["--root", str(tmp)], env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "OK 1 files")

    def test_exact_limit_fails(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            init_repo(tmp, env)
            (tmp / "CLAUDE.md").write_text("b" * 10000)
            subprocess.run(["git", "add", "-A"], cwd=tmp, check=True, env=env)
            result = run("rules-size.sh", ["--root", str(tmp)], env=env)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("CLAUDE.md 10000", result.stdout)

    def test_repo_rules_are_under_limit(self):
        result = run("rules-size.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout.strip(), r"^OK [1-9][0-9]* files$")


class PlaceholderTests(unittest.TestCase):
    def test_unknown_placeholder_fails(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            (tmp / "template").mkdir()
            (tmp / "template" / "note.md").write_text("Hello {{ZEBRA_ONLY}} and {{COMPANY_NAME}}\n")
            (tmp / "start-core.md").write_text("Use {{COMPANY_OS}}\n")
            allow = tmp / "allow.txt"
            allow.write_text("COMPANY_NAME\nCOMPANY_OS\n")
            init_repo(tmp, env)
            result = run(
                "placeholders.sh",
                ["--root", str(tmp), "--allow", str(allow)],
                env=env,
            )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("template/note.md:1:{{ZEBRA_ONLY}}", result.stdout)
        self.assertNotIn("{{COMPANY_NAME}}", result.stdout)
        self.assertNotIn("{{COMPANY_OS}}", result.stdout)

    def test_built_finds_leftover_outside_skills(self):
        with tempfile.TemporaryDirectory() as raw:
            built = Path(raw) / "company"
            (built / "skills").mkdir(parents=True)
            (built / "skills" / "note.md").write_text("{{COMPANY_NAME}} stays\n")
            (built / ".git").mkdir()
            (built / ".git" / "config").write_text("{{COMPANY_NAME}}\n")
            (built / "AGENTS.md").write_text("Left {{COMPANY_NAME}} here\n")
            result = run("placeholders.sh", ["--built", str(built)])
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("AGENTS.md:1:{{COMPANY_NAME}}", result.stdout)
        self.assertNotIn("skills/", result.stdout)
        self.assertNotIn(".git/", result.stdout)

    def test_built_clean_folder_passes(self):
        with tempfile.TemporaryDirectory() as raw:
            built = Path(raw) / "company"
            built.mkdir()
            (built / "AGENTS.md").write_text("Acme Co\n")
            result = run("placeholders.sh", ["--built", str(built)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "OK")

    def test_repo_placeholders_are_known(self):
        result = run("placeholders.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "OK")


class PiiTests(unittest.TestCase):
    def test_slug_hit(self):
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text("zebra-company is fine\nWork with Zebra-Co today.\n")
            result = run(
                "pii-check.sh",
                ["--allow-unconfigured", "--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("term 1\n", result.stdout)
        self.assertIn(":term", result.stdout)
        self.assertNotIn("zebra-co", result.stdout.lower())
        self.assertNotIn("Zebra-Co", result.stdout)
        self.assertNotIn(str(slug_dir), result.stdout)
        self.assertNotIn(str(terms), result.stdout)

    def test_path_hit(self):
        home = "/" + "Users" + "/" + "zebra" + "/" + "notes"
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text("see " + home + "\n")
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("path 1\n", result.stdout)
        self.assertIn(":path", result.stdout)
        self.assertNotIn(home, result.stdout)
        self.assertNotIn(home, result.stderr)

    def test_token_hit(self):
        secret = "".join(["gh", "p_", "ZZZZNOTASECRET1234567890"])
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text("value " + secret + "\n")
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("token 1\n", result.stdout)
        self.assertIn(":token", result.stdout)
        self.assertNotIn(secret, result.stdout)
        self.assertNotIn(secret, result.stderr)
        self.assertNotIn("".join(["gh", "p_"]), result.stdout)

    def test_allowed_email_passes(self):
        text = "\n".join([
            "owner@example.com",
            "owner@example.org",
            "owner@example.net",
            "bot@users.noreply.github.com",
            "ada@acme.test",
            "ada@mail.acme.test",
            "ada@foo.example",
            "",
        ])
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text(text)
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "pii-check: OK")

    def test_disallowed_email_fails(self):
        bad = "owner@" + "acme.invalid"
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text(bad + "\n")
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("email 1\n", result.stdout)
        self.assertIn(":email", result.stdout)
        self.assertNotIn(bad, result.stdout)
        self.assertNotIn(bad, result.stderr)

    def test_allowed_term_is_skipped(self):
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text("zebra-co is allowed here\n")
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms, allow="Zebra-Co"),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "pii-check: OK")

    def test_unconfigured_exits_3(self):
        env = clear_pii(os.environ.copy())
        with tempfile.TemporaryDirectory() as raw:
            hit = Path(raw) / "hit.txt"
            hit.write_text("nothing here\n")
            result = run("pii-check.sh", ["--paths", str(hit)], env=env)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "pii-check: NOT CONFIGURED")

    def test_allow_unconfigured_runs_generic_checks(self):
        home = "/" + "home" + "/" + "zebra" + "/" + "notes"
        env = clear_pii(os.environ.copy())
        with tempfile.TemporaryDirectory() as raw:
            hit = Path(raw) / "hit.txt"
            hit.write_text("see " + home + "\n")
            result = run(
                "pii-check.sh",
                ["--allow-unconfigured", "--paths", str(hit)],
                env=env,
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(":path", result.stdout)
        self.assertNotIn("NOT CONFIGURED", result.stdout)
        self.assertNotIn(home, result.stdout)

    def test_allowed_path_forms_pass(self):
        lines = [
            "/" + "Users" + "/" + "<name>" + "/" + "notes",
            "$HOME/notes",
            "${HOME}/notes",
            "/" + "home" + "/" + "runner" + "/" + "work",
        ]
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text("\n".join(lines) + "\n")
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "pii-check: OK")

    def test_substring_term_hits(self):
        marker = "~/" + "secret-place"
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir = tmp / "slugs"
            slug_dir.mkdir()
            terms = tmp / "terms.txt"
            terms.write_text(marker + "\n")
            hit = tmp / "hit.txt"
            hit.write_text("see " + marker + "/notes now\n")
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(":term", result.stdout)
        self.assertNotIn(marker, result.stdout)
        self.assertNotIn(marker, result.stderr)

    def test_base_flags_added_lines_only(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            note = tmp / "note.md"
            note.write_text("zebra-co was already here\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=tmp, text=True).strip()
            note.write_text("zebra-co was already here\nclean line\n")
            commit_all(tmp, env, "add clean")
            clean = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
            note.write_text("zebra-co was already here\nclean line\nzebra-co added\n")
            commit_all(tmp, env, "add term")
            dirty = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(clean.returncode, 0, clean.stdout + clean.stderr)
        self.assertEqual(clean.stdout.strip(), "pii-check: OK")
        self.assertEqual(dirty.returncode, 1, dirty.stdout + dirty.stderr)
        self.assertIn(":term", dirty.stdout)
        self.assertNotIn("zebra-co", dirty.stdout.lower())


class ShellcheckTests(unittest.TestCase):
    def test_no_scripts_passes(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            init_repo(tmp, env)
            result = run("shellcheck.sh", ["--root", str(tmp)], env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "OK 0 files")

    def test_bad_script_fails(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            init_repo(tmp, env)
            (tmp / "bad.sh").write_text("#!/bin/bash\necho $not_quoted\n")
            subprocess.run(["git", "add", "-A"], cwd=tmp, check=True, env=env)
            result = run("shellcheck.sh", ["--root", str(tmp)], env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("OK ", result.stdout)

    def test_repo_scripts_pass(self):
        result = run("shellcheck.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout.strip(), r"^OK [1-9][0-9]* files$")


if __name__ == "__main__":
    unittest.main()
