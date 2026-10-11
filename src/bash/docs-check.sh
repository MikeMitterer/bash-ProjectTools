#!/usr/bin/env bash
#------------------------------------------------------------------------------
# docs-check.sh — Nutzerdokumente eines Projekts gegen das Projekt pruefen
#
# Prueft README und weitere Dokumente auf tote Links und Bilder, fehlende
# Anker, nicht existierende Make-Targets, npm-Skripte und Deno-Tasks,
# unbekannte Variablen, falsche Repo-Pfade, Platzhalter und Begriffe, die das
# Projekt aus seiner Doku verbannt hat (z. B. interne IDs). So fallen veraltete
# Angaben beim Commit auf und nicht erst beim naechsten README-Lauf.
#
# Welche Dokumente geprueft werden und welche Begriffe verboten sind, steht in
# einer projektspezifischen Config im aktuellen Verzeichnis. Die Config ist ein
# sourcebares Bash-Snippet (DOCS, EXCLUDE, FORBIDDEN, MAX_ALERTS); der Name wird aus dem
# Script-Namen abgeleitet (docs-check.sh -> .docs-check.conf.sh, .conf wird
# ebenfalls akzeptiert). Die Pruefung selbst macht src/deno/docs-check.ts:
# nur lesend, nur git, kein Netz.
#
# Voraussetzung: Deno 2.
#
# Verwendung:
#   docs-check.sh [--run [DATEI|ORDNER ...]] [--verbose] [--config <datei>]
#   docs-check.sh --example > .docs-check.conf.sh   # Starter-Config anlegen
#   make docs-check
#
# Optionen:
#   -r | --run       Dokumente aus der Config pruefen; mit Pfaden nur diese
#   -v | --verbose   Auch fehlerfreie Dokumente, Zahlenangaben und URLs zeigen
#   -c | --config    Alternative Config-Datei (Default: ./.docs-check.conf.sh)
#   -e | --example   Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)
#   -h | --help      Diese Hilfe anzeigen
#
# FORBIDDEN-Eintraege sind Text ("PUID") oder regulaere Ausdruecke
# ("/\bP(U|G)ID\b/i"), jeweils optional mit "|<grund>".
#
# Exit-Code: 0 ohne Probleme, 1 bei Problemen oder Fehlern, 2 bei einem
# ungueltigen Eintrag (z. B. kaputter regulaerer Ausdruck).
#------------------------------------------------------------------------------

set -euo pipefail

# Logische Pfadaufloesung beibehalten (kein pwd -P) — der Fallback muss auch
# ueber einen .libs/ProjectTools-Symlink funktionieren (.libs/BashLib daneben)
BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../../../BashLib/src" 2>/dev/null && pwd || true)}"

