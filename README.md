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
aus dem Script-Namen abgeleitet: `repo-status.sh` → `.repo-status.conf`.
Override via `--config <datei>`. Die Config gehört ins jeweilige Projekt-Repo.

### Format `.repo-status.conf`

```
# Kommentar (ganze Zeile) und Leerzeilen werden ignoriert

# Settings: KEY=VALUE (aktuell nur ISSUES_REPO; unbekannte Keys -> Warnung)
ISSUES_REPO=MikeMitterer/mein-issue-repo

# Repo-Einträge: <pfad>:<anzeigename> (Split am ersten ':')
.:MeinProjekt (Root)
apps/backend:apps/backend
```

- `#`-Zeilen und Leerzeilen: ignoriert
- Zeilen der Form `KEY=VALUE`: Settings — derzeit nur `ISSUES_REPO` (GitHub-Repo
  für die optionale Blocker/high-priority-Issue-Sektion); unbekannte Keys werden
  mit Warnung übersprungen
- Alle anderen Zeilen: Repo-Einträge `pfad:anzeigename`, aufgeteilt am **ersten**
  `:` (der Anzeigename darf `:` enthalten, der Pfad nicht)
- Fehlt die Datei oder enthält sie keinen Repo-Eintrag → Fehlermeldung mit
  Beispiel-Config, Exit 1

## Tools

| Script | Zweck | Config |
|---|---|---|
| `src/bash/repo-status.sh` | Git-Status aller Workspace-Repos als Tabelle + Blocker-Issues | `.repo-status.conf` |
