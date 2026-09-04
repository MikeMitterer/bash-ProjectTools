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
# **Vier Eigenschaften, die beim Bauen Blut gekostet haben** — jede einzelne
# war eine echte Fehlfunktion, keine Vorsichtsmassnahme:
#
# - **stdout des Uploads bleibt unangetastet.** `npm` bricht seine OTP-Abfrage
#   ab, sobald `stdin` **oder** `stdout` kein TTY ist (npm 11,
#   `lib/utils/auth.js:10`). Ein `output="$(npm publish)"` schaltet damit die
#   Zwei-Faktor-Anmeldung stumm ab. Eingefangen wird deshalb **nur stderr** —
#   dort und ausschliesslich dort stehen npms Fehlerzeilen.
# - **Erkannt wird der exakte Fehlercode `E409`,** nicht die Zeichenfolge
#   `409` irgendwo in der Ausgabe. Ein Paket namens `pkg409` oder eine URL mit
#   dieser Ziffernfolge loeste sonst Wiederholungen fuer einen fremden Fehler
#   aus. Einen eigenen Prozess-Exit-Code je HTTP-Status gibt es nicht: npm
#   endet bei jedem HTTP-Fehler mit 1.
# - **„nicht vorhanden" und „nicht feststellbar" sind zwei Zustaende.** Faellt
#   die Registry-Abfrage aus, darf niemand „ist noch frei" oder „liegt nicht
#   oben" behaupten — das erste ist eine falsche Freigabe, das zweite verkennt
#   einen geglueckten Upload.
# - **Wiederholt wird nur ohne Lifecycle-Scripte.** Jeder neue Versuch startet
#   `npm publish` komplett neu, samt `prepublishOnly`, `prepack`, `prepare`,
#   `postpack`, `publish` und `postpublish`. Dass die Registry eine Version
#   nicht ueberschreibt, macht diese **lokalen** Hooks nicht idempotent.
#   Erklaert die package.json einen davon, unterbleibt die Wiederholung.
#
# **Wiederholt wird ausschliesslich bei `E409`.** Bei `401`, `402` oder `403`
# bricht das Script sofort ab — dort ist die Ursache Zugang oder Abo, und ein
# zweiter Versuch aendert daran nichts.
#
# Projektunabhaengig: Registry, Name und Version kommen aus der package.json im
# aktuellen Verzeichnis und aus der npm-Konfiguration — nichts ist fest
# verdrahtet.
#
# Verwendung:
#   npm-publish.sh --publish [weitere npm-Argumente]
#   npm-publish.sh [--ensure] [--status] [--help]
#
# Alles nach `--publish` geht unveraendert an `npm publish` weiter, etwa
# `--otp=123456` oder `--tag next`.
#
# Optionen:
#   -p | --publish  Anmelden, pruefen, hochladen, nachsehen
#   -e | --ensure   Nur die Anmeldung sicherstellen (private Abhaengigkeiten, CI)
#   -s | --status   Nur berichten, nichts aendern (fuer CI)
#   -h | --help     Diese Hilfe anzeigen
#
# Exit-Codes:
#   0  veroeffentlicht beziehungsweise angemeldet
#   1  Anmeldung fehlt oder schlug fehl, Version liegt bereits oben, der
#      Registry-Zustand ist unbekannt, oder das Hochladen ist endgueltig
#      gescheitert
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

# Lifecycle-Scripte, die ein zweiter `npm publish` erneut ausfuehren wuerde.
readonly LIFECYCLE_HOOKS=(prepublishOnly prepack prepare postpack publish postpublish)

# Auffangdatei fuer stderr des Uploads; siehe Kopf, warum nicht stdout.
ERR_FILE=""

# Raeumt die Auffangdatei weg. Gibt immer 0 zurueck, damit ein EXIT-Trap den
# Exit-Code des Scripts nicht ueberschreibt.
cleanup() {
    [[ -n "${ERR_FILE}" && -f "${ERR_FILE}" ]] && rm -f "${ERR_FILE}"
    return 0
}

trap cleanup EXIT

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
    echo -e "    Mit OTP:          ${GREEN}${APPNAME} --publish --otp=123456${NC}"
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

