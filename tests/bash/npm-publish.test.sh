#!/usr/bin/env bash
#------------------------------------------------------------------------------
# npm-publish.test.sh — Tests fuer src/bash/npm-publish.sh
#
# Integrationstests: Das Script laeuft als **Prozess** ueber seinen
# oeffentlichen Aufruf, gegen eine `npm`-Attrappe auf dem `PATH`. Keine
# gesourcten Funktionen — sonst prueft der Test eine Verdrahtung, die es beim
# echten Aufruf so nicht gibt.
#
# Die Faelle, derentwegen es diese Datei gibt. Jeder war eine echte
# Fehlfunktion, gefunden in den Review-Runden zu T-20:
#
# - `laeuft_unter_echtem_tty`: npm bricht seine OTP-Abfrage ab, sobald `stdin`
#   **oder** `stdout` kein TTY ist (npm 11, `lib/utils/auth.js:10`). Geprueft
#   wird das unter einem **echten PTY** — die schwaechere Frage „kommt npms
#   Ausgabe beim Aufrufer an?" beantwortet auch eine `tee`-Pipeline mit ja,
#   waehrend npm trotzdem kein TTY saehe.
# - `fremder_409_wird_nicht_wiederholt`: Ein `grep '409'` auf der ganzen
#   Ausgabe trifft auch ein Paket namens `pkg409`.
# - `unbekanntes_paket_*`, `unlesbare_antwort_*`, `unbekannter_zustand_*`:
#   Weder ein Ausfall der Abfrage noch eine unlesbare Antwort noch ein `E404`
#   sind ein sicheres „nicht vorhanden". Bei einem privaten Paket heisst 404
#   „gibt es nicht **oder** du darfst nicht".
# - `registry_override_gilt_fuer_alle_schritte`: Ein `--registry` hinter
#   `--publish` verschob nur den Upload; Anmeldung und Pruefung schauten
#   weiter auf die alte Registry.
# - `wert_darf_keine_option_sein`: `--otp --dry-run` rutschte durch die
#   Positivliste, weil die Wertoption das naechste Token ungeprueft schluckte.
#   npm liest dann `otp=--dry-run` und `dry-run=false` — ein echter Upload.
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
readonly DEFAULT_REGISTRY="https://default.example.test/"
readonly OVERRIDE_REGISTRY="https://override.example.test/"

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
# Die Attrappe protokolliert je Aufruf drei Zeilen:
#
#   <unterbefehl> <alle argumente>   fuer Zaehlung und Argumentpruefung
#   REGISTRY[<unterbefehl>]=<url>    welches Ziel dieser Schritt benutzte
#   PUBLISH_STDIO_TTY=<yes|no>       nur bei `publish`: sah npm stdin UND
#                                    stdout als TTY?
#
# Ihre Antworten steuern zwei Umgebungsvariablen:
#
#   STUB_VIEW_SEQUENCE  Antworten fuer `npm view`, eine je Aufruf; die letzte
#                       wiederholt sich. Werte:
#                       published | absent | unparsable | e404 | efail
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
sub="\$1"
echo "\$*" >> "\${STUB_LOG}"

# Welche Registry benutzte dieser Schritt tatsaechlich?
reg="${DEFAULT_REGISTRY}"
prev=""
for a in "\$@"; do
    case "\${a}" in
        --registry=*) reg="\${a#--registry=}" ;;
    esac
    [[ "\${prev}" == "--registry" ]] && reg="\${a}"
    prev="\${a}"
done
echo "REGISTRY[\${sub}]=\${reg}" >> "\${STUB_LOG}"

