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
# sourcebares Bash-Snippet (DOCS, LINKS_ONLY, EXCLUDE, FORBIDDEN, KNOWN_VARIABLES,
# MAX_ALERTS, REQUIRED, SCREENSHOTS, MAX_SCREENSHOT_AGE_DAYS); der Name wird aus dem
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
LINKS_ONLY=()
EXCLUDE=()
FORBIDDEN=()
KNOWN_VARIABLES=()
MAX_ALERTS=""
REQUIRED=()
SCREENSHOTS=()
MAX_SCREENSHOT_AGE_DAYS=""

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
# Config für docs-check.sh (ProjectTools) — wird gesourced, kein Custom-Parser.
# .sh-Endung fürs IDE-Highlighting. Format-Doku: ProjectTools/README.md
# Anlegen/aktualisieren:  ${APPNAME} --example > ${CONFIG_DISPLAY}
# shellcheck disable=SC2034  # von docs-check.sh gesourct

# Pfadangaben in DOCS, EXCLUDE und REQUIRED: relativ zum Projekt-Root,
# führendes "./" erlaubt. Muster wie in .gitignore:
#   *    beliebige Zeichen innerhalb eines Ordners   docs/*.md
#   **   beliebig viele Ordner                       docs/**/*.md, **/README.md
#   ?    genau ein Zeichen                           docs/v?.md
# Ordner und Muster treffen nur Dateien, die git nicht ignoriert.

