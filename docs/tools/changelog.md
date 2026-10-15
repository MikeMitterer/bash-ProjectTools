# changelog.py — Release-Historie aus Git

[← README](../../README.md)

`changelog.py` schreibt `CHANGELOG.md` aus den Release-Tags und Conventional
Commits des aufrufenden Repositorys. Es braucht nur Git und Python 3.9+, nutzt
ausschließlich die Standardbibliothek und startet direkt, ohne venv und ohne
Paketinstallation.

## Übersicht

- [Aufruf](#aufruf)
- [Was in den Changelog kommt](#was-in-den-changelog-kommt)
- [Einbindung beim Release](#einbindung-beim-release)

## Aufruf

```bash
python3 "${PROJECT_TOOLS}/python/changelog.py" --dry-run
python3 "${PROJECT_TOOLS}/python/changelog.py" --generate
python3 "${PROJECT_TOOLS}/python/changelog.py" --publish
```

- **`-n`/`--dry-run`** zeigt die Datei nur, **`-g`/`--generate`** schreibt sie.
- **`-p`/`--publish`** schreibt, committet ausschließlich diese Datei und pusht
  den aktuellen Branch über dessen Upstream.  
  Ein wiederholter Publish pusht erneut, erzeugt bei gleichem Inhalt aber
  keinen neuen Commit. Fremde Änderungen an versionierten Dateien oder ein
  gefüllter Git-Index verhindern Publish; die Ausgabedatei selbst darf lokal
  geändert sein.
- **`-o`/`--output`** wählt eine andere Datei innerhalb des Arbeitsbaums.

Ohne Argumente oder mit `--help` erscheint nur die Hilfe. `LANGUAGE=en`
erzeugt ein englisches Dokument; Commit- und Tag-Texte bleiben unverändert.

[↑ Übersicht](#übersicht)

## Was in den Changelog kommt

Die vollständige Git-Historie muss lokal vorhanden sein; fehlende Tags bei
Bedarf mit `git fetch --tags` holen.

Verarbeitet werden SemVer-Tags, auch mit Build-Metadaten, auf der
First-Parent-Historie des aktuellen Branches. Tags auf Feature-Branches werden
keine Releases des Hauptbranches. Commits eingemergter Branches erscheinen im
nächsten Release genau einmal; noch nicht getaggte Änderungen fehlen bewusst.

Gruppiert wird nach inkompatiblen Änderungen, Funktionen, Fehlerkorrekturen,
Geschwindigkeit, weiteren Änderungen und Dokumentation. Es entfallen:

- die internen Scopes `tickets`, `activity`, `lessons` und `changelog`,
- normale `chore`-, `test`- und `ci`-Commits sowie Merge-Commits,
- reine Änderungen unter `_tickets/` oder in Agenten-Regeldateien,
- nicht konventionelle Commit-Titel.

Annotierte Tag-Nachrichten liefern die Kurztexte der Releases; leichtgewichtige
Tags erhalten keinen erfundenen Kurztext. Manuelle Änderungen an der
erzeugten Datei werden überschrieben.

[↑ Übersicht](#übersicht)

## Einbindung beim Release

Das konsumierende Makefile ruft nach einem erfolgreichen `semVerBump` das
Skript mit `--publish` auf. Der Changelog-Commit liegt damit nach dem
Release-Tag.

Scheitert dieser Schritt, bleibt das Release bestehen: nur `--publish`
wiederholen, nicht erneut bumpen. Hinterlässt ein abgebrochener Commit einen
vorgemerkten Changelog, zuerst die Ursache beheben und den Commit gezielt
abschließen.

[↑ Übersicht](#übersicht)
