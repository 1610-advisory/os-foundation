"""The library: the admin's private repo keeps the company's own copy, by choice, per source.

Run: python3 -m unittest discover -s tests -v
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "template"
PRESETS = TEMPLATE / "skills/add-area/templates"
STARTER = TEMPLATE / "templates/library"
OLD_RULE = [
    "not a copy",
    "duplicate markdown",
    "bulk export",
    "bulk copies",
    "scheduled sync",
    "no automatic copying",
    "source of truth",
    "stays authoritative",
    "without duplicating",
]


def git(cwd, *args):
    env = os.environ.copy()
    env.update(GIT_AUTHOR_NAME="Ada Admin", GIT_AUTHOR_EMAIL="ada@example.com",
               GIT_COMMITTER_NAME="Ada Admin", GIT_COMMITTER_EMAIL="ada@example.com")
    return subprocess.run(["git", *args], cwd=cwd, env=env, capture_output=True, text=True)


class LibraryFolderTests(unittest.TestCase):
    def test_template_ships_the_library_starter(self):
        readme = (STARTER / "README.md").read_text()
        for word in ("Copy by choice, per source", "One writer per fact",
                     "raw form and the readable form", "rows, not Markdown",
                     "Plan for deletion", "Never edit a file under `raw/`",
                     "its own private git repo", "Teammates never clone it",
                     "The team reads the wiki", "business system", "CRM",
                     "Never make it on a teammate's computer", "git -C library init",
                     "create-repo", "--private", "user-access", "later version"):
            self.assertIn(word, readme)
        for key in ("source:", "captured:", "original:", "raw:", "people:", "access:", "retention:"):
            self.assertIn(key, readme)
        for path in ("media/LOCAL.md", "raw/.gitkeep", "transcripts/.gitkeep", ".gitignore"):
            self.assertTrue((STARTER / path).is_file(), path)
        ignore = (STARTER / ".gitignore").read_text().splitlines()
        for line in ("/media/*", "!/media/LOCAL.md", "/data/"):
            self.assertIn(line, ignore)

    def test_library_is_not_tracked_by_the_company_repo(self):
        self.assertFalse((TEMPLATE / "library").exists())
        self.assertIn("/library/", (TEMPLATE / ".gitignore").read_text().splitlines())
        for name in ("AGENTS.md", "CLAUDE.md", "skills", "inbox", "memory"):
            self.assertFalse((STARTER / name).exists(), name)

    def test_no_area_library_anywhere(self):
        self.assertFalse((PRESETS / "library").exists())
        self.assertNotIn("library", (TEMPLATE / "skills/add-area/SKILL.md").read_text())
        for gitignore in PRESETS.rglob(".gitignore"):
            self.assertNotIn("library", gitignore.read_text(), gitignore)
        files = [ROOT / "README.md", ROOT / "start-core.md", ROOT / "CHANGELOG.md"]
        files += [p for p in TEMPLATE.rglob("*") if p.is_file() and p.suffix in (".md", ".sh", "")]
        for path in files:
            if "skill-creator" in path.parts:
                continue
            text = path.read_text(errors="ignore")
            for phrase in ("areas/<area>/library", "area's own `library/`", "area's `library/`"):
                self.assertNotIn(phrase, text, path.relative_to(ROOT))

    def test_starter_makes_a_private_repo_that_keeps_text_only(self):
        if shutil.which("git") is None:
            self.skipTest("git is missing")
        with tempfile.TemporaryDirectory() as tmp:
            company = Path(tmp) / "acme-os"
            shutil.copytree(TEMPLATE, company, symlinks=True)
            self.assertEqual(git(company, "init", "-q", "-b", "main").returncode, 0)
            shutil.copytree(company / "templates/library", company / "library")
            lib = company / "library"
            self.assertEqual(git(lib, "init", "-q", "-b", "main").returncode, 0)
            (lib / "media/ab").mkdir(parents=True)
            (lib / "media/ab/abcd.jpg").write_bytes(b"photo")
            (lib / "media/ab/abce.m4a").write_bytes(b"audio")
            (lib / "data").mkdir()
            (lib / "data/ledger.parquet").write_bytes(b"rows")
            (lib / "raw/meeting-recorder/2026").mkdir(parents=True)
            (lib / "raw/meeting-recorder/2026/call.vtt").write_text("WEBVTT\n")
            (lib / "transcripts/2026-01-15 Kickoff.md").write_text("# Kickoff\n")
            self.assertEqual(git(lib, "add", "-A").returncode, 0)
            tracked = git(lib, "ls-files").stdout.splitlines()
            for path in ("README.md", "media/LOCAL.md", "raw/meeting-recorder/2026/call.vtt",
                         "transcripts/2026-01-15 Kickoff.md"):
                self.assertIn(path, tracked)
            for path in tracked:
                self.assertFalse(path.startswith("data/"), path)
                if path.startswith("media/"):
                    self.assertEqual(path, "media/LOCAL.md")
            self.assertEqual(git(company, "add", "-A").returncode, 0)
            root = git(company, "ls-files", "--stage").stdout
            self.assertNotIn("library", root.replace("templates/library", ""))

    def test_lint_skips_the_library(self):
        lint = TEMPLATE / "skills/lint/lint.sh"
        self.assertEqual(lint.read_bytes(), (TEMPLATE / ".github/scripts/tools/lint/lint.sh").read_bytes())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "skills").mkdir()
            for d in (".agents", ".claude"):
                (root / d).mkdir()
                (root / d / "skills").symlink_to("../skills")
            (root / "company-profile.md").write_text(
                "---\ntype: company-profile\ncompany_slug: acme\nlevel: solo\nswitches: []\n"
                "os_version: v9.9.9\n---\n\n# Acme Co\n")
            (root / "library/raw/tool/2026").mkdir(parents=True)
            (root / "library/raw/tool/2026/export.json").write_text('{"x": "{{not-ours}}"}\n')
            env = dict(os.environ, HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "home/.config"))
            proc = subprocess.run(["bash", str(lint), "--ci", "--root", str(root)],
                                  capture_output=True, text=True, env=env)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            (root / "notes.md").write_text("{{COMPANY_NAME}}\n")
            proc = subprocess.run(["bash", str(lint), "--ci", "--root", str(root)],
                                  capture_output=True, text=True, env=env)
            self.assertIn("placeholder: notes.md", proc.stdout)

    def test_existing_sources_has_mode_edited_and_retention(self):
        sources = (TEMPLATE / "memory/existing-sources.md").read_text()
        for field in ("**Mode:**", "`index`", "`copy`", "**Copy goes to:**", "**Refreshed:**",
                      "`manual`", "`nightly`", "**Edited in:**", "**Retention:**",
                      "**Access status:**", "library/raw/", "private"):
            self.assertIn(field, sources)

    def test_no_template_file_keeps_the_old_never_copy_rule(self):
        files = [ROOT / "README.md", ROOT / "start-core.md"]
        for path in TEMPLATE.rglob("*.md"):
            rel = path.relative_to(TEMPLATE).as_posix()
            # v0 files are the upgrade base: they must stay as v0 shipped them.
            if rel.startswith("skills/upgrade/v0/") or rel.startswith("skills/skill-creator/"):
                continue
            files.append(path)
        for path in files:
            text = path.read_text().lower()
            for phrase in OLD_RULE:
                self.assertNotIn(phrase, text, f"{path.relative_to(ROOT)}: {phrase}")

    def test_readme_tree_lists_library_beside_areas(self):
        readme = (ROOT / "README.md").read_text()
        tree = readme.split("## What you get")[1].split("```")[1]
        lines = tree.splitlines()
        lib = [i for i, line in enumerate(lines) if line.startswith("├── library/")]
        areas = [i for i, line in enumerate(lines) if line.startswith("└── areas/")]
        self.assertTrue(lib and areas and lib[0] < areas[0], tree)

    def test_ingest_and_meeting_template_point_at_the_library(self):
        ingest = (TEMPLATE / "skills/ingest/SKILL.md").read_text()
        for word in ("library/README.md", "raw/<source>/YYYY/", "transcripts/YYYY-MM-DD Title.md",
                     "transcript:", "media/LOCAL.md", "delete-audio-after-transcript",
                     "templates/library/README.md", "never make one",
                     "The full copy is kept by the admin.", "There are no area libraries",
                     "Never leave duplicates in the inbox", "stop and flag it"):
            self.assertIn(word, ingest)
        self.assertNotIn("areas/library", ingest)
        meeting = (TEMPLATE / "templates/meeting.md").read_text().split("---")[1]
        self.assertIn("transcript:", meeting)

    def test_privacy_line_says_more_in_the_folder_means_more_to_read(self):
        self.assertIn("The more the folder holds, the more an agent can read", (ROOT / "start-core.md").read_text())
        self.assertIn("The more the folder holds, the more an agent can read", (ROOT / "README.md").read_text())


if __name__ == "__main__":
    unittest.main()
