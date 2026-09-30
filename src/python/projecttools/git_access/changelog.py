"""Git-Zugriff für den Changelog; keine Shell-Auswertung von Commit-Texten."""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

RELEASE_TAG = re.compile(r"^v?\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?$")


@dataclass(frozen=True)
class Release:
    """Ein erreichbarer Release-Tag auf der Hauptlinie des aktuellen Branches."""

    tag: str
    commit: str
    date: str
    message: str


class GitRepository:
    """Bündelt die Git-Prozesse; Tests verwenden echte temporäre Repositories."""

    def __init__(self, directory: Path) -> None:
        self.directory = directory

    def run(self, *arguments: str) -> str:
        """Führt Git aus und reicht Fehler samt Exit-Code an den Aufrufer weiter."""
        result = subprocess.run(
            ["git", *arguments],
            cwd=self.directory,
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
            check=True,
        )
        return result.stdout.strip()

    def releases(self) -> list[Release]:
        """Liest Tags in historischer Reihenfolge; fremde Branch-Tags entfallen."""
        history = self.run("rev-list", "--first-parent", "HEAD").splitlines()
        order = {commit: index for index, commit in enumerate(history)}
        releases = []
        for tag in self.run("tag", "--merged", "HEAD").splitlines():
            if not RELEASE_TAG.fullmatch(tag):
                continue
            commit = self.run("rev-parse", f"refs/tags/{tag}^{{commit}}")
            if commit not in order:
                continue
            reference = f"refs/tags/{tag}"
            kind = self.run("cat-file", "-t", reference)
            message = (
                self.run("for-each-ref", "--format=%(contents)", reference) if kind == "tag" else ""
            )
            date = self.run("show", "-s", "--format=%cs", commit)
            releases.append(Release(tag, commit, date, message))
        return sorted(releases, key=lambda release: (-order[release.commit], release.tag))

    def commits(self, previous: str | None, current: str) -> list[tuple[str, str, str]]:
        """Liest jeden Nicht-Merge-Commit im Release-Bereich genau einmal."""
        revision = f"{previous}..{current}" if previous else current
        records = self.run(
            "log", "--reverse", "--no-merges", "--format=%H%x00%s%x00%b%x00", revision, "--"
        ).split("\0")
        entries = []
        for index in range(0, len(records) - 2, 3):
            commit = records[index].strip()
            paths = self.run(
                "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", commit
            ).splitlines()
            if paths and all(self.is_internal_path(path) for path in paths):
                continue
            entries.append((commit, records[index + 1], records[index + 2]))
        return entries

    @staticmethod
    def is_internal_path(path: str) -> bool:
        """Erkennt reine Agenten-/Ticketpflege auch bei abweichenden Commit-Scopes."""
        return path.startswith(("_tickets/", ".agents/", ".claude/", ".codex/")) or path in {
            "AGENTS.md",
            "CLAUDE.md",
            "CHANGELOG.md",
        }

    def publish(self, output: Path) -> None:
        """Committet nur den Changelog und pusht auch beim Wiederholungsaufruf."""
        relative = str(output.relative_to(self.directory))
        self.run("add", "--", relative)
        if self.run("diff", "--cached", "--name-only", "--", relative):
            self.run("commit", "-m", "docs(changelog): update release history", "--", relative)
        self.run("push")