# Nennt die Lifecycle-Scripte, die diese package.json erklaert.
#
# Sie sind der Grund, weshalb eine Wiederholung nicht pauschal gefahrlos ist:
# Ein zweiter `npm publish` fuehrt sie alle erneut aus.
#
# Returns:
#   0; die gefundenen Namen kommaseparariert auf stdout, sonst nichts
declaredLifecycleHooks() {
    [[ -f package.json ]] || return 0

    node -e '
        const scripts = require("./package.json").scripts || {}
        const found = process.argv.slice(1)
            .filter((hook) => typeof scripts[hook] === "string" && scripts[hook].trim())
        if (found.length) console.log(found.join(", "))
    ' "${LIFECYCLE_HOOKS[@]}" 2>/dev/null || true
}

# Liest npms Fehlercode aus einer aufgefangenen stderr-Datei.
#
# Gesucht wird die Codezeile, nicht die blosse Ziffernfolge: `409` steht auch
# in einem Paketnamen oder einer URL, und ein Fremdfehler darf keine
# Wiederholung ausloesen.
#
# Params:
#   $1 - Datei mit der stderr-Ausgabe
#
# Returns:
#   0; der Code (etwa `E409`) auf stdout, sonst nichts
npmErrorCode() {
    [[ -f "$1" ]] || return 0

    sed -nE 's/.*npm (error|ERR!) code (E[A-Z0-9]+).*/\2/p' "$1" 2>/dev/null | head -1
}

