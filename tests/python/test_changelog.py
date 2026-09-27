"""Prüft den Generator mit echten, voneinander isolierten Git-Repositories."""

import os
import pty
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[2] / "src/python/changelog.py"


class ChangelogTests(unittest.TestCase):
    """Prüft Release-Zuordnung, Filter und den öffentlichen Einstieg."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="changelog test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.env = dict(
            os.environ,
            XDG_CACHE_HOME=str(self.root / "cache"),
            LANGUAGE="en",
        )
        self.git("init", "-b", "master")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")

    def git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", *args], cwd=self.repo, text=True, stderr=subprocess.PIPE
        ).strip()

    def commit(self, message: str) -> None:
        self.git("commit", "--allow-empty", "-m", message)

    def run_tool(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(TOOL), *args],
            cwd=self.repo,
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_releases_filter_merged_commits_and_messages(self) -> None:
        self.commit("feat(ui): First feature")
        self.git("tag", "-a", "v0.1.0+first", "-m", "First release")
        self.git("checkout", "-b", "feature")
        self.commit("fix(api): Merged fix")
        self.git("checkout", "master")
        self.git("merge", "--no-ff", "feature", "-m", "Merge feature")
        self.commit("docs(tickets): Internal review")
        (self.repo / "_tickets").mkdir()
        (self.repo / "_tickets/T-99.md").write_text("internal")
        self.git("add", "_tickets/T-99.md")
        self.git("commit", "-m", "docs(T-99): Hidden review")
        self.commit("chore: bump version to 0.2.0")
        self.git("tag", "-a", "v0.2.0+second", "-m", "Second release")
        self.commit("feat(ui): Not released")
        result = self.run_tool("--generate")
        self.assertEqual(result.returncode, 0, result.stderr)
        content = (self.repo / "CHANGELOG.md").read_text()
        self.assertIn("Second release", content)
        self.assertIn("Merged fix", content)
        self.assertEqual(content.count("First feature"), 1)
        self.assertNotIn("Internal review", content)
        self.assertNotIn("Hidden review", content)
        self.assertNotIn("bump version", content)
        self.assertNotIn("Not released", content)
        self.assertLess(content.index("v0.2.0"), content.index("v0.1.0"))
        self.assertEqual(self.run_tool("-g").returncode, 0)
        self.assertEqual(content, (self.repo / "CHANGELOG.md").read_text())

    def test_lightweight_tag_breaking_change_and_preview(self) -> None:
        self.commit("chore(api)!: Remove obsolete endpoint\n\nBREAKING CHANGE: Use /v2.")
        self.git("tag", "v1.0.0")
        result = self.run_tool("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Breaking changes", result.stdout)
        self.assertIn("Remove obsolete endpoint", result.stdout)
        self.assertFalse((self.repo / "CHANGELOG.md").exists())

    def test_help_and_bad_input_do_not_create_environment(self) -> None:
        for args in [(), ("-h",), ("--help",)]:
            result = self.run_tool(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--generate", result.stdout)
            self.assertIn("Examples:", result.stdout)
        result = self.run_tool("--generate", "--output", "missing/CHANGELOG.md")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "cache").exists())

    def test_no_tags_fails_without_writing(self) -> None:
        self.commit("feat: Initial")
        self.assertNotEqual(self.run_tool("-g").returncode, 0)
        self.assertFalse((self.repo / "CHANGELOG.md").exists())

    def test_publish_only_changelog_and_retries_push(self) -> None:
        remote = self.root / "remote.git"
        subprocess.run(["git", "init", "--bare", str(remote)], check=True, capture_output=True)
        self.git("remote", "add", "origin", str(remote))
        self.commit("feat: Initial")
        self.git("tag", "-a", "v0.1.0", "-m", "Initial release")
        self.git("push", "-u", "origin", "master")
        result = self.run_tool("--publish")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"), "CHANGELOG.md"
        )
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(self.run_tool("--publish").returncode, 0)
        self.assertEqual(head, self.git("rev-parse", "HEAD"))
        (self.repo / "CHANGELOG.md").write_text("previous generated content")
        self.assertEqual(self.run_tool("--publish").returncode, 0)
        self.assertEqual(head, self.git("rev-parse", "HEAD"))
        self.commit("feat: Another feature")
        self.git("tag", "v0.2.0")
        self.git("remote", "set-url", "origin", str(self.root / "unavailable.git"))
        failed = self.run_tool("--publish")
        self.assertNotEqual(failed.returncode, 0)
        published_head = self.git("rev-parse", "HEAD")
        self.git("remote", "set-url", "origin", str(remote))
        self.assertEqual(self.run_tool("--publish").returncode, 0)
        self.assertEqual(published_head, self.git("rev-parse", "HEAD"))
        self.assertEqual(published_head, self.git("rev-parse", "origin/master"))
        (self.repo / "foreign.txt").write_text("preserve")
        self.git("add", "foreign.txt")
        self.assertNotEqual(self.run_tool("--publish").returncode, 0)
        self.assertEqual(self.git("diff", "--cached", "--name-only"), "foreign.txt")

    def test_unreachable_and_side_branch_tags_are_ignored(self) -> None:
        self.commit("feat: Main feature")
        self.git("tag", "v0.1.0")
        self.git("checkout", "-b", "other")
        self.commit("feat: Not merged")
        self.git("tag", "v9.0.0")
        self.git("checkout", "master")
        result = self.run_tool("-n")
        self.assertNotIn("v9.0.0", result.stdout)
        self.assertNotIn("Not merged", result.stdout)
        self.git("merge", "--no-ff", "other", "-m", "Merge other")
        self.git("tag", "v0.2.0")
        result = self.run_tool("-n")
        self.assertNotIn("v9.0.0", result.stdout)
        self.assertEqual(result.stdout.count("Not merged"), 1)

    def test_german_catalog_and_output_symlink(self) -> None:
        self.env["LANGUAGE"] = "de"
        self.assertIn("Schreibt den Changelog", self.run_tool("-h").stdout)
        self.commit("feat: Initial")
        self.git("tag", "v0.1.0")
        outside = self.root / "keep.md"
        outside.write_text("preserve")
        (self.repo / "CHANGELOG.md").symlink_to(outside)
        self.assertNotEqual(self.run_tool("-g").returncode, 0)
        self.assertEqual(outside.read_text(), "preserve")

    def test_direct_start_leaves_environments_untouched(self) -> None:
        self.commit("feat: Initial")
        self.git("tag", "v0.1.0")
        project_venv = self.repo / ".venv"
        project_venv.mkdir()
        marker = project_venv / "keep"
        marker.write_text("unchanged")
        self.assertEqual(self.run_tool("-g").returncode, 0)
        self.assertEqual(self.run_tool("-g").returncode, 0)
        self.assertFalse((self.root / "cache").exists())
        self.assertEqual(marker.read_text(), "unchanged")

    def terminal(self, *args: str) -> tuple[int, str]:
        """Prüft die echte Ausgabe am Pseudoterminal statt nur Farbkonstanten."""
        master, slave = pty.openpty()
        process = subprocess.Popen(
            [sys.executable, str(TOOL), *args],
            cwd=self.repo,
            env=self.env,
            stdout=slave,
            stderr=slave,
        )
        os.close(slave)
        chunks = []
        try:
            while True:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                chunks.append(chunk)
        finally:
            os.close(master)
        return process.wait(), b"".join(chunks).decode()

    def test_terminal_colors_and_no_color(self) -> None:
        self.env["TERM"] = "xterm-256color"
        self.env.pop("NO_COLOR", None)
        self.commit("feat: Initial")
        self.git("tag", "v0.1.0")
        status, help_output = self.terminal("-h")
        self.assertEqual(status, 0, help_output)
        self.assertIn("\x1b[38;5;45m-g | --generate", help_output)
        self.assertIn("\x1b[38;5;11mOUTPUT", help_output)
        self.assertIn("\x1b[38;5;10m  python3", help_output)
        status, output = self.terminal("-g")
        self.assertEqual(status, 0, output)
        self.assertIn("\x1b[38;5;10m✓", output)
        status, output = self.terminal("--unknown")
        self.assertEqual(status, 2)
        self.assertIn("\x1b[38;5;196m✗", output)
        self.assertNotIn("Traceback", output)
        self.env["NO_COLOR"] = "1"
        self.assertNotIn("\x1b[", self.terminal("-g")[1])
        self.assertNotIn("\x1b[", self.terminal("--unknown")[1])
        self.assertNotIn("\x1b[", self.run_tool("-g").stdout)

    def test_native_help_columns_and_no_side_effects(self) -> None:
        self.env["NO_COLOR"] = "1"
        output = self.run_tool("-h").stdout
        lines = [line for line in output.splitlines() if " | --" in line]
        self.assertEqual(len(lines), 5)
        self.assertEqual({line.index("|") for line in lines}, {5})
        self.assertEqual({line.index("--") for line in lines}, {7})
        self.assertIn("-o | --output OUTPUT", output)
        descriptions = [
            "Write the changelog",
            "Print a preview",
            "Write, commit",
            "Output file",
            "Show this help",
        ]
        self.assertEqual(
            {lines[index].index(description) for index, description in enumerate(descriptions)},
            {36},
        )
        self.assertRegex(lines[3], r"OUTPUT {10,}Output file")
        self.assertIn("python3 changelog.py --dry-run", output)
        self.assertNotRegex(output, re.compile(r"\x1b\["))
        self.assertFalse((self.root / "cache").exists())
