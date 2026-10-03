#!/usr/bin/env bash
#------------------------------------------------------------------------------
# dev-ports.test.sh — Tests fuer src/bash/dev-ports.sh
#
# Integrationstests: Das Script laeuft als Prozess gegen echte lauschende
# Prozesse (python3 -m http.server auf freien Ports). Kein Mock — nur so zeigt
# sich, ob ein Port danach wirklich frei ist.
#
# Der wichtigste Fall ist `testFremdesVerzeichnisBleibtUnberuehrt`: Ein Prozess
# aus einem anderen Projekt darf ohne --any-dir nie beendet werden.
#
# Jeder Test raeumt nur die Prozesse auf, die er selbst gestartet hat.
#
# Verwendung:
#   ./tests/bash/dev-ports.test.sh --run
#   ./tests/bash/dev-ports.test.sh --help
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

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../../src/bash" && pwd)/dev-ports.sh"
readonly SCRIPT_UNDER_TEST

TESTS_RUN=0
TESTS_FAILED=0
FIXTURE=""
STARTED_PIDS=()
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

# Gibt einen freien TCP-Port auf 127.0.0.1 aus.
freePort() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

# Prueft, ob auf dem Port jemand lauscht.
#
# Params:
#   $1 - Port
isListening() {
    [[ -n "$(lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null)" ]]
}

isFree() { ! isListening "$1"; }

isAlive() { kill -0 "$1" 2>/dev/null; }

isDead() { ! isAlive "$1"; }

# Startet einen lauschenden Python-Server und wartet, bis der Port offen ist.
# Die PID landet in STARTED_PID.
#
# Params:
#   $1 - Arbeitsverzeichnis
#   $2 - Port
#   $3 - Python-Code vor dem Serverstart (optional)
startListener() {
    local -r _DIR="$1"
    local -r _PORT="$2"
    local -r _PRELUDE="${3:-}"
    (
        cd "${_DIR}" || exit 1
        exec python3 -c "
import http.server, signal, subprocess, sys
${_PRELUDE}
http.server.HTTPServer(('127.0.0.1', ${_PORT}), http.server.SimpleHTTPRequestHandler).serve_forever()
" >/dev/null 2>&1
    ) &
    STARTED_PID=$!
    # Ohne Jobtabelle meldet die Shell beendete Listener nicht als "Killed: 9".
    disown "${STARTED_PID}" 2>/dev/null || true
    STARTED_PIDS+=("${STARTED_PID}")
    local _TRY
    for _TRY in $(seq 1 50); do
        isListening "${_PORT}" && return 0
        sleep 0.1
    done
    echo "Listener auf ${_PORT} startete nicht" >&2
    return 1
}

# Startet das Script im Projektverzeichnis. Ausgabe ohne ANSI-Farben in
# OUTPUT, Exit-Code in EXIT_CODE.
runScript() {
    local _RAW
    _RAW="$(cd "${FIXTURE}/project" && "${SCRIPT_UNDER_TEST}" "$@" 2>&1)"
    EXIT_CODE=$?
    OUTPUT="$(printf '%s' "${_RAW}" | sed $'s/\x1b\\[[0-9;]*m//g')"
}

outputContains() { [[ "${OUTPUT}" == *"$1"* ]]; }

exitCodeIs() { [[ "${EXIT_CODE}" -eq "$1" ]]; }

setupFixture() {
    FIXTURE="$(mktemp -d)"
    mkdir -p "${FIXTURE}/project" "${FIXTURE}/other"
}

# Beendet nur die selbst gestarteten Prozesse und loescht das Temp-Verzeichnis.
teardownFixture() {
    local _PID
    for _PID in "${STARTED_PIDS[@]+"${STARTED_PIDS[@]}"}"; do
        pkill -KILL -P "${_PID}" 2>/dev/null || true
        kill -KILL "${_PID}" 2>/dev/null || true
    done
    STARTED_PIDS=()
    if [[ -n "${FIXTURE}" && -d "${FIXTURE}" ]]; then
        rm -rf "${FIXTURE}"
    fi
    FIXTURE=""
}