case "\${sub}" in
    whoami)
        echo "testuser"
        exit 0
        ;;
    config)
        echo "${DEFAULT_REGISTRY}"
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
            published)  echo '["${PKG_VERSION}"]'; exit 0 ;;
            absent)     echo '["${OTHER_VERSION}"]'; exit 0 ;;
            unparsable) echo 'not-json'; exit 0 ;;
            e404)       echo "npm error code E404" >&2; exit 1 ;;
            *)          echo "npm error code E500" >&2; exit 1 ;;
        esac
        ;;
    publish)
        # Die Zusage, an der die OTP-Abfrage haengt. npm prueft **stdin und
        # stdout** (\`lib/utils/auth.js:10\`), deshalb beide — ein \`< /dev/null\`
        # am Upload liesse stdout heil und die Abfrage trotzdem sterben.
        # Beobachtbar ist das nur unter einem echten PTY; im umgeleiteten
        # Harness steht hier immer \`no\`, egal was das Script tut.
        if [[ -t 0 && -t 1 ]]; then
            echo "PUBLISH_STDIO_TTY=yes" >> "\${STUB_LOG}"
        else
            echo "PUBLISH_STDIO_TTY=no (stdin=\$([ -t 0 ] && echo tty || echo nein)," \
                 "stdout=\$([ -t 1 ] && echo tty || echo nein))" >> "\${STUB_LOG}"
        fi
        echo "${STDOUT_MARKER}"
        if [[ -z "\${STUB_PUBLISH_CODE:-}" ]]; then
            exit 0
        fi
        echo "npm error code \${STUB_PUBLISH_CODE}" >&2
        echo "npm error \${STUB_PUBLISH_CODE} - PUT ${DEFAULT_REGISTRY}pkg409" >&2
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

# Leert Protokoll und Attrappen-Zustand vor einem Lauf.
resetStub() {
    rm -f "${fixture}/calls.txt" "${fixture}/state.txt"
    : > "${fixture}/calls.txt"
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

    resetStub

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

# Wie runScript, nur unter einem **echten PTY**.
#
# Das ist der einzige Weg, die TTY-Zusage ohne echten Upload zu pruefen: Ein
# umgeleitetes stdout ist im Harness immer kein TTY, egal was das Script tut.
# Unter dem PTY sieht die Attrappe genau das, was npm sehen wuerde.
#
# Genommen wird `script`, nicht Pythons `pty.spawn`: Letzteres liefert zwar
# ein korrektes PTY, kehrt auf macOS aber nach dem Kindprozess nicht aus
# seiner Kopierschleife zurueck — der Testlauf haengt dann endlos.
#
# Die beiden `script`-Fassungen sind unvereinbar (BSD nimmt das Kommando als
# Argumente, GNU als Zeichenkette hinter `-c`), deshalb erst die eine, dann
# die andere. `< /dev/null` verhindert, dass die Sitzung auf eine Eingabe
# wartet; das Kind behaelt sein TTY trotzdem, es bekommt die PTY-Seite.
#
# Geprueft wird ausschliesslich das Protokoll der Attrappe — `script`
# schreibt Wagenruecklaeufe und ein `^D` in die Ausgabe, die dort nichts
# verloren haetten.
#
# Params:
#   $@ - Argumente fuer das Script
#
# Returns:
#   0 wenn ein PTY-Lauf zustande kam, sonst 127
runScriptUnderPty() {
    command -v script >/dev/null 2>&1 || return 127

    resetStub

    (
        cd "${fixture}" || exit 1
        export PATH="${fixture}/bin:${PATH}"
        export STUB_LOG="${fixture}/calls.txt"
        export STUB_STATE="${fixture}/state.txt"

        script -q /dev/null bash "${SCRIPT_UNDER_TEST}" "$@" \
            < /dev/null > "${fixture}/out.txt" 2> "${fixture}/err.txt"
    ) || true

    grep -q '^publish' "${fixture}/calls.txt" 2>/dev/null && return 0

    # Zweiter Anlauf in der GNU-Fassung.
    (
        cd "${fixture}" || exit 1
        export PATH="${fixture}/bin:${PATH}"
        export STUB_LOG="${fixture}/calls.txt"
        export STUB_STATE="${fixture}/state.txt"

        script -qec "bash '${SCRIPT_UNDER_TEST}' $*" /dev/null \
            < /dev/null > "${fixture}/out.txt" 2> "${fixture}/err.txt"
    ) || true

    grep -q '^publish' "${fixture}/calls.txt" 2>/dev/null && return 0
    return 127
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

# Runde 2, Finding 2: `E404` heisst bei einem privaten Paket „gibt es nicht
# ODER du darfst nicht". Als „frei" gelesen ist das eine falsche Freigabe.
testUnbekanntesPaketIstNichtSicherFrei() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="e404" runScript --status || rc=$?
    assertEquals "1" "${rc}" "E404: keine gruene Auskunft"
    assertNotContains "${fixture}/out.txt" "ist noch frei" "E404: behauptet nicht, die Version sei frei"
    assertContains "${fixture}/out.txt" "kein Zugriff" "E404: nennt beide moeglichen Ursachen"
    teardownFixture
}

# Runde 2, Finding 2: Eine unlesbare Antwort ist kein „Version fehlt".
testUnlesbareAntwortIstNichtFrei() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="unparsable" runScript --status || rc=$?
    assertEquals "1" "${rc}" "unlesbare Antwort: keine gruene Auskunft"
    assertNotContains "${fixture}/out.txt" "ist noch frei" "unlesbare Antwort: behauptet nichts"
    assertContains "${fixture}/out.txt" "nicht lesbar" "unlesbare Antwort: benennt die Ursache"
    teardownFixture
}

