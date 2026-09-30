"""Theme-Vertrag und echte Make-/Bash-/Python-Ausgabe gegeneinander prüfen."""

import os
import subprocess
from pathlib import Path

import pytest
from projecttools.ui.colors import THEMES, Theme

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "src/bash/py-run.sh"


@pytest.mark.parametrize("name", [*THEMES, "unknown"])
def test_shared_palette_and_layout(
    name: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    make_root = os.environ.get("THEME_MAKE_LIB")
    bash_root = os.environ.get("BASH_LIBS")
    if not make_root or not bash_root:
        pytest.skip(
            "THEME_MAKE_LIB und BASH_LIBS für den repositoryübergreifenden Vergleich setzen"
        )
    for key in list(os.environ):
        if key.startswith("THEME_"):
            monkeypatch.delenv(key)
    monkeypatch.setenv("MAKE_THEME", name)
    monkeypatch.setenv("TERM", "xterm-256color")
    monkeypatch.delenv("NO_COLOR", raising=False)
    theme = Theme()

    class Terminal:
        def isatty(self) -> bool:
            return True

    terminal = Terminal()
    makefile = tmp_path / "theme.mk"
    makefile.write_text(
        f"include {make_root}/colours.mk\nall:\n"
        + "".join(
            f"\t@printf '%sVALUE\\033[0m\\n' '$(THEME_COLOR_{role})'\n"
            for role in ["GROUP", "TARGET", "DESC", "SERVER", "DANGER"]
        )
    )
    actual = subprocess.check_output(
        ["make", "--no-print-directory", "-sf", str(makefile)], text=True
    )
    # tput sgr0 ist nur am Ende eines ausgegebenen Textes relevant; hier Standardreset.
    expected = "".join(
        theme.style("VALUE", role, terminal) + "\n"
        for role in ["GROUP", "TARGET", "DESC", "SERVER", "DANGER"]
    )
    assert actual == expected
    command = (
        'source "$1/colors.lib.sh"; '
        "for ROLE in GROUP TARGET DESC SERVER DANGER; "
        "do KEY=THEME_COLOR_$ROLE; "
        'printf "%bVALUE\\033[0m\\n" "${!KEY}"; '
        "done"
    )
    bash = subprocess.check_output(["bash", "-c", command, "_", bash_root], text=True)
    assert bash == expected
    monkeypatch.setenv("NO_COLOR", "1")
    for label in [
        "-o | --output OUTPUT",
        "an-option-name-that-is-longer-than-the-column",
    ]:
        command = 'source "$1/colors.lib.sh"; themeLine "$2" "description"'
        actual = subprocess.check_output(["bash", "-c", command, "_", bash_root, label], text=True)
        assert actual == theme.line(label, "description")


def test_theme_layout_can_be_overridden(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NO_COLOR", "1")
    monkeypatch.setenv("THEME_INDENT_TARGET", "   ")
    monkeypatch.setenv("THEME_WIDTH_TARGET", "12")
    monkeypatch.setenv("THEME_COLUMN_GAP", "4")
    theme = Theme()
    assert theme.line("label", "description").index("description") == 19
    assert (
        theme.line("a label longer than twelve", "description").splitlines()[1].index("description")
        == 19
    )
    monkeypatch.setenv("THEME_WIDTH_TARGET", "invalid")
    assert Theme().width_target == 22


@pytest.mark.parametrize(
    "arguments, status",
    [
        ([], 0),
        (["--help"], 0),
        (["--list"], 0),
        (["--run"], 2),
        (["--run", "missing"], 2),
        (["--unknown"], 2),
    ],
)
def test_runner_help_list_and_errors_do_not_install(
    arguments: list[str], status: int, tmp_path: Path
) -> None:
    result = subprocess.run(
        [str(RUNNER), *arguments],
        env={**os.environ, "XDG_CACHE_HOME": str(tmp_path / "cache"), "LANGUAGE": "en"},
        text=True,
        capture_output=True,
    )
    assert result.returncode == status, result.stderr
    assert "Traceback" not in result.stderr
    if arguments == ["--list"]:
        assert "changelog" in result.stdout and "dockerhub-readme" in result.stdout
        assert "colors" not in result.stdout and "py-run" not in result.stdout
    assert not (tmp_path / "cache").exists()


def test_runner_forwards_help_without_installation(tmp_path: Path) -> None:
    result = subprocess.run(
        [str(RUNNER), "--run", "changelog", "--help"],
        env={**os.environ, "XDG_CACHE_HOME": str(tmp_path / "cache")},
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert "--generate" in result.stdout
    assert not (tmp_path / "cache").exists()


def test_make_macros_and_bash_legacy_calls(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Alte Makronamen, Semikolon-Ersetzung, Leerzeichen und Zusatz-Einrückung."""
    make_root = os.environ.get("THEME_MAKE_LIB")
    bash_root = os.environ.get("BASH_LIBS")
    if not make_root or not bash_root:
        pytest.skip("THEME_MAKE_LIB und BASH_LIBS setzen")
    monkeypatch.setenv("NO_COLOR", "1")
    for name in ["THEME_INDENT_TARGET", "THEME_WIDTH_TARGET", "THEME_COLUMN_GAP"]:
        monkeypatch.delenv(name, raising=False)
    makefile = tmp_path / "compat.mk"
    makefile.write_text(f"""include {make_root}/colours.mk
include {make_root}/tools.mk
all:
\t@$(call usageLine, "label", "description")
\t$(usageLine2) "label" "description"
\t@$(call infoLine, text; more)
\t$(infoLine2) "text, more"
\t@$(call optionLine, "label", "description")
\t$(optionLine2) "label" "description"
""")
    output = subprocess.check_output(["make", "-sf", str(makefile)], text=True).splitlines()
    expected = Theme().line("label", "description").rstrip("\n")
    assert [output[index] for index in [0, 1, 4, 5]] == [expected] * 4
    assert output[2:4] == [" " * 30 + "text, more"] * 2
    command = (
        'source "$1/colors.lib.sh"; '
        "__APPS_LIB__=test; "
        "__DTIME_LIB__=test; "
        'source "$1/tools.lib.sh"; '
        'usageLine "  label  " "description"; '
        'usageLine "" "description" yes; '
        'usageLine "" "description" intend; '
        'usageLine "" "description" 8; '
        'usageLine "label" "${YELLOW}description${NC}"'
    )
    output = subprocess.check_output(
        ["bash", "-c", command, "_", bash_root], text=True
    ).splitlines()
    assert output[0] == expected and output[4] == expected
    assert output[1:3] == [" " * 34 + "description"] * 2
    assert output[3] == " " * 38 + "description"


def test_runner_forwards_exit_code_without_environment(tmp_path: Path) -> None:
    result = subprocess.run(
        [str(RUNNER), "--run", "changelog.py", "--unknown"],
        env={**os.environ, "XDG_CACHE_HOME": str(tmp_path / "cache")},
        text=True,
        capture_output=True,
    )
    assert result.returncode == 2
    assert "unrecognized arguments" in result.stderr or "required" in result.stderr
    assert not (tmp_path / "cache").exists()
