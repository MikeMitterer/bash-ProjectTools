# CLI-Themes und Abstände

[← README](../README.md)

Die drei eigenständigen Dateien MakeLib `colours.mk`, BashLib
`colors.lib.sh` und ProjectTools `src/python/projecttools/ui/colors.py` verwenden dieselbe
Palette und Theme-Auswahl: `classic` (Standard), `ocean`, `earth`, `night`,
`mono`, `sunset`, `forest`, `neon`, `shell`. Ein unbekannter Name verwendet
`classic`. Die Auswahl lässt sich in der jeweiligen Datei umstellen oder mit
`MAKE_THEME` überschreiben. Es gibt keine generierte Datei.
Make exportiert die Auswahl und Layout-Werte an seine Kindprozesse.

```bash
make help MAKE_THEME=ocean
MAKE_THEME=ocean ./src/bash/py-run.sh --help
MAKE_THEME=ocean python3 src/python/changelog.py --help
```

| Einstellung | Vorgabe | Bedeutung |
|---|---|---|
| `THEME_INDENT_GROUP` | zwei Leerzeichen | Gruppenüberschrift |
| `THEME_INDENT_TARGET` | sieben Leerzeichen | Target oder Option |
| `THEME_WIDTH_TARGET` | `22` | Breite der ersten Spalte |
| `THEME_COLUMN_GAP` | `1` | Mindestabstand zur Beschreibung |
| `THEME_WIDTH_HELP` | `110` | Python-Hilfe: gesamte Textbreite |
| `THEME_GROUP_SPACING` | `1` | Leerzeilen zwischen Gruppen |

Mit diesen Vorgaben beginnt die Beschreibung in Spalte 31. Lange Beschriftungen
stehen bei `usageLine`/`themeLine` und der Python-Hilfe auf einer eigenen Zeile.
Python bricht lange Beschreibungen an der Gesamtbreite um; Bash und Make
geben Beschreibungstexte unverändert aus. Einrückungen sind
**Leerzeichenketten**, Breiten und Abstände nichtnegative Zahlen. Einzelne
Werte vor dem Include/Source beziehungsweise per Umgebung überschreiben.

`THEME_COLOR_GROUP`, `TARGET`, `DESC`, `SERVER`, `DANGER` (jeweils mit dem Präfix
`THEME_COLOR_`) behalten ihre Namen. Hinzu kommen `THEME_COLOR_SUCCESS` und
`THEME_COLOR_WARNING`. Grundfarben und die bisherigen öffentlichen Makros,
Bash-Funktionen und Argumente bleiben verfügbar. Die Standarddarstellung der
Ausgabehelfer folgt dem gemeinsamen Theme.

Die Bash- und Python-Helfer geben in Pipes, bei `NO_COLOR` und `TERM=dumb`
keine ANSI-Farben aus. Make berücksichtigt `NO_COLOR` und behält seine
TERM-basierte Farberkennung. Bash-Grundkonstanten bleiben aus Kompatibilität
unveränderte Escape-Strings für `printf '%b'` oder `echo -e`.

Python verwendet `from projecttools.ui.colors import HelpFormatter, Theme`; der Formatter
liest die Optionen aus argparse. `Theme().line(label, description)` formatiert
eine einzelne Zeile. `styled(text, color, stream)` bleibt für vorhandene
Python-Farbaufrufe und `PROJECTTOOLS_COLOR_*` verfügbar.
