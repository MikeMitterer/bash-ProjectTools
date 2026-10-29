<div align="center">

# ProjectTools

**Geteilte Entwicklungs-Skripte für Projekte im DevBash-Ökosystem**

[Werkzeuge](#werkzeuge) · [Schnellstart](#schnellstart) · [Konfiguration](#konfiguration) · [Entwicklung](docs/development.md)

[English](README.md) · Deutsch

</div>

ProjectTools sammelt Skripte, die mehrere Projekte gleich brauchen: Status
der Repos, Doku-Prüfung, Ports des Dev-Stacks freigeben, npm-Pakete umschalten
und veröffentlichen, Changelog und Docker-Hub-Beschreibung.

Projekte installieren ProjectTools mit pipx als versioniertes Paket; die
Befehle `docs-check`, `repo-status` und `changelog` stehen dann im PATH.
Daneben bleibt der direkte Aufruf aus einer Arbeitskopie über `PROJECT_TOOLS`.

| Repo | Zweck | Konsum |
|---|---|---|
| BashLib | Wiederverwendbare Bash-Funktionen | `source` über `BASH_LIBS` |
| BashTools | Werkzeuge unabhängig von Projekten | Deploy nach `/usr/local/bin` |
| **ProjectTools** | Projektbezogene Entwicklungs-Skripte | `pipx install` mit Version; sonst direkt über `PROJECT_TOOLS` oder den Symlink `.libs/ProjectTools` |

## Übersicht

- [Werkzeuge](#werkzeuge)
- [Schnellstart](#schnellstart)
- [Konfiguration](#konfiguration)
- [Entwicklung](#entwicklung)
- [Weitere Dokumentation](#weitere-dokumentation)
- [Lizenz](#lizenz)

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

Voraussetzungen: Bash, Git, Python ab 3.10 und
[pipx](https://pipx.pypa.io/); dazu je Werkzeug, was sein Dokument nennt.

**Installieren** mit festem Release-Tag. Tags folgen dem Schema
`vX.Y.Z+YYMMDD.HHMM.hash` (Datum als JJMMTT, dann Uhrzeit), und pipx braucht
den vollen Tag. Den jüngsten nennt `make hints` in einer Arbeitskopie, ohne
Arbeitskopie dieser Befehl:

```bash
git ls-remote --tags --refs --sort=-v:refname https://github.com/MikeMitterer/bash-ProjectTools.git | head -1
```

Damit installieren, `<release-tag>` durch den Tag ersetzen:

```bash
pipx install 'git+https://github.com/MikeMitterer/bash-ProjectTools.git@<release-tag>'
projecttools --version
```

Danach stehen `docs-check`, `repo-status`, `changelog` und `projecttools` im
PATH. Das Paket bringt BashLib und Deno als Abhängigkeiten mit; `.libs/` und
`PROJECT_TOOLS` braucht es dafür nicht. Ein gesetztes `BASH_LIBS` hat Vorrang
vor der mitgelieferten BashLib.

**Aktualisieren:** `pipx install --force` mit dem neuen vollen Tag aufrufen.
`pipx upgrade` bleibt beim installierten Tag und bringt keine neue Version. Wer an ProjectTools arbeitet, installiert die
Arbeitskopie mit `pipx install -e <checkout>`; Änderungen an den Skripten
wirken dann ohne Neuinstallation.

**Ohne Installation** zeigt `PROJECT_TOOLS` auf `src/` dieses Repos. Ein Projekt legt zusätzlich den
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

Installiert heißen dieselben Aufrufe `repo-status --example` und
`repo-status --show`. Wie die Skripte in Make-Targets eingebunden werden,
steht im jeweiligen Werkzeug-Dokument. Die Projektkopie von `setup-libs.sh`,
die `.libs/ProjectTools` anlegt, ist durch die Installation abgelöst.

[↑ Übersicht](#übersicht)

## Konfiguration

**Jedes Skript liest seine Config aus dem Arbeitsverzeichnis.** Der Name folgt
dem Skript: `repo-status.sh` liest `.repo-status.conf.sh`; die Endung `.conf`
ohne `.sh` gilt ebenfalls. `--config <file>` wählt eine andere Datei.

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

## Lizenz

Copyright © 2026 Michael Mitterer. **MangoLila GmbH** ist Anbieterin und
Lizenzgeberin.

ProjectTools steht unter der **[EUPL 1.2](LICENSE)**, nur Version 1.2. Sie
erlaubt private und gewerbliche Nutzung, Änderungen, Weitergabe, Verkauf und
Hosting ohne kostenpflichtige Lizenz.

Wer ProjectTools oder eine geänderte Fassung weitergibt oder als
Netzwerkdienst anbietet, muss die Urheber- und Lizenzhinweise erhalten,
Änderungen kennzeichnen und den zugehörigen Quelltext nach den
Copyleft-Regeln der Lizenz bereitstellen.

Die Gewährleistungs- und Haftungsausschlüsse der EUPL-Artikel 7 und 8 gelten
auch gegenüber Verbrauchern, soweit das Gesetz es zulässt. Zwingende Rechte
bleiben unberührt, darunter die Haftung für Vorsatz, grobe Fahrlässigkeit,
Personenschäden und nach dem Produkthaftungsgesetz. Eine zusätzliche Garantie
wird nicht übernommen.

Kontakt: **office@MangoLila.at**.

Details: [LICENSE](LICENSE) · [Deutscher Lizenztext](LICENSE.de.txt) ·
[Anbieter- und Verbrauchererklärung](LICENSING.md)

[↑ Übersicht](#übersicht)
