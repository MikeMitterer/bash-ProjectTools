# ProjectTools — Claude Context

> Ergänzt den systemweiten `code-standards`-Skill mit projektspezifischem Kontext.
> Konventionen und Library-Details → siehe `code-standards`-Skill.

## Projektübersicht

ProjectTools ist Teil des **DevBash-Ökosystems** unter `/Volumes/DevLocal/DevBash/Production/`.

- Projektbezogene Dev-Scripts, die über mehrere Projekte geteilt werden
  (Abgrenzung: BashTools = projektunabhängige Tools mit `/usr/local/bin`-Deploy)
- **Kein Deploy** — Konsum direkt via `PROJECT_TOOLS`-Env-Variable
  (`~/.ci.machine.bashrc` → `.../ProjectTools/src`) bzw. `.libs/ProjectTools`-Symlink
  in den Projekten

## Konventionen

- Config-Naming: `.$(basename "$0" .sh).conf` im CWD, Override `--config` —
  Details im `code-standards`-Skill (Abschnitt „Config-Datei — Name folgt dem Script-Namen")
- BashLib-Einbindung via `BASH_LIBS`; Fallback **logisch** aufgelöst
  (`$(cd "$(dirname "$0")/../../BashLib/src" && pwd)`, kein `pwd -P`) — funktioniert
  direkt im DevBash-Baum und über Projekt-Symlinks
- Kein Argument → `--help`; shellcheck-clean; kebab-case-Dateinamen

## Tools

- `src/repo-status.sh` — Git-Status aller Workspace-Repos (Config: `.repo-status.conf`,
  optional `ISSUES_REPO` für die GitHub-Issue-Sektion)
