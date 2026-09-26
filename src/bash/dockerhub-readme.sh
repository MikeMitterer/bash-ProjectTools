#!/usr/bin/env bash
#------------------------------------------------------------------------------
# dockerhub-readme.sh — Python-Umgebung prüfen und README-Werkzeug starten
#
# Hilfe ohne Installation; Aktionen nutzen eine eigene .venv im Benutzer-Cache.
# Python 3.11+ und Pandoc werden lokal vorausgesetzt. Pakete nur in der .venv.
#
# Verwendung:
#   .libs/ProjectTools/src/bash/dockerhub-readme.sh --help
#   .libs/ProjectTools/src/bash/dockerhub-readme.sh --preview --ref master
#   .libs/ProjectTools/src/bash/dockerhub-readme.sh --publish --ref master -r user/repo
#------------------------------------------------------------------------------
set -euo pipefail

readonly APPNAME="${0##*/}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# BashLib-Farben an die Python-Ausgabe reichen; ohne BashLib nutzt sie ANSI-Basisfarben.
BASH_LIBS="${BASH_LIBS:-${SCRIPT_DIR}/../../../BashLib/src}"
if [[ -r "${BASH_LIBS}/colors.lib.sh" ]]; then
    # shellcheck disable=SC1091  # Geteilte Bibliothek aus BASH_LIBS.
    if [[ "${__COLORS_LIB__:-}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
    for COLOR_NAME in BLUE LIGHT_BLUE YELLOW GREEN RED; do
        printf -v "PROJECTTOOLS_COLOR_${COLOR_NAME}" '%b' "${!COLOR_NAME}"
        export "PROJECTTOOLS_COLOR_${COLOR_NAME}"
    done
fi
export PROJECTTOOLS_APPNAME="${APPNAME}"
readonly ENGINE="${SCRIPT_DIR}/../python/dockerhub-readme.py"
BOOTSTRAP_PYTHON="${PYTHON_BOOTSTRAP:-python3}"
if [[ -z "${PYTHON_BOOTSTRAP:-}" ]] && ! "${BOOTSTRAP_PYTHON}" -c \
    'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; then
    for CANDIDATE in python3.14 python3.13 python3.12 python3.11; do
        if command -v "${CANDIDATE}" >/dev/null 2>&1 && "${CANDIDATE}" -c \
            'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; then
            BOOTSTRAP_PYTHON="${CANDIDATE}"
            break
        fi
    done
fi
readonly BOOTSTRAP_PYTHON

# Vorhandenen gettext-Katalog nutzen, ohne eigene Text- oder Optionskopie.
reportError() {
    "${BOOTSTRAP_PYTHON}" -c '
import runpy, sys
module = runpy.run_path(sys.argv[1])
module["report_error"](module["_"](sys.argv[2]))
' "${ENGINE}" "$1"
}

# Hilfe startet weder venv noch pip. Der Parser bleibt ausschließlich in Python.
if [[ $# -eq 0 ]]; then
    exec "${BOOTSTRAP_PYTHON}" "${ENGINE}" --help
fi
for ARGUMENT in "$@"; do
    if [[ "${ARGUMENT}" == "--help" || "${ARGUMENT}" == "-h" ]]; then
        exec "${BOOTSTRAP_PYTHON}" "${ENGINE}" "$@"
    fi
done

# Erst alle Optionen validieren; ungültige Aufrufe verändern keine Umgebung.
"${BOOTSTRAP_PYTHON}" -c '
import runpy, sys
module = runpy.run_path(sys.argv[1])
options = module["parse_args"](sys.argv[2:])
try:
    module["validate_inputs"](options)
except module["UploadError"] as error:
    module["report_error"](str(error))
    sys.exit(1)
' "${ENGINE}" "$@"
readonly RUNTIME_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/projecttools/dockerhub-readme"
readonly VENV="${RUNTIME_DIR}/.venv"
readonly REQUIREMENTS="${SCRIPT_DIR}/../python/dockerhub-readme.requirements.txt"

if ! command -v pandoc >/dev/null 2>&1; then
    reportError "Pandoc is missing. Install it from https://pandoc.org/installing.html."
    exit 1
fi
if [[ -L "${RUNTIME_DIR}" || -L "${VENV}" ]]; then
    reportError "The tool environment must not be a symlink. Check the ProjectTools cache directory."
    exit 1
fi
if [[ ! -x "${VENV}/bin/python" ]]; then
    if ! "${BOOTSTRAP_PYTHON}" -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
        reportError "Python 3.11 or newer is required. Set PYTHON_BOOTSTRAP to a suitable interpreter."
        exit 1
    fi
    if ! "${BOOTSTRAP_PYTHON}" -m venv "${VENV}"; then
        reportError "Could not create .venv. Check Python's venv support and directory permissions."
        exit 1
    fi
fi
# Eine vorhandene Umgebung weder löschen noch durch eine fremde ersetzen.
if ! "${VENV}/bin/python" -c '
import pathlib, sys
assert sys.version_info >= (3, 11)
assert sys.prefix != sys.base_prefix
assert pathlib.Path(sys.prefix).resolve() == pathlib.Path(sys.argv[1]).resolve()
' "${VENV}" >/dev/null 2>&1; then
    reportError "The tool .venv must be a working virtual environment with Python 3.11 or newer."
    exit 1
fi
if ! "${VENV}/bin/python" -c '
import httpx, pathlib, sys
assert "httpx==" + httpx.__version__ == pathlib.Path(sys.argv[1]).read_text().strip()
' "${REQUIREMENTS}" >/dev/null 2>&1; then
    if ! "${VENV}/bin/python" -m pip --version >/dev/null 2>&1; then
        if ! "${VENV}/bin/python" -m ensurepip --upgrade >/dev/null 2>&1; then
            reportError "Could not install the README dependencies in .venv. Check pip and package-index access."
            exit 1
        fi
    fi
    if ! "${VENV}/bin/python" -m pip install --disable-pip-version-check --quiet \
        -r "${REQUIREMENTS}" >/dev/null 2>&1; then
        reportError "Could not install the README dependencies in .venv. Check pip and package-index access."
        exit 1
    fi
fi
exec "${VENV}/bin/python" "${ENGINE}" "$@"
