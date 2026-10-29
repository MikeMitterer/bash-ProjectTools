# README-Vorlage für ProjectTools

Hinweise an den Agenten, kein Text zum Übernehmen. Diese Projektvorlage geht
der Hausvorlage aus dem Skill `docs-conventions` vor. Sie folgt deren Aufbau
und passt ihn an eine Werkzeugsammlung an: statt Screenshot ein kleinstes
Aufrufbeispiel, statt Feature-Liste die Werkzeugtabelle.

Die Datei hat zwei Teile: zuerst Anweisungen für die Arbeit, dann die
nummerierten Abschnitte des README in ihrer Reihenfolge. Nur die nummerierten
Abschnitte erscheinen im README.

## Anweisungen

**Allgemeine Regeln** (nur Belegtes, Navigation, Lizenz, Prüfung) stehen in
`docs-conventions` und werden hier nicht wiederholt. Was geprüft wird, legt
`.docs-check.conf.sh` fest.

**Sprache:** Deutsch, für README und alle Dokumente unter `docs/`.

**Zielgruppe:** Entwickler eines Projekts, das ProjectTools einbindet. Das
README zeigt, welche Werkzeuge es gibt und wie man sie einbindet; wie ein
Werkzeug im Einzelnen arbeitet, steht in dessen Werkzeug-Dokument.

**Was nicht ins README gehört:** Optionen einzelner Werkzeuge,
Config-Schlüssel, Abläufe, Grenzen, Tests und Make-Targets dieses Repos. Sie
stehen in diesen Dokumenten:

| Inhalt | Dokument |
|---|---|
| Aufruf, Ablauf, Grenzen und Config-Format eines Werkzeugs | `docs/tools/<werkzeug>.md` |
| Einrichten, Make-Targets, Tests, Projektaufbau | `docs/development.md` |
| Python-Paket `projecttools` in fremden venvs | `docs/python-package.md` |
| Gemeinsame CLI-Themes von MakeLib, BashLib und ProjectTools | `docs/cli-themes.md` |

**Werkzeug-Dokumente** (`docs/tools/<werkzeug>.md`), je Werkzeug eines:

- Titel `# <skript> — <zweck>`, darunter ein Link zurück auf das README.
- Einstieg: welches Problem das Werkzeug löst, danach seine Voraussetzungen
  (BashLib, Deno, Python-Version, externe Programme).
- Übersicht und Rücksprünge nach jedem Abschnitt.
- Abschnitt **Aufruf** mit kopierbarem Beispiel; bei einer Config ein
  Abschnitt **Format `.<werkzeug>.conf.sh`**. Auf diese Datei verweist der
  Kommentar „Format-Doku“ in der Config, die `--example` erzeugt.
- Abläufe, Grenzen und Einbindung in ein Makefile nur, soweit es sie gibt.
- Keine Testbeschreibungen; die gehören nach `docs/development.md`.

**Neues Werkzeug:** Zeile in der Werkzeugtabelle, eigenes Werkzeug-Dokument,
Eintrag in `DEPENDS_HINT` der `.docs-check.conf.sh` (Skript → Dokument) und,
falls das Werkzeug eine Config hat, der Pfad des Dokuments im Kommentar
„Format-Doku“ seiner `--example`-Ausgabe. Ein entferntes Werkzeug verliert all
das wieder.

## 1. Kopf

Zentriert und nur der Kopf: Name als Überschrift, fette Subheadline in einer
Zeile, Link-Leiste zu Werkzeuge, Schnellstart, Konfiguration und
Entwicklerdoku, getrennt durch ` · `. Badges nur für belegte Fakten.

## 2. Überblick

Zwei bis vier Sätze: welche Aufgaben die Werkzeuge abdecken und dass Projekte
sie mit pipx als versioniertes Paket installieren; daneben der direkte Aufruf
über `PROJECT_TOOLS`.

Darunter die Tabelle der Repos im DevBash-Ökosystem (BashLib, BashTools,
ProjectTools) mit Zweck und Art des Konsums; ProjectTools fett. Quelle:
`AGENTS.md`.

## 3. Übersicht

Inhaltsverzeichnis der folgenden Abschnitte.

## 4. Werkzeuge

Ein Satz: Projekte komponieren ihre Make-Targets aus diesen Skripten.

Tabelle mit den Spalten Skript, Zweck, Config. Das Skript verlinkt sein
Werkzeug-Dokument, Config ist der Dateiname, „Optionen“ oder „—“. Die
Tabelle ist das **Inventar**, auf das `makefile-conventions` verweist: Sie
nennt jedes Werkzeug, auch die ohne Make-Target.

Quelle: die ausführbaren Skripte unter `src/bash/` und die Werkzeuge, die
`py-run.sh --list` zeigt. Links unter `src/bash/` auf `py-run.py` erscheinen
mit ihrem Python-Werkzeug, nicht doppelt.

Danach ein Absatz: wo die Skripte liegen und welche ohne BashLib laufen. Quelle
ist der Fallback auf `BASH_LIBS` im Kopf jedes Skripts.

## 5. Schnellstart

Statt eines Screenshots das kleinste Beispiel:

- Voraussetzungen in einem Satz, mit Verweis auf die Werkzeug-Dokumente.
- Installation mit `pipx install` und Release-Tag, die installierten Befehle,
  Aktualisieren und `pipx install -e` für die Arbeitskopie. Quelle:
  `[project.scripts]` und `version` in `pyproject.toml`.
- Wie ein Projekt ohne Installation ProjectTools findet: `PROJECT_TOOLS`, der
  Symlink `.libs/ProjectTools` und die Zeile für das Makefile als Codeblock;
  dazu, dass die Projektkopie von `setup-libs.sh` abgelöst ist.
- Ein Werkzeug von der Starter-Config bis zum ersten Aufruf, bevorzugt
  `repo-status.sh`, weil es jedes Git-Repo kann.

## 6. Konfiguration

Die gemeinsame Config-Konvention aller Skripte: Name aus dem Skriptnamen,
Arbeitsverzeichnis, `--config`, sourcebares Bash-Snippet, `--example` für eine
Starter-Config. Keine Schlüssel einzelner Werkzeuge; dafür auf den Abschnitt
„Format“ der Werkzeug-Dokumente verweisen.

## 7. Entwicklung

Ein Satz und der Link auf `docs/development.md`.

## 8. Weitere Dokumentation

Die Werkzeug-Dokumente, `docs/python-package.md` und `docs/cli-themes.md`, je
mit Link und kurzer Beschreibung. Gibt es einen Changelog, ihn ergänzen.

## 9. Support

Nur wenn festgelegt ist, wie Issues und Pull Requests behandelt werden; heute
nicht.

## 10. Lizenz

Nach den Lizenzregeln von `docs-conventions` (EUPL-Baustein), belegt aus
`LICENSE`, `LICENSE.de.txt` und `LICENSING.md`. In der Übersicht verlinkt.
