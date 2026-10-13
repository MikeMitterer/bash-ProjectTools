#!/usr/bin/env bash
#------------------------------------------------------------------------------
# docs-check.test.sh — Tests fuer src/bash/docs-check.sh
#
# Integrationstests: Das Script laeuft als Prozess in einem kleinen Git-Repo
# im Temp-Ordner, mit echter Config und echter Deno-Pruefung. Die Pruefregeln
# selbst testet tests/deno/docs-check.test.ts; hier geht es um Config,
# Optionen und Exit-Codes.
#
# Verwendung:
#   ./tests/bash/docs-check.test.sh --run
#   ./tests/bash/docs-check.test.sh --help
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

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../../src/bash" && pwd)/docs-check.sh"
readonly SCRIPT_UNDER_TEST

tests_run=0
tests_failed=0
fixture=""
output=""
rc=0

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

# Prueft, ob die letzte Ausgabe einen Text enthaelt.
#
# Params:
#   $1 - Gesuchter Text
#   $2 - Beschreibung
assertOutputContains() {
    if [[ "${output}" == *"$1"* ]]; then report 0 "$2"; else report 1 "$2 ${YELLOW}(fehlt: '$1')${NC}"; fi
}

# Prueft, ob die letzte Ausgabe einen Text nicht enthaelt.
#
# Params:
#   $1 - Text, der fehlen muss
#   $2 - Beschreibung
assertOutputLacks() {
    if [[ "${output}" != *"$1"* ]]; then report 0 "$2"; else report 1 "$2 ${YELLOW}(gefunden: '$1')${NC}"; fi
}

# Startet das Script im Fixture; Ausgabe in ${output}, Exit-Code in ${rc}.
runScript() {
    rc=0
    output="$(cd "${fixture}" && "${SCRIPT_UNDER_TEST}" "$@" 2>&1)" || rc=$?
}

# Kleines Repo: README mit gueltigem Link, docs/ mit einer verbotenen Angabe,
# datierter Entwurf, der ausgeschlossen wird.
setupFixture() {
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/docs-check-test.XXXXXX")"
    mkdir -p "${fixture}/docs/drafts"
    printf '# Demo\n\nSee [the guide](docs/guide.md).\n' > "${fixture}/README.md"
    printf '# Guide\n\nThe container runs as 99:100.\n' > "${fixture}/docs/guide.md"
    printf '# Plan\n\nInternal: 99:100.\n' > "${fixture}/docs/drafts/plan.md"
    git -C "${fixture}" init -q
    git -C "${fixture}" add -A
}

teardownFixture() {
    if [[ -n "${fixture}" && -d "${fixture}" ]]; then
        command rm -rf -- "${fixture}"
    fi
}

writeConfig() {
    cat > "${fixture}/.docs-check.conf.sh" <<'EOF'
# shellcheck disable=SC2034
DOCS=("README.md" "docs")
EXCLUDE=("docs/drafts")
FORBIDDEN=("99:100|interne IDs")
EOF
}

testOhneArgumentKommtHilfe() {
    runScript
    assertEquals "0" "${rc}" "ohne Argument: Exit-Code 0"
    assertOutputContains "--run" "ohne Argument: Hilfe mit --run"
}

testBeispielConfigIstSourcebar() {
    runScript --example
    assertEquals "0" "${rc}" "--example: Exit-Code 0"
    # shellcheck disable=SC2034  # EXCLUDE wird von der Config gesetzt
    local DOCS=() EXCLUDE=() FORBIDDEN=()
    # shellcheck source=/dev/null
    . <(printf '%s\n' "${output}")
    assertEquals "README.md docs" "${DOCS[*]}" "--example: README und docs/ vorgeschlagen"
    assertEquals "0" "${#FORBIDDEN[@]}" "--example: keine verbotenen Begriffe vorbelegt"
    assertOutputLacks '"docker/README.md|' "--example: ohne docker/README.md kein Vorschlag"
}

testBeispielConfigSchlaegtDockerReadmeVor() {
    mkdir -p "${fixture}/docker"
    printf '# Container\n' > "${fixture}/docker/README.md"
    git -C "${fixture}" add docker/README.md
    runScript --example
    # shellcheck disable=SC2034  # von der Config gesetzt
    local REQUIRED=()
    # shellcheck source=/dev/null
    . <(printf '%s\n' "${output}")
    assertEquals "README.md|docker/README.md|Container-Anleitung, Quelle der Docker-Hub-Beschreibung" \
        "${REQUIRED[0]}|${REQUIRED[1]}" "--example: docker/README.md als Pflichtdatei vorgeschlagen"
    git -C "${fixture}" rm -q --cached docker/README.md
    command rm -rf -- "${fixture}/docker"
}

