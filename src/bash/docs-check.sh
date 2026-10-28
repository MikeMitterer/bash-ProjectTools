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
# KNOWN_MAKE_TARGETS, MAX_ALERTS, REQUIRED, SCREENSHOTS, SCREENSHOTS_EXCLUDE, DEPENDS,
# DEPENDS_HINT, TRANSLATIONS, CODE_VARIABLES, INTERNAL_VARIABLES); der Name wird aus dem
# Script-Namen abgeleitet (docs-check.sh -> .docs-check.conf.sh, .conf wird
# ebenfalls akzeptiert). Die Pruefung selbst macht src/deno/docs-check.ts:
# nur lesend, nur git, kein Netz.
#
# Voraussetzung: Deno 2.
#
# Verwendung:
#   docs-check.sh [--run [DATEI|ORDNER ...]] [--verbose] [--config <datei>]
#   docs-check.sh --ack [DATEI|ORDNER ...]          # Rueckstaende quittieren
#   docs-check.sh --example > .docs-check.conf.sh   # Starter-Config anlegen
#   make docs-check
#
# Optionen:
#   -r | --run       Dokumente aus der Config pruefen; mit Pfaden nur diese
#   -v | --verbose   Auch fehlerfreie Dokumente, Zahlenangaben und URLs zeigen
#   -c | --config    Alternative Config-Datei (Default: ./.docs-check.conf.sh)
#   -a | --ack       Rueckstaende aus SCREENSHOTS, DEPENDS und DEPENDS_HINT
#                    quittieren: angesehen, nichts zu tun. Schreibt
#                    .docs-check.ack; ohne Pfad alle offenen
#   -e | --example   Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)
#   -h | --help      Diese Hilfe anzeigen
#
# FORBIDDEN-Eintraege sind Text ("PUID") oder regulaere Ausdruecke
# ("/\bP(U|G)ID\b/i"), jeweils optional mit "|<grund>".
#
# KNOWN_MAKE_TARGETS nennt Make-Targets, die als vorhanden gelten, obwohl kein
# Makefile im Projekt sie enthaelt ("dev-up|aus MakeLib"); andere fehlende
# Targets meldet die Pruefung weiter.
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
KNOWN_MAKE_TARGETS=()
MAX_ALERTS=""
REQUIRED=()
SCREENSHOTS=()
SCREENSHOTS_EXCLUDE=()
MAX_SCREENSHOT_AGE_DAYS=""
DEPENDS=()
DEPENDS_HINT=()
TRANSLATIONS=()
FOLLOWER_ARGS=()
CODE_VARIABLES=()
INTERNAL_VARIABLES=()

# Zeigt die Verwendungshinweise an.
#
# Aufbau: Usage-Zeile, Optionen mit usageLine(), Hints-Sektion.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-r | --run [PFAD ...]" "Dokumente aus der Config pruefen; mit ${YELLOW}PFAD${NC} nur diese"
    usageLine "-a | --ack [PFAD ...]" "Rueckstaende quittieren (angesehen, nichts zu tun); ohne ${YELLOW}PFAD${NC} alle"
    usageLine "-v | --verbose       " "Auch fehlerfreie Dokumente, Zahlenangaben und URLs zeigen"
    usageLine "-c | --config DATEI  " "Alternative Config-Datei (Default: ${CONFIG_DISPLAY})"
    usageLine "-e | --example       " "Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)"
    usageLine "-h | --help          " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Alle Dokumente pruefen:   ${GREEN}${APPNAME} --run${NC}"
    echo -e "    Einzelne Datei pruefen:   ${GREEN}${APPNAME} --run README.md${NC}"
    echo -e "    Screenshot quittieren:    ${GREEN}${APPNAME} --ack docs/images/dashboard.png${NC}"
    echo -e "    Config anlegen:           ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
    echo -e "    Target aus Bibliothek:    ${YELLOW}KNOWN_MAKE_TARGETS=(\"dev-up|aus MakeLib\")${NC} in ${CONFIG_DISPLAY}"
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
# .sh-Endung fürs IDE-Highlighting. Format-Doku: ProjectTools/docs/tools/docs-check.md
# Anlegen/aktualisieren:  ${APPNAME} --example > ${CONFIG_DISPLAY}
# shellcheck disable=SC2034  # von docs-check.sh gesourct

