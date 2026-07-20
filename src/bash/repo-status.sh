#!/usr/bin/env bash
#------------------------------------------------------------------------------
# repo-status.sh — Git-Status aller Workspace-Repos als formatierte Tabelle
#
# Liest die Repo-Liste aus einer projektspezifischen Config-Datei im aktuellen
# Verzeichnis. Die Config ist ein sourcebares Bash-Snippet (setzt ISSUES_REPO
# und das REPOS-Array) — kein Custom-Parser. Der Name wird aus dem Script-Namen
# abgeleitet (repo-status.sh -> .repo-status.conf.sh; .sh-Endung fuer
# IDE-Highlighting, .conf wird ebenfalls akzeptiert). Optional zeigt das Script
# offene GitHub-Issues (blocker / high-priority) des in ISSUES_REPO
# konfigurierten GitHub-Repos an.
#
# Verwendung:
#   repo-status.sh [--show] [--config <datei>] [--example] [--help]
#   repo-status.sh --example > .repo-status.conf.sh   # Starter-Config anlegen
#   make status
#
# Optionen:
#   -s | --show     Git-Status aller Workspace-Repos als Tabelle anzeigen
#   -c | --config   Alternative Config-Datei (Default: ./.repo-status.conf.sh)
#   -e | --example  Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)
#   -h | --help     Diese Hilfe anzeigen
#------------------------------------------------------------------------------

set -euo pipefail

