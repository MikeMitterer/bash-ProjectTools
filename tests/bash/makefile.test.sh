#!/usr/bin/env bash
#------------------------------------------------------------------------------
# makefile.test.sh — Tests fuer das Makefile nach makefile-conventions
#
# Integrationstests: Eine Kopie des Arbeitsstands (alle Dateien, die git nicht
# ignoriert, ohne .libs/ und .venv) liegt in einem Temp-Ordner ohne BashLib
# daneben, wie ein frischer Klon. make laeuft dort mit leerer Umgebung (env -i).
# Ein echtes `make setup` (venv + pip) laeuft hier nicht; die Stempeldatei
# wird fuer require-setup von Hand gelegt.
#
# Verwendung:
#   ./tests/bash/makefile.test.sh --run
#   ./tests/bash/makefile.test.sh --help
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

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly PROJECT_ROOT

tests_run=0
tests_failed=0
fixture=""
output=""
MAKE_ENV=()
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

# Prueft, ob ein Exit-Code ungleich 0 ist.
#
# Params:
#   $1 - Beschreibung
assertFailed() {
    if [[ "${rc}" -ne 0 ]]; then report 0 "$1"; else report 1 "$1 ${YELLOW}(Exit-Code 0)${NC}"; fi
}

# Startet make in der Kopie mit leerer Umgebung; Ausgabe ohne Farbcodes in
# ${output}, Exit-Code in ${rc}. Ohne MakeLib setzt das Makefile Ersatzfarben.
# MAKE_PATH ersetzt den PATH, MAKE_ENV (Array) setzt weitere Variablen.
runMake() {
    rc=0
    output="$(cd "${fixture}/project" && env -i PATH="${MAKE_PATH:-${PATH}}" HOME="${HOME}" \
        "${MAKE_ENV[@]+"${MAKE_ENV[@]}"}" make --no-print-directory "$@" 2>&1)" || rc=$?
    output="$(printf '%s' "${output}" | sed $'s/\x1b\\[[0-9;]*m//g')"
}

# Kopiert den Arbeitsstand ohne von git ignorierte Dateien in einen Temp-Ordner.
setupFixture() {
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/makefile-test.XXXXXX")"
    fixture="$(cd "${fixture}" && pwd -P)"   # wie WORKSPACE im Makefile (realpath)
    mkdir -p "${fixture}/project"
    (cd "${PROJECT_ROOT}" && git ls-files -z --cached --others --exclude-standard |
        while IFS= read -r -d '' path; do [[ -e "${path}" || -L "${path}" ]] && printf '%s\0' "${path}"; done |
        tar --null -T - -cf - | tar -xf - -C "${fixture}/project")
}

teardownFixture() {
    if [[ -n "${fixture}" && -d "${fixture}" ]]; then
        command rm -rf -- "${fixture}"
    fi
}

testHilfeOhneBibliotheken() {
    runMake help
    assertEquals "0" "${rc}" "help: laeuft ohne .libs/ und BASH_LIBS"
    assertOutputContains "Versionierung" "help: Gruppe Versionierung"
    for target in check version tags tag-major tag-minor tag-patch; do
        if grep -qE "^[[:space:]]+${target}[[:space:]]" <<< "${output}"; then
            report 0 "help: ${target} gelistet"
        else
            report 1 "help: ${target} gelistet ${YELLOW}(keine Zeile fuer ${target})${NC}"
        fi
    done
    assertOutputContains "[Maintainer]" "help: Maintainer-Targets markiert"
}

# Die Repo-Adresse kommt aus git remote origin, nie aus dem Makefile: ohne
# Remote ein Hinweis, mit Remote dessen Owner (auch nach einem Umzug).
testHintsLesenRepoAusRemote() {
    runMake hints
    assertEquals "0" "${rc}" "hints: Exit 0 ohne Remote"
    assertOutputContains "kein Remote origin" "hints: ohne Remote ein Hinweis"
    if [[ "${output}" == *"MikeMitterer"* ]]; then
        report 1 "hints: keine fest eingetragene Adresse ${YELLOW}(MikeMitterer gefunden)${NC}"
    else
        report 0 "hints: keine fest eingetragene Adresse"
    fi

    git -C "${fixture}/project" init -q
    git -C "${fixture}/project" remote add origin git@github.com:MangoLila/bash-ProjectTools.git
    runMake hints
    assertOutputContains "https://github.com/MangoLila/bash-ProjectTools" "hints: GitHub-Link aus dem Remote"
    assertOutputContains "pipx install 'git+https://github.com/MangoLila/bash-ProjectTools.git@" \
        "hints: Installation per pipx mit URL aus dem Remote"
    command rm -rf -- "${fixture}/project/.git"
}

# Zeichen einer Zeichenkette, unabhaengig von der Locale (UTF-8-Folgebytes
# zaehlen nicht mit).
charCount() {
    printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '
}