# Pfadangaben in DOCS, LINKS_ONLY, EXCLUDE, REQUIRED, CODE_VARIABLES,
# SCREENSHOTS, SCREENSHOTS_EXCLUDE, DEPENDS und DEPENDS_HINT: relativ zum Projekt-Root, führendes
# "./" erlaubt. Muster wie in .gitignore:
#   *    beliebige Zeichen innerhalb eines Ordners   docs/*.md
#   **   beliebig viele Ordner                       docs/**/*.md, **/README.md
#   ?    genau ein Zeichen                           docs/v?.md
# Ordner und Muster treffen nur Dateien, die git nicht ignoriert.

# ─── Welche Dokumente geprüft werden ───────────────────────────────────────────

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

# ─── Was in den Dokumenten stehen darf ─────────────────────────────────────────

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

# Optional: höchstens so viele farbige Hinweisboxen (> [!WARNING] usw.) je
# Dokument. Leer oder nicht gesetzt: keine Grenze.
MAX_ALERTS=""

# ─── Variablen zwischen Doku und Code ──────────────────────────────────────────

# Variablen, die die Doku nennen darf, obwohl sie in keiner versionierten
# Datei vorkommen, z. B. aus einer eingebundenen, nicht versionierten
# Bibliothek. Je Eintrag optional mit "|<grund>".
KNOWN_VARIABLES=(
    # "NO_COLOR|Standard der Kommandozeile, schaltet Farben ab"
)

# Make-Targets, die die Doku nennen darf, obwohl kein Makefile im Projekt sie
# enthält, z. B. aus einer nicht versionierten Bibliothek (MakeLib unter .libs/).
# Je Eintrag "TARGET" optional mit "|<grund>"; gilt in jedem Verzeichnis mit Makefile.
KNOWN_MAKE_TARGETS=(
    # "dev-up|aus MakeLib, über .libs/MakeLib eingebunden"
)

# Optional: Code (Datei, Ordner oder Muster), dessen Umgebungsvariablen
# dokumentiert sein müssen. Jede Variable, die der Code dort ausdrücklich
# liest (process.env.X, os.environ["X"], getenv("X") u. a.), muss in einem
# Dokument aus DOCS stehen; sonst ist das ein Problem. Tests zählen nicht.
CODE_VARIABLES=(
EOF
    local code
    for code in src api backend frontend/src server; do
        if [[ -d "${code}" ]]; then
            printf '    # "%s"\n' "${code}"
        fi
    done
    cat <<EOF
)

# Vom Code gelesen, aber bewusst nicht dokumentiert, je mit "|<grund>".
INTERNAL_VARIABLES=(
)

# ─── Dateien, die es geben muss ────────────────────────────────────────────────

# Dateien, die es geben muss, je optional mit "|<grund>". Sie zählen nur,
# wenn sie versioniert und nicht leer sind; .md-Dateien brauchen mindestens
# eine Überschrift ("# Titel").
#   "LICENSE"             ohne "/": irgendwo im Projekt
#   "./README.md"         mit "/": genau dort, "./" heißt Projekt-Root
#   "./docs/**/*.md"      Muster: mindestens ein Treffer
REQUIRED=(
EOF
    # Vorgeschlagen wird nur, was versioniert ist; der Grund steht hinter "|".
    local required
    for required in \
        "README.md" \
        "docker/README.md|Container-Anleitung, Quelle der Docker-Hub-Beschreibung" \
        "LICENSE" \
        "LICENSE.md" \
        "CHANGELOG.md"; do
        if git ls-files --error-unmatch -- "${required%%|*}" >/dev/null 2>&1; then
            printf '    "%s"\n' "${required}"
        fi
    done
    cat <<EOF
)

# ─── Abhängige Dateien und Screenshots ─────────────────────────────────────────

# Abhängige Dateien müssen ihrer Basis folgen: Screenshots dem UI-Code,
# Übersetzungen und Kurzfassungen ihrem Original, erzeugte Dateien ihrer
# Quelle. Ändert sich die Basis nach der abhängigen Datei, meldet die Prüfung
# das. Maßgeblich ist der letzte Commit laut git, uncommittete Änderungen
# zählen als jetzt; Dateidatum und Tagesdatum zählen nicht.
#
# Quittieren statt sinnlos anfassen: Verlangt eine Änderung der Basis nichts
# (Tippfehler im README, Codeänderung ohne sichtbare Folge), die Meldung aus
# SCREENSHOTS, DEPENDS oder DEPENDS_HINT nach dem Prüfen quittieren:
#
#   ${APPNAME} --ack docs/images/dashboard.png
#   ${APPNAME} --ack docs/images   # ganzer Ordner
#   ${APPNAME} --ack               # alle offenen
#
# Das schreibt je Paar den letzten Commit der Basis nach .docs-check.ack; die
# Datei mitcommitten. Die Quittung gilt, bis die Basis einen neueren Commit
# hat, dann kommt die Meldung zurück. Nicht quittieren lassen sich Einträge mit
# Frist 0 (neu erzeugen) und uncommittete Basen (erst committen).