testRunOhneConfigScheitert() {
    command rm -f "${fixture}/.docs-check.conf.sh"
    runScript --run
    assertEquals "1" "${rc}" "--run ohne Config: Exit-Code 1"
    assertOutputContains "--example" "--run ohne Config: Hinweis auf --example"
}

testRunMitConfigFindetVerbotenenBegriff() {
    writeConfig
    runScript --run
    assertEquals "1" "${rc}" "verbotener Begriff: Exit-Code 1"
    assertOutputContains "docs/guide.md" "verbotener Begriff: Datei genannt"
    assertOutputContains "interne IDs" "verbotener Begriff: Grund genannt"
    assertOutputLacks "docs/drafts/plan.md" "ausgeschlossener Entwurf wird nicht geprueft"
}

testRunMitPfadPrueftNurDiesen() {
    writeConfig
    runScript --run README.md
    assertEquals "0" "${rc}" "nur README.md: ohne Probleme"
    assertOutputContains "1 Dokument geprüft" "nur README.md: genau ein Dokument"
}

testConfigOptionGewinnt() {
    writeConfig
    printf '# shellcheck disable=SC2034\nDOCS=("README.md")\n' > "${fixture}/other.conf.sh"
    runScript --config other.conf.sh --run
    assertEquals "0" "${rc}" "--config: andere Config ohne verbotene Begriffe"
}

# Regulaerer Ausdruck in der Config: Backslashes und "|" kommen unveraendert
# bei der Deno-Pruefung an.
testRunMitRegulaeremAusdruck() {
    cat > "${fixture}/regex.conf.sh" <<'EOF'
# shellcheck disable=SC2034
DOCS=("docs/guide.md")
FORBIDDEN=("/\b99:\d+\b|nobody/|interne IDs")
EOF
    runScript --config regex.conf.sh --run
    assertEquals "1" "${rc}" "Muster: Exit-Code 1"
    assertOutputContains 'Verbotener Text „99:100“' "Muster: Treffer genannt"
}

# REQUIRED allein genuegt als Config; mit Pfaden bei --run bleiben die
# Pflichtdateien aussen vor.
testRequiredAusConfig() {
    printf '# shellcheck disable=SC2034\nREQUIRED=("./README.md" "docs/missing.md|im README verlinkt")\n' > "${fixture}/req.conf.sh"
    runScript --config req.conf.sh --run
    assertEquals "1" "${rc}" "REQUIRED: fehlende Pflichtdatei ergibt Exit-Code 1"
    assertOutputContains "Grund: im README verlinkt" "REQUIRED: Grund genannt"
    assertOutputContains "2 Pflichtdateien geprüft" "REQUIRED: beide Eintraege geprueft"
    runScript --config req.conf.sh --run README.md
    assertOutputLacks "Pflichtdateien" "--run mit Pfad: keine Pflichtdateien"
}

# Muster in DOCS und EXCLUDE kommen unveraendert an (keine Shell-Expansion).
testMusterInDocsUndExclude() {
    printf '# shellcheck disable=SC2034\nDOCS=("**/*.md")\nEXCLUDE=("docs/dr*")\n' > "${fixture}/glob.conf.sh"
    runScript --config glob.conf.sh --run
    assertEquals "0" "${rc}" "Muster: ohne Probleme"
    assertOutputContains "docs/guide.md" "Muster: docs/guide.md geprueft"
    assertOutputLacks "docs/drafts/plan.md" "Muster-Ausschluss: Entwurf nicht geprueft"
}

# Die Grenze fuer Hinweisboxen kommt nur aus der Config.
testMaxAlertsAusConfig() {
    printf '# Demo\n\n> [!NOTE]\n> a\n\n> [!TIP]\n> b\n' > "${fixture}/boxes.md"
    printf '# shellcheck disable=SC2034\nDOCS=("boxes.md")\n' > "${fixture}/nolimit.conf.sh"
    runScript --config nolimit.conf.sh --run
    assertOutputLacks "Hinweisboxen" "ohne MAX_ALERTS: keine Grenze"
    printf '# shellcheck disable=SC2034\nDOCS=("boxes.md")\nMAX_ALERTS=1\n' > "${fixture}/limit.conf.sh"
    runScript --config limit.conf.sh --run
    assertOutputContains "höchstens 1 (MAX_ALERTS)" "MAX_ALERTS=1: Grenze genannt"
    assertEquals "0" "${rc}" "MAX_ALERTS: zu pruefen, kein Problem"
}

