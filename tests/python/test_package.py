"""ProjectTools als pip-Paket: Befehle, Version, Paketdaten und Editable-Install.

Installiert in temporäre venvs ohne Abhängigkeiten (--no-deps); BashLib kommt
dabei aus BASH_LIBS bzw. dem DevBash-Baum, deno aus dem PATH. Braucht
Python ab 3.11 und Zugriff auf setuptools über den Paketindex oder den pip-Cache.
"""

from __future__ import annotations

import os
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest
import tomllib

ROOT = Path(__file__).resolve().parents[2]
PYPROJECT = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
VERSION = PYPROJECT["project"]["version"]
COMMANDS = ["projecttools", "docs-check", "repo-status", "changelog"]
BASH_LIBS = os.environ.get("BASH_LIBS") or str(ROOT.parents[1] / "BashLib/src")


def pip(venv: Path, *arguments: str) -> None:
    subprocess.run(
        [
            str(venv / "bin/python"),
            "-m",
            "pip",
            "install",
            "--quiet",
            "--disable-pip-version-check",
            "--no-deps",
            *arguments,
        ],
        check=True,
    )


def make_venv(path: Path) -> Path:
    subprocess.run([sys.executable, "-m", "venv", str(path)], check=True)
    return path


def run(venv: Path, command: str, *arguments: str, cwd: Path, **env: str):
    """Befehl aus der venv, ohne PROJECT_TOOLS und ohne .libs im Arbeitsverzeichnis."""
    environment = {k: v for k, v in os.environ.items() if k not in ("PROJECT_TOOLS", "BASH_LIBS")}
    environment.update(env)
    return subprocess.run(
        [str(venv / "bin" / command), *arguments],
        cwd=cwd,
        env=environment,
        capture_output=True,
        text=True,
    )


@pytest.fixture(scope="module")
def wheel(tmp_path_factory: pytest.TempPathFactory) -> Path:
    out = tmp_path_factory.mktemp("wheel")
    builder = make_venv(out / "build-venv")
    subprocess.run(
        [
            str(builder / "bin/python"),
            "-m",
            "pip",
            "wheel",
            "--quiet",
            "--disable-pip-version-check",
            "--no-deps",
            "-w",
            str(out),
            str(ROOT),
        ],
        check=True,
    )
    return next(out.glob("*.whl"))


@pytest.fixture(scope="module")
def installed(wheel: Path, tmp_path_factory: pytest.TempPathFactory) -> Path:
    venv = make_venv(tmp_path_factory.mktemp("installed") / "venv")
    pip(venv, str(wheel))
    return venv


@pytest.fixture(scope="module")
def editable(tmp_path_factory: pytest.TempPathFactory) -> Path:
    venv = make_venv(tmp_path_factory.mktemp("editable") / "venv")
    pip(venv, "-e", str(ROOT))
    return venv


def test_dependencies_are_declared_in_pyproject() -> None:
    """Welche Bibliotheken mitkommen, steht nur in pyproject.toml."""
    dependencies = PYPROJECT["project"]["dependencies"]
    assert any(d.startswith("deno") for d in dependencies)
    bashlib = [d for d in dependencies if d.startswith("mmit-bashlib")]
    assert bashlib and "github.com/MikeMitterer/bash-lib.git@v" in bashlib[0]
    assert sorted(PYPROJECT["project"]["scripts"]) == sorted(COMMANDS)


def test_wheel_contains_tools_and_metadata(wheel: Path) -> None:
    names = set(zipfile.ZipFile(wheel).namelist())
    for path in [
        "projecttools/cli.py",
        "projecttools/tools/bash/docs-check.sh",
        "projecttools/tools/bash/repo-status.sh",
        "projecttools/tools/deno/docs-check.ts",
        "projecttools/tools/python/changelog.py",
        "projecttools/tools/python/locales/de/LC_MESSAGES/changelog.mo",
    ]:
        assert path in names, path
    assert f"-{VERSION}-" in wheel.name


def test_version(installed: Path, tmp_path: Path) -> None:
    result = run(installed, "projecttools", "--version", cwd=tmp_path)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == VERSION


@pytest.mark.parametrize("command", COMMANDS)
def test_commands_show_help_without_libs(installed: Path, command: str, tmp_path: Path) -> None:
    """Ohne .libs und PROJECT_TOOLS; BashLib nur über BASH_LIBS von außen."""
    result = run(installed, command, "--help", cwd=tmp_path, BASH_LIBS=BASH_LIBS)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.strip()


def test_docs_check_runs_from_package(installed: Path, tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    (tmp_path / "README.md").write_text("# Demo\n\nText.\n", encoding="utf-8")
    (tmp_path / ".docs-check.conf.sh").write_text('DOCS=("README.md")\n', encoding="utf-8")
    result = run(installed, "docs-check", "--run", cwd=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "keine Probleme" in result.stdout


def test_docs_check_without_deno_fails_clearly(installed: Path, tmp_path: Path) -> None:
    """Ohne deno im PATH und ohne deno-Paket: klare Meldung, Exit-Code ungleich 0."""
    (tmp_path / ".docs-check.conf.sh").write_text('DOCS=("README.md")\n', encoding="utf-8")
    result = run(installed, "docs-check", "--run", cwd=tmp_path, PATH="/usr/bin:/bin")
    assert result.returncode != 0
    assert "Deno nicht gefunden" in result.stderr
    assert "pipx" in result.stderr


def test_editable_uses_working_copy(editable: Path, tmp_path: Path) -> None:
    """pipx install -e: die Skripte kommen direkt aus src/ der Arbeitskopie."""
    result = subprocess.run(
        [
            str(editable / "bin/python"),
            "-c",
            "from projecttools import cli; print(cli.tool_root())",
        ],
        capture_output=True,
        text=True,
        cwd=tmp_path,
    )
    assert result.returncode == 0, result.stderr
    assert Path(result.stdout.strip()) == ROOT / "src"
    version = run(editable, "projecttools", "--version", cwd=tmp_path)
    assert version.stdout.strip() == VERSION


def test_changelog_matches_script(installed: Path, tmp_path: Path) -> None:
    """changelog verhält sich wie changelog.py, samt ausgefilterter Scopes."""
    repo = tmp_path / "repo"
    repo.mkdir()

    def git(*arguments: str) -> None:
        subprocess.run(
            ["git", "-c", "user.name=T", "-c", "user.email=t@example.invalid", *arguments],
            cwd=repo,
            check=True,
            capture_output=True,
        )

    git("init", "-q", "-b", "master")
    for subject in ["feat(api): Erstes Feature", "chore(tickets): Board", "fix(ui): Knopf"]:
        git("commit", "-q", "--allow-empty", "-m", subject)
        if subject.startswith("feat"):
            git("tag", "-a", "v0.1.0", "-m", "Erstes Release")
    git("tag", "-a", "v0.2.0", "-m", "Zweites Release")
    script = subprocess.run(
        [sys.executable, str(ROOT / "src/python/changelog.py"), "--dry-run"],
        cwd=repo,
        capture_output=True,
        text=True,
        env={**os.environ, "PYTHONPATH": str(ROOT / "src/python")},
    )
    command = run(installed, "changelog", "--dry-run", cwd=repo)
    assert command.returncode == script.returncode == 0, command.stderr + script.stderr
    assert command.stdout == script.stdout
    assert "Knopf" in command.stdout and "Board" not in command.stdout