testStatusWirdBeiUnbekanntemZustandNichtGruen() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="efail" runScript --status || rc=$?
    assertEquals "1" "${rc}" "status: unbekannter Zustand ist nicht gruen"
    assertNotContains "${fixture}/out.txt" "ist noch frei" "status: behauptet nichts ueber die Version"
    teardownFixture
}

# Die schwaechere Zusage: npms Ausgabe erreicht den Aufrufer. Notwendig, aber
# **nicht hinreichend** fuer die OTP-Abfrage — dafuer gibt es den PTY-Test.
testStdoutErreichtDenAufrufer() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish || rc=$?
    assertEquals "0" "${rc}" "publish: Erfolgsfall endet mit 0"
    assertContains "${fixture}/out.txt" "${STDOUT_MARKER}" \
        "publish: npms stdout-Ausgabe erreicht den Aufrufer"
    teardownFixture
}

# Runde 2, Finding 3: **Die** Zusage, an der die OTP-Abfrage haengt. Unter
# einem echten PTY muss npm ein TTY auf stdout sehen.
testPublishLaeuftUnterEchtemTty() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScriptUnderPty --publish || rc=$?

    if [[ ${rc} -eq 127 ]]; then
        report 1 "TTY: kein brauchbares 'script' — die Gegenprobe konnte nicht laufen"
        teardownFixture
        return
    fi

    assertContains "${fixture}/calls.txt" "PUBLISH_STDIO_TTY=yes" \
        "TTY: npm sieht unter einem echten PTY **stdin und stdout** als TTY (OTP bleibt moeglich)"
    assertEquals "1" "$(publishCalls)" "TTY: genau ein Upload-Versuch"
    teardownFixture
}

testWeitereArgumenteGehenAnNpm() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --otp=123456 --tag next || rc=$?
    assertEquals "0" "${rc}" "publish: zusaetzliche Argumente stoeren nicht"
    assertContains "${fixture}/calls.txt" "publish --otp=123456 --tag next" \
        "publish: reicht weitere Argumente unveraendert an npm weiter"
    teardownFixture
}

# Runde 2, Finding 1: Der Upload ging in die Override-Registry, Anmeldung und
# Pruefung schauten weiter auf die Default-Registry — und rc war 0.
testRegistryOverrideGiltFuerAlleSchritte() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish "--registry=${OVERRIDE_REGISTRY}" || rc=$?
    assertEquals "0" "${rc}" "Registry-Override: Lauf endet mit 0"
    assertContains "${fixture}/calls.txt" "REGISTRY[whoami]=${OVERRIDE_REGISTRY}" \
        "Registry-Override: die Anmeldung fragt am selben Ort"
    assertContains "${fixture}/calls.txt" "REGISTRY[view]=${OVERRIDE_REGISTRY}" \
        "Registry-Override: die Pruefung liest am selben Ort"
    assertContains "${fixture}/calls.txt" "REGISTRY[publish]=${OVERRIDE_REGISTRY}" \
        "Registry-Override: der Upload schreibt dorthin"
    assertNotContains "${fixture}/calls.txt" "REGISTRY[view]=${DEFAULT_REGISTRY}" \
        "Registry-Override: kein Schritt bleibt auf der alten Registry"
    teardownFixture
}

testScopeRegistryWirdAbgelehnt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish "--@scope:registry=${OVERRIDE_REGISTRY}" || rc=$?
    assertEquals "1" "${rc}" "Scope-Registry: Abbruch mit 1"
    assertEquals "0" "$(publishCalls)" "Scope-Registry: nichts wird hochgeladen"
    assertContains "${fixture}/err.txt" "nicht durchgereicht" "Scope-Registry: sagt warum"
    teardownFixture
}