# LINKS_ONLY, KNOWN_VARIABLES und SCREENSHOTS kommen aus der Config an;
# Nur-Link-Dokumente und Screenshots nur beim Lauf ueber das ganze Projekt.
# shellcheck disable=SC2016  # Backticks sind Markdown, keine Ersetzung
testNeueConfigEintraege() {
    printf '# Regeln\n\nIntern 99:100, `LIB_VAR`. Siehe [alt](docs/old.md).\n' > "${fixture}/AGENTS.md"
    printf '# Lib\n\n`LIB_VAR` setzen.\n' > "${fixture}/lib.md"
    mkdir -p "${fixture}/shots"
    printf 'png' > "${fixture}/shots/a.png"
    touch -t 202001010000 "${fixture}/shots/a.png"
    cat > "${fixture}/new.conf.sh" <<'EOF'
# shellcheck disable=SC2034
DOCS=("lib.md")
LINKS_ONLY=("AGENTS.md")
FORBIDDEN=("99:100|interne IDs")
KNOWN_VARIABLES=("LIB_VAR|aus einer Bibliothek")
SCREENSHOTS=("shots")
MAX_SCREENSHOT_AGE_DAYS=60
EOF
    runScript --config new.conf.sh --run
    assertEquals "1" "${rc}" "LINKS_ONLY: toter Link ergibt Exit-Code 1"
    assertOutputContains "AGENTS.md (nur Links)" "LINKS_ONLY: Pruefart genannt"
    assertOutputLacks "interne IDs" "LINKS_ONLY: keine verbotenen Begriffe"
    assertOutputLacks "LIB_VAR" "KNOWN_VARIABLES: Variable gilt als bekannt"
    assertOutputContains "älter als 60 Tage" "SCREENSHOTS: altes Bild gemeldet"
    runScript --config new.conf.sh --run lib.md
    assertEquals "0" "${rc}" "--run mit Pfad: ohne Nur-Link-Dokumente und Screenshots"
    assertOutputLacks "Screenshots" "--run mit Pfad: keine Screenshots"
}

# CODE_VARIABLES und INTERNAL_VARIABLES kommen aus der Config an.
testCodeVariablenAusConfig() {
    mkdir -p "${fixture}/svc"
    printf 'const a = process.env.SVC_OPEN\nconst b = process.env.SVC_INNER\n' > "${fixture}/svc/app.js"
    git -C "${fixture}" add svc/app.js
    cat > "${fixture}/code.conf.sh" <<'EOF'
# shellcheck disable=SC2034
DOCS=("README.md")
CODE_VARIABLES=("svc")
INTERNAL_VARIABLES=("SVC_INNER|nur intern")
EOF
    runScript --config code.conf.sh --run
    assertEquals "1" "${rc}" "CODE_VARIABLES: undokumentierte Variable ergibt Exit-Code 1"
    assertOutputContains "SVC_OPEN" "CODE_VARIABLES: Variable genannt"
    assertOutputContains "intern: nur intern" "INTERNAL_VARIABLES: Grund genannt"
    git -C "${fixture}" rm -q --cached svc/app.js
    command rm -rf -- "${fixture}/svc"
}

testUngueltigerAusdruckBrichtAb() {
    printf '# shellcheck disable=SC2034\nDOCS=("README.md")\nFORBIDDEN=("/[/")\n' > "${fixture}/broken.conf.sh"
    runScript --config broken.conf.sh --run
    assertEquals "2" "${rc}" "ungueltiges Muster: Exit-Code 2"
    assertOutputContains "ungültiger regulärer Ausdruck" "ungueltiges Muster: Meldung"
}

runAll() {
    if ! command -v deno >/dev/null 2>&1; then
        echo -e "${RED}Fehler:${NC} Deno nicht gefunden, Tests uebersprungen." >&2
        return 1
    fi
    setupFixture

    echo
    echo -e "${LIGHT_BLUE}docs-check.sh${NC}"
    echo

    testOhneArgumentKommtHilfe
    testBeispielConfigIstSourcebar
    testBeispielConfigSchlaegtDockerReadmeVor
    testRunOhneConfigScheitert
    testRunMitConfigFindetVerbotenenBegriff
    testRunMitPfadPrueftNurDiesen
    testConfigOptionGewinnt
    testRunMitRegulaeremAusdruck
    testUngueltigerAusdruckBrichtAb
    testMaxAlertsAusConfig
    testRequiredAusConfig
    testMusterInDocsUndExclude
    testNeueConfigEintraege
    testCodeVariablenAusConfig

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
