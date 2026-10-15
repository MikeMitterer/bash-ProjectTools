<div align="center">

# ProjectTools

**Geteilte Entwicklungs-Skripte für Projekte im DevBash-Ökosystem**

[Werkzeuge](#werkzeuge) · [Schnellstart](#schnellstart) · [Konfiguration](#konfiguration) · [Entwicklung](docs/development.md)

</div>

ProjectTools sammelt Skripte, die mehrere Projekte gleich brauchen: Status
der Repos, Doku-Prüfung, Ports des Dev-Stacks freigeben, npm-Pakete umschalten
und veröffentlichen, Changelog und Docker-Hub-Beschreibung.

Die Projekte rufen die Skripte direkt aus diesem Repo auf. Es gibt keinen
Deploy und keine Kopie je Projekt.

| Repo | Zweck | Konsum |
|---|---|---|
| BashLib | Wiederverwendbare Bash-Funktionen | `source` über `BASH_LIBS` |
| BashTools | Werkzeuge unabhängig von Projekten | Deploy nach `/usr/local/bin` |
| **ProjectTools** | Projektbezogene Entwicklungs-Skripte | Direkt über `PROJECT_TOOLS` oder den Symlink `.libs/ProjectTools` |

## Übersicht

- [Werkzeuge](#werkzeuge)
- [Schnellstart](#schnellstart)
- [Konfiguration](#konfiguration)
- [Entwicklung](#entwicklung)
- [Weitere Dokumentation](#weitere-dokumentation)

## Werkzeuge

Ein Projekt komponiert sein Make-Target `status` und seine übrigen Targets aus
diesen Skripten.

| Skript | Zweck | Config |
|---|---|---|
| [`repo-status.sh`](docs/tools/repo-status.md) | Git-Status aller Workspace-Repos als Tabelle, dazu offene Blocker-Issues | `.repo-status.conf.sh` |
| [`docs-check.sh`](docs/tools/docs-check.md) | Nutzerdoku gegen das Projekt prüfen: Links, Anker, Befehle, Variablen, verbotene Begriffe, Screenshots, abhängige Dateien | `.docs-check.conf.sh` |
| [`dev-ports.sh`](docs/tools/dev-ports.md) | Ports des Dev-Stacks anzeigen und samt Prozessen freigeben | `.dev-ports.conf.sh` |
| [`pkg-link.sh`](docs/tools/pkg-link.md) | npm-Paket zwischen lokalem Repo und Registry umschalten | `.pkg-link.conf.sh` |
| [`npm-publish.sh`](docs/tools/npm-publish.md) | npm-Paket veröffentlichen: anmelden, prüfen, hochladen, nachsehen | — |
| [`dockerhub-readme.sh`](docs/tools/dockerhub-readme.md) | Container-README mit absoluten GitHub-Links nach Docker Hub übertragen | Optionen |
| [`changelog.py`](docs/tools/changelog.md) | `CHANGELOG.md` aus Release-Tags und Conventional Commits | Optionen |
| [`py-run.sh`](docs/tools/py-run.md) | Python-Werkzeuge starten, bei Bedarf mit eigener venv | — |

Die Bash-Skripte liegen unter `src/bash/`, die Python-Werkzeuge unter
`src/python/`. `dev-ports.sh` und `docs-check.sh` laufen auch ohne BashLib,
die übrigen Bash-Skripte brauchen sie.

[↑ Übersicht](#übersicht)

## Schnellstart

Voraussetzungen: Bash und Git; dazu je Werkzeug, was sein Dokument nennt,
etwa Deno 2 für `docs-check.sh`.

`PROJECT_TOOLS` zeigt auf `src/` dieses Repos. Ein Projekt legt zusätzlich den
Symlink `.libs/ProjectTools` an und setzt im Makefile:

```makefile
PROJECT_TOOLS ?= $(WORKSPACE)/.libs/ProjectTools/src
```

Ein Skript braucht im Projekt-Root einmal seine Config und läuft dann direkt.
Am Beispiel des Repo-Status:

```bash
"$PROJECT_TOOLS/bash/repo-status.sh" --example > .repo-status.conf.sh
"$PROJECT_TOOLS/bash/repo-status.sh" --show
```

Wie die Skripte in Make-Targets eingebunden werden, steht im jeweiligen
Werkzeug-Dokument.

[↑ Übersicht](#übersicht)

## Konfiguration

**Jedes Skript liest seine Config aus dem Arbeitsverzeichnis.** Der Name folgt
dem Skript: `repo-status.sh` liest `.repo-status.conf.sh`; die Endung `.conf`
ohne `.sh` gilt ebenfalls. `--config <datei>` wählt eine andere Datei.

Die Config ist ein Bash-Snippet, das das Skript sourct und danach prüft. Sie
enthält deshalb nur Zuweisungen und gehört ins jeweilige Projekt-Repo.

Eine gültige Starter-Config schreibt jedes Skript mit `--example`; danach
einmal durchsehen. Die Schlüssel beschreibt das Werkzeug-Dokument im Abschnitt
„Format“.

[↑ Übersicht](#übersicht)

## Entwicklung

Einrichten aus dem Checkout, Make-Targets, Tests und Projektaufbau stehen in
der [Entwicklerdoku](docs/development.md).

[↑ Übersicht](#übersicht)

## Weitere Dokumentation

- [Werkzeug-Dokumente](docs/tools/): Aufruf, Ablauf und Config-Format je
  Skript, verlinkt in der Tabelle [Werkzeuge](#werkzeuge).
- [Python-Paket für Projektumgebungen](docs/python-package.md): die Module
  unter `projecttools` in der venv eines anderen Projekts nutzen.
- [CLI-Themes und Abstände](docs/cli-themes.md): gemeinsame Farben und
  Layout von MakeLib, BashLib und ProjectTools.

[↑ Übersicht](#übersicht)
