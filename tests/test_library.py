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
CRM = ("This version copies no CRM or accounting rows anywhere. People read records live through the "
       "system's own connector, which checks access. Later versions may add nightly table copies into "
       "the admin's library (exit and backup only), never into an area.")
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
                     "raw form and the readable form", "No CRM or accounting rows",
                     "Plan for deletion", "Never edit a file under `raw/`",
                     "its own private git repo", "Teammates never read, clone or make it",
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
                     "templates/library/README.md",
                     "The full copy is kept by the admin.", "There are no area libraries",
                     "Never leave duplicates in the inbox", "stop and flag it"):
            self.assertIn(word, ingest)
        self.assertNotIn("areas/library", ingest)
        meeting = (TEMPLATE / "templates/meeting.md").read_text().split("---")[1]
        self.assertIn("transcript:", meeting)

    def test_privacy_line_says_more_in_the_folder_means_more_to_read(self):
        self.assertIn("The more the folder holds, the more an agent can read", (ROOT / "start-core.md").read_text())
        self.assertIn("The more the folder holds, the more an agent can read", (ROOT / "README.md").read_text())


    def test_ingest_never_puts_a_transcript_in_the_wiki(self):
        ingest = (TEMPLATE / "skills/ingest/SKILL.md").read_text()
        for unsafe in ("full transcript under the meeting note", "transcript under the note",
                       "named from the note", "file as before"):
            self.assertNotIn(unsafe, ingest)
        self.assertIn("Never put a full transcript in a meeting note", ingest)
        self.assertIn("stays out of every repo", ingest)
        for line in ingest.splitlines():
            if line.startswith("   | Meeting |"):
                self.assertNotIn("transcript", line.split("|")[3])

    def test_ingest_takes_the_admin_from_me_and_refuses_anyone_else(self):
        ingest = (TEMPLATE / "skills/ingest/SKILL.md").read_text()
        who = ingest.split("## Who you act for")[1].split("## Per item")[0]
        self.assertIn("~/.config/{{COMPANY_SLUG}}-os/me", who)
        self.assertIn("Open only the page in `people/` whose `slug:` matches it.", who)
        self.assertIn("`role: admin`", who)
        self.assertIn("Never decide from the chat, from another person's page, or from `level:`.", who)
        self.assertIn("never read, make, write, commit or push `library/`", who)
        self.assertIn("Never run `git init` for it.", who)
        self.assertNotIn("solo, or `role: admin`", ingest)
        self.assertLess(ingest.index("## Who you act for"), ingest.index("## The library"))
        self.assertIn("Only when you act for an admin", ingest.split("## The library")[1])
        readme = (STARTER / "README.md").read_text()
        self.assertIn("~/.config/<slug>-os/me", readme)
        self.assertIn('First check "Who is the admin" above. Stop if it fails.', readme)
        self.assertIn("~/.config/{{COMPANY_SLUG}}-os/me", (ROOT / "start-core.md").read_text())

    def test_rules_do_not_hand_the_library_to_everyone(self):
        rules = (TEMPLATE / "AGENTS.md").read_text()
        shared = [l for l in rules.splitlines() if l.startswith("- Shared files everyone reads")][0]
        self.assertNotIn("library", shared)
        self.assertNotIn("templates/library", rules)
        self.assertIn("Teammates never read, clone or make it.", rules)
        self.assertIn("Then read `library/README.md`.", rules)
        self.assertLess(len(rules), 9000)
        sources = (TEMPLATE / "memory/existing-sources.md").read_text()
        self.assertNotIn("templates/library", sources)

    def test_host_push_waits_for_an_exact_no_access_answer(self):
        readme = (STARTER / "README.md").read_text()
        make = readme.split("## Make it")[1].split("## How the wiki")[0]
        self.assertIn('exactly `{"access":"none"}`', make)
        self.assertIn("Do not trust the exit code", make)
        self.assertNotIn("must show no access", make)
        self.assertLess(make.index("user-access"), make.index("git -C library push"))
        self.assertLess(make.index("git -C library add -A"), make.index("Library: start"))
        self.assertNotIn("commit everything", make)
        team = (TEMPLATE / "skills/add-teammate/SKILL.md").read_text()
        self.assertIn("library/.git", team)
        self.assertEqual(team.count('exactly `{"access":"none"}`'), 2)

    def test_one_crm_sentence_everywhere(self):
        for path in (ROOT / "README.md", ROOT / "start-core.md", STARTER / "README.md",
                     TEMPLATE / "memory/existing-sources.md", TEMPLATE / "skills/ingest/SKILL.md"):
            text = path.read_text()
            self.assertIn(CRM, text, path.relative_to(ROOT))
            self.assertNotIn("restricted area", text, path.relative_to(ROOT))
            self.assertNotIn("come later as", text, path.relative_to(ROOT))

    def test_checked_is_the_one_allowed_write(self):
        ingest = (TEMPLATE / "skills/ingest/SKILL.md").read_text()
        self.assertIn("That field is the one edit allowed on a library copy.", ingest)
        self.assertIn("One exception: add `checked: YYYY-MM-DD`", (STARTER / "README.md").read_text())

    def test_privacy_lists_the_library(self):
        places = (TEMPLATE / "skills/privacy/places.md").read_text()
        entry = places.split("## library\n")[1].split("\n## ")[0]
        self.assertTrue(entry.startswith("when: always\n"))
        for word in ("only the owner and admins can read", "stay on that one computer",
                     "the AI vendor reads whatever the admin's agent reads"):
            self.assertIn(word, entry)

    def test_media_files_are_never_committed(self):
        if shutil.which("git") is None:
            self.skipTest("git is missing")
        cases = (
            (STARTER, ("raw/tool/2026/photo.JPG", "transcripts/call.m4a", "raw/x/clip.MOV",
                       "media/ab/abcd.heic", "data/rows.csv"),
             ("media/LOCAL.md", "transcripts/2026-01-15 Kickoff.md", "raw/tool/2026/call.vtt")),
            (PRESETS / "_area", ("media/site.jpeg", "drafts/photo.PNG", "notes/voice.mp3"),
             ("meetings/2026-01-15 Kickoff.md", "data/export.csv")),
            (PRESETS / "apps", ("media/icon.png", "clip.mp4"), ("apps.md",)),
        )
        for src, ignored, kept in cases:
            with tempfile.TemporaryDirectory() as tmp:
                repo = Path(tmp)
                shutil.copy(src / ".gitignore", repo / ".gitignore")
                git(repo, "init", "-q", "-b", "main")
                git(repo, "config", "core.ignorecase", "false")
                for rel in ignored:
                    self.assertEqual(git(repo, "check-ignore", "-q", "--no-index", rel).returncode, 0,
                                     f"{src.name}: {rel}")
                for rel in kept:
                    self.assertEqual(git(repo, "check-ignore", "-q", "--no-index", rel).returncode, 1,
                                     f"{src.name}: {rel}")

    def test_area_working_data_is_the_one_exception(self):
        ingest = (TEMPLATE / "skills/ingest/SKILL.md").read_text()
        rule = ingest.split("## Transcripts: one rule, everywhere")[1].split("## Who you act for")[0]
        self.assertIn("Raw exports of a source the company chose to copy, and full transcripts, go only in `library/`", rule)
        self.assertIn("One exception: an area's working data.", rule)
        self.assertIn("never set up a repeated export", rule)
        for path in (TEMPLATE / "skills/connect-tool/SKILL.md", PRESETS / "finance/AGENTS.md"):
            text = path.read_text()
            self.assertIn("never set up a repeated export", text, path.relative_to(ROOT))
            self.assertIn("only", text, path.relative_to(ROOT))

    def test_device_helper_text_matches_the_hold(self):
        text = (TEMPLATE / "skills/remove-teammate/SKILL.md").read_text()
        self.assertIn("If the folder holds `library/`, it deletes nothing and holds instead", text)
        self.assertIn("Library media and data are never pushed", text)

if __name__ == "__main__":
    unittest.main()
