#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# py-run.py — gemeinsame Ausführung für den Bash-Einstieg py-run.sh
#
# Verwendung: py-run.sh --list | --run SCRIPT [ARGUMENTE ...]
# Hilfe und Werkzeugliste ändern keine Umgebung. Pakete nur in Werkzeug-venv.
# ------------------------------------------------------------------------------
"""ProjectTools-Werkzeuge auflisten und mit ihrer eigenen Umgebung ausführen."""

from __future__ import annotations

import argparse
import gettext
import hashlib
import os
import runpy
import shutil
import subprocess
import sys
from pathlib import Path

from projecttools.ui.colors import HelpFormatter, Theme

_ = gettext.translation(
    "py_run", localedir=Path(__file__).resolve().parent / "locales", fallback=True
).gettext
ROOT = Path(__file__).resolve().parent


def report_error(message: str) -> None:
    """Fehlermeldung mit gemeinsamer Farbe auf stderr."""
    theme = Theme()
    print(
        theme.indent_group + theme.style("✗ " + message, "DANGER", sys.stderr),
        file=sys.stderr,
    )


class ScriptArgumentParser(argparse.ArgumentParser):
    """Native Argumentvalidierung mit der gemeinsamen Fehlerausgabe."""

    def format_help(self) -> str:
        """Leerzeilen wie bei den übrigen CLI-Einstiegen."""
        return "\n" + super().format_help() + "\n"

    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        report_error(message)
        self.exit(2)


def parse_args(arguments: list[str]) -> argparse.Namespace:
    """Runner-Optionen; alles nach dem Werkzeugnamen geht unverändert weiter."""
    parser = ScriptArgumentParser(
        prog=os.environ.get("PROJECTTOOLS_RUNNER_NAME", Path(sys.argv[0]).name),
        description=_("List and run ProjectTools Python scripts."),
        formatter_class=HelpFormatter,
        add_help=False,
        epilog=_("Examples:") + "\n  py-run.sh --list\n  py-run.sh --run changelog --help",
    )
    parser.color = False
    group = parser.add_argument_group(_("Options"))
    actions = group.add_mutually_exclusive_group(required=True)
    actions.add_argument("-l", "--list", action="store_true", help=_("List available scripts."))
    actions.add_argument(
        "-r",
        "--run",
        nargs=argparse.REMAINDER,
        metavar="SCRIPT",
        help=_("Run a script; remaining arguments belong to that script."),
    )
    group.add_argument("-h", "--help", action="help", help=_("Show this help and exit."))
    options = parser.parse_args(arguments or ["--help"])
    if options.run == []:
        parser.error(_("Specify a script after --run."))
    return options


def scripts() -> dict[str, Path]:
    """Findet direkte CLI-Einstiege, ohne Module oder Werkzeuge zu importieren."""
    return {
        path.stem: path
        for path in sorted(ROOT.glob("*.py"))
        if path.name != "py-run.py"
        and path.read_text(encoding="utf-8").startswith("#!/usr/bin/env python3")
        and 'if __name__ == "__main__":' in path.read_text(encoding="utf-8")
    }


