"""Befehle des pip-Pakets: projecttools, docs-check, repo-status und changelog.

Die Befehle starten die Skripte aus src/ unverändert. Im installierten Paket
liegen sie unter projecttools/tools/, bei ``pipx install -e`` kommen sie direkt
aus der Arbeitskopie. Welche Bibliotheken mitkommen, steht in pyproject.toml.
"""

from __future__ import annotations

import argparse
import os
import runpy
import sys
from importlib import metadata
from pathlib import Path

DISTRIBUTION = "mmit-projecttools"
COMMANDS = {
    "docs-check": "Nutzerdokumente gegen das Projekt prüfen",
    "repo-status": "Git-Status aller Workspace-Repos",
    "changelog": "CHANGELOG.md aus Release-Tags erzeugen",
}


def tool_root() -> Path:
    """Wurzel mit bash/, deno/ und python/: im Paket tools/, sonst src/."""
    here = Path(__file__).resolve().parent
    bundled = here / "tools"
    return bundled if (bundled / "bash").is_dir() else here.parents[1]


def tool_environment() -> dict[str, str]:
    """BASH_LIBS aus dem BashLib-Paket, außer es ist von außen gesetzt; deno aus dem Paket."""
    environment = dict(os.environ)
    if not environment.get("BASH_LIBS"):
        try:
            import bashlib

            environment["BASH_LIBS"] = str(bashlib.lib_dir())
        except ImportError:
            pass
    try:
        import deno

        deno_dir = str(Path(deno.find_deno_bin()).parent)
        environment["PATH"] = os.pathsep.join([deno_dir, environment.get("PATH", "")])
    except (ImportError, FileNotFoundError):
        pass
    return environment


def _run_bash(name: str) -> int:
    script = tool_root() / "bash" / f"{name}.sh"
    os.execve(script, [str(script), *sys.argv[1:]], tool_environment())
    return 1  # pragma: no cover - execve kehrt nicht zurück


def docs_check() -> int:
    return _run_bash("docs-check")


def repo_status() -> int:
    return _run_bash("repo-status")


def changelog() -> int:
    os.environ.update(tool_environment())
    os.environ.setdefault("PROJECTTOOLS_APPNAME", "changelog")
    script = tool_root() / "python" / "changelog.py"
    sys.argv = [str(script), *sys.argv[1:]]
    runpy.run_path(str(script), run_name="__main__")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="projecttools",
        description="ProjectTools: "
        + "; ".join(f"{name} – {text}" for name, text in COMMANDS.items()),
    )
    parser.add_argument("--version", action="store_true", help="Version ausgeben")
    arguments = parser.parse_args()
    if arguments.version:
        print(metadata.version(DISTRIBUTION))
        return 0
    parser.print_help()
    return 0
