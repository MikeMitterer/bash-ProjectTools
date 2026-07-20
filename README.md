# ProjectTools

Projektbezogene Dev-Scripts, geteilt zwischen mehreren Projekten.

Teil des DevBash-Ökosystems:

| Repo | Zweck | Konsum |
|---|---|---|
| BashLib | Wiederverwendbare Funktionen (Libs) | `source` via `BASH_LIBS` |
| BashTools | Übergeordnete Tools, unabhängig von Dev-Projekten | Deploy nach `/usr/local/bin` |
| **ProjectTools** | Projektbezogene Dev-Scripts | Direkt via `PROJECT_TOOLS` / `.libs`-Symlink — kein Deploy |

## Konsum

- Env-Variable `PROJECT_TOOLS` zeigt auf `src/` (gesetzt in `~/.ci.machine.bashrc`)
- Projekte legen zusätzlich einen Symlink `.libs/ProjectTools` an (wie `BashLib`/`BashTools`)
- Aufruf im Projekt-Makefile: `PROJECT_TOOLS ?= $(WORKSPACE)/.libs/ProjectTools/src`

## Konfiguration

Jedes Script liest seine projektspezifische Config aus dem CWD. Der Name wird
aus dem Script-Namen abgeleitet: `repo-status.sh` → `.repo-status.conf.sh` (die
`.conf`-Endung ohne `.sh` wird ebenfalls akzeptiert). Die Config ist ein
**sourcebares Bash-Snippet** (BashTools-Konvention) — das Script sourct sie mit
`. "${CONFIG_FILE}"` und validiert danach die Pflichtwerte, statt selbst zu parsen.
Die `.sh`-Endung sorgt fürs IDE-Syntaxhighlighting. Override via `--config <datei>`.
Die Config gehört ins jeweilige Projekt-Repo.

Eine Starter-Config erzeugt `repo-status.sh --example > .repo-status.conf.sh`: das
Beispiel erkennt die vorhandenen Git-Repos automatisch (Root + Sub-Repos bis zwei
Ebenen tief) und belegt `ISSUES_REPO` aus dem `origin`-Remote vor.

### Format `.repo-status.conf.sh`

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2034  # von repo-status.sh gesourct

# Optional: GitHub-Repo für die Issue-Sektion (blocker/high-priority)
ISSUES_REPO="MikeMitterer/mein-issue-repo"

# Workspace-Repos: "<pfad>:<anzeigename>" (Split am ersten ':')
REPOS=(
    ".:MeinProjekt (Root)"
    "apps/backend:apps/backend"
)
```

- `ISSUES_REPO` (optional): GitHub-Repo für die Blocker/high-priority-Issue-Sektion;
  leer/ungesetzt → keine Issue-Sektion
- `REPOS` (Pflicht): Bash-Array aus `"<pfad>:<anzeigename>"`-Einträgen, aufgeteilt
  am **ersten** `:` (der Anzeigename darf `:` enthalten, der Pfad nicht)
- Fehlt die Datei oder ist `REPOS` leer/ungesetzt → Fehlermeldung mit
  Beispiel-Config, Exit 1
- Die Datei wird gesourced: nur Variablen-/Array-Zuweisungen hineinschreiben,
  keine Seiteneffekte

## Tools

Diese Tabelle ist das Inventar: ein Projekt komponiert `make status` aus den
gewünschten Scripten. Wie ein `status`-Target verdrahtet wird (`## `-Target,
Aufruf `$(PROJECT_TOOLS)/bash/<check>.sh --show`): siehe `makefile-conventions`-Skill,
Abschnitt „Status-Target (ProjectTools-Scripte)".

| Script | Zweck | Config |
|---|---|---|
| `src/bash/repo-status.sh` | Git-Status aller Workspace-Repos als Tabelle + Blocker-Issues | `.repo-status.conf.sh` |