testOhneArgumentKommtHilfe() {
    setupFixture
    runScript
    assertThat "ohne Argument: Hilfe, Exit 0" exitCodeIs 0
    assertThat "ohne Argument: Usage-Zeile" outputContains "Usage: dev-ports.sh"
    teardownFixture
}

testOhneConfigKommtTipp() {
    setupFixture
    runScript --status
    assertThat "ohne Config: Exit 1" exitCodeIs 1
    assertThat "ohne Config: Tipp auf --example" outputContains "--example"
    teardownFixture
}

testBeispielConfigErkenntPortsAusProcfile() {
    setupFixture
    printf '%s\n' \
        'backend: uvicorn app:app --port 8000 --reload' \
        'dashboard: npm run dev -- --port=5173' >"${FIXTURE}/project/Procfile.dev"
    runScript --example
    printf '%s\n' "${OUTPUT}" >"${FIXTURE}/project/.dev-ports.conf.sh"
    local _PORTS
    _PORTS="$(PORTS=(); . "${FIXTURE}/project/.dev-ports.conf.sh"; echo "${PORTS[*]}")"
    OUTPUT="${_PORTS}"
    assertThat "--example: sourcebar, Ports aus Procfile.dev" [ "${_PORTS}" == "5173 8000" ]
    teardownFixture
}

testShowNenntFreienUndBelegtenPort() {
    setupFixture
    local -r _BUSY="$(freePort)"
    local -r _FREE="$(freePort)"
    startListener "${FIXTURE}/project" "${_BUSY}"
    runScript --status --port "${_BUSY}" --port "${_FREE}"
    assertThat "--status: Exit 0" exitCodeIs 0
    assertThat "--status: freier Port als frei" outputContains "${_FREE} frei"
    assertThat "--status: belegter Port mit PID" outputContains "PID ${STARTED_PID}"
    assertThat "--status: belegter Port mit Benutzer" outputContains "$(id -un)"
    assertThat "--status: beendet nichts" isAlive "${STARTED_PID}"
    teardownFixture
}

testKillBeendetLauscherSamtKind() {
    setupFixture
    local -r _PORT="$(freePort)"
    startListener "${FIXTURE}/project" "${_PORT}" \
        "CHILD = subprocess.Popen(['sleep', '300'])"
    local -r _LISTENER="${STARTED_PID}"
    local _CHILD
    _CHILD="$(pgrep -P "${_LISTENER}" | head -n1)"
    runScript --kill --port "${_PORT}"
    assertThat "--kill: Exit 0" exitCodeIs 0
    assertThat "--kill: Port frei" isFree "${_PORT}"
    assertThat "--kill: Lauscher beendet" isDead "${_LISTENER}"
    assertThat "--kill: Kindprozess beendet" isDead "${_CHILD}"
    teardownFixture
}

testDryRunBeendetNichts() {
    setupFixture
    local -r _PORT="$(freePort)"
    startListener "${FIXTURE}/project" "${_PORT}"
    runScript --kill --dry-run --port "${_PORT}"
    assertThat "--dry-run: Exit 0" exitCodeIs 0
    assertThat "--dry-run: kuendigt an" outputContains "Dry-Run"
    assertThat "--dry-run: Prozess lebt" isAlive "${STARTED_PID}"
    teardownFixture
}

testFremdesVerzeichnisBleibtUnberuehrt() {
    setupFixture
    local -r _PORT="$(freePort)"
    startListener "${FIXTURE}/other" "${_PORT}"
    runScript --kill --port "${_PORT}"
    assertThat "fremdes Verzeichnis: Exit 1" exitCodeIs 1
    assertThat "fremdes Verzeichnis: Prozess lebt" isAlive "${STARTED_PID}"
    assertThat "fremdes Verzeichnis: Hinweis auf --any-dir" outputContains "--any-dir"

    runScript --kill --any-dir --port "${_PORT}"
    assertThat "--any-dir: Exit 0" exitCodeIs 0
    assertThat "--any-dir: Prozess beendet" isDead "${STARTED_PID}"
    teardownFixture
}

