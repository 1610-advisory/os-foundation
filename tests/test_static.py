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

    def test_hidden_and_plain_slug_entries_are_not_terms(self):
        hidden = "." + "DS_Store"
        plain = "notes.txt"
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir = tmp / "slugs"
            slug_dir.mkdir()
            (slug_dir / hidden).write_text("x\n")
            (slug_dir / plain).write_text("x\n")
            (slug_dir / "zebra-co").mkdir()
            real = slug_dir / "real-co"
            real.mkdir()
            (slug_dir / "link-co").symlink_to(real, target_is_directory=True)
            terms = tmp / "terms.txt"
            terms.write_text("\n")
            hit = tmp / "hit.txt"
            hit.write_text(hidden + " and " + plain + "\n")
            skipped = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
            linked = tmp / "link.txt"
            linked.write_text("see link-co today\n")
            kept = run(
                "pii-check.sh",
                ["--paths", str(linked)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(skipped.returncode, 0, skipped.stdout + skipped.stderr)
        self.assertEqual(skipped.stdout.strip(), "pii-check: OK")
        self.assertEqual(kept.returncode, 1, kept.stdout + kept.stderr)
        self.assertIn(":term", kept.stdout)
        self.assertNotIn("link-co", kept.stdout)

    def test_file_name_hit(self):
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "zebra-co.txt"
            hit.write_text("clean text\n")
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("term 1\n", result.stdout)
        self.assertIn(str(hit) + ":name", result.stdout)
        self.assertNotIn("clean text", result.stdout)
        self.assertNotIn(":term", result.stdout)

    def test_commit_message_hit(self):
        env = git_env()
        message = "note about zebra-co today"
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            note = tmp / "note.md"
            note.write_text("clean\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            note.write_text("still clean\n")
            commit_all(tmp, env, message)
            short = subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("commit:" + short + ":term", result.stdout)
        self.assertNotIn(message, result.stdout)
        self.assertNotIn(message, result.stderr)
        self.assertNotIn("zebra-co", result.stdout)
        self.assertNotIn("zebra-co", result.stderr)

    def test_noreply_and_test_domains_are_not_counted(self):
        text = "\n".join([
            "Co-Authored-By: Helper <noreply@acme.invalid>",
            "Noreply@other.invalid",
            "owner@foo.test",
            "owner@bar.baz.test",
            "noreply@foo.test",
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
        self.assertNotIn("acme.invalid", result.stdout)
        self.assertNotIn("acme.invalid", result.stderr)

    def test_other_addresses_are_still_counted(self):
        bad = "owner@" + "acme.invalid"
        hidden = "notnoreply@" + "acme.invalid"
        testing = "owner@" + "foo.testing"
        lookalike = "owner@" + "example.com.invalid"
        similar = "\n".join([
            "noreply@" + "acme.invalid " + bad,
            hidden,
            testing,
            lookalike,
            "",
        ])
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            hit = tmp / "hit.txt"
            hit.write_text(similar)
            result = run(
                "pii-check.sh",
                ["--paths", str(hit)],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("email 4\n", result.stdout)
        self.assertNotIn(bad, result.stdout)
        self.assertNotIn(bad, result.stderr)
        self.assertNotIn(hidden, result.stdout)
        self.assertNotIn(testing, result.stdout)
        self.assertNotIn(lookalike, result.stdout)

    def test_added_binary_is_a_finding(self):
        env = git_env()
        marker = "/" + "Users" + "/" + "zebra" + "/secret"
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            (tmp / "note.md").write_text("clean\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            (tmp / "secret.bin").write_bytes(b"prefix\x00" + marker.encode() + b"\x00suffix")
            commit_all(tmp, env, "add binary")
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("binary 1\n", result.stdout)
        self.assertIn("binary: secret.bin", result.stdout)
        self.assertNotIn(marker, result.stdout)
        self.assertNotIn(marker, result.stderr)
        self.assertNotIn("prefix", result.stdout)
        self.assertNotIn("suffix", result.stdout)

    def test_allowed_images_are_not_binary_findings(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            (tmp / "note.md").write_text("clean\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            (tmp / "docs").mkdir()
            (tmp / "assets").mkdir()
            (tmp / "template" / "docs").mkdir(parents=True)
            (tmp / "docs" / "logo.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00")
            (tmp / "assets" / "pic.jpg").write_bytes(b"\xff\xd8\xff\x00")
            (tmp / "assets" / "mark.jpeg").write_bytes(b"\xff\xd8\xff\x00")
            (tmp / "docs" / "anim.gif").write_bytes(b"GIF89a\x00\x00")
            (tmp / "docs" / "photo.webp").write_bytes(b"RIFF\x00WEBP")
            (tmp / "docs" / "diagram.svg").write_text("<svg></svg>\n")
            (tmp / "template" / "docs" / "logo.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00")
            commit_all(tmp, env, "add images")
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "pii-check: OK")
        self.assertNotIn("binary:", result.stdout)

    def test_image_outside_docs_or_assets_is_a_finding(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            (tmp / "note.md").write_text("clean\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            (tmp / "logo.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00")
            (tmp / "documentation").mkdir()
            (tmp / "documentation" / "pic.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00")
            commit_all(tmp, env, "add images")
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("binary: logo.png", result.stdout)
        self.assertIn("binary: documentation/pic.png", result.stdout)
        self.assertIn("binary 2\n", result.stdout)

    def test_bytecode_is_always_a_finding(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            (tmp / "note.md").write_text("clean\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            cache = tmp / "docs" / "__pycache__"
            cache.mkdir(parents=True)
            (cache / "mod.pyc").write_bytes(b"\x00pyc")
            (tmp / "docs" / "cache.pyc").write_text("not really bytecode\n")
            (tmp / "pkg" / "__pycache__").mkdir(parents=True)
            (tmp / "pkg" / "__pycache__" / "note.txt").write_text("plain\n")
            commit_all(tmp, env, "add bytecode")
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("binary: docs/__pycache__/mod.pyc", result.stdout)
        self.assertIn("binary: docs/cache.pyc", result.stdout)
        self.assertIn("binary: pkg/__pycache__/note.txt", result.stdout)
        self.assertIn("binary 3\n", result.stdout)
        self.assertNotIn("not really bytecode", result.stdout)

    def test_untracked_binary_is_a_finding(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            (tmp / "note.md").write_text("clean\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            (tmp / "loose.bin").write_bytes(b"loose\x00bytes")
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("binary: loose.bin", result.stdout)
        self.assertNotIn("loose", result.stdout.split("binary: loose.bin", 1)[-1])
        self.assertNotIn("bytes", result.stdout)

    def test_changed_existing_binary_is_not_an_added_finding(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            (tmp / "note.md").write_text("clean\n")
            (tmp / "old.bin").write_bytes(b"old\x00")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            (tmp / "old.bin").write_bytes(b"new\x00value")
            commit_all(tmp, env, "change binary")
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "pii-check: OK")
        self.assertNotIn("binary:", result.stdout)

    def test_binary_added_then_deleted_is_a_finding(self):
        env = git_env()
        marker = "/" + "Users" + "/" + "zebra" + "/secret"
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            slug_dir, terms = slug_fixture(tmp)
            (tmp / "note.md").write_text("clean\n")
            init_repo(tmp, env)
            commit_all(tmp, env, "base")
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            (tmp / "docs").mkdir()
            (tmp / "docs" / "mod.pyc").write_bytes(b"\x00" + marker.encode())
            (tmp / "docs" / "logo.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00")
            (tmp / "secret.bin").write_bytes(b"bin\x00" + marker.encode())
            commit_all(tmp, env, "add files")
            short = subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"], cwd=tmp, text=True, env=env
            ).strip()
            (tmp / "docs" / "mod.pyc").unlink()
            (tmp / "docs" / "logo.png").unlink()
            (tmp / "secret.bin").unlink()
            commit_all(tmp, env, "drop files")
            result = run(
                "pii-check.sh",
                ["--root", str(tmp), "--base", base],
                env=pii_env(slug_dir, terms),
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("binary: docs/mod.pyc (commit " + short + ")", result.stdout)
        self.assertIn("binary: secret.bin (commit " + short + ")", result.stdout)
        self.assertNotIn("logo.png", result.stdout)
        self.assertIn("binary 2\n", result.stdout)
        self.assertNotIn(marker, result.stdout)
        self.assertNotIn(marker, result.stderr)


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

    def test_skips_directory_links(self):
        env = git_env()
        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            (tmp / "template").mkdir()
            (tmp / "template" / "real").mkdir()
            (tmp / "template" / "skills").symlink_to("real", target_is_directory=True)
            init_repo(tmp, env)
            result = run("shellcheck.sh", ["--root", str(tmp)], env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Is a directory", result.stderr)
        self.assertNotIn("read error", result.stderr)
        self.assertEqual(result.stdout.strip(), "OK 0 files")


if __name__ == "__main__":
    unittest.main()