testWorkspaceWirdAbgelehnt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --workspace=paket-a || rc=$?
    assertEquals "1" "${rc}" "Workspace: Abbruch mit 1"
    assertEquals "0" "$(publishCalls)" "Workspace: nichts wird hochgeladen"
    assertContains "${fixture}/err.txt" "anderes Paket" "Workspace: nennt die Gefahr"
    teardownFixture
}

# Runde 3, Finding 1: `npm publish ./anderes-paket` lud ein anderes Paket hoch
# als das gepruefte — und der Wrapper meldete den Erfolg des geprueften.
testPositionalerSpecWirdAbgelehnt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish ./anderes-paket || rc=$?
    assertEquals "1" "${rc}" "package-spec: Abbruch mit 1"
    assertEquals "0" "$(publishCalls)" "package-spec: nichts wird hochgeladen"
    assertNotContains "${fixture}/out.txt" "veroeffentlicht" \
        "package-spec: meldet keinen Erfolg"
    assertContains "${fixture}/err.txt" "package-spec" "package-spec: nennt die Gefahr"
    teardownFixture
}

# Runde 3, Finding 1: `--dry-run` endet mit 0, ohne etwas zu veroeffentlichen.
testDryRunWirdAbgelehnt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --dry-run || rc=$?
    assertEquals "1" "${rc}" "--dry-run: Abbruch mit 1"
    assertEquals "0" "$(publishCalls)" "--dry-run: npm wird gar nicht erst gerufen"
    assertNotContains "${fixture}/out.txt" "veroeffentlicht" \
        "--dry-run: meldet keinen Erfolg"
    teardownFixture
}

testErlaubteArgumenteGehenDurch() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --otp 123456 --tag=next \
        --access public --provenance || rc=$?
    assertEquals "0" "${rc}" "Positivliste: erlaubte Argumente laufen durch"
    assertContains "${fixture}/calls.txt" "publish --otp 123456 --tag=next --access public --provenance" \
        "Positivliste: beide Schreibweisen kommen unveraendert bei npm an"
    teardownFixture
}

# Runde 4, Finding 1: Die Wertoption schluckte das naechste Token ungeprueft.
# `--otp --dry-run` kam damit durch — und npm liest dann `otp=--dry-run` und
# `dry-run=false`: aus dem gewollten Trockenlauf wird ein **echter Upload**.
testWertDarfKeineOptionSein() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --otp --dry-run || rc=$?
    assertEquals "1" "${rc}" "Wert-als-Option: Abbruch mit 1"
    assertEquals "0" "$(publishCalls)" "Wert-als-Option: nichts wird hochgeladen"
    assertNotContains "${fixture}/out.txt" "veroeffentlicht" \
        "Wert-als-Option: meldet keinen Erfolg"
    assertContains "${fixture}/err.txt" "--dry-run" "Wert-als-Option: nennt das Token"
    teardownFixture
}

testLeererWertWirdAbgelehnt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --otp= || rc=$?
    assertEquals "1" "${rc}" "leerer Wert: Abbruch mit 1"
    assertEquals "0" "$(publishCalls)" "leerer Wert: nichts wird hochgeladen"
    teardownFixture
}

testFehlenderWertWirdAbgelehnt() {
    setupFixture
    local rc=0
    STUB_VIEW_SEQUENCE="absent" runScript --publish --otp || rc=$?
    assertEquals "1" "${rc}" "fehlender Wert: Abbruch mit 1"
    assertEquals "0" "$(publishCalls)" "fehlender Wert: nichts wird hochgeladen"
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

# Runde 1, Finding 2: `grep '409'` traf auch `pkg409` in einer URL.
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

# Runde 1, Finding 4: Jeder neue Versuch fuehrt die Lifecycle-Scripte des
# Pakets erneut aus.
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
    testUnbekanntesPaketIstNichtSicherFrei
    testUnlesbareAntwortIstNichtFrei
    testStatusWirdBeiUnbekanntemZustandNichtGruen
    testStdoutErreichtDenAufrufer
    testPublishLaeuftUnterEchtemTty
    testWeitereArgumenteGehenAnNpm
    testRegistryOverrideGiltFuerAlleSchritte
    testScopeRegistryWirdAbgelehnt
    testWorkspaceWirdAbgelehnt
    testPositionalerSpecWirdAbgelehnt
    testDryRunWirdAbgelehnt
    testErlaubteArgumenteGehenDurch
    testFehlenderWertWirdAbgelehnt
    testWertDarfKeineOptionSein
    testLeererWertWirdAbgelehnt
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