def run_command(arguments: list[str]) -> bool:
    """Unterdrückt Paketmanager-Ausgaben; Fehler werden ohne Zugangsdaten gemeldet."""
    return (
        subprocess.run(arguments, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
        == 0
    )


def bootstrap_python() -> Path:
    """Wählt für Paketumgebungen ein vorhandenes Python; installiert Python nicht.

    PYTHON_BOOTSTRAP ist ein expliziter Override. Ohne Override werden der
    laufende Interpreter und danach bekannte Python-Namen im PATH geprüft.
    """
    override = os.environ.get("PYTHON_BOOTSTRAP")
    candidates = [override] if override else [
        sys.executable, "python3.14", "python3.13", "python3.12", "python3.11", "python3"
    ]
    for candidate in dict.fromkeys(candidates):
        interpreter = shutil.which(candidate)
        if interpreter and run_command([
            interpreter, "-c", "import sys; sys.exit(sys.version_info < (3, 11))"
        ]):
            return Path(interpreter)
    raise RuntimeError(
        _(
            "Package setup requires an installed Python 3.11 or newer. "
            "Install a suitable Python or set PYTHON_BOOTSTRAP to its executable."
        )
    )


def tool_python(engine: Path, arguments: list[str]) -> Path:
    """Hilfe und Standardbibliothek direkt, sonst isolierte venv mit Requirements.

    Ein optionales prepare_cli(arguments) validiert Eingaben vor der Installation.
    Die Requirements-Datei neben dem Script ist die einzige Paketliste.
    """
    requirements = engine.with_suffix(".requirements.txt")
    if (
        not requirements.exists()
        or not arguments
        or any(arg in {"-h", "--help"} for arg in arguments)
    ):
        return Path(sys.executable)
    bootstrap = bootstrap_python()
    # Keine Fachaktion auslösen: run_name ist ausdrücklich nicht __main__.
    module = runpy.run_path(str(engine))
    prepare = module.get("prepare_cli")
    if prepare is not None:
        prepare(arguments)
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    if not cache.is_absolute():
        cache = Path.home() / ".cache"
    runtime = cache / "projecttools" / engine.stem
    venv = runtime / ".venv"
    if runtime.is_symlink() or venv.is_symlink():
        raise RuntimeError(
            _("The tool environment must not be a symlink. Check the ProjectTools cache directory.")
        )
    interpreter = venv / "bin/python"
    if not interpreter.exists():
        if not run_command([str(bootstrap), "-m", "venv", str(venv)]):
            raise RuntimeError(
                _("Could not create .venv. Check Python's venv support and directory permissions.")
            )
    if not run_command(
        [
            str(interpreter),
            "-c",
            "import pathlib,sys; assert sys.version_info >= (3,11); assert "
            "sys.prefix != sys.base_prefix; assert "
            "pathlib.Path(sys.prefix).resolve() == "
            "pathlib.Path(sys.argv[1]).resolve()",
            str(venv),
        ]
    ):
        raise RuntimeError(
            _("The tool .venv must be a working virtual environment with Python 3.11 or newer.")
        )
    stamp = runtime / "requirements.sha256"
    digest = hashlib.sha256(requirements.read_bytes()).hexdigest()
    unchanged = stamp.is_file() and stamp.read_text() == digest
    installed = run_command(
        [
            str(interpreter),
            "-c",
            """
import importlib.metadata, pathlib, re, sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    pin = re.fullmatch(r"([A-Za-z0-9_.-]+)==([^ ;]+)", line.strip())
    if pin:
        assert importlib.metadata.version(pin[1]) == pin[2]
""",
            str(requirements),
        ]
    )
    if not unchanged or not installed or not run_command([str(interpreter), "-m", "pip", "check"]):
        if not run_command([str(interpreter), "-m", "pip", "--version"]):
            if not run_command([str(interpreter), "-m", "ensurepip", "--upgrade"]):
                raise RuntimeError(
                    _(
                        "Could not install dependencies in .venv. Check pip and "
                        "package-index access."
                    )
                )
        if not run_command(
            [
                str(interpreter),
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--quiet",
                "-r",
                str(requirements),
            ]
        ):
            raise RuntimeError(
                _("Could not install dependencies in .venv. Check pip and package-index access.")
            )
        stamp.write_text(digest)
    return interpreter


def main(arguments: list[str]) -> int:
    """Listet oder übergibt Prozess, Argumente und Exit-Code an das Werkzeug."""
    available = scripts()
    # Symlinks wie bash/dockerhub-readme.sh wählen das Werkzeug über ihren Namen.
    invoked_name = Path(sys.argv[0]).stem
    if invoked_name in available:
        os.environ.setdefault("PROJECTTOOLS_APPNAME", Path(sys.argv[0]).name)
        arguments = ["--run", invoked_name, *arguments]
    options = parse_args(arguments)
    if options.list:
        theme = Theme()
        print(
            "\n" * theme.group_spacing
            + theme.indent_group
            + theme.style(_("Available scripts:"), "GROUP")
        )
        for name, engine in available.items():
            mode = (
                _("Own virtual environment")
                if engine.with_suffix(".requirements.txt").exists()
                else _("Standard library; no installation")
            )
            print(theme.line(name, mode), end="")
        print()
        return 0
    name, *forwarded = options.run
    if name.endswith(".py"):
        name = name[:-3]
    if name not in available:
        report_error(_("Unknown script: {name}. Use --list.").format(name=name))
        return 2
    try:
        interpreter = tool_python(available[name], forwarded)
        os.execv(str(interpreter), [str(interpreter), str(available[name]), *forwarded])
    except (OSError, RuntimeError) as error:
        report_error(str(error))
        if os.environ.get("DOCKER_README_AFTER_PUSH") == "1" and name == "dockerhub-readme":
            report_error(_("The image was already pushed. Retry the README upload separately."))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
