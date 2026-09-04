#!/usr/bin/env bash
#------------------------------------------------------------------------------
# npm-publish.sh — Veroeffentlicht ein npm-Paket und raeumt die bekannten
# Stolperstellen aus dem Weg
#
# Das Script verantwortet den **ganzen** Vorgang: anmelden, pruefen,
# hochladen, nachsehen. Es ersetzt das blosse `npm publish` im Makefile, weil
# dessen Fehlermeldungen regelmaessig auf die falsche Faehrte fuehren.
#
# Drei Fallen, die es abraeumt:
#
# 1. **Nicht angemeldet.** Bei einem privaten Paket antwortet die Registry mit
#    `404 Not Found` statt `401` — sie verraet dessen Existenz nicht. Die
#    Meldung zeigt dann auf den Paketnamen statt auf den abgelaufenen Token.
# 2. **Version liegt schon oben.** Der haeufigste Grund fuers Scheitern, und
#    einer, der sich vorher beantworten laesst statt hinterher.
# 3. **`409 Conflict — Failed to save packument`.** Registry-seitig und meist
#    voruebergehend. Der beigefuegte Erklaerungstext („vorheriges Paket noch
#    nicht verarbeitet") passt fast nie. Hier wird stattdessen nachgesehen, ob
#    es trotz des Fehlers oben liegt, und andernfalls erneut versucht.
#
# **Wiederholt wird ausschliesslich bei `409`.** Das ist gefahrlos, weil npm
# eine bestehende Version nie ueberschreibt. Bei `401`, `402` oder `403` bricht
# das Script sofort ab — dort ist die Ursache Zugang oder Abo, und ein zweiter
# Versuch aendert daran nichts.
#
# Projektunabhaengig: Registry, Name und Version kommen aus der package.json im
# aktuellen Verzeichnis und aus der npm-Konfiguration — nichts ist fest
# verdrahtet.
#
# Verwendung:
#   npm-publish.sh [--publish] [--ensure] [--status] [--help]
#
# Optionen:
#   -p | --publish  Anmelden, pruefen, hochladen, nachsehen
#   -e | --ensure   Nur die Anmeldung sicherstellen (private Abhaengigkeiten, CI)
#   -s | --status   Nur berichten, nichts aendern (fuer CI)
#   -h | --help     Diese Hilfe anzeigen
#
# Exit-Codes:
#   0  veroeffentlicht beziehungsweise angemeldet
#   1  Anmeldung fehlt oder schlug fehl, Version liegt bereits oben,
#      oder das Hochladen ist endgueltig gescheitert
#------------------------------------------------------------------------------

set -euo pipefail

