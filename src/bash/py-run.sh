#!/usr/bin/env bash
#------------------------------------------------------------------------------
# py-run.sh — ProjectTools-Python-Werkzeuge auflisten und starten
#
# Aufruf: py-run.sh --list | --run SCRIPT [ARGUMENTE ...]
# Ohne Argumente: Hilfe. Reine Standardbibliothek benötigt keine Umgebung.
# Paketabhängigkeiten werden einmalig in einer eigenen Werkzeug-venv eingerichtet.
#------------------------------------------------------------------------------
set -euo pipefail

readonly APPNAME="${0##*/}"
export PROJECTTOOLS_RUNNER_NAME="${APPNAME}"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
BOOTSTRAP_PYTHON="${PYTHON_BOOTSTRAP:-python3}"
if [[ -z ${PYTHON_BOOTSTRAP:-} ]] && ! "${BOOTSTRAP_PYTHON}" -c \
    'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; then
    for CANDIDATE in python3.14 python3.13 python3.12 python3.11; do
        if command -v "${CANDIDATE}" >/dev/null 2>&1; then
            BOOTSTRAP_PYTHON="${CANDIDATE}"
            break
        fi
    done
fi
readonly BOOTSTRAP_PYTHON
exec "${BOOTSTRAP_PYTHON}" "${SCRIPT_DIR}/../python/py-run.py" "$@"
