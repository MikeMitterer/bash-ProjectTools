#!/usr/bin/env bash
#------------------------------------------------------------------------------
# dev-ports.sh — Ports des Dev-Stacks samt zugehoeriger Prozesse freigeben
#
# `make dev-up` startet Backend und Frontend ueber overmind. Stuerzt overmind
# oder eine App ab, bleiben oft Prozesse uebrig, die den Port weiter belegen:
# ein uvicorn-Reloader, ein Vite-Node-Prozess. `make dev-down` erreicht sie
# dann nicht mehr, und der naechste Start scheitert mit "address in use".
#
# Dieses Script findet die Prozesse, die auf den konfigurierten Ports lauschen,
# beendet sie samt Kindprozessen (erst SIGTERM, nach Ablauf der Wartezeit
# SIGKILL) und prueft danach, dass jeder Port wirklich frei ist.
#
# Beendet werden nur Prozesse des eigenen Benutzers, deren Arbeitsverzeichnis
# im aktuellen Projekt liegt. Fremde Lauscher — etwa Docker bei `make up` oder
# eine App aus einem anderen Projekt — bleiben unberuehrt und werden gemeldet.
#
# Die Ports kommen aus einer Config im aktuellen Verzeichnis (Projekt-Root).
#
# Verwendung:
#   dev-ports.sh [--status] [--kill [--dry-run]] [--port <n>]
#   dev-ports.sh --example > .dev-ports.conf.sh   # Starter-Config anlegen
#
# Optionen:
#   -s | --status          Zeigen, ob und von wem die Ports belegt sind
#   -k | --kill            Lauschende Prozesse samt Kindprozessen beenden
#   -n | --dry-run         Mit --kill: nur anzeigen, nichts beenden
#   -p | --port N          Nur diesen Port (mehrfach moeglich, statt Config)
#   -a | --any-dir         Auch Prozesse ausserhalb des Projekts beenden
#   -t | --timeout SEK     Wartezeit vor SIGKILL (Default: 5)
#   -c | --config DATEI    Alternative Config-Datei (Default: ./.dev-ports.conf.sh)
#   -e | --example         Gueltige Beispiel-Config auf stdout ausgeben
#   -h | --help            Diese Hilfe anzeigen
#------------------------------------------------------------------------------

set -euo pipefail