# Inhaltlich zu prüfende Dokumente: Datei, Ordner (alle *.md darin) oder
# Muster. Ein Muster ohne Treffer ist ein Problem.
DOCS=(
EOF
    if [[ ${#docs[@]} -gt 0 ]]; then
        printf '    "%s"\n' "${docs[@]}"
    else
        printf '    "README.md"\n'
    fi
    cat <<EOF
)

# Interne Doku, die nur auf tote Links, fehlende Bilder und Anker geprüft
# wird, nicht auf verbotene Begriffe, Befehle oder Variablen. Gedacht für
# Projektregeln und Tickets, die interne Angaben nennen dürfen.
LINKS_ONLY=(
EOF
    local internal
    for internal in AGENTS.md CLAUDE.md; do
        if git ls-files --error-unmatch -- "${internal}" >/dev/null 2>&1; then
            printf '    "%s"\n' "${internal}"
        fi
    done
    cat <<EOF
)

# Aus DOCS und LINKS_ONLY ausgenommen: Datei, Ordner samt Inhalt oder Muster (ein Muster
# darf auch einen Ordner treffen, z. B. "docs/drafts-*"). Gedacht für
# datierte Entwürfe oder Vorlagen, die verbotene Begriffe bewusst nennen.
EXCLUDE=(
EOF
    if [[ ${#excludes[@]} -gt 0 ]]; then
        printf '    "%s"\n' "${excludes[@]}"
    fi
    cat <<EOF
)

# Text, der in keinem Dokument aus DOCS stehen darf. Geprüft wird jede
# Zeile, auch in Codeblöcken; jeder Treffer ist ein Problem (Exit-Code 1).
# Die Meldung nennt Zeilen, gefundenen Text und den Grund.
#
# Ein Eintrag ist eine von zwei Formen, jeweils optional mit "|<grund>":
#
#   "<text>"             Genau dieser Text, Groß-/Kleinschreibung zählt.
#                        Trifft auch innerhalb von Wörtern: "UID" trifft
#                        "PUID".
#
#   "/<muster>/<flags>"  Regulärer Ausdruck in JavaScript-Syntax:
#                          \b        Wortgrenze: "/\bUID\b/" trifft nicht "PUID"
#                          (a|b)     Alternative: "/\bP(U|G)ID\b/"
#                          a|b       ganze Alternativen: "/PUID|nobody:users/"
#                          \d+       Ziffern: "/\b99:\d+\b/"
#                        Flags: i = Groß-/Kleinschreibung egal, u = Unicode.
#                        "|" im Muster ist erlaubt: Das Muster endet am
#                        ersten "/", dem nur Flags und dann "|" oder das
#                        Zeilenende folgen. Ein "/" im Muster wird "\/".
#                        Ein ungültiger Ausdruck bricht mit Exit-Code 2 ab.
#
# In Bash-Strings mit doppelten Anführungszeichen bleiben "\b" und "\d"
# erhalten; Dollarzeichen und Backticks brauchen einen Backslash davor.
#
# Ein Eintrag je Zusammenhang, damit jeder seinen eigenen Grund hat:
FORBIDDEN=(
    # Interne Umgebungsvariablen, in jeder Schreibweise
    # "/\bP(U|G)ID\b/i|interne Variablen, nicht in Nutzerdoku"
    # Standardnutzer als Zahl und als Name
    # "/\b99:100\b|\bnobody:users\b/i|Standard-IDs, nicht in Nutzerdoku"
)

# Variablen, die die Doku nennen darf, obwohl sie in keiner versionierten
# Datei vorkommen, z. B. aus einer eingebundenen, nicht versionierten
# Bibliothek. Je Eintrag optional mit "|<grund>".
KNOWN_VARIABLES=(
    # "NO_COLOR|Standard der Kommandozeile, schaltet Farben ab"
)

# Optional: höchstens so viele farbige Hinweisboxen (> [!WARNING] usw.) je
# Dokument. Leer oder nicht gesetzt: keine Grenze.
MAX_ALERTS=""

# Dateien, die es geben muss, je optional mit "|<grund>". Sie zählen nur,
# wenn sie versioniert und nicht leer sind; .md-Dateien brauchen mindestens
# eine Überschrift ("# Titel").
#   "LICENSE"             ohne "/": irgendwo im Projekt
#   "./README.md"         mit "/": genau dort, "./" heißt Projekt-Root
#   "./docs/**/*.md"      Muster: mindestens ein Treffer
REQUIRED=(
EOF
    local required
    for required in README.md LICENSE LICENSE.md CHANGELOG.md; do
        if git ls-files --error-unmatch -- "${required}" >/dev/null 2>&1; then
            printf '    "%s"\n' "${required}"
        fi
    done
    cat <<EOF
)

# Optional: Screenshots, deren Alter geprüft wird (Datei, Ordner oder Muster;
# ohne von git ignorierte Bilder). Maßgeblich ist das Änderungsdatum der
# Datei. Ist ein Bild älter als MAX_SCREENSHOT_AGE_DAYS Tage, erscheint ein
# Hinweis; die Prüfung scheitert daran nicht. Beide Einträge gehören zusammen.
SCREENSHOTS=(
EOF
    if [[ -d docs/images ]]; then
        printf '    # "docs/images"\n'
    fi
    cat <<EOF
)
MAX_SCREENSHOT_AGE_DAYS=""
EOF
}

# Laedt die Config, falls vorhanden.
#
# Returns:
#   0 - Config geladen, DOCS, LINKS_ONLY oder REQUIRED gesetzt
#   1 - Config fehlt
#   2 - Config ohne DOCS-, LINKS_ONLY- und REQUIRED-Eintraege
loadConfig() {
    local config_file="$1"

    [[ -f "${config_file}" ]] || return 1

    # shellcheck source=/dev/null
    . "${config_file}"

    [[ ${#DOCS[@]} -gt 0 || ${#LINKS_ONLY[@]} -gt 0 || ${#REQUIRED[@]} -gt 0 ]] || return 2
}

# Startet die Deno-Pruefung mit EXCLUDE, FORBIDDEN, KNOWN_VARIABLES und
# MAX_ALERTS aus der Config; beim Lauf ueber das ganze Projekt auch mit
# REQUIRED, LINKS_ONLY und SCREENSHOTS.
#
# Params:
#   $1    - "true" fuer ausfuehrliche Ausgabe
#   $2    - Name der geladenen Config fuer die Kopfzeile, leer ohne Config
#   $3    - "true", um REQUIRED, LINKS_ONLY und SCREENSHOTS zu pruefen
#   $4... - zu pruefende Dateien oder Ordner
runCheck() {
    local verbose="$1"
    local config_name="$2"
    local with_required="$3"
    shift 3

    local args=(--root .) entry
    [[ -n "${config_name}" ]] && args+=(--config-name "${config_name}")
    for entry in "${EXCLUDE[@]+"${EXCLUDE[@]}"}"; do
        args+=(--exclude "${entry}")
    done
    for entry in "${FORBIDDEN[@]+"${FORBIDDEN[@]}"}"; do
        args+=(--forbid "${entry}")
    done
    for entry in "${KNOWN_VARIABLES[@]+"${KNOWN_VARIABLES[@]}"}"; do
        args+=(--known-variable "${entry}")
    done
    [[ -n "${MAX_ALERTS}" ]] && args+=(--max-alerts "${MAX_ALERTS}")
    if [[ "${with_required}" == "true" ]]; then
        for entry in "${REQUIRED[@]+"${REQUIRED[@]}"}"; do
            args+=(--require "${entry}")
        done
        for entry in "${LINKS_ONLY[@]+"${LINKS_ONLY[@]}"}"; do
            args+=(--links-only "${entry}")
        done
        for entry in "${SCREENSHOTS[@]+"${SCREENSHOTS[@]}"}"; do
            args+=(--screenshot "${entry}")
        done
        if [[ -n "${MAX_SCREENSHOT_AGE_DAYS}" ]]; then
            args+=(--max-screenshot-age "${MAX_SCREENSHOT_AGE_DAYS}")
        fi
    fi
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
# Begriffe und Ausnahmen. Pflichtdateien, Nur-Link-Dokumente und Screenshots
# gehoeren zum ganzen Projekt und werden nur ohne Pfade geprueft.
with_required="false"
if [[ ${#paths[@]} -eq 0 ]]; then
    if [[ ${_RC} -ne 0 ]]; then
        {
            if [[ ${_RC} -eq 1 ]]; then
                echo -e "${RED}Fehler:${NC} Config '${config_file}' nicht gefunden."
            else
                echo -e "${RED}Fehler:${NC} Config '${config_file}' ohne DOCS-, LINKS_ONLY- und REQUIRED-Eintraege."
            fi
            echo -e "Vorlage anlegen: ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
        } >&2
        exit 1
    fi
    paths=("${DOCS[@]+"${DOCS[@]}"}")
    with_required="true"
fi

# Die Kopfzeile nennt die Config nur, wenn sie gelesen wurde.
loaded_config=""
[[ ${_RC} -ne 1 ]] && loaded_config="${config_file#./}"

runCheck "${verbose}" "${loaded_config}" "${with_required}" "${paths[@]+"${paths[@]}"}"