testSigtermIgnoriertFolgtSigkill() {
    setupFixture
    local -r _PORT="$(freePort)"
    startListener "${FIXTURE}/project" "${_PORT}" \
        "signal.signal(signal.SIGTERM, signal.SIG_IGN)"
    runScript --kill --timeout 1 --port "${_PORT}"
    assertThat "SIGTERM ignoriert: Exit 0" exitCodeIs 0
    assertThat "SIGTERM ignoriert: SIGKILL gemeldet" outputContains "SIGKILL"
    assertThat "SIGTERM ignoriert: Prozess beendet" isDead "${STARTED_PID}"
    assertThat "SIGTERM ignoriert: Port frei" isFree "${_PORT}"
    teardownFixture
}

# Startet einen Prozess, dessen Kommandozeile wie overmind bzw. sein
# tmux-Server aussieht (`exec -a` setzt argv[0]); PID in STARTED_PID.
#
# Params:
#   $1 - Arbeitsverzeichnis
#   $2 - vorgetaeuschte Kommandozeile
startFakeOvermind() {
    (
        cd "$1" || exit 1
        exec -a "$2" sleep 300
    ) &
    STARTED_PID=$!
    disown "${STARTED_PID}" 2>/dev/null || true
    STARTED_PIDS+=("${STARTED_PID}")
    sleep 0.3
}

testOvermindResteDesProjektsWerdenBeendet() {
    setupFixture
    local -r _PORT="$(freePort)"
    startFakeOvermind "${FIXTURE}/project" "tmux -C -L overmind-project-abc new -s project"
    local -r _TMUX="${STARTED_PID}"
    startFakeOvermind "${FIXTURE}/other" "tmux -C -L overmind-other-xyz new -s other"
    local -r _FOREIGN="${STARTED_PID}"
    runScript --kill --port "${_PORT}"
    assertThat "overmind: Exit 0" exitCodeIs 0
    assertThat "overmind: tmux-Rest des Projekts beendet" isDead "${_TMUX}"
    assertThat "overmind: tmux eines anderen Projekts lebt" isAlive "${_FOREIGN}"
    teardownFixture
}

testVerwaisteOvermindSocketWirdEntfernt() {
    setupFixture
    local -r _PORT="$(freePort)"
    python3 -c "import socket; s=socket.socket(socket.AF_UNIX); s.bind('${FIXTURE}/project/.overmind.sock'); s.close()"
    runScript --kill --dry-run --port "${_PORT}"
    assertThat "Socket: Dry-Run laesst sie liegen" [ -S "${FIXTURE}/project/.overmind.sock" ]
    runScript --kill --port "${_PORT}"
    assertThat "Socket: Exit 0" exitCodeIs 0
    assertThat "Socket: verwaiste .overmind.sock entfernt" [ ! -e "${FIXTURE}/project/.overmind.sock" ]
    teardownFixture
}

testMehrfachaufrufNacheinander() {
    setupFixture
    local -r _PORT="$(freePort)"
    startListener "${FIXTURE}/project" "${_PORT}"
    runScript --kill --port "${_PORT}"
    assertThat "1. Aufruf: Exit 0" exitCodeIs 0
    runScript --kill --port "${_PORT}"
    assertThat "2. Aufruf ohne Stack: Exit 0" exitCodeIs 0
    assertThat "2. Aufruf ohne Stack: Port frei gemeldet" outputContains "${_PORT} ist frei"
    runScript --kill --port "${_PORT}"
    assertThat "3. Aufruf ohne Stack: Exit 0" exitCodeIs 0
    teardownFixture
}

