#!/usr/bin/env bash
#------------------------------------------------------------------------------
# npm-publish.test.sh — Tests fuer src/bash/npm-publish.sh
#
# Integrationstests: Das Script laeuft als **Prozess** ueber seinen
# oeffentlichen Aufruf, gegen eine `npm`-Attrappe auf dem `PATH`. Keine
# gesourcten Funktionen — sonst prueft der Test eine Verdrahtung, die es beim
# echten Aufruf so nicht gibt.
#
# Vier Faelle sind der Grund, dass es diese Datei gibt. Jeder war eine echte
# Fehlfunktion, gefunden im Review von T-20:
#
# - `reicht_stdout_durch`: Ein `output="$(npm publish)"` nimmt npm das TTY und
#   schaltet damit die OTP-Abfrage stumm ab (npm 11, `lib/utils/auth.js:10`
#   prueft `stdin` **und** `stdout`). Der Test prueft die beobachtbare Folge:
#   Was npm nach stdout schreibt, muss beim Aufrufer ankommen.
# - `fremder_409_wird_nicht_wiederholt`: Ein `grep '409'` auf der ganzen
#   Ausgabe trifft auch ein Paket namens `pkg409`.
# - `unbekannter_zustand_*`: Faellt die Registry-Abfrage aus, ist das nicht
#   „nicht vorhanden". Weder „frei" noch „liegt nicht oben" darf behauptet
#   werden.
# - `lifecycle_hooks_verhindern_wiederholung`: Ein zweiter `npm publish`
#   fuehrt `prepare` und Geschwister erneut aus.
#
# Verwendung:
#   ./tests/bash/npm-publish.test.sh --run
#   ./tests/bash/npm-publish.test.sh --help
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

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../../src/bash" && pwd)/npm-publish.sh"
readonly SCRIPT_UNDER_TEST

readonly PKG_NAME="@scope/demo"
readonly PKG_VERSION="1.0.0"
readonly OTHER_VERSION="0.9.0"
readonly STDOUT_MARKER="NPM-SCHREIBT-NACH-STDOUT"

tests_run=0
tests_failed=0
fixture=""

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
    tests_run=$((tests_run + 1))
    if [[ "$1" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} $2"
    else
        tests_failed=$((tests_failed + 1))
        echo -e "  ${RED}✗${NC} $2"
    fi
}

# Vergleicht zwei Werte und meldet das Ergebnis.
#
# Params:
#   $1 - Erwartet
#   $2 - Tatsaechlich
#   $3 - Beschreibung
assertEquals() {
    if [[ "$1" == "$2" ]]; then
        report 0 "$3"
    else
        report 1 "$3 ${YELLOW}(erwartet '$1', war '$2')${NC}"
    fi
}

# Prueft, ob eine Datei einen Text enthaelt.
#
# Params:
#   $1 - Datei
#   $2 - gesuchter Text (fester String)
#   $3 - Beschreibung
assertContains() {
    if grep -qF -- "$2" "$1" 2>/dev/null; then
        report 0 "$3"
    else
        report 1 "$3 ${YELLOW}('$2' fehlt)${NC}"
    fi
}

# Prueft, ob eine Datei einen Text **nicht** enthaelt.
#
# Params:
#   $1 - Datei
#   $2 - verbotener Text (fester String)
#   $3 - Beschreibung
assertNotContains() {
    if grep -qF -- "$2" "$1" 2>/dev/null; then
        report 1 "$3 ${YELLOW}('$2' steht dort, darf aber nicht)${NC}"
    else
        report 0 "$3"
    fi
}

# Baut ein Wegwerf-Paket mit `npm`- und `sleep`-Attrappe auf dem PATH.
#
# Die `npm`-Attrappe protokolliert jeden Aufruf mit allen Argumenten. Ihre
# Antworten steuern zwei Umgebungsvariablen:
#
#   STUB_VIEW_SEQUENCE  Antworten fuer `npm view`, eine je Aufruf; die letzte
#                       wiederholt sich. Werte: published | absent | e404 | efail
#   STUB_PUBLISH_CODE   npm-Fehlercode fuer `npm publish`; leer = Erfolg
setupFixture() {
    fixture="$(mktemp -d)"
    mkdir -p "${fixture}/bin"

    printf '{"name":"%s","version":"%s"}\n' "${PKG_NAME}" "${PKG_VERSION}" \
        > "${fixture}/package.json"

    cat > "${fixture}/bin/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

    cat > "${fixture}/bin/npm" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "\${STUB_LOG}"

case "\$1" in
    whoami)
        echo "testuser"
        exit 0
        ;;
    config)
        echo "https://registry.example.test/"
        exit 0
        ;;
    view)
        idx=0
        [[ -f "\${STUB_STATE}" ]] && idx="\$(cat "\${STUB_STATE}")"
        read -ra seq <<< "\${STUB_VIEW_SEQUENCE:-absent}"
        last=\$(( \${#seq[@]} - 1 ))
        [[ \${idx} -gt \${last} ]] && idx=\${last}
        answer="\${seq[\${idx}]}"
        echo \$(( idx + 1 )) > "\${STUB_STATE}"

        case "\${answer}" in
            published) echo '["${PKG_VERSION}"]'; exit 0 ;;
            absent)    echo '["${OTHER_VERSION}"]'; exit 0 ;;
            e404)      echo "npm error code E404" >&2; exit 1 ;;
            *)         echo "npm error code E500" >&2; exit 1 ;;
        esac
        ;;
    publish)
        echo "${STDOUT_MARKER}"
        if [[ -z "\${STUB_PUBLISH_CODE:-}" ]]; then
            exit 0
        fi
        echo "npm error code \${STUB_PUBLISH_CODE}" >&2
        echo "npm error \${STUB_PUBLISH_CODE} - PUT https://registry.example.test/pkg409" >&2
        exit 1
        ;;
