#!/usr/bin/env bash
#------------------------------------------------------------------------------
# npm-login.sh — Stellt sicher, dass man am richtigen npm-Registry angemeldet ist
#
# Gedacht als Vorschaltung vor allem, was eine Anmeldung braucht: veroeffentlichen,
# private Abhaengigkeiten installieren, CI-Schritte. Ist niemand angemeldet,
# startet das Script die Anmeldung — statt sie nur anzumahnen.
#
# Der Grund fuer das Script: Ohne Anmeldung antwortet die Registry bei einem
# privaten Paket mit `404 Not Found` statt `401`, weil sie dessen Existenz nicht
# verraten will. Die Fehlermeldung zeigt dann auf den Paketnamen, und man sucht
# lange an der falschen Stelle.
#
# Projektunabhaengig: Registry und Scope kommen aus der package.json im
# aktuellen Verzeichnis und aus der npm-Konfiguration — nichts ist fest
# verdrahtet. Ohne package.json gilt das global eingestellte Registry.
#
# Verwendung:
#   npm-login.sh [--ensure] [--status] [--help]
#   make publish
#
# Optionen:
#   -e | --ensure   Anmeldung sicherstellen — meldet an, falls noetig
#   -s | --status   Nur berichten, nicht anmelden (fuer CI)
#   -h | --help     Diese Hilfe anzeigen
#
# Exit-Codes:
#   0  angemeldet
#   1  nicht angemeldet (bei --status) oder Anmeldung fehlgeschlagen
#------------------------------------------------------------------------------

set -euo pipefail

# Logische Pfadaufloesung beibehalten (kein pwd -P) — der Fallback muss auch
# ueber einen .libs/ProjectTools-Symlink funktionieren (.libs/BashLib daneben)
BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../../../BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
if [[ "${__TOOLS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";  fi

APPNAME="$(basename "$0")"
readonly APPNAME

# Zeigt die Verwendungshinweise an.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-e | --ensure " "Anmeldung sicherstellen — meldet an, falls noetig"
    usageLine "-s | --status " "Nur berichten, nicht anmelden (fuer CI)"
    usageLine "-h | --help   " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Vor dem Publish:  ${GREEN}${APPNAME} --ensure${NC}"
    echo -e "    Nur pruefen:      ${GREEN}${APPNAME} --status${NC}"
    echo
}

# Ermittelt das Registry, das fuer dieses Paket gilt.
#
# Reihenfolge wie bei npm: publishConfig.registry schlaegt die
# Scope-Einstellung, diese die globale. Ohne package.json gilt die globale.
#
# Returns:
#   Registry-URL auf stdout
resolveRegistry() {
    local from_package="" scope="" scoped=""

    if [[ -f package.json ]]; then
        from_package="$(node -p \
            'const p=require("./package.json"); (p.publishConfig&&p.publishConfig.registry)||""' \
            2>/dev/null || true)"
        if [[ -n "${from_package}" ]]; then
            echo "${from_package}"
            return 0
        fi

        # Scope aus dem Paketnamen: "@mmit/ux-foundation" -> "@mmit"
        scope="$(node -p \
            'const n=require("./package.json").name||""; n.startsWith("@")?n.split("/")[0]:""' \
            2>/dev/null || true)"
        if [[ -n "${scope}" ]]; then
            scoped="$(npm config get "${scope}:registry" 2>/dev/null || true)"
            if [[ -n "${scoped}" && "${scoped}" != "undefined" ]]; then
                echo "${scoped}"
                return 0
            fi
        fi
    fi

    npm config get registry 2>/dev/null || echo "https://registry.npmjs.org/"
}

# Gibt den angemeldeten Benutzer aus, falls einer angemeldet ist.
#
# Params:
#   $1 - Registry-URL
#
# Returns:
#   0 mit Benutzername auf stdout, sonst 1
currentUser() {
    npm whoami --registry "$1" 2>/dev/null
}

# Startet die interaktive Anmeldung und prueft danach nach.
#
# Params:
#   $1 - Registry-URL
#
# Returns:
#   0 wenn danach jemand angemeldet ist, sonst 1
runLogin() {
    local registry="$1" user

    echo -e "  ${YELLOW}→${NC} Anmeldung wird gestartet — Browser und 2FA folgen"
    echo

    # Ohne `|| true` wuerde `set -e` hier abbrechen und die Nachkontrolle
    # ueberspringen; die Meldung soll aber aus diesem Script kommen.
    npm login --registry "${registry}" || true
    echo

    if user="$(currentUser "${registry}")"; then
        echo -e "  ${GREEN}✓${NC} angemeldet als ${YELLOW}${user}${NC}"
        return 0
    fi

    echo -e "  ${RED}✗${NC} Anmeldung fehlgeschlagen" >&2
    return 1
}

# Prueft die Anmeldung und meldet bei Bedarf an.
#
# Params:
#   $1 - "ensure" meldet an, "status" berichtet nur
#
# Returns:
#   0 wenn angemeldet, sonst 1
checkLogin() {
    local mode="$1" registry user

    registry="$(resolveRegistry)"

    echo
    echo -e "${CYAN}▶ npm-Anmeldung${NC}"
    echo
    echo -e "  ${BLUE}ℹ${NC} Registry: ${YELLOW}${registry}${NC}"

    if user="$(currentUser "${registry}")"; then
        echo -e "  ${GREEN}✓${NC} angemeldet als ${YELLOW}${user}${NC}"
        echo
        return 0
    fi

    echo -e "  ${YELLOW}⚠${NC} niemand angemeldet"

    if [[ "${mode}" == "status" ]]; then
        echo -e "      ${BLUE}Anmelden mit: ${GREEN}${APPNAME} --ensure${NC}"
        echo
        return 1
    fi

    if runLogin "${registry}"; then
        echo
        return 0
    fi

    echo
    return 1
}

# ─── Einstieg ───────────────────────────────────────────────────────────────

# Kein Argument → Help anzeigen (keine Ausnahmen)
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    -e|--ensure)
        checkLogin "ensure"
        ;;
    -s|--status)
        checkLogin "status"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo -e "${RED}Unbekannte Option: $1${NC}" >&2
        usage
        exit 1
        ;;
esac
