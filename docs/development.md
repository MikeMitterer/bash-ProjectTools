# Entwicklung

[← README](../README.md)

Diese Seite beschreibt die Arbeit **an** ProjectTools: Einrichten aus dem
Checkout, Befehle, Tests und Aufbau. Die Projektregeln stehen in
[AGENTS.md](../AGENTS.md).

## Übersicht

- [Voraussetzungen](#voraussetzungen)
- [Einrichten](#einrichten)
- [Befehle](#befehle)
- [Tests](#tests)
- [Paket und Release](#paket-und-release)
- [Projektaufbau](#projektaufbau)

## Voraussetzungen

| Werkzeug | Wofür |
|---|---|
| Bash, Git, `jq`, `lsof` | Skripte und Bash-Tests |
| Deno 2 | `docs-check` und dessen Tests |
| Python 3.14 | Entwicklungs-venv für die Python-Tests und Ruff (`PYTHON_BOOTSTRAP` wählt einen anderen Interpreter) |
| Pandoc | `dockerhub-readme` |
| `shellcheck` | `make lint` |
| BashLib, MakeLib | Werden von `make setup` unter `.libs/` verlinkt. Ohne BashLib laufen `status`, `version`, `tag-*`, einige Skripte und die Bash-Tests nicht; `make test-bash` nennt dann den Weg (Klon neben ProjectTools oder `BASH_LIBS`) |

Die Werkzeuge selbst laufen schon ab Python 3.9. Mit einer venv aus Python
3.9 scheitern aber einige Bootstrap-Tests von `dockerhub-readme`; deshalb die
neuere Vorgabe für die Entwicklung.

[↑ Übersicht](#übersicht)

## Einrichten

```bash
make setup
```

Das verlinkt BashLib und MakeLib unter `.libs/`, aktiviert den
pre-commit-Hook aus `.githooks/` und legt `.venv` mit den Paketen aus
`requirements-dev.txt` an. Der Hook prüft vor jedem Commit die vorgemerkte
Doku mit `make docs-check`.

`make setup` ist der einzige Weg, das Projekt einzurichten, und lässt sich
beliebig oft aufrufen. Die Pakete gleicht es nur neu ab, wenn
`requirements-dev.txt` oder eine eingebundene Requirements-Datei neuer ist
als die Stempeldatei `.venv/.installed`. `make test`, `make test-python` und
`make lint` richten nichts selbst ein: Fehlt die Einrichtung oder ist sie
veraltet, brechen sie mit dem Hinweis auf `make setup` ab.

Die Make-Targets verwenden immer die Skripte aus diesem Checkout, nicht die
aus `PROJECT_TOOLS` der Umgebung.

[↑ Übersicht](#übersicht)

## Befehle

| Befehl | Zweck |
|---|---|
| `make help` | Alle Targets anzeigen |
| `make test` | Doku-Prüfung, Bash-, Deno- und Python-Tests |
| `make test-bash32` | Bash-Tests unter `/bin/bash` 3.2 (macOS) |
| `make lint` | Shellcheck, `deno lint` und Ruff |
| `make docs-check` | Nur die Doku-Prüfung |
| `make status` | Git-Status und offene Blocker-Issues (braucht BashLib) |
| `make clean` | Test- und Lint-Caches und Reste von Paket-Builds löschen |
| `make version` | Version aus `pyproject.toml` und letzten Tag zeigen (braucht BashLib) |
| `make tags` | Die letzten zehn Tags mit Nachricht |
| `make tag-patch MSG="…"` | Version erhöhen, committen, taggen und pushen; ebenso `tag-minor`, `tag-major` (braucht BashLib) |

Einzelne Teile laufen auch über `make test-bash`, `make test-deno` und
`make test-python`; `ARGS` reicht Optionen an pytest weiter:

```bash
make test-python ARGS="-k changelog"
```

[↑ Übersicht](#übersicht)

## Tests

**Die Skripte müssen auch unter `/bin/bash` 3.2 laufen,** der Bash von macOS.
`make test-bash32` stellt dafür einen Link auf `/bin/bash` vorn in den PATH;
die getesteten Skripte starten über `#!/usr/bin/env bash` und nähmen sonst
wieder die neuere Bash.

Was die Suiten besonders prüfen:

- **`tests/bash/pkg-link.test.sh`** stellt den Unfall nach, bei dem ein `mv`
  die Sicherung im fremden Repo ablegte; mit dem naiven `mv` fällt der Test.
- **`tests/bash/npm-publish.test.sh`** startet das Skript über seinen
  öffentlichen Aufruf gegen eine `npm`-Attrappe. Jede Grenze hat ihren eigenen
  Fall, geprüft gegen einen Mutanten, der die Korrektur zurückdreht.  
  Die TTY-Zusage läuft unter einem echten PTY (`script -q /dev/null`, mit
  Rückfall auf die GNU-Form) und prüft beide Deskriptoren. Pythons
  `pty.spawn` hängt auf macOS nach dem Kindprozess und taugt dafür nicht.
- **`tests/bash/dev-ports.test.sh`** startet echte Server auf freien Ports und
  prüft, dass Prozesse außerhalb des Projekts weiterlaufen und mehrfache, auch
  gleichzeitige Aufrufe gelingen.
- **`tests/bash/makefile.test.sh`** startet `make` in einer Kopie ohne
  `.libs/` und mit leerer Umgebung: Hilfe, Hints, Abbruch der
  Maintainer-Targets, `require-setup` samt veralteter Stempeldatei und
  `clean`.
- **`tests/deno/docs-check.test.ts`** prüft die Regeln, mit Kanarienwerten in
  sensiblen Dateien; **`tests/bash/docs-check.test.sh`** Config, Optionen und
  Exit-Codes.
- **`tests/python/`** testet Changelog, Runner und `dockerhub-readme` mit
  temporären Git-Repositories und echten temporären venvs.
  **`test_package.py`** baut das pip-Paket, installiert es ohne
  Abhängigkeiten normal und editierbar und ruft die Befehle auf; BashLib kommt
  dabei aus `BASH_LIBS` oder dem DevBash-Baum, Deno aus dem PATH.

Für Python-Tests ohne Netz vorher Wheels herunterladen und
`PIP_NO_INDEX=1 PIP_FIND_LINKS=<wheel-ordner>` setzen.

Der Vergleich der CLI-Themes über alle drei Repos braucht die Pfade zu MakeLib
und BashLib:

```bash
THEME_MAKE_LIB=/path/to/MakeLib BASH_LIBS=/path/to/BashLib/src \
  .venv/bin/python -m pytest tests/python/test_cli_themes.py
```

Die deutschen gettext-Kataloge liegen unter `src/python/locales/de/`. Nach
Textänderungen die `.mo`-Datei neu übersetzen:

```bash
msgfmt <datei.po> -o <datei.mo>
```

[↑ Übersicht](#übersicht)

## Paket und Release

`pyproject.toml` ist die einzige Quelle für Version, Befehle und
Abhängigkeiten. Unter `dependencies` stehen BashLib (`mmit-bashlib` mit
Release-Tag aus github.com/MikeMitterer/bash-lib) und `deno`; welche Skripte
ins Paket kommen, steht unter `[tool.setuptools.package-data]`. Im Paket
liegen sie unter `projecttools/tools/`; `projecttools.cli` startet sie von dort
oder bei `pipx install -e` direkt aus `src/`.

Das Paket verlangt Python ab 3.10, weil es das `deno`-Paket erst ab dieser
Version gibt; direkt aufgerufen laufen die Werkzeuge weiter ab 3.9.
`test_package.py` prüft, dass sich alle Abhängigkeiten vom Paketindex für die
Mindestversion aus `requires-python` auflösen lassen.

Ein Release ist ein Tag `vX.Y.Z` auf `master`, passend zu `version`. Für eine
neue BashLib-Version zuerst deren Tag setzen, dann den Tag in `dependencies`
anheben.

[↑ Übersicht](#übersicht)

## Projektaufbau

| Pfad | Inhalt |
|---|---|
| `src/bash/` | Bash-Skripte; `changelog.sh` und `dockerhub-readme.sh` sind Links auf `py-run.py` |
| `src/python/` | Python-Werkzeuge, der Runner `py-run.py` und das Paket `projecttools` samt Befehlen (`projecttools/cli.py`) |
| `src/deno/` | Die Prüfung von `docs-check` |
| `tests/` | Tests je Sprache: `bash/`, `deno/`, `python/` |
| `scripts/` | `setup-libs.sh` und `test-bash.sh` für das Makefile |
| `docs/` | Diese Seite, die Werkzeug-Dokumente unter `docs/tools/` und weitere Anleitungen |

[↑ Übersicht](#übersicht)