# Optional: Screenshots und der UI-Code, den sie zeigen, je
# "<ui-code>|<bilder>|<grund>". UI-Code: Datei, Ordner oder Muster, mehrere
# mit Komma; Bilder: Datei, Ordner oder Muster (ohne von git ignorierte).
# Hat sich der UI-Code nach einem Bild geändert, erscheint ein Hinweis; die
# Prüfung scheitert daran nicht.
SCREENSHOTS=(
EOF
    if [[ -d docs/images ]]; then
        local ui
        for ui in src frontend/src dashboard/src web app/templates; do
            if [[ -d "${ui}" ]]; then
                printf '    # "%s|docs/images|Oberfläche"\n' "${ui}"
            fi
        done
    fi
    cat <<EOF
)

# Optional: Bilder aus SCREENSHOTS, deren Alter keine Rolle spielt, etwa
# Logos, Diagramme oder Aufnahmen fremder Oberflächen: Datei, Ordner oder
# Muster wie in EXCLUDE. Sie müssen vorhanden sein, mit dem UI-Code verglichen
# werden sie nicht. Eine Ausnahme ohne Bild ist ein Problem.
SCREENSHOTS_EXCLUDE=(
    # "docs/images/logo.png"
)

# Optional: Dateien, die einer anderen bald nach deren Änderung folgen müssen,
# je "<basis>|<abhängig>|<tage>|<grund>" (z. B. Übersetzung oder erzeugte
# Vorschau). Ändert sich die Basis nach der abhängigen Datei, ist das ein
# Hinweis, nach <tage> Tagen ein Problem; 0 heißt: im selben Commit. Die Basis
# darf ein Ordner, ein Muster oder eine Liste mit Komma sein.
DEPENDS=(
    # "README.md|README.de.md|3|deutsche Fassung"
)

# Gleiches Format, auch überfällig nur ein Hinweis: für Basen, die sich oft
# ändern, ohne dass die abhängige Datei etwas nachziehen muss.
DEPENDS_HINT=(
)

# Optional: Sprachfassungen mit derselben Gliederung, je
# "<original>|<übersetzung>|<grund>". Verglichen werden die Überschriften und
# je Abschnitt Linkziele, Bilder, Inline-Code, Codeblöcke (Mermaid nur als
# Anzahl), Hinweisboxen und Absätze. Fehlt in einer Fassung ein Teil, ist das
# ein Problem. Den übersetzten Text selbst prüft das nicht.
TRANSLATIONS=(
EOF
    if [[ -f README.de.md ]]; then
        printf '    "README.md|README.de.md|deutsche Fassung"\n'
    fi
    cat <<EOF
)
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

# Sammelt SCREENSHOTS, SCREENSHOTS_EXCLUDE, DEPENDS und DEPENDS_HINT als
# Argumente fuer die Deno-Pruefung in FOLLOWER_ARGS: die Dateien, die einer
# Basis folgen muessen, und die Bilder ohne Alterspruefung.
collectFollowerArgs() {
    local entry
    FOLLOWER_ARGS=()
    for entry in "${SCREENSHOTS[@]+"${SCREENSHOTS[@]}"}"; do
        FOLLOWER_ARGS+=(--screenshot "${entry}")
    done
    for entry in "${SCREENSHOTS_EXCLUDE[@]+"${SCREENSHOTS_EXCLUDE[@]}"}"; do
        FOLLOWER_ARGS+=(--screenshot-exclude "${entry}")
    done
    for entry in "${DEPENDS[@]+"${DEPENDS[@]}"}"; do
        FOLLOWER_ARGS+=(--depends "${entry}")
    done
    for entry in "${DEPENDS_HINT[@]+"${DEPENDS_HINT[@]}"}"; do
        FOLLOWER_ARGS+=(--depends-hint "${entry}")
    done
}