# ProjectTools ist oeffentlich, BashLib nicht. Damit `make docs-check` auch in
# einem frischen Klon funktioniert, laeuft das Script ohne BashLib weiter —
# dann mit einfachen Farben statt des gemeinsamen Themes.
if [[ -r "${BASH_LIBS}/colors.lib.sh" && -r "${BASH_LIBS}/tools.lib.sh" ]]; then
    if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
    if [[ "${__TOOLS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";  fi
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    LIGHT_BLUE='\033[1;34m'; NC='\033[0m'

    # Ersatz fuer usageLine aus BashLib: Option und Beschreibung in Spalten.
    #
    # Params:
    #   $1 - Option(en), z.B. "-r | --run"
    #   $2 - Beschreibung
    usageLine() {
        local _OPTIONS="$1"
        _OPTIONS="${_OPTIONS%"${_OPTIONS##*[![:space:]]}"}"
        printf '       %-22s %b\n' "${_OPTIONS}" "$2"
    }
fi

APPNAME="$(basename "$0")"
readonly APPNAME
APPNAME_WITHOUT_EXTENSION="${APPNAME%%.*}"
readonly APPNAME_WITHOUT_EXTENSION

# Die Deno-Pruefung liegt neben src/bash in src/deno.
DOCS_CHECK_TS="$(cd "$(dirname "$0")/../deno" && pwd)/docs-check.ts"
readonly DOCS_CHECK_TS

# Config-Name aus Script-Namen ableiten (BashTools-Konvention). Beide Endungen
# werden unterstuetzt; Default ist .conf.sh (IDE-Highlighting), ein vorhandenes
# .conf gewinnt.
CONFIG_BASE="./.${APPNAME_WITHOUT_EXTENSION}.conf"
if [[ -f "${CONFIG_BASE}" ]]; then
    CONFIG_NAME="${CONFIG_BASE}"
else
    CONFIG_NAME="${CONFIG_BASE}.sh"
fi
readonly CONFIG_NAME
CONFIG_DISPLAY="${CONFIG_NAME#./}"
readonly CONFIG_DISPLAY

# Defaults — von der gesourcten Config ueberschrieben
DOCS=()
EXCLUDE=()
FORBIDDEN=()
MAX_ALERTS=""

# Zeigt die Verwendungshinweise an.
#
# Aufbau: Usage-Zeile, Optionen mit usageLine(), Hints-Sektion.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-r | --run [PFAD ...]" "Dokumente aus der Config pruefen; mit ${YELLOW}PFAD${NC} nur diese"
    usageLine "-v | --verbose       " "Auch fehlerfreie Dokumente, Zahlenangaben und URLs zeigen"
    usageLine "-c | --config DATEI  " "Alternative Config-Datei (Default: ${CONFIG_DISPLAY})"
    usageLine "-e | --example       " "Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)"
    usageLine "-h | --help          " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Alle Dokumente pruefen:   ${GREEN}${APPNAME} --run${NC}"
    echo -e "    Einzelne Datei pruefen:   ${GREEN}${APPNAME} --run README.md${NC}"
    echo -e "    Config anlegen:           ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
    echo
}

# Gibt eine gueltige, sourcebare Beispiel-Config auf stdout aus — direkt umleitbar:
#   docs-check.sh --example > .docs-check.conf.sh
#
# Schlaegt alle versionierten README-Dateien und einen vorhandenen docs/-Ordner
# vor; datierte Entwuerfe unter docs/superpowers werden ausgeschlossen.
printConfigExample() {
    local docs=() excludes=() path

    while IFS= read -r path; do
        [[ -n "${path}" ]] && docs+=("${path}")
    done < <(git ls-files -- 'README.md' '*/README.md' 2>/dev/null \
                 | grep -v -E '(^|/)(node_modules|\.libs)/' || true)
    [[ ${#docs[@]} -eq 0 && -f README.md ]] && docs+=("README.md")
    [[ -d docs ]] && docs+=("docs")
    [[ -d docs/superpowers ]] && excludes+=("docs/superpowers")

    cat <<EOF
#!/usr/bin/env bash
# Config fuer docs-check.sh (ProjectTools) — wird gesourced, kein Custom-Parser.
# .sh-Endung fuers IDE-Highlighting. Format-Doku: ProjectTools/README.md
# Anlegen/aktualisieren:  ${APPNAME} --example > ${CONFIG_DISPLAY}
# shellcheck disable=SC2034  # von docs-check.sh gesourct

# Zu pruefende Dokumente: Dateien oder Ordner (Ordner: alle *.md darin),
# relativ zum Projekt-Root.
DOCS=(
EOF
    if [[ ${#docs[@]} -gt 0 ]]; then
        printf '    "%s"\n' "${docs[@]}"
    else
        printf '    "README.md"\n'
    fi
    cat <<EOF
)

# Ausgenommene Dateien oder Ordner, z. B. datierte Entwuerfe oder Vorlagen,
# die verbotene Begriffe bewusst nennen.
EXCLUDE=(
EOF
    if [[ ${#excludes[@]} -gt 0 ]]; then
        printf '    "%s"\n' "${excludes[@]}"
    fi
    cat <<EOF
)

# Was in keinem geprueften Dokument stehen darf, je Eintrag optional mit
# "|<grund>":
#   "<begriff>"         Text, Gross-/Kleinschreibung zaehlt
#   "/<muster>/<flags>" regulaerer Ausdruck (JavaScript), z. B. Flag i;
#                       "|" im Muster ist erlaubt, "/" als "\/" schreiben
FORBIDDEN=(
    # "PUID|interne Kennung, nicht in Nutzerdoku"
    # "/\bP(U|G)ID\b|nobody:users/i|interne Kennungen, nicht in Nutzerdoku"
)

# Optional: hoechstens so viele farbige Hinweisboxen (> [!WARNING] usw.) je
# Dokument. Leer oder nicht gesetzt: keine Grenze.
MAX_ALERTS=""
EOF
}

# Laedt die Config, falls vorhanden.
#
# Returns:
#   0 - Config geladen und DOCS gesetzt
#   1 - Config fehlt
#   2 - Config ohne DOCS-Eintraege
loadConfig() {
    local config_file="$1"

    [[ -f "${config_file}" ]] || return 1

    # shellcheck source=/dev/null
    . "${config_file}"

    [[ ${#DOCS[@]} -gt 0 ]] || return 2
}

# Startet die Deno-Pruefung mit EXCLUDE und FORBIDDEN aus der Config.
#
# Params:
#   $1    - "true" fuer ausfuehrliche Ausgabe
#   $2    - Name der geladenen Config fuer die Kopfzeile, leer ohne Config
#   $3... - zu pruefende Dateien oder Ordner
runCheck() {
    local verbose="$1"
    local config_name="$2"
    shift 2

    local args=(--root .) entry
    [[ -n "${config_name}" ]] && args+=(--config-name "${config_name}")
    for entry in "${EXCLUDE[@]+"${EXCLUDE[@]}"}"; do
        args+=(--exclude "${entry}")
    done
    for entry in "${FORBIDDEN[@]+"${FORBIDDEN[@]}"}"; do
        args+=(--forbid "${entry}")
    done
    [[ -n "${MAX_ALERTS}" ]] && args+=(--max-alerts "${MAX_ALERTS}")
    [[ "${verbose}" == "true" ]] && args+=(--verbose)

    deno run --quiet --allow-read --allow-run=git "${DOCS_CHECK_TS}" "${args[@]}" "$@"
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

# Kein Argument → Help anzeigen
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

config_file="${CONFIG_NAME}"
action=""
verbose="false"
paths=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--run)
            action="run"
            # Folgende Argumente ohne fuehrenden Bindestrich sind Pfade.
            while [[ $# -gt 1 && "$2" != -* ]]; do
                paths+=("$2")
                shift
            done
            ;;
        -v|--verbose)
            verbose="true"
            ;;
        -c|--config)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Fehler: --config braucht einen Dateinamen${NC}" >&2
                exit 1
            fi
            config_file="$2"
            shift
            ;;
        -e|--example)
            printConfigExample
            exit 0
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
    shift
done

if [[ "${action}" != "run" ]]; then
    usage
    exit 0
fi

if ! command -v deno >/dev/null 2>&1; then
    {
        echo -e "${RED}Fehler:${NC} Deno nicht gefunden."
        echo -e "${YELLOW}Tipp:${NC} Deno 2 installieren: ${GREEN}https://docs.deno.com/runtime/${NC}"
    } >&2
    exit 1
fi

_RC=0
loadConfig "${config_file}" || _RC=$?

# Mit Pfaden genuegt eine fehlende Config: Dann gibt es nur keine verbotenen
# Begriffe und Ausnahmen.
if [[ ${#paths[@]} -eq 0 ]]; then
    if [[ ${_RC} -ne 0 ]]; then
        {
            if [[ ${_RC} -eq 1 ]]; then
                echo -e "${RED}Fehler:${NC} Config '${config_file}' nicht gefunden."
            else
                echo -e "${RED}Fehler:${NC} Config '${config_file}' ohne DOCS-Eintraege."
            fi
            echo -e "Vorlage anlegen: ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
        } >&2
        exit 1
    fi
    paths=("${DOCS[@]}")
fi

# Die Kopfzeile nennt die Config nur, wenn sie gelesen wurde.
loaded_config=""
[[ ${_RC} -ne 1 ]] && loaded_config="${config_file#./}"

runCheck "${verbose}" "${loaded_config}" "${paths[@]}"
