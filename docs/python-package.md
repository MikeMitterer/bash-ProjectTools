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

Danach ist `from projecttools.ui.colors import HelpFormatter, Theme` ohne
maschinenabhängigen Pfad oder `sys.path`-Änderung möglich. Die Installation
gehört zur Umgebung des konsumierenden Projekts; der ProjectTools-Runner
ändert diese Umgebung nicht.