testMehrfachaufrufGleichzeitig() {
    setupFixture
    local -r _PORT="$(freePort)"
    startListener "${FIXTURE}/project" "${_PORT}" \
        "CHILD = subprocess.Popen(['sleep', '300'])"
    local -r _LISTENER="${STARTED_PID}"
    python3 -c "import socket; s=socket.socket(socket.AF_UNIX); s.bind('${FIXTURE}/project/.overmind.sock'); s.close()"
    local _RUNNERS=()
    local _RUN
    for _RUN in 1 2 3; do
        (cd "${FIXTURE}/project" && "${SCRIPT_UNDER_TEST}" --kill --port "${_PORT}" >"${FIXTURE}/run-${_RUN}.log" 2>&1) &
        _RUNNERS+=("$!")
    done
    local _FAILED=0
    for _RUN in "${_RUNNERS[@]}"; do
        wait "${_RUN}" || _FAILED=1
    done
    OUTPUT="$(cat "${FIXTURE}"/run-*.log)"
    assertThat "3 gleichzeitige Aufrufe: alle Exit 0" [ "${_FAILED}" -eq 0 ]
    assertThat "3 gleichzeitige Aufrufe: Port frei" isFree "${_PORT}"
    assertThat "3 gleichzeitige Aufrufe: Lauscher beendet" isDead "${_LISTENER}"
    assertThat "3 gleichzeitige Aufrufe: Socket entfernt" [ ! -e "${FIXTURE}/project/.overmind.sock" ]
    teardownFixture
}

testLaeuftOhneBashLib() {
    setupFixture
    local -r _PORT="$(freePort)"
    startListener "${FIXTURE}/project" "${_PORT}"
    local _RAW
    _RAW="$(cd "${FIXTURE}/project" && BASH_LIBS="${FIXTURE}/keine-bashlib" "${SCRIPT_UNDER_TEST}" --help 2>&1)"
    EXIT_CODE=$?
    OUTPUT="$(printf '%s' "${_RAW}" | sed $'s/\x1b\\[[0-9;]*m//g')"
    assertThat "ohne BashLib: Hilfe, Exit 0" exitCodeIs 0
    assertThat "ohne BashLib: Optionen sichtbar" outputContains "-k | --kill"
    _RAW="$(cd "${FIXTURE}/project" && BASH_LIBS="${FIXTURE}/keine-bashlib" "${SCRIPT_UNDER_TEST}" --kill --port "${_PORT}" 2>&1)"
    EXIT_CODE=$?
    OUTPUT="$(printf '%s' "${_RAW}" | sed $'s/\x1b\\[[0-9;]*m//g')"
    assertThat "ohne BashLib: --kill Exit 0" exitCodeIs 0
    assertThat "ohne BashLib: Port frei" isFree "${_PORT}"
    teardownFixture
}

testPortAusConfig() {
    setupFixture
    local -r _PORT="$(freePort)"
    printf 'PORTS=(%s)\n' "${_PORT}" >"${FIXTURE}/project/.dev-ports.conf.sh"
    startListener "${FIXTURE}/project" "${_PORT}"
    runScript --kill
    assertThat "Config: Exit 0" exitCodeIs 0
    assertThat "Config: Port frei" isFree "${_PORT}"
    teardownFixture
}

runAll() {
    echo
    echo -e "${CYAN}▶ ${APPNAME}${NC}"
    testOhneArgumentKommtHilfe
    testOhneConfigKommtTipp
    testBeispielConfigErkenntPortsAusProcfile
    testShowNenntFreienUndBelegtenPort
    testKillBeendetLauscherSamtKind
    testDryRunBeendetNichts
    testFremdesVerzeichnisBleibtUnberuehrt
    testSigtermIgnoriertFolgtSigkill
    testOvermindResteDesProjektsWerdenBeendet
    testVerwaisteOvermindSocketWirdEntfernt
    testMehrfachaufrufNacheinander
    testMehrfachaufrufGleichzeitig
    testLaeuftOhneBashLib
    testPortAusConfig

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
