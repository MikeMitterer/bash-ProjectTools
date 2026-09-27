#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# changelog.py — Git-Releases als Markdown aufbereiten
#
# Aufruf: python3 src/python/changelog.py -g | -n | -p
# Standardbibliothek; Git-Zugriff liegt in git_access/changelog.py.
# ------------------------------------------------------------------------------
from __future__ import annotations

import argparse
import gettext
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from colors import HelpFormatter, Theme
from colors import styled as styled
from git_access.changelog import GitRepository

_ = gettext.translation(
    "changelog", localedir=Path(__file__).parent / "locales", fallback=True
).gettext
SUBJECT = re.compile(r"^(\w+)(?:\(([^)]+)\))?(!)?:\s*(.+)$")


class ChangelogError(Exception):
    """Erwarteter Eingabe- oder Zustandsfehler mit übersetzbarer Meldung."""


def report_error(message: str) -> None:
    """Meldet Eingabe- und Ausführungsfehler einheitlich auf stderr."""
    print(
        Theme().indent_group + Theme().style("✗ " + message, "DANGER", sys.stderr),
        file=sys.stderr,
    )


class ScriptArgumentParser(argparse.ArgumentParser):
    """Färbt die native Optionsliste nach dem Layout, ohne zweite Optionsdefinition."""

    def format_help(self) -> str:
        return "\n" + super().format_help() + "\n"

    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        report_error(message)
        self.exit(2)


def parse_args(arguments: list[str]) -> argparse.Namespace:
    """Liest die einzige Optionsdefinition für Bash und Python."""
    parser = ScriptArgumentParser(
        description=_("Generate a changelog from release tags."),
        formatter_class=HelpFormatter,
        add_help=False,
    )
    parser.color = False  # Farbe erst nach dem nativen Spaltenlayout anwenden.
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument(
        "-g",
        "--generate",
        action="store_true",
        help=_("Write the changelog without committing."),
    )
    action.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help=_("Print a preview without writing a file."),
    )
    action.add_argument(
        "-p",
        "--publish",
        action="store_true",
        help=_("Write, commit and push the changelog."),
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("CHANGELOG.md"),
        help=_("Output file inside the current repository."),
    )
    parser.add_argument("-h", "--help", action="help", help=_("Show this help and exit."))
    parser.epilog = (
        _("Examples:")
        + "\n  python3 "
        + Path(__file__).name
        + " --dry-run\n  python3 "
        + Path(__file__).name
        + " --generate"
    )
    return parser.parse_args(arguments or ["--help"])


def validate_inputs(options: argparse.Namespace) -> GitRepository:
    """Prüft vor dem Schreiben die lokalen Voraussetzungen."""
    repository = GitRepository(Path.cwd())
    root = Path(repository.run("rev-parse", "--show-toplevel")).resolve()
    repository = GitRepository(root)
    if repository.run("rev-parse", "--is-shallow-repository") == "true":
        raise ChangelogError(_("Fetch the complete Git history and tags first."))
    output = options.output.absolute()
    if output.is_symlink() or not output.parent.is_dir():
        raise ChangelogError(_("The output must be a regular file in an existing directory."))
    output = output.resolve()
    if not output.is_relative_to(root) or output.is_relative_to(root / ".git"):
        raise ChangelogError(_("The output must be inside the working tree, outside .git."))
    if output.exists() and not output.is_file():
        raise ChangelogError(_("The output must be a regular file in an existing directory."))
    options.output = output
    if options.publish:
        # Fremde Änderungen nicht versehentlich in den Release-Commit aufnehmen.
        if repository.run(
            "status",
            "--porcelain",
            "--untracked-files=no",
            "--",
            ".",
            f":(exclude){output.relative_to(root)}",
        ):
            raise ChangelogError(_("Commit or stash tracked changes before publishing."))
        if repository.run("diff", "--cached", "--name-only"):
            raise ChangelogError(_("The Git index must be empty before publishing."))
        repository.run("symbolic-ref", "--quiet", "HEAD")
        repository.run("rev-parse", "--abbrev-ref", "@{upstream}")
    if not repository.releases():
        raise ChangelogError(_("No release tags found on the current branch."))
    return repository


def markdown_text(text: str) -> str:
    """Hält Commit- und Tag-Texte als sichtbaren Text, ohne HTML auszuführen."""
    text = " ".join(text.split())
    return re.sub(r"([\\`*_[\]<>])", r"\\\1", text)


def categorize(subject: str, body: str) -> tuple[str, str] | None:
    """Filtert interne Pflege und ordnet nutzerrelevante Conventional Commits zu."""
    match = SUBJECT.fullmatch(subject)
    if not match:
        return None
    kind, scope, breaking, title = match.groups()
    if scope in {"tickets", "activity", "lessons", "changelog"}:
        return None
    if breaking or re.search(r"^BREAKING[ -]CHANGE:", body, re.MULTILINE):
        return _("Breaking changes"), title
    groups = {
        "feat": _("Features"),
        "fix": _("Fixes"),
        "perf": _("Performance"),
        "refactor": _("Other changes"),
        "build": _("Other changes"),
        "docs": _("Documentation"),
    }
    return (groups[kind], title) if kind in groups else None


def render(repository: GitRepository) -> str:
    """Erzeugt stabile Abschnitte aus veröffentlichten Tags und ihren Commit-Bereichen."""
    sections = []
    previous = None
    for release in repository.releases():
        groups: dict[str, list[str]] = {}
        for commit, subject, body in repository.commits(previous, release.commit):
            entry = categorize(subject, body)
            if entry:
                group, title = entry
                groups.setdefault(group, []).append(f"- {markdown_text(title)} (`{commit[:7]}`)")
        heading = f"## {release.tag} — {release.date}"
        lines = [heading, ""]
        if release.message:
            lines.extend([markdown_text(release.message), ""])
        for group, entries in groups.items():
            lines.extend([f"### {group}", "", *entries, ""])
        if not groups:
            lines.extend([_("No user-facing changes recorded."), ""])
        sections.append("\n".join(lines))
        previous = release.commit
    return (
        "# Changelog\n\n"
        + _("Generated from release tags and Conventional Commits.")
        + "\n\n"
        + "\n".join(reversed(sections))
    )


def write_output(output: Path, content: str) -> None:
    """Ersetzt die Ausgabe atomar und lässt identische Dateien unverändert."""
    if output.exists() and output.read_text(encoding="utf-8") == content:
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=output.parent,
            prefix=".changelog-",
            delete=False,
        ) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        temporary.chmod(0o644)
        temporary.replace(output)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def main(arguments: list[str]) -> int:
    """Verbindet Parser, Validierung, Renderer und die ausdrücklich gewählte Aktion."""
    try:
        options = parse_args(arguments)
        repository = validate_inputs(options)
        content = render(repository)
        if options.dry_run:
            print(content, end="")
        else:
            write_output(options.output, content)
            if options.publish:
                repository.publish(options.output)
            print(
                Theme().indent_group
                + Theme().style(
                    "✓ " + _("Changelog updated: {path}").format(path=options.output),
                    "SUCCESS",
                    sys.stdout,
                )
            )
        return 0
    except (ChangelogError, OSError, subprocess.CalledProcessError) as error:
        details = (
            error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        )
        report_error(_("Changelog failed: {reason}").format(reason=details))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
