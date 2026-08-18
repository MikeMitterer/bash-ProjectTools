#!/usr/bin/env bash
#------------------------------------------------------------------------------
# pkg-link.test.sh — Tests fuer src/bash/pkg-link.sh
#
# Integrationstests: Das Script laeuft als Prozess gegen eine echte
# Verzeichnisstruktur im Temp-Ordner — kein Mock, keine gestubbten Dateisystem-
# Aufrufe. Nur so faellt der Fehler auf, um den es hier geht.
#
# Der wichtigste Fall ist `verschiebt_niemals_ins_fremde_repo`: Beim Umschalten
# von Hand ist ein `mv` einem noch bestehenden Symlink gefolgt und hat das
# Backup **im fremden Repo** abgelegt. Nach jedem Test wird deshalb geprueft,
# dass das lokale Repo unveraendert ist.
#
# Verwendung:
#   ./tests/bash/pkg-link.test.sh --run
#   ./tests/bash/pkg-link.test.sh --help
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

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../../src/bash" && pwd)/pkg-link.sh"
readonly SCRIPT_UNDER_TEST

readonly PKG_NAME="@scope/demo"
readonly REGISTRY_VERSION="1.0.0"
readonly LOCAL_VERSION="2.0.0"

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

# Prueft eine Bedingung und meldet sie.
#
# Die Bedingung kommt als Kommando herein (z.B. `test -L /pfad`) statt als
# `[[ … ]] && … || …` — jene Form ist kein if-then-else: Schlaegt der
# Erfolgszweig fehl, laeuft der Fehlerzweig zusaetzlich.
#
# Params:
#   $1 - Beschreibung
#   $@ - Kommando, das die Bedingung prueft
assertThat() {
    local description="$1"
    shift
    if "$@"; then report 0 "${description}"; else report 1 "${description}"; fi
}

# Wie assertThat, nur umgekehrt: Der Test gilt als bestanden, wenn das Kommando
# fehlschlaegt.
#
# Params:
#   $1 - Beschreibung
#   $@ - Kommando, das fehlschlagen muss
assertNot() {
    local description="$1"
    shift
    if "$@"; then report 1 "${description}"; else report 0 "${description}"; fi
}

# Baut eine frische App samt lokalem Paket-Repo im Temp-Ordner auf.
#
# Struktur:
#   <fixture>/app/node_modules/@scope/demo   Registry-Fassung (echtes Verzeichnis)
#   <fixture>/local-repo                     lokales Paket-Repo
setupFixture() {
    fixture="$(mktemp -d)"

    mkdir -p "${fixture}/app/node_modules/${PKG_NAME}"
    printf '{"name":"%s","version":"%s"}\n' "${PKG_NAME}" "${REGISTRY_VERSION}" \
        > "${fixture}/app/node_modules/${PKG_NAME}/package.json"
    printf '{"name":"app","dependencies":{"%s":"^1.0.0"}}\n' "${PKG_NAME}" \
        > "${fixture}/app/package.json"

    mkdir -p "${fixture}/local-repo/src"
    printf '{"name":"%s","version":"%s"}\n' "${PKG_NAME}" "${LOCAL_VERSION}" \
        > "${fixture}/local-repo/package.json"

    cat > "${fixture}/app/.pkg-link.conf.sh" <<EOF
#!/usr/bin/env bash
# shellcheck disable=SC2034
PACKAGE_ROOT="."
PACKAGES=(
    "${PKG_NAME}=${fixture}/local-repo"
)
EOF
}

teardownFixture() {
    [[ -n "${fixture}" && -d "${fixture}" ]] && command rm -rf "${fixture}"
    fixture=""
}

# Ruft das Script im App-Verzeichnis der Fixture auf.
#
# Params:
#   $@ - Argumente fuer pkg-link.sh
#
# Returns:
#   Exit-Code des Scripts; Ausgabe wird verworfen
runScript() {
    ( cd "${fixture}/app" && "${SCRIPT_UNDER_TEST}" "$@" ) >/dev/null 2>&1
}

# Zaehlt die Eintraege im lokalen Repo — die Wache gegen den mv-Unfall.
countLocalRepoEntries() {
    find "${fixture}/local-repo" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' '
}

# --- Tests -------------------------------------------------------------------

testStatusZeigtRegistry() {
    setupFixture
    local out
    out="$( cd "${fixture}/app" && "${SCRIPT_UNDER_TEST}" --status 2>&1 )"
    if grep -q "Registry" <<<"${out}" && grep -q "${REGISTRY_VERSION}" <<<"${out}"; then
        report 0 "status: meldet die Registry-Fassung samt Version"
    else
        report 1 "status: meldet die Registry-Fassung samt Version"
    fi
    teardownFixture
}

testLinkSetztSymlinkUndSichert() {
    setupFixture
    runScript --link "${PKG_NAME}"

    local path="${fixture}/app/node_modules/${PKG_NAME}"
    assertThat "link: legt einen Symlink an" test -L "${path}"
    assertThat "link: sichert die Registry-Fassung daneben" test -d "${path}.pkg-link-backup"

    local version
    version="$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "${path}/package.json")"
    assertEquals "${LOCAL_VERSION}" "${version}" "link: die App sieht das lokale Repo"
    teardownFixture
}