# Jede zweispaltige hints-Zeile beginnt die zweite Spalte an derselben
# Bildschirmspalte, auch mit Umlauten in der Beschriftung.
testHintsBuendig() {
    runMake hints
    local line prefix columns=""
    while IFS= read -r line; do
        [[ "${line}" =~ ^(\ +[^\ ]+(\ [^\ ]+)*\ {2,})[^\ ] ]] || continue
        prefix="${BASH_REMATCH[1]}"
        columns+="$(charCount "${prefix}") "
    done <<< "${output}"
    local unique
    unique="$(tr ' ' '\n' <<< "${columns}" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
    assertEquals "1" "${unique}" "hints: zweite Spalte buendig (Spalten: ${columns% })"
}

testMaintainerTargetsBrechenAb() {
    local target
    for target in status tag-patch; do
        runMake "${target}"
        assertFailed "${target}: bricht ohne BashLib ab"
        assertOutputContains "Nur für Maintainer" "${target}: nennt den Grund"
    done
}

testRequireSetup() {
    runMake require-setup
    assertFailed "require-setup: ohne Einrichtung Abbruch"
    assertOutputContains "make setup" "require-setup: nennt make setup"
    runMake test-python
    assertFailed "test-python: haengt an require-setup"
    assertOutputContains "make setup" "test-python: nennt make setup"
    runMake check
    assertFailed "check: haengt an require-setup"
    assertOutputContains "make setup" "check: nennt make setup"
    assertOutputContains "Nicht eingerichtet" "check: bricht vor den Tests ab"

    mkdir -p "${fixture}/project/.venv"
    touch "${fixture}/project/.venv/.installed"
    runMake require-setup
    assertEquals "0" "${rc}" "require-setup: Stempel aktuell"

    touch -t 203001010000 "${fixture}/project/requirements-dev.txt"
    runMake require-setup
    assertFailed "require-setup: Stempel aelter als requirements-dev.txt"
    assertOutputContains "veraltet" "require-setup: nennt veraltet"
}

# Ohne BashLib brechen die Bash-Tests einmal mit klarer Meldung ab statt in
# jeder Suite mit einem fehlenden tools.lib.sh.
testBashTestsOhneBashLib() {
    runMake test-bash
    assertFailed "test-bash: ohne BashLib Abbruch"
    assertOutputContains "BashLib fehlt" "test-bash: nennt BashLib"
    assertOutputContains "bash-lib.git" "test-bash: nennt den Weg"
    # Die Adresse kommt aus pyproject.toml, nicht fest aus dem Skript.
    sed -i.bak 's|github.com/MikeMitterer/bash-lib.git|github.com/MangoLila/bash-lib.git|' \
        "${fixture}/project/pyproject.toml"
    runMake test-bash
    assertOutputContains "github.com/MangoLila/bash-lib.git" "test-bash: Adresse aus pyproject.toml"
    command mv -f "${fixture}/project/pyproject.toml.bak" "${fixture}/project/pyproject.toml"
    if [[ "${output}" == *"fehlgeschlagen"* ]]; then
        report 1 "test-bash: keine Suite gestartet ${YELLOW}(Suiten liefen)${NC}"
    else
        report 0 "test-bash: keine Suite gestartet"
    fi
}

# Tag-Namen und Remote-URLs kommen von aussen und duerfen $, ( und )
# enthalten. hints darf sie nie als Befehl ausfuehren; Werte mit anderen als
# den erlaubten Zeichen gelten als nicht vorhanden.
testHintsFuehrenKeineBefehleAusGit() {
    local project="${fixture}/project"
    git -C "${project}" init -q
    git -C "${project}" -c user.name=T -c user.email=t@example.invalid \
        commit -q --allow-empty -m test
    # shellcheck disable=SC2016  # Die Expansion soll gerade nicht hier passieren
    git -C "${project}" tag 'v1$(touch${IFS}PWNED_TAG)'
    # shellcheck disable=SC2016
    git -C "${project}" remote add origin 'git@github.com:A/b$(touch${IFS}PWNED_REMOTE).git'
    runMake hints
    assertEquals "0" "${rc}" "hints: Exit 0 mit boesartigem Tag und Remote"
    assertEquals "no" "$([[ -e "${project}/PWNED_TAG" ]] && echo yes || echo no)" \
        "hints: Tag-Name wird nicht ausgefuehrt"
    assertEquals "no" "$([[ -e "${project}/PWNED_REMOTE" ]] && echo yes || echo no)" \
        "hints: Remote-URL wird nicht ausgefuehrt"
    assertOutputContains "kein Remote origin" "hints: ungueltiger Remote gilt als fehlend"
    command rm -rf -- "${project}/.git" "${project}/PWNED_TAG" "${project}/PWNED_REMOTE"
}

