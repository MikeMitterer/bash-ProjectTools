"""CLI-Gestaltung mit echten Terminal- und Pipe-Ausgaben prüfen."""

import os
import pty
import re
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "src/bash/dockerhub-readme.sh"
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def terminal_output(arguments: list[str], environment: dict[str, str]) -> tuple[int, str]:
    """Führt den Bash-Einstieg an einem echten Pseudoterminal aus.

    Args:
        arguments: CLI-Argumente ohne Programmnamen.
        environment: Vollständige Kindprozess-Umgebung.

    Returns:
        Exit-Code und gemeinsame Terminalausgabe.
    """
    master, slave = pty.openpty()
    process = subprocess.Popen(
        [str(SCRIPT), *arguments], stdout=slave, stderr=slave, env=environment
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


@pytest.mark.parametrize("no_color", [False, True])
def test_terminal_hilfe_hat_feste_spalten_und_beispiele(tmp_path: Path, no_color: bool) -> None:
    environment = {
        **os.environ,
        "LANGUAGE": "de",
        "TERM": "xterm-256color",
        "XDG_CACHE_HOME": str(tmp_path),
    }
    environment.pop("NO_COLOR", None)
    if no_color:
        environment["NO_COLOR"] = "1"
    status, output = terminal_output([], environment)
    assert status == 0
    assert bool(ANSI.search(output)) is not no_color
    text = ANSI.sub("", output)
    for heading in ["Aktionen:", "Repository:", "Dateien:", "Hilfe:", "Beispiele:"]:
        assert heading in text
    rows = [line for line in text.splitlines() if " | --" in line]
    assert len(rows) == 12
    assert {line.index("|") for line in rows} == {5}
    assert {line.index("--") for line in rows} == {7}
    assert "dockerhub-readme.sh --preview" in " ".join(text.split())
    assert "Vorgabe: master." in " ".join(text.split())
    assert "Vorgabe: README.md." in " ".join(text.split())
    assert not (tmp_path / "projecttools").exists()


def test_pipe_ausgabe_bleibt_ohne_ansi(tmp_path: Path) -> None:
    environment = {**os.environ, "TERM": "xterm-256color", "XDG_CACHE_HOME": str(tmp_path)}
    environment.pop("NO_COLOR", None)
    result = subprocess.run(
        [str(SCRIPT), "--help"], env=environment, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert "--preview" in result.stdout and not ANSI.search(result.stdout)


def test_terminal_fehler_ist_rot_und_ohne_traceback(tmp_path: Path) -> None:
    environment = {
        **os.environ,
        "LANGUAGE": "de",
        "TERM": "xterm-256color",
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
    }
    environment.pop("NO_COLOR", None)
    status, output = terminal_output(
        ["--preview", "--ref", "master", "--project-dir", str(tmp_path)], environment
    )
    assert status == 1 and "✗" in output and "README" in output
    assert "\x1b[38;5;196m" in output or "\x1b[31m" in output
    assert "Traceback" not in output
