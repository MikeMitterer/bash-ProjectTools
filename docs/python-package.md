# Python-Paket für Projektumgebungen

[← README](../README.md)

Die wiederverwendbaren Python-Module liegen unter
`src/python/projecttools/`. `projecttools.ui.colors` enthält Farben und
Argparse-Formatierung, `projecttools.git_access` den Git-Zugriff des
Changelog-Werkzeugs. Die ausführbaren Werkzeuge bleiben unter `src/python/`
und laufen direkt über Python oder [py-run.sh](tools/py-run.md).

Für Python-Skripte in anderen Projekten das Paket in deren eigener venv
installieren:

```bash
.venv/bin/python -m pip install -e ./.libs/ProjectTools
```

Das zieht BashLib und Deno als Abhängigkeiten mit und braucht deshalb
Python ab 3.10; wer nur die Python-Module braucht, ergänzt `--no-deps`, dann
reicht Python 3.9. Die Befehle `docs-check`,
`repo-status` und `changelog` installiert man dagegen mit pipx (siehe
[README](../README.md#schnellstart)).

Danach ist `from projecttools.ui.colors import HelpFormatter, Theme` ohne
maschinenabhängigen Pfad oder `sys.path`-Änderung möglich. Die Installation
gehört zur Umgebung des konsumierenden Projekts; der ProjectTools-Runner
ändert diese Umgebung nicht.
