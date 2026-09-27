"""Direkten Python- und Bash-Einstieg unter dem unterstützten Python 3.9 prüfen."""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def python39() -> str:
    """Kompatibilitätslauf braucht einen echten, explizit angegebenen Interpreter."""
    interpreter = os.environ.get("PYTHON_TEST_39")
    if not interpreter:
        pytest.skip("PYTHON_TEST_39 für den echten Python-3.9-Lauf setzen")
    version = subprocess.check_output(
        [interpreter, "-c", "import sys; print(sys.version_info[:2])"], text=True
    )
    assert version.strip() == "(3, 9)"
    return interpreter


@pytest.mark.parametrize("entry", ["python", "bash"])
@pytest.mark.parametrize("arguments", [[], ["--help"], ["--dry-run"], ["--unknown"]])
def test_changelog_runs_without_installation(
    python39: str, entry: str, arguments: list[str], tmp_path: Path
) -> None:
    """Stdlib-Werkzeuge brauchen weder Python 3.11 noch eine Paketumgebung."""
    command = (
        [python39, str(ROOT / "src/python/py-run.py")]
        if entry == "python"
        else [str(ROOT / "src/bash/py-run.sh")]
    )
    repository = tmp_path / "repo"
    repository.mkdir()
    if arguments == ["--dry-run"]:
        for arguments_git in [
            ["init", "-b", "master"],
            ["config", "user.name", "Test"],
            ["config", "user.email", "test@example.invalid"],
            ["config", "core.hooksPath", str(tmp_path / "no-hooks")],
            ["commit", "--allow-empty", "-m", "feat: Example"],
            ["tag", "v0.1.0"],
        ]:
            subprocess.run(["git", *arguments_git], cwd=repository, check=True, capture_output=True)
    cache = tmp_path / "cache"
    environment = {
        **os.environ, "PYTHON_BOOTSTRAP": python39, "XDG_CACHE_HOME": str(cache),
        "MAKE_THEME": "ocean", "LANGUAGE": "en",
    }
    result = subprocess.run(
        [*command, "-r", "changelog", *arguments], env=environment, cwd=repository,
        text=True, capture_output=True,
    )
    direct = subprocess.run(
        [python39, str(ROOT / "src/python/changelog.py"), *arguments],
        env=environment, cwd=repository, text=True, capture_output=True,
    )
    assert result.returncode == direct.returncode == (2 if arguments == ["--unknown"] else 0)
    assert result.stdout == direct.stdout
    assert result.stderr == direct.stderr
    assert not cache.exists()


def test_missing_package_interpreter_reports_action(python39: str, tmp_path: Path) -> None:
    """Nur der Paket-Bootstrap meldet seine höhere Versionsanforderung."""
    cache = tmp_path / "cache"
    result = subprocess.run(
        [python39, str(ROOT / "src/python/py-run.py"), "-r", "dockerhub-readme", "--preview"],
        env={
            **os.environ, "LANGUAGE": "en", "XDG_CACHE_HOME": str(cache),
            "PYTHON_BOOTSTRAP": python39,
        },
        text=True, capture_output=True,
    )
    assert result.returncode == 1
    assert "Package setup requires an installed Python 3.11" in result.stderr
    assert "PYTHON_BOOTSTRAP" in result.stderr
    assert not cache.exists()


def test_direct_runner_creates_and_reuses_package_environment(
    python39: str, tmp_path: Path
) -> None:
    """Python 3.9 findet selbst den neueren Interpreter und richtet die venv ein."""
    project = tmp_path / "project"
    (project / "docker").mkdir(parents=True)
    (project / "docker/README.md").write_text("# Demo\n")
    cache = tmp_path / "cache"
    environment = {**os.environ, "LANGUAGE": "en", "XDG_CACHE_HOME": str(cache)}
    environment.pop("PYTHON_BOOTSTRAP", None)
    command = [
        python39, str(ROOT / "src/python/py-run.py"), "-r", "dockerhub-readme",
        "--preview", "--project-dir", str(project), "--github-repository", "example/demo",
    ]
    first = subprocess.run(command, env=environment, text=True, capture_output=True)
    assert first.returncode == 0, first.stderr
    interpreter = cache / "projecttools/dockerhub-readme/.venv/bin/python"
    subprocess.run([
        str(interpreter), "-c",
        "import sys,httpx; assert sys.version_info >= (3,11); assert sys.prefix != sys.base_prefix"
    ], check=True)
    assert (project / "docker/preview/README.md").exists()
    inode = interpreter.lstat().st_ino
    second = subprocess.run(
        command,
        env={**environment, "PIP_NO_INDEX": "1", "PIP_FIND_LINKS": str(tmp_path / "empty")},
        text=True, capture_output=True,
    )
    assert second.returncode == 0, second.stderr
    assert interpreter.lstat().st_ino == inode
    assert not (project / ".venv").exists()


@pytest.mark.parametrize("arguments", [[], ["--help"], ["--unknown"]])
def test_named_symlink_dispatches_without_run_option(
    python39: str, arguments: list[str], tmp_path: Path
) -> None:
    """Ein relativer Link wählt das Werkzeug ohne eingebettete Argumente."""
    local_tools = tmp_path / "local tools"
    local_tools.symlink_to(ROOT, target_is_directory=True)
    alias = tmp_path / "changelog.sh"
    alias.symlink_to("local tools/src/python/py-run.py")
    environment = {
        **os.environ, "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"],
        "LANGUAGE": "en", "XDG_CACHE_HOME": str(tmp_path / "cache"),
    }
    (tmp_path / "python3").symlink_to(python39)
    result = subprocess.run(
        [str(alias), *arguments], env=environment, text=True, capture_output=True,
    )
    assert result.returncode == (2 if arguments == ["--unknown"] else 0), result.stderr
    if not arguments or arguments == ["--help"]:
        assert "--generate" in result.stdout
    assert "--run" not in result.stdout
    assert not (tmp_path / "cache").exists()


@pytest.mark.parametrize(
    "script, option", [("changelog", "--generate"), ("dockerhub-readme", "--preview")]
)
def test_shipped_alias_preserves_german_output(script: str, option: str, tmp_path: Path) -> None:
    """Ausgelieferte Links laden Kataloge relativ zum echten Python-Ziel."""
    alias = ROOT / "src/bash" / f"{script}.sh"
    assert alias.is_symlink()
    assert os.readlink(alias) == "../python/py-run.py"
    result = subprocess.run(
        [str(alias), "--help"], text=True, capture_output=True,
        env={**os.environ, "LANGUAGE": "de", "XDG_CACHE_HOME": str(tmp_path / "cache")},
    )
    assert result.returncode == 0, result.stderr
    assert f"{script}.sh" in result.stdout
    assert option in result.stdout and "Optionen" in result.stdout
    assert not (tmp_path / "cache").exists()
