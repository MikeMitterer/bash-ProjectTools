# repo-status.sh — Git-Status aller Workspace-Repos

[← README](../../README.md)

`repo-status.sh` zeigt den Git-Status aller Repos eines Workspace als Tabelle.
Ist ein GitHub-Repo angegeben, folgen die offenen Issues mit Blocker- oder
hoher Priorität. Ein Projekt ruft es meist über sein Make-Target `status` auf.

Voraussetzungen: BashLib (im pipx-Paket enthalten, Befehl `repo-status`); für
die Issue-Sektion die angemeldete `gh` CLI.

## Übersicht

- [Aufruf](#aufruf)
- [Format `.repo-status.conf.sh`](#format-repo-statusconfsh)

## Aufruf

Im Projekt-Root:

```bash
repo-status.sh --example > .repo-status.conf.sh   # Starter-Config anlegen
repo-status.sh --show                             # Status anzeigen
```

`--example` erkennt die vorhandenen Git-Repos selbst (Root und Sub-Repos bis
zwei Ebenen tief) und belegt `ISSUES_REPO` aus dem `origin`-Remote vor.

[↑ Übersicht](#übersicht)

## Format `.repo-status.conf.sh`

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

- **`ISSUES_REPO`** (optional): GitHub-Repo für die Issue-Sektion. Leer oder
  nicht gesetzt: keine Issue-Sektion.
- **`REPOS`** (Pflicht): Einträge `"<pfad>:<anzeigename>"`, aufgeteilt am
  **ersten** `:`. Der Anzeigename darf `:` enthalten, der Pfad nicht.
- **Fehlt die Datei oder ist `REPOS` leer,** endet das Skript mit einer
  Beispiel-Config und Exit-Code 1.

Die Datei wird gesourct: nur Zuweisungen hineinschreiben, keine
Seiteneffekte.

[↑ Übersicht](#übersicht)