# Stellt fest, ob eine Version in der Registry liegt.
#
# **Drei Zustaende, nicht zwei.** Faellt die Abfrage aus, ist das nicht
# dasselbe wie „nicht vorhanden": Vorher waere es eine falsche Freigabe,
# nachher wuerde es einen geglueckten Upload verkennen.
#
# Gelesen wird **ungecacht** (`--prefer-online`). Ein veraltetes Paket-Dokument
# im npm-Cache beantwortet die Frage sonst mit dem Stand von gestern — und ist
# zugleich ein Verdaechtiger fuer die `409`. Der Aufruf frischt den Cache also
# auf, bevor geschrieben wird.
#
# Params:
#   $1 - Paketname
#   $2 - Version
#   $3 - Registry-URL
#
# Returns:
#   0; `published`, `absent` oder `unknown` auf stdout
versionState() {
    local name="$1" version="$2" registry="$3"
    local versions="" errors="" state="unknown"
    local -i rc=0

    errors="$(mktemp)"

    versions="$(npm view "${name}" versions --json --prefer-online \
        --registry "${registry}" 2>"${errors}")" || rc=$?

    if (( rc == 0 )); then
        # `npm view` liefert bei genau einer Version eine Zeichenkette statt
        # einer Liste — beide Formen muessen hier durchgehen.
        if node -e '
            let list
            try { list = JSON.parse(process.argv[1]) } catch { process.exit(1) }
            if (!Array.isArray(list)) list = [list]
            process.exit(list.includes(process.argv[2]) ? 0 : 1)
        ' "${versions}" "${version}" 2>/dev/null; then
            state="published"
        else
            state="absent"
        fi
    elif grep -qE 'npm (error|ERR!) code E404' "${errors}"; then
        # Ein unbekanntes Paket ist kein Ausfall: Vor der ersten
        # Veroeffentlichung gibt es das Dokument schlicht noch nicht.
        state="absent"
    fi

    rm -f "${errors}"
    echo "${state}"
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

# Laedt das Paket hoch und wiederholt ausschliesslich bei einem echten `E409`.
#
# Nach jedem Fehlschlag wird nachgesehen, ob die Version trotzdem oben liegt:
# Bei einer `409` ist genau das die offene Frage, und ein blindes Wiederholen
# wuerde sie mit einer zweiten, ebenso unklaren Meldung beantworten.
#
# Params:
#   $1 - Paketname
#   $2 - Version
#   $3 - Registry-URL
#   $@ - weitere Argumente fuer `npm publish` (etwa `--otp=…`)
#
# Returns:
#   0 wenn die Version danach oben liegt, sonst 1
publishWithRetries() {
    local name="$1" version="$2" registry="$3"
    shift 3
    local code="" delay="" hooks="" state=""
    local -i attempt=0 rc=0

    hooks="$(declaredLifecycleHooks)"

    while (( attempt < MAX_ATTEMPTS )); do
        attempt=$(( attempt + 1 ))

        if (( attempt > 1 )); then
            echo -e "  ${YELLOW}→${NC} Versuch ${attempt} von ${MAX_ATTEMPTS}"
        fi

        : > "${ERR_FILE}"
        rc=0

        # **stdout bleibt unberuehrt.** npm bricht seine OTP-Abfrage ab, sobald
        # stdin oder stdout kein TTY ist; ein Einfangen der Ausgabe schaltet
        # damit die Zwei-Faktor-Anmeldung stumm ab. Fehlerzeilen stehen
        # ohnehin ausschliesslich auf stderr.
        npm publish "$@" 2>"${ERR_FILE}" || rc=$?

        if [[ -s "${ERR_FILE}" ]]; then
            cat "${ERR_FILE}" >&2
        fi

        if (( rc == 0 )); then
            echo -e "  ${GREEN}✓${NC} ${YELLOW}${name}@${version}${NC} veroeffentlicht"
            return 0
        fi

        state="$(versionState "${name}" "${version}" "${registry}")"

        if [[ "${state}" == "published" ]]; then
            echo -e "  ${GREEN}✓${NC} ${YELLOW}${name}@${version}${NC} liegt oben —" \
                    "der Fehlschlag betraf nur die Antwort, nicht den Upload"
            return 0
        fi

        if [[ "${state}" == "unknown" ]]; then
            echo -e "  ${RED}✗${NC} Upload gescheitert **und** der Registry-Zustand ist" \
                    "nicht feststellbar." >&2
            echo -e "      Ob ${YELLOW}${version}${NC} oben liegt, muss von Hand" \
                    "geklaert werden:" >&2
            echo -e "      ${GREEN}npm view ${name} versions --prefer-online${NC}" >&2
            return 1
        fi

        code="$(npmErrorCode "${ERR_FILE}")"

        if [[ "${code}" != "E409" ]]; then
            echo -e "  ${RED}✗${NC} Abbruch bei ${YELLOW}${code:-unbekanntem Fehler}${NC} —" \
                    "nur ${YELLOW}E409${NC} wird wiederholt" >&2
            return 1
        fi

        echo -e "  ${YELLOW}⚠${NC} ${YELLOW}E409${NC} — Registry konnte das Paket-Dokument nicht speichern"

        if [[ -n "${hooks}" ]]; then
            echo -e "  ${RED}✗${NC} keine Wiederholung: Die package.json erklaert" \
                    "${YELLOW}${hooks}${NC}." >&2
            echo -e "      Ein zweiter Lauf fuehrt diese Scripte erneut aus; ob das" \
                    "gefahrlos ist," >&2
            echo -e "      weiss nur das Paket selbst. Erneut starten bitte von Hand." >&2
            return 1
        fi

        if (( attempt < MAX_ATTEMPTS )); then
            delay="${RETRY_DELAYS[$(( attempt - 1 ))]}"
            echo -e "      warte ${delay}s und versuche erneut"
            sleep "${delay}"
        fi
    done

    echo -e "  ${RED}✗${NC} nach ${MAX_ATTEMPTS} Versuchen aufgegeben —" \
            "${YELLOW}${version}${NC} liegt nicht oben" >&2
    return 1
}

# Der ganze Vorgang: anmelden, pruefen, hochladen, nachsehen.
#
# Params:
#   $1 - "publish", "ensure" oder "status"
#   $@ - weitere Argumente fuer `npm publish`
#
# Returns:
#   0 bei Erfolg, sonst 1
run() {
    local mode="$1"
    shift
    local registry name version state
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

    state="$(versionState "${name}" "${version}" "${registry}")"

    if [[ "${state}" == "published" ]]; then
        echo -e "  ${YELLOW}⚠${NC} ${YELLOW}${version}${NC} liegt bereits oben —" \
                "eine Version wird nie ueberschrieben"
        echo -e "      ${BLUE}Version anheben mit: ${GREEN}npm version patch|minor|major${NC}"
        echo
        # Beim Berichten ist das keine Stoerung, sondern die Auskunft selbst.
        [[ "${mode}" == "status" ]] && return 0
        return 1
    fi

    if [[ "${state}" == "unknown" ]]; then
        echo -e "  ${YELLOW}⚠${NC} Registry nicht erreichbar — ob ${YELLOW}${version}${NC}" \
                "frei ist, bleibt offen"

        if [[ "${mode}" == "status" ]]; then
            echo
            # Eine Auskunft, die nichts weiss, ist keine gruene Auskunft.
            return 1
        fi

        echo -e "      Der Upload laeuft trotzdem an; npm lehnt eine bestehende" \
                "Version selbst ab."
    else
        echo -e "  ${GREEN}✓${NC} ${YELLOW}${version}${NC} ist noch frei"
    fi

    if [[ "${mode}" == "status" ]]; then
        echo
        return 0
    fi

    ERR_FILE="$(mktemp)"

    echo
    publishWithRetries "${name}" "${version}" "${registry}" "$@" || rc=$?
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
        shift
        run "publish" "$@"
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