# Logische Pfadaufloesung beibehalten (kein pwd -P) — der Fallback muss auch
# ueber einen .libs/ProjectTools-Symlink funktionieren (.libs/BashLib daneben)
BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../../../BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/colors.lib.sh";  fi
if [[ "${__TOOLS_LIB__:=""}"   == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";   fi

APPNAME="$(basename "$0")"
readonly APPNAME
APPNAME_WITHOUT_EXTENSION="${APPNAME%%.*}"
readonly APPNAME_WITHOUT_EXTENSION

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
# Anzeigename ohne fuehrendes ./ (das ./ ist nur fuers slash-erzwungene `source` noetig,
# sonst wuerde bash die Datei im PATH statt im CWD suchen)
CONFIG_DISPLAY="${CONFIG_NAME#./}"
readonly CONFIG_DISPLAY
readonly COL_WIDTH_NAME=28
readonly COL_WIDTH_LOCAL=20

# Defaults — von der gesourcten Config ueberschrieben
ISSUES_REPO=""
REPOS=()

# Zeigt die Verwendungshinweise an.
#
# Aufbau: Usage-Zeile, Optionen mit usageLine(), Hints-Sektion.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-s | --show   " "Git-Status aller Workspace-Repos als Tabelle anzeigen"
    usageLine "-c | --config " "Alternative Config-Datei (Default: ${CONFIG_DISPLAY})"
    usageLine "-e | --example" "Gueltige Beispiel-Config auf stdout ausgeben (umleitbar)"
    usageLine "-h | --help   " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Status anzeigen:    ${GREEN}${APPNAME} --show${NC}"
    echo -e "    Config anlegen:     ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
    echo
}

# Gibt eine gueltige, sourcebare Beispiel-Config auf stdout aus — direkt umleitbar:
#   repo-status.sh --example > .repo-status.conf.sh
#
# Erkennt die vorhandenen Git-Repos automatisch: Root (falls Git-Repo) und
# Sub-Repos bis zwei Ebenen tief werden als REPOS-Eintraege vorgeschlagen;
# ISSUES_REPO wird aus dem origin-Remote (GitHub) vorbelegt, falls vorhanden.
# Ohne gefundene Git-Repos faellt es auf eine editierbare Vorlage zurueck.
printConfigExample() {
    local root_name
    root_name="$(basename "$(pwd)")"

    # ISSUES_REPO aus dem origin-Remote ableiten (nur GitHub: owner/repo)
    local origin issues_repo="" remote_path
    origin="$(git remote get-url origin 2>/dev/null || true)"
    case "${origin}" in
        *github.com[:/]*)
            remote_path="${origin##*github.com}"   # ":owner/repo.git" | "/owner/repo.git"
            remote_path="${remote_path#[:/]}"       # fuehrendes : oder / entfernen
            issues_repo="${remote_path%.git}"       # .git-Endung entfernen
            ;;
    esac

    # Git-Repos einsammeln: Root + Sub-Repos (bis 2 Ebenen tief), Symlink-Libs
    # und ueblichen Noise ausschliessen. find folgt Symlinks nicht (.libs bleibt aussen vor).
    local repos=()
    if [[ -e .git ]]; then
        repos+=(".:${root_name} (Root)")
    fi

    local gitdir repo_path
    while IFS= read -r gitdir; do
        repo_path="${gitdir#./}"
        repo_path="${repo_path%/.git}"
        [[ "${repo_path}" == "." || -z "${repo_path}" ]] && continue
        repos+=("${repo_path}:${repo_path}")
    done < <(find . -maxdepth 3 -name .git \
                  -not -path './.git' \
                  -not -path '*/.libs/*' \
                  -not -path '*/node_modules/*' \
                  -not -path '*/.venv/*' 2>/dev/null | sort)

    cat <<EOF
#!/usr/bin/env bash
# Config fuer repo-status.sh (ProjectTools) — wird gesourced, kein Custom-Parser.
# .sh-Endung fuers IDE-Highlighting. Format-Doku: ProjectTools/README.md
# shellcheck disable=SC2034  # von repo-status.sh gesourct

# Optional: GitHub-Repo fuer die Issue-Sektion (blocker/high-priority)
ISSUES_REPO="${issues_repo}"

# Workspace-Repos: "<pfad>:<anzeigename>" (Split am ersten ':')
REPOS=(
EOF

    if [[ ${#repos[@]} -gt 0 ]]; then
        printf '    "%s"\n' "${repos[@]}"
    else
        printf '    ".:%s (Root)"\n' "${root_name}"
        printf '    # "apps/backend:apps/backend"\n'
    fi

    echo ')'
}

# Sourct die Config-Datei und validiert das REPOS-Array.
#
# Die Config ist ein sourcebares Bash-Snippet, das ISSUES_REPO (optional) und
# das REPOS-Array ("<pfad>:<anzeigename>") setzt — kein Custom-Parser noetig.
#
# Params:
#   $1 - Pfad zur Config-Datei
#
# Returns:
#   0 bei Erfolg, 1 wenn Datei fehlt oder REPOS leer/ungesetzt ist
loadConfig() {
    local config_file="$1"

    [[ -f "${config_file}" ]] || return 1

    # shellcheck source=/dev/null
    . "${config_file}"

    [[ ${#REPOS[@]} -gt 0 ]]
}

# Gibt den lokalen Commit-Status eines Repos zurueck.
#
# Params:
#   $1 - Pfad zum Repo
#
# Returns:
#   Formatierter Status-String (coloriert)
getLocalStatus() {
    local repo_path="$1"

    local dirty_files
    dirty_files=$(git -C "${repo_path}" status --porcelain 2>/dev/null)

    if [[ -n "${dirty_files}" ]]; then
        local file_count
        file_count=$(echo "${dirty_files}" | wc -l | tr -d ' ')
        echo -e "${RED}✗ ${file_count} unkommitiert${NC}"
    else
        echo -e "${GREEN}✓ clean${NC}"
    fi
}

# Gibt den Remote-Sync-Status eines Repos zurueck.
#
# Params:
#   $1 - Pfad zum Repo
#
# Returns:
#   Formatierter Status-String (coloriert), leer wenn kein Remote
getRemoteStatus() {
    local repo_path="$1"

    local ahead behind
    ahead=$(git  -C "${repo_path}" rev-list --count "@{upstream}..HEAD" 2>/dev/null || true)
    behind=$(git -C "${repo_path}" rev-list --count "HEAD..@{upstream}" 2>/dev/null || true)

    if [[ -z "${ahead}" ]]; then
        echo -e "${YELLOW}kein Remote${NC}"
        return
    fi

    if [[ "${ahead}" == "0" && "${behind}" == "0" ]]; then
        echo -e "${GREEN}✓ aktuell${NC}"
        return
    fi

    local status_parts=()
    [[ "${ahead}"  != "0" ]] && status_parts+=("${YELLOW}↑ ${ahead} ahead${NC}")
    [[ "${behind}" != "0" ]] && status_parts+=("${RED}↓ ${behind} behind${NC}")
    echo -e "${status_parts[*]}"
}

# Gibt die Tabellen-Kopfzeile aus.
printHeader() {
    local separator_name separator_local
    separator_name="$(repeat '-' "${COL_WIDTH_NAME}")"
    separator_local="$(repeat '-' "${COL_WIDTH_LOCAL}")"

    local fmt_header fmt_separator
    fmt_header="    ${YELLOW}%-*s  %-*s  %s${NC}\n"
    fmt_separator="    %-*s  %-*s  %s\n"

    echo ""
    # shellcheck disable=SC2059
    printf "${fmt_header}" \
        "${COL_WIDTH_NAME}" "Repo" "${COL_WIDTH_LOCAL}" "Lokal" "Remote"
    # shellcheck disable=SC2059
    printf "${fmt_separator}" \
        "${COL_WIDTH_NAME}" "${separator_name}" \
        "${COL_WIDTH_LOCAL}" "${separator_local}" \
        "${separator_local}"
}

# Entfernt ANSI-Escape-Codes aus einem String.
#
# Params:
#   $1 - String mit ANSI-Codes
#
# Returns:
#   Reiner Text ohne Escape-Sequenzen
stripAnsi() {
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Gibt eine einzelne Repo-Zeile aus.
#
# Params:
#   $1 - Anzeigename des Repos
#   $2 - Pfad zum Repo (relativ zum Workspace-Root)
printRepoRow() {
    local repo_name="$1"
    local repo_path="$2"

    if [[ ! -d "${repo_path}/.git" ]]; then
        printf "    ${BLUE}%-${COL_WIDTH_NAME}s${NC}  ${YELLOW}%s${NC}\n" \
            "${repo_name}" "nicht ausgecheckt"
        return
    fi

    local local_status remote_status
    local_status=$(getLocalStatus "${repo_path}")
    remote_status=$(getRemoteStatus "${repo_path}")

    # Sichtbare Laenge ohne ANSI berechnen, Luecke manuell auffuellen
    # ${#var} zaehlt Zeichen (nicht Bytes) — korrekt fuer UTF-8 Symbole wie ✓/✗
    local visible_text pad_len padding
    visible_text=$(stripAnsi "${local_status}" | tr -d '\n')
    pad_len=$(( COL_WIDTH_LOCAL - ${#visible_text} ))
    padding="$(repeat ' ' "${pad_len}")"

    printf "    ${BLUE}%-${COL_WIDTH_NAME}s${NC}  %b%s  %b\n" \
        "${repo_name}" "${local_status}" "${padding}" "${remote_status}"
}

# Gibt die Status-Tabelle aller konfigurierten Repos aus.
printReposTable() {
    printHeader

    for entry in "${REPOS[@]}"; do
        local repo_path="${entry%%:*}"
        local repo_name="${entry#*:}"
        printRepoRow "${repo_name}" "${repo_path}"
    done

    echo ""
}

# Gibt offene GitHub Issues mit Label 'blocker' oder 'high-priority' aus.
#
# Laeuft nur, wenn ISSUES_REPO in der Config gesetzt ist.
#
# Benoetigt: gh CLI, authentifiziert
printIssues() {
    if [[ -z "${ISSUES_REPO}" ]]; then
        return
    fi

    if ! command -v gh &>/dev/null; then
        return
    fi

    local issues
    issues=$(gh issue list \
        --repo "${ISSUES_REPO}" \
        --state open --limit 50 \
        --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | any(. == "blocker" or . == "high-priority"))] | .[]' \
        2>/dev/null) || return

    if [[ -z "${issues}" ]]; then
        return
    fi

    echo -e "  ${YELLOW}Offene Issues (blocker / high-priority)${NC}"
    echo ""

    while IFS= read -r issue; do
        local number title labels_str label_color
        number=$(echo "${issue}" | jq -r '.number')
        title=$(echo "${issue}"  | jq -r '.title')
        labels_str=$(echo "${issue}" | jq -r '[.labels[].name] | join(", ")')

        if echo "${labels_str}" | grep -q "blocker"; then
            label_color="${RED}"
        else
            label_color="${YELLOW}"
        fi

        printf "    ${BLUE}#%-4s${NC}  %b%-12s${NC}  %s\n" \
            "${number}" "${label_color}" "[${labels_str}]" "${title}"
    done < <(echo "${issues}" | jq -c '.')

    echo ""
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

# Kein Argument → Help anzeigen
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

config_file="${CONFIG_NAME}"
action=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--show)
            action="show"
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

if [[ "${action}" != "show" ]]; then
    usage
    exit 0
fi

if ! loadConfig "${config_file}"; then
    {
        echo -e "${RED}Fehler:${NC} Config '${config_file}' nicht gefunden oder ohne Repo-Eintraege."
        echo -e "Vorlage anlegen: ${GREEN}${APPNAME} --example > ${CONFIG_DISPLAY}${NC}"
    } >&2
    exit 1
fi

printReposTable
printIssues