# Quittiert Rueckstaende aus SCREENSHOTS, DEPENDS und DEPENDS_HINT. Die
# Deno-Pruefung darf dafuer nur .docs-check.ack im Projekt-Root schreiben.
#
# Params:
#   $@ - abhaengige Dateien oder Ordner; ohne Angabe alle offenen
runAck() {
    collectFollowerArgs
    local args=(--root . "${FOLLOWER_ARGS[@]+"${FOLLOWER_ARGS[@]}"}") path
    if [[ $# -eq 0 ]]; then
        args+=(--ack-all)
    fi
    for path in "$@"; do
        args+=(--ack "${path}")
    done
    # Aufgeloester Pfad: Die Pruefung arbeitet mit dem echten Projekt-Root.
    deno run --quiet --allow-read --allow-run=git --allow-write="$(pwd -P)/.docs-check.ack" \
        "${DOCS_CHECK_TS}" "${args[@]}"
}

# Startet die Deno-Pruefung mit EXCLUDE, FORBIDDEN, KNOWN_VARIABLES,
# KNOWN_MAKE_TARGETS und MAX_ALERTS aus der Config; beim Lauf ueber das ganze Projekt auch mit
# REQUIRED, LINKS_ONLY, SCREENSHOTS, DEPENDS, TRANSLATIONS und CODE_VARIABLES.
#
# Params:
#   $1    - "true" fuer ausfuehrliche Ausgabe
#   $2    - Name der geladenen Config fuer die Kopfzeile, leer ohne Config
#   $3    - "true", um REQUIRED, LINKS_ONLY, SCREENSHOTS, DEPENDS, TRANSLATIONS und
#           CODE_VARIABLES zu pruefen
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
    for entry in "${KNOWN_MAKE_TARGETS[@]+"${KNOWN_MAKE_TARGETS[@]}"}"; do
        args+=(--known-make-target "${entry}")
    done
    [[ -n "${MAX_ALERTS}" ]] && args+=(--max-alerts "${MAX_ALERTS}")
    if [[ "${with_required}" == "true" ]]; then
        for entry in "${REQUIRED[@]+"${REQUIRED[@]}"}"; do
            args+=(--require "${entry}")
        done
        for entry in "${LINKS_ONLY[@]+"${LINKS_ONLY[@]}"}"; do
            args+=(--links-only "${entry}")
        done
        collectFollowerArgs
        args+=("${FOLLOWER_ARGS[@]+"${FOLLOWER_ARGS[@]}"}")
        for entry in "${TRANSLATIONS[@]+"${TRANSLATIONS[@]}"}"; do
            args+=(--translation "${entry}")
        done
        for entry in "${CODE_VARIABLES[@]+"${CODE_VARIABLES[@]}"}"; do
            args+=(--code-variables "${entry}")
        done
        for entry in "${INTERNAL_VARIABLES[@]+"${INTERNAL_VARIABLES[@]}"}"; do
            args+=(--internal-variable "${entry}")
        done
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
        -a|--ack)
            action="ack"
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

if [[ "${action}" != "run" && "${action}" != "ack" ]]; then
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

# Das Alter der Screenshots gegen das Tagesdatum gibt es nicht mehr.
if [[ -n "${MAX_SCREENSHOT_AGE_DAYS}" ]]; then
    {
        echo -e "${RED}Fehler:${NC} MAX_SCREENSHOT_AGE_DAYS entfaellt."
        echo -e "Screenshots werden mit dem UI-Code verglichen, den sie zeigen:"
        echo -e "  ${GREEN}SCREENSHOTS=(\"<ui-code>|<bilder>|<grund>\")${NC}"
    } >&2
    exit 2
fi

if [[ "${action}" == "ack" ]]; then
    if [[ ${_RC} -eq 1 ]]; then
        echo -e "${RED}Fehler:${NC} Config '${config_file}' nicht gefunden." >&2
        exit 1
    fi
    runAck "${paths[@]+"${paths[@]}"}"
    exit $?
fi

# Mit Pfaden genuegt eine fehlende Config: Dann gibt es nur keine verbotenen
# Begriffe und Ausnahmen. Pflichtdateien, Nur-Link-Dokumente, Screenshots und
# Code-Variablen gehoeren zum ganzen Projekt und werden nur ohne Pfade geprueft.
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
