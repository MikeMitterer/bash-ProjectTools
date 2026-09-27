#!/usr/bin/env bash
# dockerhub-readme.sh — kompatibler Einstieg zum gemeinsamen Python-Starter.
# Ohne Argumente / --help: Hilfe; --preview / --publish: README verarbeiten.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
export PROJECTTOOLS_APPNAME="${0##*/}"
exec "${SCRIPT_DIR}/py-run.sh" --run dockerhub-readme "$@"
