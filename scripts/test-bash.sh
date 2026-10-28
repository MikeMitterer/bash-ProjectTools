#!/usr/bin/env bash
#------------------------------------------------------------------------------
# test-bash.sh — Alle Bash-Testsuiten unter tests/bash/ ausführen
#
# Mit --bash32 laufen die Suiten unter /bin/bash 3.2 (macOS). Dazu reicht es
# nicht, die Suite mit /bin/bash zu starten: Die getesteten Skripte starten über
# "#!/usr/bin/env bash" und nähmen sonst wieder die neuere Bash aus dem PATH.
# Deshalb steht ein Link auf /bin/bash vorn im PATH.
#
# Verwendung:
#   ./scripts/test-bash.sh --run | --bash32 | --help
#   make test-bash / make test-bash32
#------------------------------------------------------------------------------
set -euo pipefail

readonly APPNAME="${0##*/}"
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_ROOT
readonly BASH32="/bin/bash"

usage() {
    printf '\nUsage: %s [ options ]\n\n' "${APPNAME}"
    printf '    %-12s %s\n' "--run" "Alle Suiten mit der Bash aus dem PATH ausführen"
    printf '    %-12s %s\n' "--bash32" "Alle Suiten unter ${BASH32} 3.2 ausführen (macOS)"
    printf '    %-12s %s\n\n' "--help" "Diese Hilfe anzeigen"
}

# Die Suiten binden BashLib ein (wie in den Suiten: BASH_LIBS, sonst der
# Nachbar im DevBash-Baum). Fehlt sie, einmal klar abbrechen statt in jeder Suite.
#
# Returns:
#   0 wenn BashLib lesbar ist, 1 sonst
requireBashLib() {
    local -r _LIBS="${BASH_LIBS:-${PROJECT_ROOT}/../BashLib/src}"
    [[ -r "${_LIBS}/tools.lib.sh" ]] && return 0
    printf '✗ BashLib fehlt (%s): Die Bash-Tests brauchen sie.\n' "${_LIBS}" >&2
    printf '  Neben ProjectTools klonen: git clone https://github.com/MikeMitterer/bash-lib.git ../BashLib\n' >&2
    printf '  danach make setup, oder BASH_LIBS auf deren src setzen.\n' >&2
    return 1
}

# Führt jede Suite aus und meldet das Ergebnis je Suite.
#
# Returns:
#   0 wenn alle Suiten grün sind, 1 sonst
runSuites() {
    local _SUITE _FAILED=0
    requireBashLib || return 1
    printf '\n%s\n' "$(bash --version | head -1)"
    for _SUITE in "${PROJECT_ROOT}"/tests/bash/*.test.sh; do
        if ! bash "${_SUITE}" --run; then
            printf '✗ %s fehlgeschlagen\n' "${_SUITE#"${PROJECT_ROOT}"/}" >&2
            _FAILED=1
        fi
    done
    return "${_FAILED}"
}

# Führt die Suiten mit /bin/bash 3.2 vorn im PATH aus.
runSuitesWithBash32() {
    # shellcheck disable=SC2016  # die Expansion gehört der Bash 3.2, nicht dieser Shell
    if [[ "$("${BASH32}" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')" != "3.2" ]]; then
        printf '✗ %s ist keine Bash 3.2 — der Lauf ist nur unter macOS sinnvoll.\n' "${BASH32}" >&2
        return 2
    fi
    local _DIR _RESULT=0
    _DIR="$(mktemp -d)"
    ln -s "${BASH32}" "${_DIR}/bash"
    PATH="${_DIR}:${PATH}" runSuites || _RESULT=$?
    command rm -rf -- "${_DIR}"
    return "${_RESULT}"
}

case "${1:-}" in
    --run)    runSuites ;;
    --bash32) runSuitesWithBash32 ;;
    ""|-h|--help) usage ;;
    *) printf '✗ Unbekannte Option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
