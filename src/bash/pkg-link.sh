#!/usr/bin/env bash
#------------------------------------------------------------------------------
# pkg-link.sh — Ein npm-Paket zwischen lokalem Repo und Registry umschalten
#
# Waehrend an einem geteilten Paket (z.B. @mmit/ux-foundation) und der App
# gleichzeitig gearbeitet wird, muss die App das lokale Repo sehen — sonst
# laesst sich nichts pruefen, bevor veroeffentlicht ist. Danach muss sie wieder
# auf die Registry-Fassung zurueck, sonst laeuft man auf einem Stand, den
# niemand sonst hat.
#
# Genau dieses Hin und Her von Hand ist schiefgegangen: Ein `mv` auf einen noch
# bestehenden Symlink schiebt das Backup **in das Ziel-Repo hinein**, und
# interaktive Aliase (`rm -i`) lassen den Rueckbau still scheitern. Beides
# faengt dieses Script ab.
#
# Die Paketliste kommt aus einer Config im aktuellen Verzeichnis — dadurch
# funktioniert dasselbe Script fuer jede App und jedes Paket.
#
# Verwendung:
#   pkg-link.sh [--status] [--link <paket>|--all] [--unlink <paket>|--all]
#   pkg-link.sh --example > .pkg-link.conf.sh   # Starter-Config anlegen
#   make pkg-status
#
# Optionen:
#   -s | --status   Quelle jedes konfigurierten Pakets anzeigen (lokal/Registry)
#   -l | --link     Paket auf das lokale Repo umstellen (Symlink)
#   -u | --unlink   Paket zurueck auf die Registry-Fassung
#   -a | --all      Mit --link/--unlink: alle konfigurierten Pakete
#   -c | --config   Alternative Config-Datei (Default: ./.pkg-link.conf.sh)
#   -e | --example  Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)
#   -h | --help     Diese Hilfe anzeigen
#------------------------------------------------------------------------------

set -euo pipefail

