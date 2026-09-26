"""Bash-Einstieg gegen echte leere Python-Umgebungen und pip prüfen."""

import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "src/bash/dockerhub-readme.sh"
ENGINE = ROOT / "src/python/dockerhub-readme.py"


@pytest.mark.parametrize("arguments", [[], ["--help"], ["--preview"]])
def test_hilfe_und_argumentfehler_installieren_nichts(tmp_path: Path, arguments: list[str]) -> None:
    result = subprocess.run(
        [str(SCRIPT), *arguments],
        cwd=tmp_path,
        env={
            **os.environ,
            "PYTHON_BOOTSTRAP": sys.executable,
            "XDG_CACHE_HOME": str(tmp_path / "cache"),
        },
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == (2 if arguments == ["--preview"] else 0)
    assert "Traceback" not in result.stderr
    assert not (tmp_path / ".venv").exists()
    assert not (tmp_path / "cache").exists()


def test_python_hilfe_funktioniert_ohne_installierte_pakete() -> None:
    result = subprocess.run(
        [sys.executable, "-S", str(ENGINE)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "--preview" in result.stdout and "Traceback" not in result.stderr


@pytest.mark.parametrize("existing", [False, True])
def test_bash_richtet_echte_venv_ein_und_verwendet_sie_erneut(
    tmp_path: Path, existing: bool
) -> None:
    """PIP_FIND_LINKS/PIP_NO_INDEX erlauben dieselbe Installation mit lokalen Wheels."""
    project = tmp_path / "consumer with spaces"
    project.mkdir()
    (project / "README.md").write_text("# Demo\n\n![Bild](images/demo.png)\n")
    runtime = tmp_path / "cache/projecttools/dockerhub-readme/.venv/bin/python"
    # Bestehende Projektumgebung darf weder ausgeführt noch umgebaut werden.
    project_python = project / ".venv/bin/python"
    project_python.parent.mkdir(parents=True)
    project_python.write_text("#!/bin/sh\nexit 42\n")
    project_python.chmod(0o755)
    original = project_python.read_bytes()
    if existing:
        subprocess.run(
            [sys.executable, "-m", "venv", "--without-pip", str(runtime.parent.parent)], check=True
        )
        assert (
            subprocess.run([str(runtime), "-c", "import httpx"], capture_output=True).returncode
            != 0
        )
    environment = {
        **os.environ,
        "PYTHON_BOOTSTRAP": sys.executable,
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "PIP_NO_CACHE_DIR": "1",
    }
    if not existing:
        environment.pop("PYTHON_BOOTSTRAP", None)
    command = [
        str(SCRIPT),
        "--preview",
        "--project-dir",
        str(project),
        "--github-repository",
        "example/consumer",
        "--ref",
        "master",
    ]
    result = subprocess.run(command, cwd=tmp_path, env=environment, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert (
        "https://raw.githubusercontent.com/example/consumer/master/images/demo.png"
        in (project / "README.dockerhub.md").read_text()
    )
    subprocess.run(
        [str(runtime), "-c", "import httpx; assert httpx.__version__ == '0.28.1'"], check=True
    )
    # Ohne verfügbare Paketquelle muss ein zweiter Aufruf offline funktionieren.
    result = subprocess.run(
        command,
        cwd=tmp_path,
        env={**environment, "PIP_NO_INDEX": "1", "PIP_FIND_LINKS": str(tmp_path / "empty")},
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert project_python.read_bytes() == original
    assert sorted(
        path.relative_to(project / ".venv").as_posix() for path in (project / ".venv").rglob("*")
    ) == ["bin", "bin/python"]


def test_paketfehler_stoppt_vor_der_eigentlichen_aktion(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("# Demo")
    result = subprocess.run(
        [
            str(SCRIPT),
            "--preview",
            "--project-dir",
            str(tmp_path),
            "--github-repository",
            "example/consumer",
            "--ref",
            "master",
        ],
        env={
            **os.environ,
            "PYTHON_BOOTSTRAP": sys.executable,
            "XDG_CACHE_HOME": str(tmp_path / "cache"),
            "LANGUAGE": "de",
            "PIP_NO_INDEX": "1",
            "PIP_FIND_LINKS": str(tmp_path / "empty"),
        },
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert "Abhängigkeiten" in result.stderr and "pip" in result.stderr
    assert "Traceback" not in result.stderr
    assert not (tmp_path / "README.dockerhub.md").exists()


@pytest.mark.parametrize(
    "failure",
    ["readme-missing", "readme-directory", "token-missing", "token-directory", "token-empty"],
)
def test_fehlende_eingaben_stoppen_vor_venv_und_upload(tmp_path: Path, failure: str) -> None:
    source = tmp_path / "README.md"
    token = tmp_path / "token"
    if failure == "readme-directory":
        source.mkdir()
    elif failure != "readme-missing":
        source.write_text("# Demo")
    if failure == "token-directory":
        token.mkdir()
    elif failure == "token-empty":
        token.write_text(" \n\t")
    result = subprocess.run(
        [
            str(SCRIPT),
            "--publish",
            "--project-dir",
            str(tmp_path),
            "--ref",
            "master",
            "--repository",
            "example/repo",
            "--token-file",
            str(token),
        ],
        env={
            **os.environ,
            "PYTHON_BOOTSTRAP": sys.executable,
            "XDG_CACHE_HOME": str(tmp_path / "cache"),
            "LANGUAGE": "de",
        },
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert ("README" if failure.startswith("readme") else "Token-Datei") in result.stderr
    assert "Traceback" not in result.stderr
    assert not (tmp_path / ".venv").exists()
    assert not (tmp_path / "cache").exists()


def test_symlink_auf_fremde_venv_wird_nicht_verwendet(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("# Demo")
    runtime = tmp_path / "cache/projecttools/dockerhub-readme/.venv"
    runtime.parent.mkdir(parents=True)
    project_venv = tmp_path / ".venv"
    project_venv.mkdir()
    runtime.symlink_to(project_venv, target_is_directory=True)
    result = subprocess.run(
        [
            str(SCRIPT),
            "--preview",
            "--project-dir",
            str(tmp_path),
            "--github-repository",
            "example/consumer",
            "--ref",
            "master",
        ],
        env={
            **os.environ,
            "PYTHON_BOOTSTRAP": sys.executable,
            "XDG_CACHE_HOME": str(tmp_path / "cache"),
            "LANGUAGE": "de",
        },
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert "Symlink" in result.stderr
    assert list(project_venv.iterdir()) == []