# Logische Pfadaufloesung beibehalten (kein pwd -P) — der Fallback muss auch
# ueber einen .libs/ProjectTools-Symlink funktionieren (.libs/BashLib daneben)
BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../../../BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
if [[ "${__TOOLS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";  fi

APPNAME="$(basename "$0")"
readonly APPNAME
APPNAME_WITHOUT_EXTENSION="${APPNAME%%.*}"
readonly APPNAME_WITHOUT_EXTENSION

CONFIG_BASE="./.${APPNAME_WITHOUT_EXTENSION}.conf"
if [[ -f "${CONFIG_BASE}" ]]; then
    CONFIG_NAME="${CONFIG_BASE}"
else
    CONFIG_NAME="${CONFIG_BASE}.sh"
fi
CONFIG_DISPLAY="${CONFIG_NAME#./}"

# Physischer Pfad: lsof meldet Arbeitsverzeichnisse ebenfalls physisch.
PROJECT_DIR="$(pwd -P)"
readonly PROJECT_DIR

readonly PROCFILE="Procfile.dev"
readonly POLL_INTERVAL=0.2

# Defaults — von Config und Optionen ueberschrieben
PORTS=()
CLI_PORTS=()
ACTION=""
DRY_RUN=false
ANY_DIR=false
TIMEOUT=5

# Zeigt die Verwendungshinweise an.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    echo -e "\t${BLUE}# Anzeigen -------------------------------------------------------------${NC}"
    usageLine "-s | --status          " "Zeigen, ob und von wem die Ports belegt sind"
    echo
    echo -e "\t${BLUE}# Freigeben ------------------------------------------------------------${NC}"
    usageLine "-k | --kill            " "Lauschende Prozesse samt Kindprozessen beenden"
    usageLine "-n | --dry-run         " "Mit --kill: nur anzeigen, nichts beenden"
    usageLine "-p | --port N          " "Nur diesen Port (mehrfach moeglich, statt Config)"
    usageLine "-a | --any-dir         " "Auch Prozesse ausserhalb des aktuellen Projekts beenden"
    usageLine "-t | --timeout SEK     " "Wartezeit vor SIGKILL (Default: ${YELLOW}${TIMEOUT}${NC})"
    echo
    echo -e "\t${BLUE}# Config / Help --------------------------------------------------------${NC}"
    usageLine "-c | --config DATEI    " "Alternative Config-Datei (Default: ${CONFIG_DISPLAY})"
    usageLine "-e | --example         " "Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)"
    usageLine "-h | --help            " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Belegung zeigen:     ${GREEN}${APPNAME} --status${NC}"
    echo -e "    Erst ansehen:        ${GREEN}${APPNAME} --kill --dry-run${NC}"
    echo -e "    Ports freigeben:     ${GREEN}${APPNAME} --kill${NC}"
    echo -e "    Einzelner Port:      ${GREEN}${APPNAME} --kill --port 8000${NC}"
    echo -e "    Config anlegen:      ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
    echo
}

# Gibt eine gueltige, sourcebare Beispiel-Config auf stdout aus.
#
# Schlaegt die Ports vor, die im Procfile.dev als `--port N` stehen. Ports, die
# eine App aus ihrer eigenen Konfiguration nimmt (etwa Vite), findet das nicht —
# die traegt man von Hand nach.
printConfigExample() {
    local _DETECTED=""
    if [[ -f "${PROCFILE}" ]]; then
        _DETECTED="$(grep -oE -- '--port[ =]+[0-9]+' "${PROCFILE}" | grep -oE '[0-9]+' | sort -un | tr '\n' ' ' || true)"
        _DETECTED="${_DETECTED% }"
    fi

    cat <<EOF
#!/usr/bin/env bash
# Config fuer dev-ports.sh (ProjectTools) — wird gesourced, kein Custom-Parser.
# .sh-Endung fuers IDE-Highlighting. Format-Doku: ProjectTools/README.md
# Anlegen/aktualisieren:  ${APPNAME} --example > ${CONFIG_DISPLAY}
# shellcheck disable=SC2034  # von dev-ports.sh gesourct

# Ports, die \`make dev-up\` oeffnet. Aus ${PROCFILE} erkannt: ${_DETECTED:-keine}
# Ports aus App-Konfigurationen (z.B. Vite) bei Bedarf ergaenzen.
PORTS=(${_DETECTED})
EOF
}

# Laedt die Config und prueft die Pflichtwerte.
#
# Returns:
#   0 bei Erfolg, 2 wenn die Datei fehlt, 3 wenn PORTS leer ist,
#   4 bei einem ungueltigen Port
loadConfig() {
    [[ -f "${CONFIG_NAME}" ]] || return 2
    # shellcheck source=/dev/null
    . "${CONFIG_NAME}"
    [[ ${#PORTS[@]} -gt 0 ]] || return 3
    local _PORT
    for _PORT in "${PORTS[@]}"; do
        isValidPort "${_PORT}" || return 4
    done
    return 0
}

# Prueft, ob der Wert ein gueltiger TCP-Port ist.
#
# Params:
#   $1 - Kandidat
isValidPort() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

# Gibt die PIDs aller Prozesse aus, die auf dem Port lauschen (eine je Zeile).
#
# Params:
#   $1 - Port
listenerPids() {
    lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | sort -un || true
}

# Gibt das Arbeitsverzeichnis eines Prozesses aus (leer, wenn unbekannt).
#
# Params:
#   $1 - PID
processCwd() {
    lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n1 || true
}

# Gibt die Kommandozeile eines Prozesses aus (leer, wenn er nicht mehr laeuft).
# Das Programm steht ohne Pfad da: Aus einem langen Python-Framework-Pfad
# wuerde sonst nur der Pfad sichtbar, nicht `uvicorn app.main:app`.
#
# Params:
#   $1 - PID
processCommand() {
    local _COMMAND
    _COMMAND="$(ps -o command= -p "$1" 2>/dev/null || true)"
    local -r _PROGRAM="${_COMMAND%% *}"
    echo "${_PROGRAM##*/}${_COMMAND#"${_PROGRAM}"}"
}

# Prueft, ob ein Prozess dem aufrufenden Benutzer gehoert.
#
# Params:
#   $1 - PID
isOwnProcess() {
    local _UID
    _UID="$(ps -o uid= -p "$1" 2>/dev/null | tr -d ' ' || true)"
    [[ -n "${_UID}" && "${_UID}" == "$(id -u)" ]]
}

# Prueft, ob ein Verzeichnis im Projekt liegt.
#
# Params:
#   $1 - Verzeichnis
isInsideProject() {
    [[ -n "$1" && ( "$1" == "${PROJECT_DIR}" || "$1" == "${PROJECT_DIR}/"* ) ]]
}

# Gibt alle Nachkommen eines Prozesses aus (Kinder zuerst, je Zeile eine PID).
#
# Params:
#   $1 - PID
descendantPids() {
    local _CHILD
    for _CHILD in $(pgrep -P "$1" 2>/dev/null || true); do
        descendantPids "${_CHILD}"
        echo "${_CHILD}"
    done
}

# Prueft, ob noch einer der Prozesse laeuft.
#
# Params:
#   $@ - PIDs
anyAlive() {
    local _PID
    for _PID in "$@"; do
        kill -0 "${_PID}" 2>/dev/null && return 0
    done
    return 1
}

# Sendet ein Signal an alle noch laufenden Prozesse.
#
# Params:
#   $1    - Signal (TERM, KILL)
#   $2... - PIDs
signalAll() {
    local -r _SIGNAL="$1"
    shift
    local _PID
    for _PID in "$@"; do
        kill -s "${_SIGNAL}" "${_PID}" 2>/dev/null || true
    done
}

# Beendet die Prozesse: SIGTERM, Wartezeit, dann SIGKILL fuer den Rest.
#
# Params:
#   $@ - PIDs
#
# Returns:
#   0 wenn alle beendet sind, 1 sonst
terminate() {
    signalAll TERM "$@"
    local _WAITED=0
    local -r _LIMIT="$(( TIMEOUT * 5 ))"
    while anyAlive "$@" && (( _WAITED < _LIMIT )); do
        sleep "${POLL_INTERVAL}"
        _WAITED=$(( _WAITED + 1 ))
    done
    if anyAlive "$@"; then
        echo -e "      ${YELLOW}⚠${NC} nach ${TIMEOUT}s noch aktiv — SIGKILL"
        signalAll KILL "$@"
        sleep "${POLL_INTERVAL}"
    fi
    ! anyAlive "$@"
}

# Beschreibt einen lauschenden Prozess in einer Zeile.
#
# Params:
#   $1 - PID
#   $2 - Arbeitsverzeichnis
describeProcess() {
    local -r _PID="$1"
    local -r _CWD="$2"
    local _WHERE="${YELLOW}ausserhalb des Projekts${NC}: ${_CWD:-unbekannt}"
    if [[ "${_CWD}" == "${PROJECT_DIR}" ]]; then
        _WHERE="im Projekt (Root)"
    elif isInsideProject "${_CWD}"; then
        _WHERE="im Projekt: ${_CWD#"${PROJECT_DIR}"/}"
    fi
    local _USER
    _USER="$(ps -o user= -p "${_PID}" 2>/dev/null | tr -d ' ' || true)"
    echo -e "      PID ${BLUE}${_PID}${NC}  ${_USER:-?}  $(processCommand "${_PID}" | cut -c1-90)"
    echo -e "        ${_WHERE}"
}

# Zeigt, ob und von wem die Ports belegt sind.
showPorts() {
    local _PORT _PID
    echo -e "${CYAN}▶ Ports in ${PROJECT_DIR}${NC}"
    for _PORT in "${PORTS[@]}"; do
        local _PIDS=()
        mapfile -t _PIDS < <(listenerPids "${_PORT}")
        if [[ ${#_PIDS[@]} -eq 0 ]]; then
            echo -e "  ${GREEN}✓${NC} ${_PORT} frei"
            continue
        fi
        echo -e "  ${YELLOW}●${NC} ${_PORT} belegt"
        for _PID in "${_PIDS[@]}"; do
            describeProcess "${_PID}" "$(processCwd "${_PID}")"
        done
    done
}

# Gibt einen Port frei.
#
# Params:
#   $1 - Port
#
# Returns:
#   0 wenn der Port danach frei ist (bei --dry-run: wenn nichts uebersprungen
#   wurde), 1 sonst
releasePort() {
    local -r _PORT="$1"
    local _PIDS=()
    mapfile -t _PIDS < <(listenerPids "${_PORT}")
    if [[ ${#_PIDS[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} ${_PORT} ist frei"
        return 0
    fi

    echo -e "  ${YELLOW}●${NC} ${_PORT} belegt"
    local _TARGETS=()
    local _SKIPPED=0
    local _PID _CWD
    for _PID in "${_PIDS[@]}"; do
        _CWD="$(processCwd "${_PID}")"
        describeProcess "${_PID}" "${_CWD}"
        if ! isOwnProcess "${_PID}"; then
            echo -e "        ${RED}✗${NC} gehoert einem anderen Benutzer — nicht beendet"
            _SKIPPED=1
        elif ! isInsideProject "${_CWD}" && [[ "${ANY_DIR}" != true ]]; then
            echo -e "        ${RED}✗${NC} nicht beendet — ${GREEN}--any-dir${NC} erlaubt es"
            _SKIPPED=1
        else
            local _DESCENDANTS=()
            mapfile -t _DESCENDANTS < <(descendantPids "${_PID}")
            _TARGETS+=("${_DESCENDANTS[@]}" "${_PID}")
            if [[ ${#_DESCENDANTS[@]} -gt 0 ]]; then
                echo -e "        ${BLUE}ℹ${NC} mit ${#_DESCENDANTS[@]} Kindprozess(en): ${_DESCENDANTS[*]}"
            fi
        fi
    done

    if [[ ${#_TARGETS[@]} -eq 0 ]]; then
        return 1
    fi
    # Ein uvicorn-Reloader und sein Worker lauschen beide; der Worker steht
    # dann als Lauscher und als Kind in der Liste.
    mapfile -t _TARGETS < <(printf '%s\n' "${_TARGETS[@]}" | awk '!SEEN[$0]++')
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "      ${BLUE}ℹ${NC} Dry-Run — wuerde beenden: ${_TARGETS[*]}"
        return "${_SKIPPED}"
    fi

    terminate "${_TARGETS[@]}" || true

    if [[ -z "$(listenerPids "${_PORT}")" ]]; then
        echo -e "      ${GREEN}✓${NC} ${_PORT} frei"
        return 0
    fi
    echo -e "      ${RED}✗${NC} ${_PORT} weiterhin belegt"
    return 1
}

# Gibt alle Ports frei.
#
# Returns:
#   0 wenn alle Ports frei sind, 1 sonst
releaseAll() {
    local _FAILED=0
    local _PORT
    echo -e "${CYAN}▶ Ports freigeben in ${PROJECT_DIR}${NC}"
    for _PORT in "${PORTS[@]}"; do
        releasePort "${_PORT}" || _FAILED=1
    done
    if [[ "${_FAILED}" -ne 0 ]]; then
        echo -e "\n${RED}Nicht alle Ports sind frei.${NC}" >&2
        echo -e "${YELLOW}Tipp:${NC} ${GREEN}${APPNAME} --status${NC} zeigt, wer sie belegt.\n" >&2
    fi
    return "${_FAILED}"
}

# Bricht mit Fehlermeldung ab, wenn ein Werkzeug fehlt.
requireTools() {
    local _TOOL
    for _TOOL in lsof pgrep ps; do
        if ! command -v "${_TOOL}" >/dev/null 2>&1; then
            echo -e "\n${RED}Fehler:${NC} ${_TOOL} ist nicht installiert.\n" >&2
            exit 1
        fi
    done
}

# Laedt die Ports aus Config oder Optionen; bricht bei Fehlern ab.
resolvePorts() {
    if [[ ${#CLI_PORTS[@]} -gt 0 ]]; then
        PORTS=("${CLI_PORTS[@]}")
        return 0
    fi
    local _RC=0
    loadConfig || _RC=$?
    case "${_RC}" in
        0) return 0 ;;
        2) echo -e "\n${RED}Fehler:${NC} ${CONFIG_DISPLAY} nicht gefunden in ${PROJECT_DIR}." >&2 ;;
        3) echo -e "\n${RED}Fehler:${NC} ${CONFIG_DISPLAY} nennt keine Ports (PORTS ist leer)." >&2 ;;
        4) echo -e "\n${RED}Fehler:${NC} ${CONFIG_DISPLAY} enthaelt einen ungueltigen Port: ${PORTS[*]}" >&2 ;;
        *) echo -e "\n${RED}Fehler:${NC} ${CONFIG_DISPLAY} laesst sich nicht laden (rc=${_RC})." >&2 ;;
    esac
    echo -e "${YELLOW}Tipp:${NC} ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC} oder ${GREEN}--port N${NC}\n" >&2
    exit 1
}

# Parst die Optionen.
parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--status)  ACTION="status" ;;
            -k|--kill)    ACTION="kill" ;;
            -n|--dry-run) DRY_RUN=true ;;
            -a|--any-dir) ANY_DIR=true ;;
            -p|--port)
                if [[ $# -lt 2 ]] || ! isValidPort "$2"; then
                    echo -e "${RED}--port braucht eine Portnummer (1–65535)${NC}" >&2
                    exit 1
                fi
                CLI_PORTS+=("$2")
                shift
                ;;
            -t|--timeout)
                if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}--timeout braucht eine Zahl in Sekunden${NC}" >&2
                    exit 1
                fi
                TIMEOUT="$2"
                shift
                ;;
            -c|--config)
                if [[ $# -lt 2 ]]; then
                    echo -e "${RED}--config braucht einen Dateinamen${NC}" >&2
                    exit 1
                fi
                CONFIG_NAME="$2"
                CONFIG_DISPLAY="$2"
                shift
                ;;
            -e|--example) printConfigExample; exit 0 ;;
            -h|--help)    usage; exit 0 ;;
            *) echo -e "${RED}Unbekannte Option: $1${NC}" >&2; usage; exit 1 ;;
        esac
        shift
    done
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi
    parseArgs "$@"
    if [[ -z "${ACTION}" ]]; then
        echo -e "${RED}Keine Aktion — ${GREEN}--status${RED} oder ${GREEN}--kill${RED} angeben${NC}" >&2
        usage
        exit 1
    fi
    if [[ "${DRY_RUN}" == true && "${ACTION}" != "kill" ]]; then
        echo -e "${RED}--dry-run gilt nur mit --kill${NC}" >&2
        exit 1
    fi
    requireTools
    resolvePorts

    case "${ACTION}" in
        status) showPorts ;;
        kill)   releaseAll ;;
    esac
}

main "$@"
