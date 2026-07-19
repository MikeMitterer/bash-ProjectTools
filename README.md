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

## Tools

| Script | Zweck | Config |
|---|---|---|
| `src/repo-status.sh` | Git-Status aller Workspace-Repos als Tabelle + Blocker-Issues | `.repo-status.conf` |
