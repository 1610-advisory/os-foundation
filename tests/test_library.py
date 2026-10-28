"""The library: the company folder keeps its own copy, by choice, per source.

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
IGNORE_LINES = ["/library/media/*", "!/library/media/LOCAL.md", "/library/data/"]
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
    def test_root_template_ships_the_library(self):
        readme = (TEMPLATE / "library/README.md").read_text()
        for word in ("Copy by choice, per source", "One writer per fact",
                     "raw form and the readable form", "rows, not Markdown",
                     "Plan for deletion", "Never edit a file under `raw/`",
                     "areas/<area>/library/", "later version"):
            self.assertIn(word, readme)
        for key in ("source:", "captured:", "original:", "raw:", "people:", "access:", "retention:"):
            self.assertIn(key, readme)
        self.assertTrue((TEMPLATE / "library/media/LOCAL.md").is_file())
        self.assertTrue((TEMPLATE / "library/raw/.gitkeep").is_file())
        self.assertTrue((TEMPLATE / "library/transcripts/.gitkeep").is_file())

    def test_library_is_a_plain_folder(self):
        for name in ("AGENTS.md", "CLAUDE.md", "skills", "inbox", "memory"):
            self.assertFalse((TEMPLATE / "library" / name).exists(), name)

    def test_no_library_area_preset(self):
        self.assertFalse((PRESETS / "library").exists())
        add_area = (TEMPLATE / "skills/add-area/SKILL.md").read_text()
        self.assertNotIn("library", add_area)

    def test_ignore_lines_in_root_and_area_presets(self):
        for path in (TEMPLATE / ".gitignore", PRESETS / "_area/.gitignore", PRESETS / "apps/.gitignore"):
            lines = path.read_text().splitlines()
            for line in IGNORE_LINES:
                self.assertIn(line, lines, f"{path}: {line}")

    def test_git_keeps_text_and_ignores_media_and_data(self):
        if shutil.which("git") is None:
            self.skipTest("git is missing")
        with tempfile.TemporaryDirectory() as tmp:
            company = Path(tmp) / "acme-os"
            shutil.copytree(TEMPLATE, company, symlinks=True)
            area = company / "areas/finance"
            shutil.copytree(PRESETS / "_area", area, symlinks=True)
            shutil.copy(PRESETS / "_area/.gitignore", area / ".gitignore")
            for repo in (company, area):
                (repo / "library/media/ab").mkdir(parents=True, exist_ok=True)
                (repo / "library/media/ab/abcd.jpg").write_bytes(b"photo")
                (repo / "library/media/ab/abce.m4a").write_bytes(b"audio")
                (repo / "library/data").mkdir(parents=True, exist_ok=True)
                (repo / "library/data/ledger.parquet").write_bytes(b"rows")
                (repo / "library/media/LOCAL.md").write_text("# Media\n")
                (repo / "library/raw/meeting-recorder/2026").mkdir(parents=True, exist_ok=True)
                (repo / "library/raw/meeting-recorder/2026/call.vtt").write_text("WEBVTT\n")
                (repo / "library/transcripts").mkdir(parents=True, exist_ok=True)
                (repo / "library/transcripts/2026-01-15 Kickoff.md").write_text("# Kickoff\n")
                self.assertEqual(git(repo, "init", "-q", "-b", "main").returncode, 0)
                self.assertEqual(git(repo, "add", "-A").returncode, 0)
                tracked = git(repo, "ls-files").stdout.splitlines()
                self.assertIn("library/media/LOCAL.md", tracked, repo)
                self.assertIn("library/raw/meeting-recorder/2026/call.vtt", tracked)
                self.assertIn("library/transcripts/2026-01-15 Kickoff.md", tracked)
                for path in tracked:
                    self.assertFalse(path.startswith("library/data/"), path)
                    if path.startswith("library/media/"):
                        self.assertEqual(path, "library/media/LOCAL.md")
            self.assertNotIn("areas/finance/library/media/LOCAL.md",
                             git(company, "ls-files").stdout.splitlines())

    def test_existing_sources_has_mode_edited_and_retention(self):
        sources = (TEMPLATE / "memory/existing-sources.md").read_text()
        for field in ("**Mode:**", "`index`", "`copy`", "**Copy goes to:**", "**Refreshed:**",
                      "`manual`", "`nightly`", "**Edited in:**", "**Retention:**",
                      "**Access status:**", "library/raw/"):
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
                     "areas/<area>/library/", "Never leave duplicates in the inbox",
                     "stop and flag it"):
            self.assertIn(word, ingest)
        self.assertNotIn("areas/library", ingest)
        meeting = (TEMPLATE / "templates/meeting.md").read_text().split("---")[1]
        self.assertIn("transcript:", meeting)

    def test_privacy_line_says_more_in_the_folder_means_more_to_read(self):
        self.assertIn("The more the folder holds, the more an agent can read", (ROOT / "start-core.md").read_text())
        self.assertIn("The more the folder holds, the more an agent can read", (ROOT / "README.md").read_text())


if __name__ == "__main__":
    unittest.main()
