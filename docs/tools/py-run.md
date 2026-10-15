# py-run.sh — Python-Werkzeuge starten

[← README](../../README.md)

`py-run.sh` startet die Python-Werkzeuge unter `src/python/`. Braucht ein
Werkzeug Pakete, richtet der Runner dafür einmalig eine eigene venv ein; die
Umgebung des Projekts bleibt unberührt.

## Übersicht

- [Aufruf](#aufruf)
- [Benannte Symlinks](#benannte-symlinks)
- [Python-Version und Werkzeug-venv](#python-version-und-werkzeug-venv)
- [Neue Werkzeuge](#neue-werkzeuge)

## Aufruf

```bash
./src/bash/py-run.sh --list
./src/bash/py-run.sh --run changelog --dry-run
./src/bash/py-run.sh --run dockerhub-readme --preview
```

- **`-l`/`--list`** findet die direkt ausführbaren Skripte unter
  `src/python/`, ohne sie zu importieren.
- **`-r`/`--run SCRIPT`** nimmt den Namen mit oder ohne `.py`. Alle folgenden
  Argumente, auch `--help`, gehören dem Werkzeug; sein Exit-Code bleibt
  erhalten.

Unbekannte Skripte und Runner-Argumente enden mit Exit-Code 2. Ohne Argumente
erscheint die Hilfe. Hilfe und Liste installieren nichts.

[↑ Übersicht](#übersicht)

## Benannte Symlinks

Ein Symlink auf `../python/py-run.py` startet das Werkzeug seines Namens, mit
oder ohne `.sh`. So sind `src/bash/dockerhub-readme.sh` und
`src/bash/changelog.sh` angelegt:

```bash
./src/bash/changelog.sh --dry-run
```

Alle Argumente gehen unverändert an das Werkzeug. Den Link direkt ausführen,
nicht mit `bash`: Sein Ziel ist ein Python-Skript.

[↑ Übersicht](#übersicht)

## Python-Version und Werkzeug-venv

Runner und Werkzeuge mit reiner Standardbibliothek laufen ab Python 3.9, auch
direkt als `python3 src/python/py-run.py -r changelog`. Sie brauchen keine
venv.

Erst die Einrichtung von Paketen verlangt Python 3.11+. Der Runner sucht dafür
selbst einen passenden Interpreter im PATH; `PYTHON_BOOTSTRAP` legt ihn fest.

Die Pakete stehen in der benachbarten `<name>.requirements.txt`. Der Runner
verwaltet dafür ausschließlich
`${XDG_CACHE_HOME:-$HOME/.cache}/projecttools/<name>/.venv`:

- **Erster Aufruf:** venv anlegen und Pakete installieren; dafür kann Netz
  nötig sein. Fehlendes pip ergänzt der Runner über ensurepip.
- **Weitere Aufrufe:** die fertige Umgebung wiederverwenden.
- **Geänderte Requirements, fehlende gepinnte Pakete oder defekte
  Abhängigkeiten:** erneut installieren.

Symlinks am Werkzeugverzeichnis oder an dessen `.venv` sind gesperrt.

[↑ Übersicht](#übersicht)

## Neue Werkzeuge

Ein paketabhängiges Werkzeug hält Hilfe und Parser frei von optionalen
Imports. Eine Funktion `prepare_cli(arguments)` prüft bei Bedarf Argumente,
lokale Dateien und externe Programme, bevor der Runner die venv anlegt. Sie
führt keine Fachaktion aus; erwartete Fehler meldet das Werkzeug übersetzt und
endet mit einem Exit-Code ungleich 0.

Für weitere Werkzeuge wird kein Bootstrap kopiert.

[↑ Übersicht](#übersicht)
