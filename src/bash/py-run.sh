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
# Interpreterwahl für Paketumgebungen liegt zentral im Python-Runner.
readonly BOOTSTRAP_PYTHON="${PYTHON_BOOTSTRAP:-python3}"
exec "${BOOTSTRAP_PYTHON}" "${SCRIPT_DIR}/../python/py-run.py" "$@"