# Logische Pfadaufloesung beibehalten (kein pwd -P) — der Fallback muss auch
# ueber einen .libs/ProjectTools-Symlink funktionieren (.libs/BashLib daneben)
BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../../../BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/colors.lib.sh";  fi
if [[ "${__TOOLS_LIB__:=""}"   == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";   fi
if [[ "${__APPS_LIB__:=""}"    == "" ]]; then . "${BASH_LIBS}/apps.lib.sh";    fi

APPNAME="$(basename "$0")"
readonly APPNAME
APPNAME_WITHOUT_EXTENSION="${APPNAME%%.*}"
readonly APPNAME_WITHOUT_EXTENSION

CONFIG_BASE="./.${APPNAME_WITHOUT_EXTENSION}.conf"
if [[ -f "${CONFIG_BASE}" ]]; then
    CONFIG_NAME="${CONFIG_BASE}"
else
    CONFIG_NAME="${CONFIG_BASE}.sh"
fi
readonly CONFIG_NAME
CONFIG_DISPLAY="${CONFIG_NAME#./}"
readonly CONFIG_DISPLAY

# Suffix des Backups neben dem Paket. Es traegt den Scriptnamen, damit beim
# Aufraeumen erkennbar bleibt, wer es angelegt hat.
readonly BACKUP_SUFFIX=".pkg-link-backup"
readonly COL_WIDTH_NAME=32

# Defaults — von der gesourcten Config ueberschrieben
PACKAGE_ROOT="."
PACKAGES=()

# Zeigt die Verwendungshinweise an.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    echo -e "\t${BLUE}# Anzeigen -------------------------------------------------------------${NC}"
    usageLine "-s | --status " "Quelle jedes Pakets anzeigen — ${YELLOW}lokal${NC} oder ${YELLOW}Registry${NC}"
    echo
    echo -e "\t${BLUE}# Umschalten -----------------------------------------------------------${NC}"
    usageLine "-l | --link   " "Paket auf das lokale Repo umstellen (Symlink)"
    usageLine "-u | --unlink " "Paket zurueck auf die Registry-Fassung"
    usageLine "-a | --all    " "Mit --link/--unlink: alle konfigurierten Pakete"
    echo
    echo -e "\t${BLUE}# Config / Help --------------------------------------------------------${NC}"
    usageLine "-c | --config " "Alternative Config-Datei (Default: ${CONFIG_DISPLAY})"
    usageLine "-e | --example" "Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)"
    usageLine "-h | --help   " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Status:           ${GREEN}${APPNAME} --status${NC}"
    echo -e "    Lokal verlinken:  ${GREEN}${APPNAME} --link @mmit/ux-foundation${NC}"
    echo -e "    Alle zurueck:     ${GREEN}${APPNAME} --unlink --all${NC}"
    echo -e "    Config anlegen:   ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
    echo
}

# Gibt eine gueltige, sourcebare Beispiel-Config auf stdout aus.
#
# Sucht die package.json (CWD oder eine Ebene tief) und schlaegt fuer jede
# Abhaengigkeit ein lokales Repo vor, das unter DEV_LOCAL gleichen Namens liegt.
printConfigExample() {
    local package_root
    package_root="$(detectPackageRoot)"

    local entries=()
    if [[ -n "${package_root}" ]]; then
        mapfile -t entries < <(detectLocalPackages "${package_root}")
    fi

    cat <<EOF
#!/usr/bin/env bash
# Config fuer pkg-link.sh (ProjectTools) — wird gesourced, kein Custom-Parser.
# .sh-Endung fuers IDE-Highlighting. Format-Doku: ProjectTools/README.md
# Anlegen/aktualisieren:  ${APPNAME} --example > ${CONFIG_DISPLAY}
# shellcheck disable=SC2034  # von pkg-link.sh gesourct

# Verzeichnis mit package.json und node_modules, relativ zum CWD.
# Monorepo/Sub-App: z.B. "dashboard". Einfaches Repo: "."
PACKAGE_ROOT="${package_root:-.}"

# Umschaltbare Pakete: "<paketname>=<pfad zum lokalen Repo>"
# Der Pfad darf Variablen enthalten — die Config wird gesourced.
PACKAGES=(
EOF

    if [[ ${#entries[@]} -gt 0 ]]; then
        printf '    "%s"\n' "${entries[@]}"
    else
        # shellcheck disable=SC2016  # ${DEV_LOCAL} soll woertlich in der Config landen
        printf '    # "@mmit/ux-foundation=${DEV_LOCAL}/DevWeb/Production/ux-foundation"\n'
    fi

    echo ')'
}

# Sucht das Verzeichnis mit der package.json — CWD oder eine Ebene tief.
#
# Returns:
#   Pfad relativ zum CWD auf stdout, leer wenn nichts gefunden.
detectPackageRoot() {
    if [[ -f package.json ]]; then
        echo "."
        return 0
    fi

    local candidate
    while IFS= read -r candidate; do
        candidate="${candidate#./}"
        echo "${candidate%/package.json}"
        return 0
    done < <(find . -maxdepth 2 -name package.json \
                  -not -path '*/node_modules/*' 2>/dev/null | sort)
}

# Schlaegt Abhaengigkeiten vor, zu denen ein gleichnamiges Repo unter DEV_LOCAL liegt.
#
# Params:
#   $1 - Verzeichnis mit der package.json
#
# Returns:
#   Je Fund eine Zeile "<paketname>=<pfad>" auf stdout.
detectLocalPackages() {
    local package_root="$1"
    local dev_local="${DEV_LOCAL:-}"

    [[ -n "${dev_local}" ]] || return 0
    checkIfToolIsAvailable "${JQ}" >/dev/null 2>&1 || return 0

    local name repo_dir
    while IFS= read -r name; do
        repo_dir="${dev_local}/DevWeb/Production/${name##*/}"
        [[ -d "${repo_dir}" ]] || continue
        # Der Pfad bleibt als Variable stehen — die Config ist damit auf jedem
        # Rechner gueltig, nicht nur auf dem, der sie erzeugt hat.
        echo "${name}=\${DEV_LOCAL}/DevWeb/Production/${name##*/}"
    done < <("${JQ}" -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' \
                     "${package_root}/package.json" 2>/dev/null)
}

# Laedt die Config und prueft die Pflichtwerte.
#
# Params:
#   $1 - Pfad zur Config-Datei
#
# Returns:
#   0 bei gueltiger Config, 1 wenn Datei fehlt oder PACKAGES leer ist
loadConfig() {
    local config_file="$1"

    [[ -f "${config_file}" ]] || return 1

    # shellcheck source=/dev/null
    . "${config_file}"

    [[ ${#PACKAGES[@]} -gt 0 ]]
}

# Pfad, unter dem das Paket in node_modules liegt.
#
# Params:
#   $1 - Paketname (z.B. @mmit/ux-foundation)
packagePath() {
    echo "${PACKAGE_ROOT}/node_modules/$1"
}

# Zustand eines Pakets.
#
# Params:
#   $1 - Paketname
#
# Returns:
#   "link", "npm" oder "missing" auf stdout
packageState() {
    local path
    path="$(packagePath "$1")"

    if [[ -L "${path}" ]]; then
        echo "link"
    elif [[ -d "${path}" ]]; then
        echo "npm"
    else
        echo "missing"
    fi
}

# Version aus der package.json eines installierten Pakets.
#
# Params:
#   $1 - Paketname
#
# Returns:
#   Version auf stdout, "?" wenn nicht lesbar
packageVersion() {
    local manifest
    manifest="$(packagePath "$1")/package.json"

    [[ -f "${manifest}" ]] || { echo "?"; return 0; }
    "${JQ}" -r '.version // "?"' "${manifest}" 2>/dev/null || echo "?"
}

# Entfernt einen Symlink — und ausschliesslich einen.
#
# `command` umgeht ein interaktives `rm -i`-Alias, das den Rueckbau sonst still
# scheitern laesst. Ein Verzeichnis wird hier nie geloescht: Trifft der Aufruf
# kein Symlink, bricht er ab, statt `-rf` nachzulegen.
#
# Params:
#   $1 - Pfad
#
# Returns:
#   0 entfernt · 2 kein Symlink · 3 liess sich nicht entfernen
removeSymlink() {
    local path="$1"

    if [[ ! -L "${path}" ]]; then
        return 2
    fi

    command rm -f "${path}"

    if [[ -L "${path}" || -e "${path}" ]]; then
        return 3
    fi
    return 0
}

# Verschiebt einen Pfad — nur wenn das Ziel nachweislich gefahrlos ist.
#
# **Der Unfall, den das ausschliesst:** Ist das Ziel ein Symlink auf ein
# Verzeichnis, folgt `mv` ihm und legt die Quelle *darin* ab. Das Backup landet
# dann im fremden Repo statt neben dem Paket. Genau so ist es passiert, und
# genau deshalb prueft diese Funktion drei Dinge, bevor sie irgendetwas anfasst:
# Quelle vorhanden, Ziel in *keiner* Form belegt (auch nicht als toter Symlink),
# und das Elternverzeichnis des Ziels ein echtes Verzeichnis.
#
# Params:
#   $1 - Quelle
#   $2 - Ziel
#
# Returns:
#   0 verschoben · 2 Quelle fehlt · 3 Ziel belegt · 4 Elternverzeichnis untauglich
movePathSafely() {
    local source="$1" dest="$2"
    local dest_parent="${dest%/*}"

    if [[ ! -e "${source}" && ! -L "${source}" ]]; then
        return 2
    fi
    if [[ -e "${dest}" || -L "${dest}" ]]; then
        return 3
    fi
    if [[ ! -d "${dest_parent}" || -L "${dest_parent}" ]]; then
        return 4
    fi

    command mv "${source}" "${dest}"
}

# Leert den Vite-Abhaengigkeits-Cache.
#
# Ohne das serviert der Dev-Server die vorab optimierte alte Fassung weiter —
# der Fehler sieht dann wie ein fehlender Export aus, obwohl das Paket stimmt.
clearViteCache() {
    local cache="${PACKAGE_ROOT}/node_modules/.vite"
    [[ -d "${cache}" ]] || return 0
    command rm -rf "${cache}"
    echo -e "  ${BLUE}ℹ${NC} Vite-Cache geleert"
}

# Stellt ein Paket auf das lokale Repo um.
#
# Die Registry-Fassung wird daneben gesichert, damit --unlink ohne Netz und
# ohne erneutes Aufloesen zurueckfindet.
#
# Params:
#   $1 - Paketname
#   $2 - Pfad zum lokalen Repo
#
# Returns:
#   0 bei Erfolg, 1 bei Fehler
linkPackage() {
    local name="$1" repo_dir="$2"
    local path backup state
    path="$(packagePath "${name}")"
    backup="${path}${BACKUP_SUFFIX}"
    state="$(packageState "${name}")"

    if [[ ! -d "${repo_dir}" ]]; then
        echo -e "  ${RED}✗${NC} ${name}: lokales Repo fehlt — ${repo_dir}" >&2
        return 1
    fi

    if [[ "${state}" == "link" ]]; then
        echo -e "  ${BLUE}ℹ${NC} ${name}: bereits lokal verlinkt"
        return 0
    fi

    # Die Registry-Fassung zur Seite legen. `movePathSafely` lehnt ab, wenn dort
    # schon etwas liegt (zwei Staende gingen sonst durcheinander) — und vor
    # allem, wenn das Ziel ein Symlink waere.
    if [[ -d "${path}" ]]; then
        local rc=0
        movePathSafely "${path}" "${backup}" || rc=$?
        case ${rc} in
            0) ;;
            3) echo -e "  ${RED}✗${NC} ${name}: altes Backup im Weg — ${backup}" >&2; return 1 ;;
            *) echo -e "  ${RED}✗${NC} ${name}: Sicherung fehlgeschlagen (rc=${rc})" >&2; return 1 ;;
        esac
    fi

    command ln -s "${repo_dir}" "${path}"
    echo -e "  ${GREEN}✓${NC} ${name} ${BLUE}→${NC} ${repo_dir}"
}

# Stellt ein Paket zurueck auf die Registry-Fassung.
#
# Params:
#   $1 - Paketname
#
# Returns:
#   0 bei Erfolg, 1 bei Fehler
unlinkPackage() {
    local name="$1"
    local path backup
    path="$(packagePath "${name}")"
    backup="${path}${BACKUP_SUFFIX}"

    if [[ ! -L "${path}" ]]; then
        echo -e "  ${BLUE}ℹ${NC} ${name}: nicht verlinkt, nichts zu tun"
        return 0
    fi

    # Zuerst den Symlink weg, dann erst zurueckschieben — und beides ueber die
    # geprueften Helfer. Andersherum folgt `mv` dem Symlink und legt die
    # Sicherung **im Ziel-Repo** ab; genau so ist es passiert.
    local rc=0
    removeSymlink "${path}" || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        echo -e "  ${RED}✗${NC} ${name}: Symlink liess sich nicht entfernen (rc=${rc})" >&2
        return 1
    fi

    if [[ -d "${backup}" ]]; then
        rc=0
        movePathSafely "${backup}" "${path}" || rc=$?
        if [[ ${rc} -ne 0 ]]; then
            echo -e "  ${RED}✗${NC} ${name}: Sicherung liess sich nicht zurueckholen (rc=${rc})" >&2
            return 1
        fi
        echo -e "  ${GREEN}✓${NC} ${name} ${BLUE}→${NC} Registry $(packageVersion "${name}") (aus Sicherung)"
        return 0
    fi

    echo -e "  ${YELLOW}⚠${NC} ${name}: keine Sicherung — hole es ueber npm"
    ( cd "${PACKAGE_ROOT}" && npm install --silent "${name}" >/dev/null 2>&1 ) || {
        echo -e "  ${RED}✗${NC} ${name}: npm install fehlgeschlagen — bitte von Hand nachziehen" >&2
        return 1
    }
    echo -e "  ${GREEN}✓${NC} ${name} ${BLUE}→${NC} Registry $(packageVersion "${name}")"
}

# Zeigt zu jedem konfigurierten Paket die aktuelle Quelle.
printStatus() {
    echo
    echo -e "  ${LIGHT_BLUE}Pakete in ${YELLOW}${PACKAGE_ROOT}${LIGHT_BLUE}${NC}"
    echo

    local entry name repo_dir state target
    for entry in "${PACKAGES[@]}"; do
        name="${entry%%=*}"
        repo_dir="${entry#*=}"
        state="$(packageState "${name}")"

        case "${state}" in
            link)
                target="$(readlink "$(packagePath "${name}")")"
                printf "  ${GREEN}%-${COL_WIDTH_NAME}s${NC} %s ${BLUE}%s${NC}\n" \
                       "${name}" "lokal    " "${target}"
                ;;
            npm)
                printf "  ${CYAN}%-${COL_WIDTH_NAME}s${NC} %s ${YELLOW}%s${NC}\n" \
                       "${name}" "Registry " "$(packageVersion "${name}")"
                ;;
            *)
                printf "  ${RED}%-${COL_WIDTH_NAME}s${NC} %s ${YELLOW}%s${NC}\n" \
                       "${name}" "fehlt    " "npm install faellig — erwartet: ${repo_dir}"
                ;;
        esac
    done
    echo
}

# Fuehrt --link/--unlink fuer die gewaehlten Pakete aus.
#
# Params:
#   $1 - "link" oder "unlink"
#   $2 - Paketname, oder leer fuer alle
#
# Returns:
#   0 wenn alle Umschaltungen geklappt haben, sonst 1
applyAction() {
    local action="$1" wanted="$2"
    local entry name repo_dir failed=0 handled=0

    echo
    for entry in "${PACKAGES[@]}"; do
        name="${entry%%=*}"
        repo_dir="${entry#*=}"
        [[ -n "${wanted}" && "${wanted}" != "${name}" ]] && continue
        handled=1

        if [[ "${action}" == "link" ]]; then
            linkPackage "${name}" "${repo_dir}" || failed=1
        else
            unlinkPackage "${name}" || failed=1
        fi
    done

    if [[ ${handled} -eq 0 ]]; then
        echo -e "  ${RED}✗${NC} '${wanted}' steht nicht in ${CONFIG_DISPLAY}" >&2
        echo
        return 1
    fi

    clearViteCache
    echo
    return "${failed}"
}

# Kein Argument → Help anzeigen (keine Ausnahmen)
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

action=""
target_package=""
use_all=0
config_file="${CONFIG_NAME}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--status)
            action="status"
            ;;
        -l|--link|-u|--unlink)
            [[ "$1" == "-l" || "$1" == "--link" ]] && action="link" || action="unlink"
            # Ein folgendes Wort ohne fuehrenden Bindestrich ist der Paketname
            if [[ $# -ge 2 && "$2" != -* ]]; then
                target_package="$2"
                shift
            fi
            ;;
        -a|--all)
            use_all=1
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

if [[ -z "${action}" ]]; then
    usage
    exit 0
fi

if ! loadConfig "${config_file}"; then
    {
        echo -e "${RED}Fehler:${NC} Config '${config_file}' nicht gefunden oder ohne PACKAGES-Eintraege."
        echo -e "Vorlage anlegen: ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
    } >&2
    exit 1
fi

if [[ ! -d "${PACKAGE_ROOT}/node_modules" ]]; then
    {
        echo -e "${RED}Fehler:${NC} '${PACKAGE_ROOT}/node_modules' fehlt — erst ${GREEN}npm install${NC}."
        echo -e "PACKAGE_ROOT steht in ${CONFIG_DISPLAY}."
    } >&2
    exit 1
fi

if [[ "${action}" == "status" ]]; then
    printStatus
    exit 0
fi

# Umschalten braucht ein Ziel — entweder ein Paket oder ausdruecklich alle.
if [[ -z "${target_package}" && ${use_all} -eq 0 ]]; then
    {
        echo -e "${RED}Fehler:${NC} --${action} braucht einen Paketnamen oder ${GREEN}--all${NC}."
        echo -e "Verfuegbar laut ${CONFIG_DISPLAY}:"
        printf '    %s\n' "${PACKAGES[@]%%=*}"
    } >&2
    exit 1
fi

applyAction "${action}" "${target_package}"
printStatus