# pyproject.toml gehoert zu den Abhaengigkeiten der Einrichtung: BashLib und
# deno kommen ueber `-e .` aus seinen dependencies.
testEinrichtungHaengtAnPyproject() {
    assertEquals "yes" "$(grep -qxE -- '-e \.' "${fixture}/project/requirements-dev.txt" && echo yes)" \
        "requirements-dev.txt installiert das Projekt selbst (-e .)"
    mkdir -p "${fixture}/project/.venv"
    touch -t 202001010000 "${fixture}/project/.venv/.installed"
    touch -t 202001010000 "${fixture}/project/requirements-dev.txt" \
        "${fixture}/project/src/python/dockerhub-readme.requirements.txt"
    touch "${fixture}/project/pyproject.toml"
    runMake require-setup
    assertFailed "require-setup: pyproject.toml neuer als der Stempel"
    command rm -rf -- "${fixture}/project/.venv"
}

# BASH_LIBS: .libs/ und der Nachbar wie bisher, sonst bashlib-path aus der venv.
testBashLibsAusVenv() {
    local lib="${fixture}/venvlib"
    mkdir -p "${lib}" "${fixture}/project/.venv/bin"
    : > "${lib}/tools.lib.sh"
    printf '#!/bin/sh\necho "%s"\n' "${lib}" > "${fixture}/project/.venv/bin/bashlib-path"
    chmod +x "${fixture}/project/.venv/bin/bashlib-path"
    runMake info
    assertOutputContains "BASH_LIBS        = ${lib}" "BASH_LIBS: aus bashlib-path der venv"
    mkdir -p "${fixture}/project/.libs/BashLib/src"
    runMake info
    assertOutputContains "BASH_LIBS        = ${fixture}/project/.libs/BashLib/src" \
        "BASH_LIBS: .libs/ hat Vorrang vor der venv"
    command rm -rf -- "${fixture}/project/.venv" "${fixture}/project/.libs" "${lib}"
}

# Kommt BashLib nur aus der venv (kein Repo-Klon), legt setup keine
# .libs-Links an und scheitert nicht an fehlender MakeLib.
testSetupMitBashLibAusVenv() {
    local project="${fixture}/project" lib="${fixture}/venvlib"
    git -C "${project}" init -q
    mkdir -p "${lib}" "${project}/.venv/bin"
    : > "${lib}/tools.lib.sh"
    printf '#!/bin/sh\necho "%s"\n' "${lib}" > "${project}/.venv/bin/bashlib-path"
    chmod +x "${project}/.venv/bin/bashlib-path"
    touch "${project}/.venv/.installed"
    runMake setup
    assertEquals "0" "${rc}" "setup: Exit 0 mit BashLib aus der venv"
    assertOutputContains "BashLib aus der venv" "setup: nennt die Quelle, keine .libs-Links"
    command rm -rf -- "${project}/.venv" "${project}/.git" "${lib}"
}

# deno aus der venv (.venv/tools), auch wenn der PATH keins kennt.
testDenoAusVenv() {
    mkdir -p "${fixture}/project/.venv/tools"
    printf '#!/bin/sh\necho "VENV-DENO $*"\n' > "${fixture}/project/.venv/tools/deno"
    chmod +x "${fixture}/project/.venv/tools/deno"
    MAKE_PATH="/usr/bin:/bin" runMake test-deno
    assertOutputContains "VENV-DENO test" "test-deno: nimmt deno aus .venv/tools"
    command rm -rf -- "${fixture}/project/.venv"
}

# Ohne Paketindex bricht setup klar ab und legt keinen Stempel an.
testSetupOhneIndexKlar() {
    MAKE_ENV=(PIP_NO_INDEX=1 PIP_FIND_LINKS=)
    runMake setup
    MAKE_ENV=()
    assertFailed "setup: ohne Paketindex Abbruch"
    assertOutputContains "Pakete nicht installiert" "setup: klare Meldung"
    assertEquals "no" "$([[ -e "${fixture}/project/.venv/.installed" ]] && echo yes || echo no)" \
        "setup: kein Stempel nach Abbruch"
    command rm -rf -- "${fixture}/project/.venv"
}

testCleanEntferntBuildReste() {
    mkdir -p "${fixture}/project/build/lib" "${fixture}/project/src/python/demo.egg-info"
    runMake clean
    assertEquals "0" "${rc}" "clean: Exit 0"
    assertEquals "no" "$([[ -e "${fixture}/project/build" ]] && echo yes || echo no)" "clean: build/ entfernt"
    assertEquals "no" "$([[ -e "${fixture}/project/src/python/demo.egg-info" ]] && echo yes || echo no)" \
        "clean: *.egg-info entfernt"
    runMake clean
    assertEquals "0" "${rc}" "clean: wiederholbar"
}

runAll() {
    setupFixture

    echo
    echo -e "${LIGHT_BLUE}Makefile${NC}"
    echo

    testHilfeOhneBibliotheken
    testHintsBuendig
    testHintsLesenRepoAusRemote
    testHintsFuehrenKeineBefehleAusGit
    testMaintainerTargetsBrechenAb
    testRequireSetup
    testBashTestsOhneBashLib
    testEinrichtungHaengtAnPyproject
    testBashLibsAusVenv
    testSetupMitBashLibAusVenv
    testDenoAusVenv
    testSetupOhneIndexKlar
    testCleanEntferntBuildReste

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