esac
exit 0
STUB

    chmod +x "${fixture}/bin/npm" "${fixture}/bin/sleep"
}

teardownFixture() {
    [[ -n "${fixture}" && -d "${fixture}" ]] && rm -rf "${fixture}"
    fixture=""
}

# Ruft das Script im Fixture auf und legt Ausgabe und Protokoll dort ab.
#
# Params:
#   $@ - Argumente fuer das Script
#
# Returns:
#   Exit-Code des Scripts; stdout in <fixture>/out.txt, stderr in err.txt,
#   die npm-Aufrufe in calls.txt
runScript() {
    local rc=0

    rm -f "${fixture}/calls.txt" "${fixture}/state.txt"
    : > "${fixture}/calls.txt"

    (
        cd "${fixture}" || exit 1
        PATH="${fixture}/bin:${PATH}" \
        STUB_LOG="${fixture}/calls.txt" \
        STUB_STATE="${fixture}/state.txt" \
            bash "${SCRIPT_UNDER_TEST}" "$@" \
                > "${fixture}/out.txt" 2> "${fixture}/err.txt"
    ) || rc=$?

    return ${rc}
}

# Zaehlt, wie oft `npm publish` aufgerufen wurde.
publishCalls() {
    grep -c '^publish' "${fixture}/calls.txt" 2>/dev/null || true
}

# ─── Tests ──────────────────────────────────────────────────────────────────

testOhneArgumentKommtHilfe() {
    setupFixture
    local rc=0
    runScript || rc=$?
    assertEquals "0" "${rc}" "ohne Argument: Hilfe statt Handlung"
    assertContains "${fixture}/out.txt" "--publish" "ohne Argument: Hilfe nennt --publish"
    assertEquals "0" "$(publishCalls)" "ohne Argument: nichts wird hochgeladen"
    teardownFixture
}

testStatusMeldetVorhandeneVersion() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="published" runScript --status || rc=$?
    assertEquals "0" "${rc}" "status: vorhandene Version ist eine Auskunft, kein Fehler"
    assertContains "${fixture}/out.txt" "liegt bereits oben" "status: nennt die vergebene Version"
    teardownFixture
}

testStatusMeldetFreieVersion() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --status || rc=$?
    assertEquals "0" "${rc}" "status: freie Version ist gruen"
    assertContains "${fixture}/out.txt" "ist noch frei" "status: nennt die freie Version"
    teardownFixture
}

testUnbekanntesPaketGiltAlsFrei() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="e404" runScript --status || rc=$?
    assertEquals "0" "${rc}" "status: E404 heisst 'noch nie veroeffentlicht', kein Ausfall"
    assertContains "${fixture}/out.txt" "ist noch frei" "status: E404 gilt als frei"
    teardownFixture
}

# Finding 3 aus dem Review: Eine Auskunft, die nichts weiss, war gruen.
testStatusWirdBeiUnbekanntemZustandNichtGruen() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="efail" runScript --status || rc=$?
    assertEquals "1" "${rc}" "status: unbekannter Zustand ist nicht gruen"
    assertNotContains "${fixture}/out.txt" "ist noch frei" "status: behauptet nichts ueber die Version"
    teardownFixture
}

# Finding 1 aus dem Review: Das Einfangen der Ausgabe nahm npm das TTY und
# damit die OTP-Abfrage. Geprueft wird die beobachtbare Folge.
testReichtStdoutDurch() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish || rc=$?
    assertEquals "0" "${rc}" "publish: Erfolgsfall endet mit 0"
    assertContains "${fixture}/out.txt" "${STDOUT_MARKER}" \
        "publish: npms stdout erreicht den Aufrufer (OTP bleibt moeglich)"
    teardownFixture
}

