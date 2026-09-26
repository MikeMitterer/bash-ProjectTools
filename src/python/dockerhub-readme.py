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
from typing import TYPE_CHECKING
from urllib.parse import quote, urlsplit, urlunsplit

if TYPE_CHECKING:
    import httpx

_ = gettext.translation(
    "dockerhub_readme", localedir=Path(__file__).parent / "locales", fallback=True
).gettext
HUB_URL = "https://hub.docker.com"
README_LIMIT = 25_000


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


def parse_args(arguments: list[str]) -> argparse.Namespace:
    """Ohne Aktion erscheint nur die native Parser-Hilfe."""
    parser = argparse.ArgumentParser(description=_("Publish the local README to Docker Hub."))
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument(
        "-n",
        "--preview",
        action="store_true",
        help=_("Write a preview without network access or credentials."),
    )
    actions.add_argument(
        "-p",
        "--publish",
        action="store_true",
        help=_("Upload the README and verify the saved description."),
    )
    parser.add_argument(
        "-r",
        "--repository",
        help=_("Docker Hub namespace/name; required for publication."),
    )
    parser.add_argument(
        "-u",
        "--username",
        help=_("Docker Hub user; defaults to the repository namespace."),
    )
    parser.add_argument(
        "-b",
        "--ref",
        required=True,
        help=_("Published GitHub branch or commit for links (required)."),
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("README.dockerhub.md"),
        help=_("Preview file; never the source README."),
    )
    parser.add_argument(
        "-t",
        "--token-file",
        type=Path,
        default=Path(
            os.environ.get(
                "DOCKER_PW_FILE",
                str(
                    Path(os.environ.get("DOCKER_CONFIG", str(Path.home() / ".docker")))
                    / "dockerhub.sec"
                ),
            )
        ),
        help=_("Local token file; default follows DOCKER_PW_FILE / DOCKER_CONFIG."),
    )
    parser.add_argument(
        "-d",
        "--description",
        help=_("Optional short description; otherwise preserve the existing one."),
    )
    parser.add_argument(
        "-C",
        "--project-dir",
        type=Path,
        default=Path.cwd(),
        help=_("Project root; defaults to the current directory."),
    )
    parser.add_argument(
        "-s",
        "--readme",
        type=Path,
        default=Path("README.md"),
        help=_("Source README, relative to the project root."),
    )
    parser.add_argument(
        "-g", "--github-repository", help=_("GitHub owner/repository; defaults to origin.")
    )
    options = parser.parse_args(arguments or ["--help"])
    if options.publish and not options.repository:
        parser.error(_("--publish requires --repository."))
    return options


def report_error(message: str) -> None:
    """Ein Fehlertext für Python und Bash, einschließlich vorherigem Image-Push."""
    print(message, file=sys.stderr)
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
        if options.preview:
            if options.output.resolve() == source_path.resolve():
                raise UploadError(_("The preview must not overwrite README.md."))
            options.output.parent.mkdir(parents=True, exist_ok=True)
            options.output.write_text(content, encoding="utf-8")
            print(_("Preview written: {path}").format(path=options.output))
            return 0
        secret = options.token_file.read_text().strip()
        if not secret:
            raise UploadError(_("The token file is empty."))
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
            _("Docker Hub description updated and verified: {repository}").format(
                repository=options.repository
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