# Logische Pfadaufloesung beibehalten (kein pwd -P) — der Fallback muss auch
# ueber einen .libs/ProjectTools-Symlink funktionieren (.libs/BashLib daneben)
BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../../../BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
if [[ "${__TOOLS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";  fi

APPNAME="$(basename "$0")"
readonly APPNAME

# Hoechstzahl der Hochladeversuche und die Pausen dazwischen (Sekunden).
# Die Pausenliste hat genau einen Eintrag weniger, als Versuche erlaubt sind.
readonly MAX_ATTEMPTS=3
readonly RETRY_DELAYS=(5 15)

# Zeigt die Verwendungshinweise an.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-p | --publish" "Anmelden, pruefen, hochladen, nachsehen"
    usageLine "-e | --ensure " "Nur die Anmeldung sicherstellen"
    usageLine "-s | --status " "Nur berichten, nichts aendern (fuer CI)"
    usageLine "-h | --help   " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Veroeffentlichen: ${GREEN}${APPNAME} --publish${NC}"
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

# Liest ein Feld aus der package.json des aktuellen Verzeichnisses.
#
# Params:
#   $1 - Feldname, etwa "name" oder "version"
#
# Returns:
#   0 mit dem Wert auf stdout, 1 ohne package.json oder ohne das Feld
packageField() {
    local value=""

    [[ -f package.json ]] || return 1

    value="$(node -p "require('./package.json').${1} || ''" 2>/dev/null || true)"
    [[ -n "${value}" ]] || return 1

    echo "${value}"
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
#   $1 - "ensure"/"publish" meldet an, "status" berichtet nur
#   $2 - Registry-URL
#
# Returns:
#   0 wenn angemeldet, sonst 1
checkLogin() {
    local mode="$1" registry="$2" user

    if user="$(currentUser "${registry}")"; then
        echo -e "  ${GREEN}✓${NC} angemeldet als ${YELLOW}${user}${NC}"
        return 0
    fi

    echo -e "  ${YELLOW}⚠${NC} niemand angemeldet"

    if [[ "${mode}" == "status" ]]; then
        echo -e "      ${BLUE}Anmelden mit: ${GREEN}${APPNAME} --ensure${NC}"
        return 1
    fi

    runLogin "${registry}"
}

# Prueft, ob eine Version bereits in der Registry liegt.
#
# Liest **ungecacht** (`--prefer-online`). Das ist der Kern der Pruefung: Ein
# veraltetes Paket-Dokument im npm-Cache beantwortet die Frage sonst mit dem
# Stand von gestern — und ist zugleich ein Verdaechtiger fuer die `409`. Der
# Aufruf frischt den Cache also auf, bevor geschrieben wird.
#
# Params:
#   $1 - Paketname
#   $2 - Version
#   $3 - Registry-URL
#
# Returns:
#   0 wenn die Version oben liegt, sonst 1
isVersionPublished() {
    local name="$1" version="$2" registry="$3" versions=""

    versions="$(npm view "${name}" versions --json --prefer-online \
        --registry "${registry}" 2>/dev/null || true)"
    [[ -n "${versions}" ]] || return 1

    # `npm view` liefert bei genau einer Version eine Zeichenkette statt einer
    # Liste — beide Formen muessen hier durchgehen.
    node -e '
        let list
        try { list = JSON.parse(process.argv[1]) } catch { process.exit(1) }
        if (!Array.isArray(list)) list = [list]
        process.exit(list.includes(process.argv[2]) ? 0 : 1)
    ' "${versions}" "${version}" 2>/dev/null
}

# Laedt das Paket hoch und wiederholt ausschliesslich bei `409`.
#
# Nach jedem Fehlschlag wird nachgesehen, ob die Version trotzdem oben liegt:
# Bei einer `409` ist genau das die offene Frage, und ein blindes Wiederholen
# wuerde sie mit einer zweiten, ebenso unklaren Meldung beantworten.
#
# Params:
#   $1 - Paketname
#   $2 - Version
#   $3 - Registry-URL
#
# Returns:
#   0 wenn die Version danach oben liegt, sonst 1
publishWithRetries() {
    local name="$1" version="$2" registry="$3"
    local output="" delay=""
    local -i attempt=0 rc=0

    while (( attempt < MAX_ATTEMPTS )); do
        attempt=$(( attempt + 1 ))

        if (( attempt > 1 )); then
            echo -e "  ${YELLOW}→${NC} Versuch ${attempt} von ${MAX_ATTEMPTS}"
        fi

        rc=0
        output="$(npm publish 2>&1)" || rc=$?

        if (( rc == 0 )); then
            echo -e "  ${GREEN}✓${NC} ${YELLOW}${name}@${version}${NC} veroeffentlicht"
            return 0
        fi

        if isVersionPublished "${name}" "${version}" "${registry}"; then
            echo -e "  ${GREEN}✓${NC} ${YELLOW}${name}@${version}${NC} liegt oben —" \
                    "der Fehlschlag betraf nur die Antwort, nicht den Upload"
            return 0
        fi

        if ! grep -q '409' <<<"${output}"; then
            echo
            echo "${output}" >&2
            echo
            echo -e "  ${RED}✗${NC} Abbruch — kein ${YELLOW}409${NC}," \
                    "ein zweiter Versuch aendert daran nichts" >&2
            return 1
        fi

        echo -e "  ${YELLOW}⚠${NC} ${YELLOW}409${NC} — Registry konnte das Paket-Dokument nicht speichern"

        if (( attempt < MAX_ATTEMPTS )); then
            delay="${RETRY_DELAYS[$(( attempt - 1 ))]}"
            echo -e "      warte ${delay}s und versuche erneut"
            sleep "${delay}"
        fi
    done

    echo
    echo "${output}" >&2
    echo
    echo -e "  ${RED}✗${NC} nach ${MAX_ATTEMPTS} Versuchen aufgegeben —" \
            "${YELLOW}${version}${NC} liegt nicht oben" >&2
    return 1
}

# Der ganze Vorgang: anmelden, pruefen, hochladen, nachsehen.
#
# Params:
#   $1 - "publish", "ensure" oder "status"
#
# Returns:
#   0 bei Erfolg, sonst 1
run() {
    local mode="$1" registry name version
    local -i rc=0

    registry="$(resolveRegistry)"

    echo
    echo -e "${CYAN}▶ npm-Veroeffentlichung${NC}"
    echo
    echo -e "  ${BLUE}ℹ${NC} Registry: ${YELLOW}${registry}${NC}"

    if ! checkLogin "${mode}" "${registry}"; then
        echo
        return 1
    fi

    if [[ "${mode}" == "ensure" ]]; then
        echo
        return 0
    fi

    if ! name="$(packageField name)" || ! version="$(packageField version)"; then
        echo -e "  ${RED}✗${NC} keine lesbare package.json im aktuellen Verzeichnis" >&2
        echo
        return 1
    fi

    echo -e "  ${BLUE}ℹ${NC} Paket:    ${YELLOW}${name}@${version}${NC}"

    if isVersionPublished "${name}" "${version}" "${registry}"; then
        echo -e "  ${YELLOW}⚠${NC} ${YELLOW}${version}${NC} liegt bereits oben —" \
                "eine Version wird nie ueberschrieben"
        echo -e "      ${BLUE}Version anheben mit: ${GREEN}npm version patch|minor|major${NC}"
        echo
        # Beim Berichten ist das keine Stoerung, sondern die Auskunft selbst.
        [[ "${mode}" == "status" ]] && return 0
        return 1
    fi

    echo -e "  ${GREEN}✓${NC} ${YELLOW}${version}${NC} ist noch frei"

    if [[ "${mode}" == "status" ]]; then
        echo
        return 0
    fi

    echo
    publishWithRetries "${name}" "${version}" "${registry}" || rc=$?
    echo
    return ${rc}
}

# ─── Einstieg ───────────────────────────────────────────────────────────────

# Kein Argument → Help anzeigen (keine Ausnahmen)
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    -p|--publish)
        run "publish"
        ;;
    -e|--ensure)
        run "ensure"
        ;;
    -s|--status)
        run "status"
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
