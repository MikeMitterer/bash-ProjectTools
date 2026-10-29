#!/usr/bin/env bash
#------------------------------------------------------------------------------
# repo-status.test.sh — Tests fuer src/bash/repo-status.sh
#
# Integrationstests: Das Script laeuft als Prozess gegen echte Git-Repos in
# einem Temp-Verzeichnis. Wichtigster Fall ist das Repo in einem Git-Worktree
# (`.git` ist dort eine Datei) — es muss wie ein Hauptcheckout erscheinen.
#
# Verwendung:
#   ./tests/bash/repo-status.test.sh --run
#   ./tests/bash/repo-status.test.sh --help
#
# Optionen:
#   -r | --run    Alle Tests ausfuehren
#   -h | --help   Diese Hilfe anzeigen
#------------------------------------------------------------------------------

set -uo pipefail

BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../../../BashLib/src" && pwd)}"
if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
if [[ "${__TOOLS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";  fi

APPNAME="$(basename "$0")"
readonly APPNAME

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../../src/bash" && pwd)/repo-status.sh"
readonly SCRIPT_UNDER_TEST

TESTS_RUN=0
TESTS_FAILED=0
FIXTURE=""
OUTPUT=""
EXIT_CODE=0

usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-r | --run " "Alle Tests ausfuehren"
    usageLine "-h | --help" "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Tests starten:  ${GREEN}${APPNAME} --run${NC}"
    echo
}

# Meldet ein Testergebnis und zaehlt mit.
#
# Params:
#   $1 - 0 bei Erfolg, sonst Fehler
#   $2 - Beschreibung
report() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} $2"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $2"
        local _LINE
        while IFS= read -r _LINE; do
            echo "        | ${_LINE}"
        done <<<"${OUTPUT}"
    fi
}

# Prueft eine Bedingung (Befehl) und meldet das Ergebnis.
#
# Params:
#   $1    - Beschreibung
#   $2... - Befehl, der bei Erfolg 0 liefert
assertThat() {
    local -r _TEXT="$1"
    shift
    if "$@"; then report 0 "${_TEXT}"; else report 1 "${_TEXT}"; fi
}

# Git ohne globale Config des Rechners, damit Hooks oder Signierung nicht stoeren.
gitQuiet() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        git -c user.name=test -c user.email=test@example.invalid "$@" >/dev/null 2>&1
}

# Startet das Script im Workspace-Verzeichnis. Ausgabe ohne ANSI-Farben in
# OUTPUT, Exit-Code in EXIT_CODE.
runScript() {
    local _RAW
    _RAW="$(cd "${FIXTURE}/workspace" && "${SCRIPT_UNDER_TEST}" "$@" 2>&1)"
    EXIT_CODE=$?
    OUTPUT="$(printf '%s' "${_RAW}" | sed $'s/\x1b\\[[0-9;]*m//g')"
}

# Gibt die Tabellenzeile eines Repos aus (leer, wenn es fehlt).
#
# Params:
#   $1 - Anzeigename
rowOf() {
    printf '%s\n' "${OUTPUT}" | grep -E "^ +$1 " || true
}

rowContains() { [[ "$(rowOf "$1")" == *"$2"* ]]; }

rowLacks() { [[ "$(rowOf "$1")" != *"$2"* ]]; }

exitCodeIs() { [[ "${EXIT_CODE}" -eq "$1" ]]; }

# Workspace mit Hauptcheckout `main`, Worktree `main-wt`, Ordner ohne Repo
# `plain` (liegt im Workspace-Repo) und fehlendem Pfad `missing`.
setupFixture() {
    FIXTURE="$(mktemp -d)"
    local -r _WS="${FIXTURE}/workspace"
    mkdir -p "${_WS}/plain"
    gitQuiet init -q "${_WS}"
    gitQuiet init -q "${_WS}/main"
    gitQuiet -C "${_WS}/main" commit -q --allow-empty -m init
    gitQuiet -C "${_WS}/main" worktree add -q --detach "${_WS}/main-wt"
    printf '%s\n' \
        'REPOS=(' \
        '    "main:Main"' \
        '    "main-wt:Worktree"' \
        '    "plain:Plain"' \
        '    "missing:Missing"' \
        ')' >"${_WS}/.repo-status.conf.sh"
}

teardownFixture() {
    if [[ -n "${FIXTURE}" && -d "${FIXTURE}" ]]; then
        rm -rf "${FIXTURE}"
    fi
    FIXTURE=""
}

testOhneArgumentKommtHilfe() {
    setupFixture
    runScript
    assertThat "ohne Argument: Hilfe, Exit 0" exitCodeIs 0
    assertThat "ohne Argument: Usage-Zeile" [ -n "$(printf '%s' "${OUTPUT}" | grep 'repo-status.sh')" ]
    teardownFixture
}

testHauptcheckoutIstClean() {
    setupFixture
    runScript --show
    assertThat "Hauptcheckout: Exit 0" exitCodeIs 0
    assertThat "Hauptcheckout: clean" rowContains Main "clean"
    teardownFixture
}

testWorktreeZeigtZustand() {
    setupFixture
    runScript --show
    assertThat "Worktree: clean statt nicht ausgecheckt" rowContains Worktree "clean"
    assertThat "Worktree: nicht als fehlend gemeldet" rowLacks Worktree "nicht ausgecheckt"
    teardownFixture
}

testWorktreeZeigtAenderungen() {
    setupFixture
    touch "${FIXTURE}/workspace/main-wt/neu.txt"
    runScript --show
    assertThat "Worktree: 1 unkommitiert" rowContains Worktree "1 unkommitiert"
    teardownFixture
}

testOrdnerOhneRepoIstNichtAusgecheckt() {
    setupFixture
    runScript --show
    assertThat "Ordner im fremden Repo: nicht ausgecheckt" rowContains Plain "nicht ausgecheckt"
    assertThat "fehlender Pfad: nicht ausgecheckt" rowContains Missing "nicht ausgecheckt"
    teardownFixture
}

runAll() {
    echo
    echo -e "${CYAN}▶ ${APPNAME}${NC}"
    testOhneArgumentKommtHilfe
    testHauptcheckoutIstClean
    testWorktreeZeigtZustand
    testWorktreeZeigtAenderungen
    testOrdnerOhneRepoIstNichtAusgecheckt

    echo
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "  ${GREEN}${TESTS_RUN} Tests, alle gruen${NC}"
        echo
        return 0
    fi
    echo -e "  ${RED}${TESTS_FAILED} von ${TESTS_RUN} Tests fehlgeschlagen${NC}"
    echo
    return 1
}

trap teardownFixture EXIT

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    -r|--run)  runAll ;;
    -h|--help) usage; exit 0 ;;
    *)
        echo -e "${RED}Unbekannte Option: $1${NC}" >&2
        usage
        exit 1
        ;;
esac
