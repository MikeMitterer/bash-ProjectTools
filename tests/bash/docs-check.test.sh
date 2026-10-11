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
    assertOutputContains '(„99:100“)' "Muster: Treffer genannt"
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
    testRunOhneConfigScheitert
    testRunMitConfigFindetVerbotenenBegriff
    testRunMitPfadPrueftNurDiesen
    testConfigOptionGewinnt
    testRunMitRegulaeremAusdruck
    testUngueltigerAusdruckBrichtAb

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
