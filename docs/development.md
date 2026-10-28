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
| BashLib, MakeLib | Werden von `make setup` unter `.libs/` verlinkt; ohne BashLib laufen nur `status` und einige Skripte nicht |

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
| `make clean` | Test- und Lint-Caches löschen |

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