# Finding 1, zweite Haelfte: `--otp=…` wurde geschluckt statt weitergereicht.
testWeitereArgumenteGehenAnNpm() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --otp=123456 --tag next || rc=$?
    assertEquals "0" "${rc}" "publish: zusaetzliche Argumente stoeren nicht"
    assertContains "${fixture}/calls.txt" "publish --otp=123456 --tag next" \
        "publish: reicht weitere Argumente unveraendert an npm weiter"
    teardownFixture
}

testEchterE409WirdWiederholt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" STUB_PUBLISH_CODE="E409" runScript --publish || rc=$?
    assertEquals "1" "${rc}" "E409: dreimal vergeblich endet mit 1"
    assertEquals "3" "$(publishCalls)" "E409: genau drei Versuche"
    teardownFixture
}

# Finding 2 aus dem Review: `grep '409'` traf auch `pkg409` in einer URL.
testFremder409LoestKeineWiederholungAus() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" STUB_PUBLISH_CODE="E403" runScript --publish || rc=$?
    assertEquals "1" "${rc}" "E403: Abbruch mit 1"
    assertEquals "1" "$(publishCalls)" "E403: genau ein Versuch, trotz '409' im Text"
    assertContains "${fixture}/err.txt" "E403" "E403: der echte Code steht in der Meldung"
    teardownFixture
}

testErfolgTrotzFehlerWirdErkannt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent published" STUB_PUBLISH_CODE="E409" runScript --publish || rc=$?
    assertEquals "0" "${rc}" "E409, aber oben gelandet: gilt als Erfolg"
    assertEquals "1" "$(publishCalls)" "E409, aber oben gelandet: keine Wiederholung"
    teardownFixture
}

# Finding 3 aus dem Review, zweite Haelfte: Nach dem Fehlschlag durfte das
# Script nicht behaupten, die Version liege nicht oben.
testUnbekannterZustandNachFehlschlagBrichtAb() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent efail" STUB_PUBLISH_CODE="E409" runScript --publish || rc=$?
    assertEquals "1" "${rc}" "unbekannt nach Fehlschlag: Abbruch mit 1"
    assertEquals "1" "$(publishCalls)" "unbekannt nach Fehlschlag: keine Wiederholung"
    assertNotContains "${fixture}/err.txt" "liegt nicht oben" \
        "unbekannt nach Fehlschlag: behauptet nicht, es sei nicht oben"
    assertContains "${fixture}/err.txt" "nicht feststellbar" \
        "unbekannt nach Fehlschlag: benennt die Unklarheit"
    teardownFixture
}

# Finding 4 aus dem Review: Jeder neue Versuch fuehrt die Lifecycle-Scripte
# des Pakets erneut aus.
testLifecycleHooksVerhindernWiederholung() {
    setupFixture
    printf '{"name":"%s","version":"%s","scripts":{"prepare":"echo bau"}}\n' \
        "${PKG_NAME}" "${PKG_VERSION}" > "${fixture}/package.json"

    local rc=0
    STUB_VIEW_SEQUENCE="absent" STUB_PUBLISH_CODE="E409" runScript --publish || rc=$?
    assertEquals "1" "${rc}" "Lifecycle: Abbruch mit 1"
    assertEquals "1" "$(publishCalls)" "Lifecycle: genau ein Versuch trotz E409"
    assertContains "${fixture}/err.txt" "prepare" "Lifecycle: nennt das Script, das im Weg steht"
    teardownFixture
}

testRegistryAusPublishConfig() {
    setupFixture
    printf '{"name":"%s","version":"%s","publishConfig":{"registry":"https://eigene.test/"}}\n' \
        "${PKG_NAME}" "${PKG_VERSION}" > "${fixture}/package.json"

    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --status || rc=$?
    assertEquals "0" "${rc}" "publishConfig: Status laeuft durch"
    assertContains "${fixture}/out.txt" "https://eigene.test/" \
        "publishConfig: schlaegt die globale Einstellung"
    teardownFixture
}

runAll() {
    echo
    echo -e "${LIGHT_BLUE}npm-publish.sh${NC}"
    echo

    testOhneArgumentKommtHilfe
    testStatusMeldetVorhandeneVersion
    testStatusMeldetFreieVersion
    testUnbekanntesPaketGiltAlsFrei
    testStatusWirdBeiUnbekanntemZustandNichtGruen
    testReichtStdoutDurch
    testWeitereArgumenteGehenAnNpm
    testEchterE409WirdWiederholt
    testFremder409LoestKeineWiederholungAus
    testErfolgTrotzFehlerWirdErkannt
    testUnbekannterZustandNachFehlschlagBrichtAb
    testLifecycleHooksVerhindernWiederholung
    testRegistryAusPublishConfig

    echo
    if [[ ${tests_failed} -eq 0 ]]; then
        echo -e "  ${GREEN}${tests_run} Tests, alle gruen${NC}"
        echo
        return 0
    fi
    echo -e "  ${RED}${tests_failed} von ${tests_run} Tests fehlgeschlagen${NC}"
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