testUnlinkStelltRegistryWiederHer() {
    setupFixture
    runScript --link "${PKG_NAME}"
    runScript --unlink "${PKG_NAME}"

    local path="${fixture}/app/node_modules/${PKG_NAME}"
    assertNot "unlink: entfernt den Symlink" test -L "${path}"
    assertNot "unlink: raeumt die Sicherung weg" test -e "${path}.pkg-link-backup"

    local version
    version="$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "${path}/package.json")"
    assertEquals "${REGISTRY_VERSION}" "${version}" "unlink: die Registry-Fassung ist zurueck"
    teardownFixture
}

# Der Kern: Beim Umschalten von Hand ist ein `mv` dem noch bestehenden Symlink
# gefolgt und hat das Backup im fremden Repo abgelegt. Nach einem vollen Zyklus
# muss das lokale Repo exakt so aussehen wie vorher.
testVerschiebtNiemalsInsFremdeRepo() {
    setupFixture
    local before after
    before="$(countLocalRepoEntries)"

    runScript --link "${PKG_NAME}"
    runScript --unlink "${PKG_NAME}"
    runScript --link "${PKG_NAME}"
    runScript --unlink "${PKG_NAME}"

    after="$(countLocalRepoEntries)"
    assertEquals "${before}" "${after}" "Unfall-Wache: nichts landet im lokalen Repo"

    # Nicht auf einen erwarteten Pfad pruefen, sondern auf **irgendeine** Spur:
    # Wohin ein fehlgeleitetes mv die Sicherung legt, haengt am Paketnamen —
    # eine zu enge Zusicherung bliebe beim echten Fehler gruen (nachgestellt).
    local strays
    strays="$(find "${fixture}/local-repo" -name '*.pkg-link-backup' | wc -l | tr -d ' ')"
    assertEquals "0" "${strays}" "Unfall-Wache: keine Sicherung im lokalen Repo"
    teardownFixture
}

testLinkIstIdempotent() {
    setupFixture
    runScript --link "${PKG_NAME}"
    runScript --link "${PKG_NAME}"

    local path="${fixture}/app/node_modules/${PKG_NAME}"
    assertThat "link: zweiter Aufruf aendert nichts" test -L "${path}"
    # Waere der zweite Aufruf durchgelaufen, laege der Symlink jetzt als Backup daneben.
    local backup_count
    backup_count="$(find "${fixture}/app/node_modules/@scope" -maxdepth 1 -name '*.pkg-link-backup' | wc -l | tr -d ' ')"
    assertEquals "1" "${backup_count}" "link: legt keine zweite Sicherung an"
    teardownFixture
}

testAltesBackupWirdNichtUeberschrieben() {
    setupFixture
    # Eine Sicherung aus einem frueheren Lauf liegt bereits da
    mkdir -p "${fixture}/app/node_modules/${PKG_NAME}.pkg-link-backup"
    printf 'alt\n' > "${fixture}/app/node_modules/${PKG_NAME}.pkg-link-backup/marker.txt"

    runScript --link "${PKG_NAME}"
    local rc=$?

    assertThat "link: bricht ab, wenn eine alte Sicherung im Weg liegt" test "${rc}" -ne 0
    assertThat "link: die alte Sicherung bleibt unangetastet" \
        test -f "${fixture}/app/node_modules/${PKG_NAME}.pkg-link-backup/marker.txt"
    teardownFixture
}

testUnlinkOhneLinkIstFolgenlos() {
    setupFixture
    runScript --unlink "${PKG_NAME}"

    local path="${fixture}/app/node_modules/${PKG_NAME}"
    assertThat "unlink: ohne Symlink bleibt ein echtes Verzeichnis" test -d "${path}"
    assertNot  "unlink: ohne Symlink entsteht kein Symlink" test -L "${path}"
    teardownFixture
}

testOhneArgumentKommtHilfe() {
    setupFixture
    local out
    out="$( cd "${fixture}/app" && "${SCRIPT_UNDER_TEST}" 2>&1 )"
    assertThat "ohne Argument: zeigt die Hilfe" grep -q "Usage:" <<<"${out}"
    teardownFixture
}

testBeispielConfigIstSourcebar() {
    setupFixture
    local generated="${fixture}/generated.conf.sh"
    ( cd "${fixture}/app" && "${SCRIPT_UNDER_TEST}" --example ) > "${generated}" 2>/dev/null

    # shellcheck disable=SC2016  # der Rumpf wird erst in der Subshell ausgewertet
    assertThat "--example: erzeugt eine sourcebare Config" \
        bash -c 'set -euo pipefail; . "$1"; [[ -n "${PACKAGE_ROOT}" ]]' _ "${generated}"
    teardownFixture
}

runAll() {
    echo
    echo -e "${LIGHT_BLUE}pkg-link.sh${NC}"
    echo

    testStatusZeigtRegistry
    testLinkSetztSymlinkUndSichert
    testUnlinkStelltRegistryWiederHer
    testVerschiebtNiemalsInsFremdeRepo
    testLinkIstIdempotent
    testAltesBackupWirdNichtUeberschrieben
    testUnlinkOhneLinkIstFolgenlos
    testOhneArgumentKommtHilfe
    testBeispielConfigIstSourcebar

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
