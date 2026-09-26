#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# dockerhub-readme.py — README mit absoluten Links nach Docker Hub übertragen
#
# Pandoc erhält die Markdown-Struktur. Zugangsdaten werden nur beim Upload
# aus der lokalen Datei gelesen und ausschließlich an Docker Hub gesendet.
#
# Verwendung (öffentlicher Bash-Einstieg richtet die Werkzeugumgebung ein):
#   .libs/ProjectTools/src/bash/dockerhub-readme.sh --preview --ref master
#   .libs/ProjectTools/src/bash/dockerhub-readme.sh --publish --ref master -r user/repo
#   make push
# ------------------------------------------------------------------------------
"""Lokaler Veröffentlichungsweg für die Docker-Hub-Repository-Übersicht."""

from __future__ import annotations

import argparse
import gettext
import json
import os
import posixpath
import re
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING, TextIO
from urllib.parse import quote, urlsplit, urlunsplit

if TYPE_CHECKING:
    import httpx

_ = gettext.translation(
    "dockerhub_readme", localedir=Path(__file__).parent / "locales", fallback=True
).gettext
HUB_URL = "https://hub.docker.com"
README_LIMIT = 25_000
APPNAME = os.environ.get("PROJECTTOOLS_APPNAME", Path(__file__).name)


def styled(text: str, color: str, stream: TextIO = sys.stdout) -> str:
    """Färbt Text nur im Terminal, mit BashLib-Palette und NO_COLOR-Unterstützung.

    Args:
        text: Sichtbarer Text ohne ANSI-Sequenzen.
        color: Farbname aus der BashLib-Palette.
        stream: Zielausgabe zur Terminalerkennung.

    Returns:
        Farbiger oder unveränderter Text.
    """
    if "NO_COLOR" in os.environ or not stream.isatty() or os.environ.get("TERM") == "dumb":
        return text
    defaults = {"BLUE": "34", "LIGHT_BLUE": "96", "YELLOW": "33", "GREEN": "32", "RED": "31"}
    prefix = os.environ.get(f"PROJECTTOOLS_COLOR_{color}", f"\033[{defaults[color]}m")
    return f"{prefix}{text}\033[0m"


class ScriptHelpFormatter(argparse.RawDescriptionHelpFormatter):
    """Native argparse-Hilfe mit festen Spalten für Kurz- und Langoptionen."""

    def _format_action_invocation(self, action: argparse.Action) -> str:
        """Formatiert die vom Parser deklarierte Option, ohne zweite Optionsliste.

        Args:
            action: Native Parser-Aktion.

        Returns:
            Kurzoption, Trennzeichen, Langoption und optionaler Platzhalter.
        """
        if not action.option_strings:
            return super()._format_action_invocation(action)
        short, long = action.option_strings
        label = f"{short:2} | {long}"
        if action.nargs != 0:
            label += " " + self._format_args(action, action.metavar or action.dest.upper())
        return label


class ScriptArgumentParser(argparse.ArgumentParser):
    """Färbt die native Hilfe nach dem Layout, damit Spalten korrekt bleiben."""

    def format_help(self) -> str:
        """Erzeugt die gegliederte Terminalhilfe.

        Returns:
            Hilfe mit Farben nur für interaktive Ausgabe.
        """
        lines = super().format_help().splitlines()
        for index, line in enumerate(lines):
            if line.endswith(":"):
                lines[index] = styled(line, "LIGHT_BLUE")
            elif " | --" in line:
                match = re.match(r"(\s*)(.*?)(\s{2,}.*|$)", line)
                if match:
                    lines[index] = match[1] + styled(match[2], "YELLOW") + match[3]
            elif line.startswith("  " + self.prog):
                lines[index] = styled(line, "GREEN")
        return "\n" + "\n".join(lines) + "\n\n"

    def error(self, message: str) -> None:
        """Meldet Parserfehler im selben Stil wie fachliche Fehler.

        Args:
            message: Native Parserdiagnose.

        Raises:
            SystemExit: Immer mit Exit-Code 2.
        """
        self.print_usage(sys.stderr)
        report_error(message)
        self.exit(2)


class UploadError(Exception):
    """Sichere Fehlermeldung ohne Antwortkörper oder Zugangsdaten."""


def github_repository(project: Path) -> str:
    """Liest den GitHub-Projektpfad aus origin, ohne Zugangsdaten auszugeben."""
    remote = subprocess.run(
        ["git", "-C", str(project), "remote", "get-url", "origin"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    if remote.startswith("git@github.com:"):
        repository = remote.removeprefix("git@github.com:")
    elif urlsplit(remote).hostname == "github.com":
        repository = urlsplit(remote).path.lstrip("/")
    else:
        raise UploadError(_("origin must refer to a GitHub repository."))
    return repository.removesuffix(".git")


def absolute_url(target: str, repository: str, ref: str, is_image: bool, base: str = "") -> str:
    """Lässt externe URLs und lokale Anker stehen; Dateien werden GitHub-URLs."""
    parts = urlsplit(target)
    if parts.scheme or parts.netloc or not parts.path:
        return target
    path = posixpath.normpath(
        posixpath.join(base if not parts.path.startswith("/") else "", parts.path.lstrip("/"))
    )
    if path == ".." or path.startswith("../"):
        raise UploadError(_("A README link leaves the repository: {path}").format(path=target))
    branch = quote(ref, safe="")
    prefix = (
        f"https://raw.githubusercontent.com/{repository}/{branch}/"
        if is_image
        else f"https://github.com/{repository}/blob/{branch}/"
    )
    return prefix + urlunsplit(("", "", quote(path, safe="/%"), parts.query, parts.fragment))


def rewrite_links(node: object, repository: str, ref: str, base: str = "") -> None:
    """Ändert nur Link-/Bildziele im Pandoc-Baum, keine Code- oder Textknoten."""
    if isinstance(node, dict):
        if node.get("t") in {"Link", "Image"}:
            target = node["c"][-1]
            target[0] = absolute_url(target[0], repository, ref, node["t"] == "Image", base)
        for value in node.values():
            rewrite_links(value, repository, ref, base)
    elif isinstance(node, list):
        for value in node:
            rewrite_links(value, repository, ref, base)


def prepare_readme(source: str, repository: str, ref: str, base: str = "") -> str:
    """Konvertiert mit echtem Pandoc und prüft die Größe nach der Erweiterung."""
    parsed = subprocess.run(
        ["pandoc", "--from=gfm", "--to=json"],
        input=source,
        capture_output=True,
        text=True,
        check=True,
    )
    document = json.loads(parsed.stdout)
    rewrite_links(document, repository, ref, base)
    rendered = subprocess.run(
        ["pandoc", "--from=json", "--to=gfm", "--wrap=none", "--columns=1"],
        input=json.dumps(document),
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    if len(rendered.encode("utf-8")) > README_LIMIT:
        raise UploadError(
            _(
                "Converted README exceeds {limit} UTF-8 bytes; nothing uploaded. "
                "Record the Docker Hub limit in your project's AGENTS.md "
                "and move long sections into linked documents."
            ).format(limit=README_LIMIT)
        )
    return rendered


def checked_response(response: httpx.Response) -> dict:
    """Zeigt bei Fehlern nur Statuscodes, niemals den fremden Antwortkörper."""
    if not response.is_success:
        raise UploadError(
            _("Docker Hub returned HTTP {status}.").format(status=response.status_code)
        )
    try:
        payload = response.json()
    except ValueError:
        raise UploadError(_("Docker Hub returned an invalid response.")) from None
    if not isinstance(payload, dict):
        raise UploadError(_("Docker Hub returned an invalid response."))
    return payload


def publish(
    client: httpx.Client,
    content: str,
    repository: str,
    username: str,
    secret: str,
    description: str | None,
) -> None:
    """Authentifiziert, aktualisiert die Beschreibung und prüft sie durch Rücklesen."""
    if not re.fullmatch(r"[a-z0-9_-]+/[a-z0-9_.-]+", repository):
        raise UploadError(_("Repository must use the form namespace/name."))
    payload = {"full_description": content}
    if description is not None:
        if len(description.encode("utf-8")) > 100:
            raise UploadError(_("Short description exceeds 100 bytes."))
        payload["description"] = description
    auth = checked_response(
        client.post(f"{HUB_URL}/v2/auth/token", json={"identifier": username, "secret": secret})
    )
    token = auth.get("access_token")
    if not isinstance(token, str) or not token:
        raise UploadError(_("Docker Hub returned an invalid response."))
    headers = {"Authorization": f"Bearer {token}"}
    endpoint = f"{HUB_URL}/v2/repositories/{repository}/"
    response = client.patch(endpoint, json=payload, headers=headers)
    if not response.is_success:
        raise UploadError(
            _("Docker Hub returned HTTP {status}.").format(status=response.status_code)
        )
    saved = checked_response(client.get(endpoint, headers=headers))
    if any(saved.get(key) != value for key, value in payload.items()):
        raise UploadError(_("Docker Hub readback differs from the uploaded description."))


def add_action_options(parser: argparse.ArgumentParser) -> None:
    """Deklariert die ausschließenden Aktionen.

    Args:
        parser: Gemeinsamer Argumentparser.
    """
    actions = parser.add_argument_group(_("Actions")).add_mutually_exclusive_group(required=True)
    actions.add_argument(
        "-n", "--preview", action="store_true", help=_("Write a preview without Docker Hub access.")
    )
    actions.add_argument(
        "-p",
        "--publish",
        action="store_true",
        help=_("Upload the README and verify the saved description."),
    )


def add_repository_options(parser: argparse.ArgumentParser) -> None:
    """Deklariert Repository und veröffentlichten Quellstand.

    Args:
        parser: Gemeinsamer Argumentparser.
    """
    group = parser.add_argument_group(_("Repository"))
    group.add_argument(
        "-r",
        "--repository",
        metavar="NAME",
        help=_("Docker Hub namespace/name; required for publication."),
    )
    group.add_argument(
        "-u",
        "--username",
        metavar="USER",
        help=_("Docker Hub user; defaults to the repository namespace."),
    )
    group.add_argument(
        "-b",
        "--ref",
        required=True,
        metavar="REF",
        help=_("Published GitHub branch or commit for links (required)."),
    )
    group.add_argument(
        "-g",
        "--github-repository",
        metavar="NAME",
        help=_("GitHub owner/repository; defaults to origin."),
    )
    group.add_argument(
        "-d",
        "--description",
        metavar="TEXT",
        help=_("Optional short description; otherwise preserve the existing one."),
    )


def add_file_options(parser: argparse.ArgumentParser) -> None:
    """Deklariert Pfade, ohne Dateien oder Zugangsdaten zu lesen.

    Args:
        parser: Gemeinsamer Argumentparser.
    """
    group = parser.add_argument_group(_("Files"))
    token = Path(
        os.environ.get(
            "DOCKER_PW_FILE",
            str(
                Path(os.environ.get("DOCKER_CONFIG", str(Path.home() / ".docker")))
                / "dockerhub.sec"
            ),
        )
    )
    group.add_argument(
        "-C",
        "--project-dir",
        type=Path,
        default=Path.cwd(),
        metavar="DIR",
        help=_("Project root; defaults to the current directory."),
    )
    group.add_argument(
        "-s",
        "--readme",
        type=Path,
        default=Path("README.md"),
        metavar="FILE",
        help=_("Source README, relative to the project root."),
    )
    group.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("README.dockerhub.md"),
        metavar="FILE",
        help=_("Preview file; never the source README."),
    )
    group.add_argument(
        "-t",
        "--token-file",
        type=Path,
        default=token,
        metavar="FILE",
        help=_("Local token file; default follows DOCKER_PW_FILE / DOCKER_CONFIG."),
    )


def parse_args(arguments: list[str]) -> argparse.Namespace:
    """Liest Optionen; ohne Argumente erscheint Hilfe ohne Seiteneffekte.

    Args:
        arguments: Argumente ohne Programmnamen.

    Returns:
        Validierte Optionen für Vorschau oder Upload.
    """
    parser = ScriptArgumentParser(
        prog=APPNAME,
        add_help=False,
        description=_("Publish the local README to Docker Hub."),
        usage=_("%(prog)s [options]"),
        formatter_class=lambda prog: ScriptHelpFormatter(prog, max_help_position=38, width=100),
    )
    parser.color = False  # Farben nach dem nativen Layout anwenden.
    add_action_options(parser)
    add_repository_options(parser)
    add_file_options(parser)
    parser.add_argument_group(_("Help")).add_argument(
        "-h", "--help", action="help", help=_("Show this help and exit.")
    )
    parser.epilog = (
        _("Hints:") + f"\n  {APPNAME} --preview --ref master\n"
        f"  {APPNAME} --publish --ref master -r namespace/project"
    )
    options = parser.parse_args(arguments or ["--help"])
    if options.publish and not options.repository:
        parser.error(_("--publish requires --repository."))
    return options


def report_error(message: str) -> None:
    """Ein Fehlertext für Python und Bash, einschließlich vorherigem Image-Push."""
    print("  " + styled("✗ " + message, "RED", sys.stderr), file=sys.stderr)
    if os.environ.get("DOCKER_README_AFTER_PUSH") == "1":
        print(
            _("The image was already pushed. Retry the README upload separately."), file=sys.stderr
        )


def validate_inputs(options: argparse.Namespace) -> Path:
    """Lokale Eingaben vor Umgebungseinrichtung oder Netzaufrufen prüfen."""
    project = options.project_dir.resolve()
    if not project.is_dir():
        raise UploadError(_("The project directory does not exist. Check --project-dir."))
    source = (project / options.readme).resolve()
    if not source.is_relative_to(project):
        raise UploadError(_("The README must be inside the project directory."))
    try:
        source.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        raise UploadError(
            _("README is missing or unreadable. Check --project-dir and --readme.")
        ) from None
    if options.publish:
        try:
            secret = options.token_file.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError):
            raise UploadError(
                _(
                    "Docker Hub token file is missing or unreadable. "
                    "Set --token-file or DOCKER_PW_FILE."
                )
            ) from None
        if not secret:
            raise UploadError(_("The token file is empty."))
    return source


def main(arguments: list[str]) -> int:
    """Die CLI gibt ausschließlich kontrollierte Fehlertexte aus."""
    options = parse_args(arguments)
    try:
        source_path = validate_inputs(options)
    except UploadError as error:
        report_error(str(error))
        return 1
    try:
        import httpx
    except ModuleNotFoundError:
        report_error(
            _("Start this tool through ProjectTools/src/bash/dockerhub-readme.sh to prepare .venv.")
        )
        return 1
    try:
        project = options.project_dir.resolve()
        base = source_path.relative_to(project).parent.as_posix()
        repository = options.github_repository or github_repository(project)
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise UploadError(_("Repository must use the form namespace/name."))
        content = prepare_readme(
            source_path.read_text(encoding="utf-8"), repository, options.ref, base
        )
        options.output = project / options.output
        print("\n" + styled("▶ " + _("Prepare README"), "LIGHT_BLUE"))
        if options.preview:
            if options.output.resolve() == source_path.resolve():
                raise UploadError(_("The preview must not overwrite README.md."))
            options.output.parent.mkdir(parents=True, exist_ok=True)
            options.output.write_text(content, encoding="utf-8")
            print(
                "  "
                + styled("✓ ", "GREEN")
                + _("Preview written: {path}").format(path=styled(str(options.output), "YELLOW"))
            )
            return 0
        secret = options.token_file.read_text().strip()
        if not secret:
            raise UploadError(_("The token file is empty."))
        print("\n" + styled("▶ " + _("Publish to Docker Hub"), "LIGHT_BLUE"))
        with httpx.Client(timeout=30, follow_redirects=False, trust_env=False) as client:
            publish(
                client,
                content,
                options.repository,
                options.username or options.repository.split("/")[0],
                secret,
                options.description,
            )
        print(
            styled("✓ ", "GREEN")
            + _("Docker Hub description updated and verified: {repository}").format(
                repository=styled(options.repository, "YELLOW")
            )
        )
        return 0
    except UploadError as error:
        report_error(str(error))
    except (OSError, subprocess.SubprocessError, httpx.HTTPError, ValueError) as error:
        report_error(
            _("Operation failed ({kind}); check Pandoc, the token file and connectivity.").format(
                kind=type(error).__name__
            )
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
