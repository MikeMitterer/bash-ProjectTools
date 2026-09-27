# ProjectTools

Projektbezogene Dev-Scripts, geteilt zwischen mehreren Projekten.

Teil des DevBash-Ökosystems:

| Repo | Zweck | Konsum |
|---|---|---|
| BashLib | Wiederverwendbare Funktionen (Libs) | `source` via `BASH_LIBS` |
| BashTools | Übergeordnete Tools, unabhängig von Dev-Projekten | Deploy nach `/usr/local/bin` |
| **ProjectTools** | Projektbezogene Dev-Scripts | Direkt via `PROJECT_TOOLS` / `.libs`-Symlink — kein Deploy |

## Konsum

- Env-Variable `PROJECT_TOOLS` zeigt auf `src/` (gesetzt in `~/.ci.machine.bashrc`)
- Projekte legen zusätzlich einen Symlink `.libs/ProjectTools` an (wie `BashLib`/`BashTools`)
- Aufruf im Projekt-Makefile: `PROJECT_TOOLS ?= $(WORKSPACE)/.libs/ProjectTools/src`

## Konfiguration

Scripts mit projektspezifischer Config lesen sie aus dem CWD. Der Name wird
aus dem Script-Namen abgeleitet: `repo-status.sh` → `.repo-status.conf.sh` (die
`.conf`-Endung ohne `.sh` wird ebenfalls akzeptiert). Die Config ist ein
**sourcebares Bash-Snippet** (BashTools-Konvention) — das Script sourct sie mit
`. "${CONFIG_FILE}"` und validiert danach die Pflichtwerte, statt selbst zu parsen.
Die `.sh`-Endung sorgt fürs IDE-Syntaxhighlighting. Override via `--config <datei>`.
Die Config gehört ins jeweilige Projekt-Repo.

Eine Starter-Config erzeugt `repo-status.sh --example > .repo-status.conf.sh`: das
Beispiel erkennt die vorhandenen Git-Repos automatisch (Root + Sub-Repos bis zwei
Ebenen tief) und belegt `ISSUES_REPO` aus dem `origin`-Remote vor.

### `pkg-link.sh` — Paket lokal oder aus der Registry

Wird an einem geteilten Paket und einer App gleichzeitig gearbeitet, muss die App
das lokale Repo sehen — sonst laesst sich vor dem Veroeffentlichen nichts pruefen.
Danach muss sie zurueck auf die Registry-Fassung. `pkg-link.sh` schaltet zwischen
beidem um, fuer beliebige Apps und Pakete.

```bash
pkg-link.sh --status                          # woher kommt gerade welches Paket?
pkg-link.sh --link @mmit/ux-foundation        # auf das lokale Repo
pkg-link.sh --unlink --all                    # alles zurueck auf die Registry
pkg-link.sh --example > .pkg-link.conf.sh     # Starter-Config (erkennt Pakete)
```

Beim Umschalten von Hand ist genau das schiefgegangen, was das Script verhindert:
Ein `mv` folgte einem noch bestehenden Symlink und legte die Sicherung **im
fremden Repo** ab; ein interaktives `rm -i`-Alias liess den Rueckbau still
scheitern. Deshalb laufen alle Datei-Operationen ueber `removeSymlink()` und
`movePathSafely()` — sie pruefen vorher, dass das Ziel in keiner Form belegt ist
und sein Elternverzeichnis kein Symlink. `tests/bash/pkg-link.test.sh` stellt den
Unfall nach; mit dem naiven `mv` faellt der Test.

Nach jedem Umschalten wird `node_modules/.vite` geleert — sonst serviert der
Dev-Server die vorab optimierte alte Fassung weiter, und der Fehler sieht wie ein
fehlender Export aus.

#### Format `.pkg-link.conf.sh`

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2034  # von pkg-link.sh gesourct

# Verzeichnis mit package.json und node_modules, relativ zum CWD.
PACKAGE_ROOT="dashboard"

# Umschaltbare Pakete: "<paketname>=<pfad zum lokalen Repo>"
PACKAGES=(
    "@mmit/ux-foundation=${DEV_LOCAL}/DevWeb/Production/ux-foundation"
)
```

### Format `.repo-status.conf.sh`

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2034  # von repo-status.sh gesourct

# Optional: GitHub-Repo für die Issue-Sektion (blocker/high-priority)
ISSUES_REPO="MikeMitterer/mein-issue-repo"

# Workspace-Repos: "<pfad>:<anzeigename>" (Split am ersten ':')
REPOS=(
    ".:MeinProjekt (Root)"
    "apps/backend:apps/backend"
)
```

- `ISSUES_REPO` (optional): GitHub-Repo für die Blocker/high-priority-Issue-Sektion;
  leer/ungesetzt → keine Issue-Sektion
- `REPOS` (Pflicht): Bash-Array aus `"<pfad>:<anzeigename>"`-Einträgen, aufgeteilt
  am **ersten** `:` (der Anzeigename darf `:` enthalten, der Pfad nicht)
- Fehlt die Datei oder ist `REPOS` leer/ungesetzt → Fehlermeldung mit
  Beispiel-Config, Exit 1
- Die Datei wird gesourced: nur Variablen-/Array-Zuweisungen hineinschreiben,
  keine Seiteneffekte

## Tools

Diese Tabelle ist das Inventar: ein Projekt komponiert `make status` aus den
gewünschten Scripten. Wie ein `status`-Target verdrahtet wird (`## `-Target,
Aufruf `$(PROJECT_TOOLS)/bash/<check>.sh --show`): siehe `makefile-conventions`-Skill,
Abschnitt „Status-Target (ProjectTools-Scripte)".

| Script | Zweck | Config |
|---|---|---|
| `src/bash/repo-status.sh` | Git-Status aller Workspace-Repos als Tabelle + Blocker-Issues | `.repo-status.conf.sh` |
| `src/bash/dockerhub-readme.sh` | README mit absoluten GitHub-Links nach Docker Hub übertragen | CLI-Optionen |
| `src/bash/npm-publish.sh` | Ein npm-Paket veröffentlichen — anmelden, prüfen, hochladen, nachsehen | — |

Nicht jedes Script gehört in `make status`. `npm-publish.sh` ersetzt das blosse
`npm publish` überall dort, wo veröffentlicht wird:

```makefile
publish: ##R Paket veröffentlichen  [CONFIRM=yes]
	@test "$(CONFIRM)" = "yes" || \
	  (echo "${ORANGE}Sicherheitscheck: make $@ CONFIRM=yes${NC}" && exit 1)
	@bash $(PROJECT_TOOLS)/bash/npm-publish.sh --publish $(NPM_ARGS)
```

Es räumt drei Fallen ab, die man sonst je einmal selbst sucht:

1. **Niemand angemeldet.** Die Registry antwortet bei einem **privaten** Paket
   mit `404 Not Found` statt `401` — sie verrät dessen Existenz nicht. Die
   Meldung zeigt dann auf den Paketnamen, und man prüft Scope, Schreibweise und
   `publishConfig`, während bloß der Token abgelaufen ist.
2. **Die Version liegt schon oben.** Wird vorher beantwortet und ungecacht
   gelesen, statt hinterher aus einer Fehlermeldung erraten.
3. **`409 Conflict — Failed to save packument`.** Registry-seitig und meist
   vorübergehend; der mitgelieferte Erklärungstext passt fast nie. Das Script
   sieht nach, ob das Paket trotz des Fehlers oben liegt, und versucht es sonst
   erneut.

`--publish` ist der ganze Vorgang; `--ensure` stellt nur die Anmeldung sicher
(private Abhängigkeiten installieren, CI); `--status` berichtet nur und taugt
dort, wo kein Browser aufgehen darf. Das Registry ermittelt es selbst:
`publishConfig.registry` schlägt die Scope-Einstellung, diese die globale.

### Die Grenzen, die der Vertrag ausdrücklich zieht

Sie stehen hier, weil jede von ihnen einmal eine echte Fehlfunktion war:

| Grenze | Warum |
|---|---|
| **stdout des Uploads bleibt unangetastet** | npm bricht seine OTP-Abfrage ab, sobald `stdin` **oder** `stdout` kein TTY ist (npm 11, `lib/utils/auth.js:10`). Ein Einfangen der Ausgabe schaltet die Zwei-Faktor-Anmeldung stumm ab — und eine `tee`-Pipeline genauso, obwohl die Ausgabe dabei sichtbar bleibt. Eingefangen wird nur stderr; dort stehen npms Fehlerzeilen ohnehin. |
| **Wiederholt wird nur bei exaktem `E409`** | Die blosse Zeichenfolge `409` steht auch in einem Paketnamen oder einer URL. Einen eigenen Prozess-Exit-Code je HTTP-Status gibt es nicht; npm endet bei jedem HTTP-Fehler mit `1`. |
| **„nicht vorhanden" ≠ „nicht feststellbar"** | Drei Dinge sind **kein** sicheres „gibt es nicht": ein Ausfall der Abfrage, eine unlesbare Antwort und ein `E404`. Letzteres heisst bei einem privaten Paket „gibt es nicht **oder** du darfst nicht" — dieselbe Verschleierung wie oben. In allen drei Fällen wird weder „ist noch frei" noch „liegt nicht oben" behauptet, und `--status` wird **nicht grün**. |
| **Ein Ziel für alle Schritte** | Ein `--registry` unter den durchgereichten Argumenten verschöbe sonst nur den Upload, während Anmeldung, Vor- und Nachprüfung die alte Registry befragen — die Auskunft gälte dann einem anderen Paket. Es wird deshalb übernommen. |
| **Durchgereicht wird eine Positivliste** | `--otp`, `--tag`, `--access`, `--registry`, `--provenance`/`--no-provenance` — beide Schreibweisen. Alles andere wird abgelehnt. Eine Sperrliste wäre bei jedem npm-Update potenziell unvollständig, und was durchrutscht, fällt mit einer **falschen Erfolgsmeldung** aus: `npm publish ./anderes-paket` lud ein anderes Paket hoch als das geprüfte, `--dry-run` gar keines — beide Male meldete der Wrapper das geprüfte als veröffentlicht. Was hier nicht steht, gehört in einen direkten `npm publish`-Aufruf, wo niemand etwas Falsches verspricht. |
| **Ein Wert darf keine Option sein** | Sonst schluckt eine Wertoption das verbotene Token: `--otp --dry-run` kam durch, und npm liest daraus `otp=--dry-run` und `dry-run=false` — aus dem gewollten Trockenlauf wird ein **echter Upload**. Belegt mit `npm config get` unter npm 11.19.0. Leere `--option=`-Werte werden ebenso abgelehnt. |
| **Keine Wiederholung bei Lifecycle-Scripten** | Jeder neue Versuch startet `npm publish` komplett neu, samt `prepublishOnly`, `prepack`, `prepare`, `postpack`, `publish` und `postpublish`. Dass die Registry eine Version nicht überschreibt, macht diese **lokalen** Hooks nicht idempotent. Erklärt die `package.json` einen davon, bricht das Script nach dem ersten Versuch ab und nennt ihn. |

Was die Positivliste erlaubt, geht unverändert an `npm publish` weiter —
deshalb das `$(NPM_ARGS)` oben:

```bash
make publish CONFIRM=yes NPM_ARGS=--otp=123456
```

Geprüft wird das alles von `tests/bash/npm-publish.test.sh --run`: Das Script
läuft dort als Prozess über seinen öffentlichen Aufruf gegen eine
`npm`-Attrappe. Jede Grenze hat ihren eigenen Fall, und jeder wurde
gegen einen Mutanten geprüft, der die Korrektur zurückdreht.

Die TTY-Zusage läuft dabei unter einem **echten PTY** (`script -q /dev/null`,
mit Rückfall auf die GNU-Form). Das ist kein Selbstzweck: Im umgeleiteten
Testharness sieht die Attrappe grundsätzlich kein TTY, egal was das Script
tut — die schwächere Frage „kommt npms Ausgabe beim Aufrufer an?" beantwortet
auch eine `tee`-Pipeline mit ja, während npm trotzdem kein TTY sähe. Genau
dieser Mutant fällt unter dem PTY auf und nur dort. Geprüft werden dabei
**beide** Deskriptoren (`-t 0 && -t 1`): npm sieht auch dann kein TTY, wenn nur
stdin abgeklemmt ist.

Pythons `pty.spawn` wäre der naheliegende Weg gewesen und liefert auch ein
korrektes PTY — kehrt auf macOS aber nach dem Kindprozess nicht aus seiner
Kopierschleife zurück und hängt den Testlauf auf.


### `dockerhub-readme.sh` — README nach Docker Hub übertragen

`src/bash/dockerhub-readme.sh` delegiert an den gemeinsamen `py-run.sh`, der
eine eigene Werkzeug-`.venv` vorbereitet und anschließend startet:
`src/python/dockerhub-readme.py`. Das Python-Script konvertiert relative Markdown-Bild- und
Dokumentlinks in absolute GitHub-URLs und aktualisiert die Repository-Übersicht.
Python 3.11+ und Pandoc müssen vorhanden sein. Der Bash-Einstieg legt
`${XDG_CACHE_HOME:-$HOME/.cache}/projecttools/dockerhub-readme/.venv`
bei Bedarf an und installiert fehlende Pakete gemäß
`src/python/dockerhub-readme.requirements.txt`; fehlendes pip ergänzt er über
ensurepip. Passende Umgebungen werden ohne Installation wiederverwendet.
`PYTHON_BOOTSTRAP` überschreibt die automatische Auswahl eines installierten
Python ab 3.11. Die Projekt-`.venv` bleibt unberührt; Symlinks am Werkzeug-
verzeichnis oder an dessen `.venv` sind gesperrt. Ohne Argumente
erscheint die Hilfe, ohne die Umgebung zu verändern.

```bash
./.libs/ProjectTools/src/bash/dockerhub-readme.sh \
  --preview
./.libs/ProjectTools/src/bash/dockerhub-readme.sh \
  --publish
```

`--project-dir` wählt das Verbraucherprojekt (Vorgabe: Arbeitsverzeichnis),
`--readme` dessen Quelldatei (Vorgabe: `docker/README.md`). `--ref` nennt einen bereits veröffentlichten GitHub-Branch oder Commit;
Vorgabe ist `master`.
`--github-repository owner/repository` überschreibt die Ermittlung aus `origin`.
Die Quelle ist eine eigene Beschreibung für Container-Nutzer. Fehlt sie, bricht
das Script ab; es fällt nicht auf das Projekt-README zurück. Für eine andere
Quelle `--readme` verwenden. Bilder etwa mit `../images/example.png` relativ
zu `docker/README.md` verlinken; sie werden aus dem GitHub-Repository geladen.
Auch Links aus READMEs in Unterverzeichnissen werden relativ zur Quelldatei
aufgelöst. Raw-HTML-Links werden nicht umgeschrieben; dafür absolute URLs verwenden.

Das Docker-Hub-Ziel wird aus `DOCKERHUB_REPOSITORY`, sonst aus `IMAGE_NAME`
(Umgebung/Makefile) und `NAMESPACE` + `NAME` in `docker/build.sh` ermittelt.
Es werden nur literale Zuweisungen gelesen; kein Buildscript wird ausgeführt.
Widersprüchliche oder fehlende Werte erfordern `--repository namespace/name`.
Dieser explizite Parameter hat Vorrang. Tags und Docker-Hub-Registrypräfixe
werden entfernt; fremde Registries werden abgewiesen.

Die Vorschau schreibt `docker/preview/README.md` ins Verbraucherprojekt;
`--output` überschreibt den Pfad. Sie benötigt keinen Docker-Hub-Token; die erstmalige Paketinstallation kann
Netz benötigen.
Der Upload liest den Token aus `--token-file`, sonst `DOCKER_PW_FILE`, sonst
`${DOCKER_CONFIG:-$HOME/.docker}/dockerhub.sec`. Der Docker-Hub-Benutzer ist
standardmäßig der Namespace; für Organisationen `--username` angeben.
Ein Personal Access Token braucht die Berechtigung zum Ändern der Beschreibung
(Read, Write, Delete). Zugangsdaten werden nur an Docker Hub gesendet, nicht
protokolliert oder als Prozessargumente weitergereicht.

`--description` setzt optional die Kurzbeschreibung. Sonst bleibt sie erhalten.
Nach dem Upload liest das Script die gespeicherten Werte zur Kontrolle zurück.
Nach erfolgreicher Kontrolle zeigt es die vollständige Repository-URL,
z. B. `https://hub.docker.com/r/mangolila/stockinfo`, zum Öffnen im Browser.
Vor venv/pip prüft das Script das lesbare README und bei `--publish` zusätzlich
die lesbare, nicht leere Token-Datei. Gültigkeit und Schreibrechte bestätigt
erst Docker Hub beim Auth-/PATCH-Aufruf. Die konvertierte Fassung darf höchstens 25.000 UTF-8-Bytes umfassen. Bei
Überschreitung endet schon die Vorschau mit Fehler; es wird nichts abgeschnitten.
Markdown wird mit Pandoc neu formatiert; das Quell-README bleibt unverändert.

Ein Verbraucher ruft das Script erst nach erfolgreichem Docker-Hub-Image-Push
auf und übernimmt den Exit-Code. Andere Registries überspringen den Aufruf.
`DOCKER_README_AFTER_PUSH=1` ergänzt bei einem Uploadfehler den Hinweis, dass
das Image bereits veröffentlicht wurde. Der Upload kann separat wiederholt werden.

Tests: `<verbraucher>/.venv/bin/python -m pytest tests/python/`.
Die Bootstrap-Tests installieren in echte temporäre venvs. Für Offline-Tests
vorher Wheels herunterladen und `PIP_NO_INDEX=1 PIP_FIND_LINKS=<wheel-ordner>` setzen.
Deutscher gettext-Katalog: `src/python/locales/de/LC_MESSAGES/dockerhub_readme.po`;
nach Textänderungen mit `msgfmt <datei.po> -o <datei.mo>` neu übersetzen.


### `changelog.py` — Release-Historie aus Git

Der gemeinsame Generator schreibt `CHANGELOG.md` aus den Release-Tags und
Conventional Commits des aufrufenden Repositorys. Er braucht Git und
Python 3.9+, verwendet ausschließlich die Standardbibliothek und startet direkt.
Es gibt keinen Bash-Wrapper, keine Paketinstallation und keine eigene venv.
Das ist Mikes ausdrückliche Ausnahme von der Python-Bootstrap-Vorgabe für
dieses Werkzeug (2026-09-27). Ohne Argumente oder mit `--help` erscheint nur Hilfe.

```bash
python3 "${PROJECT_TOOLS}/python/changelog.py" --help
python3 "${PROJECT_TOOLS}/python/changelog.py" --dry-run
python3 "${PROJECT_TOOLS}/python/changelog.py" --generate
python3 "${PROJECT_TOOLS}/python/changelog.py" --publish
```

`-g/--generate` schreibt die Datei, `-n/--dry-run` zeigt sie nur,
`-p/--publish` schreibt, committet ausschließlich diese Datei und pusht den
aktuellen Branch über dessen Upstream. `-o/--output` wählt eine andere Datei
innerhalb des Arbeitsbaums. Ein wiederholter Publish pusht erneut, erzeugt
aber bei identischem Inhalt keinen neuen Commit. Fremde Änderungen an
versionierten Dateien und ein gefüllter Git-Index verhindern Publish.
Die generierte Ausgabedatei darf dabei bereits lokal geändert sein.

Die vollständige Git-Historie muss lokal vorhanden sein; fehlende Tags bei
Bedarf mit `git fetch --tags` holen. Verarbeitet werden SemVer-Tags, auch mit
Build-Metadaten, auf der First-Parent-Historie des aktuellen Branches.
Feature-Branch-Tags werden nicht zu Releases des Hauptbranches. Die Commits
eingemergter Branches erscheinen im nächsten Hauptbranch-Release genau einmal.
Noch nicht getaggte Änderungen fehlen bewusst.

Gruppen: inkompatible Änderungen, Funktionen, Fehlerkorrekturen,
Geschwindigkeit, weitere Änderungen und Dokumentation. Interne Scopes
`tickets`, `activity`, `lessons`, `changelog` sowie normale `chore`, `test`,
`ci` und Merge-Commits entfallen. Reine Änderungen unter `_tickets/` oder
in Agenten-Regeldateien entfallen auch bei anderen Scopes. Nicht konventionelle
Commit-Titel werden nicht interpretiert. Gemischte Commits mit Änderungen an
Produktanleitungen können erscheinen; der Generator bewertet Texte nicht
semantisch. Annotierte Tag-Nachrichten liefern die Release-Kurztexte;
leichtgewichtige Tags erhalten keinen erfundenen Kurztext. Manuelle Änderungen
an der generierten Datei werden überschrieben. CLI und Überschriften verwenden
gettext (Deutsch/Englisch); `LANGUAGE=en` erzeugt ein englisches Dokument,
die ursprünglichen Commit- und Tag-Texte bleiben unverändert.

Die Hilfe verwendet die native Parser-Optionsliste mit festen, großzügigen
Spalten. Optionen und Abschnittstitel sind hellblau, Platzhalter wie `OUTPUT`
gelb und Beispiele grün. Erfolgsmeldungen sind grün, Fehler rot, jeweils mit
Symbol. Die Farben entsprechen der BashLib-Palette; ein Bash-Start ist dafür
nicht nötig. `NO_COLOR`, `TERM=dumb` und umgeleitete Ausgaben deaktivieren Farben.

Die Einbindung erfolgt direkt im konsumierenden Makefile: nach erfolgreichem
`semVerBump` das Script mit `--publish` aufrufen. Die BashLib bleibt unverändert.
Der Changelog-Commit liegt damit nach dem Release-Tag. Scheitert dieser Schritt,
bleibt das Release bestehen; nur `--publish` wiederholen, nicht erneut bumpen.
Ein abgebrochener Commit kann einen gestagten Changelog hinterlassen: Ursache
beheben und den Commit gezielt abschließen, bevor Publish erneut startet.

Prüfung: `python -m unittest discover -s tests/python -p test_changelog.py -v`
aus einer aktivierten Testumgebung. Die Tests verwenden temporäre
Git-Repositories und lokale Remotes, ohne Netzwerk oder echte Releases.

### `py-run.sh` — Python-Werkzeuge starten

```bash
./src/bash/py-run.sh --help
./src/bash/py-run.sh --list
./src/bash/py-run.sh --run changelog --dry-run
./src/bash/py-run.sh --run dockerhub-readme --preview
```

`-l`/`--list` findet direkt ausführbare Python-Skripte unter `src/python/`,
ohne sie zu importieren. Bibliotheksmodule und der Runner selbst fehlen in der
Liste. `-r`/`--run SCRIPT` übernimmt Namen mit oder ohne `.py`; alle folgenden
Argumente, auch `--help`, gehören dem ausgewählten Skript. Unbekannte Skripte
und Runner-Argumente enden mit Status 2. Der Exit-Code des Werkzeugs bleibt erhalten.
Ohne Argumente erscheint die Hilfe. Hilfe und Liste installieren nichts.

Der Runner benötigt Python ab 3.11; `PYTHON_BOOTSTRAP` wählt den Interpreter.
Changelog bleibt unabhängig davon direkt mit Python ab 3.9 ausführbar und
benötigt keine venv. Reine Standardbibliothek wird auch über den Runner direkt
gestartet. Benötigt ein Werkzeug Pakete, stehen sie einmalig in der benachbarten
`<name>.requirements.txt`. Der Runner verwaltet dafür ausschließlich
`${XDG_CACHE_HOME:-$HOME/.cache}/projecttools/<name>/.venv`; die Projektumgebung
bleibt unberührt. Erstinstallation kann Netzwerk benötigen. Wiederholte Aufrufe
verwenden die fertige Umgebung. Geänderte Requirements lösen eine Installation
aus; fehlende exakt gepinnte Pakete und defekte Abhängigkeiten werden erkannt.

Neue paketabhängige Skripte halten Hilfe und Parser frei von optionalen Imports.
Eine Funktion `prepare_cli(arguments)` prüft bei Bedarf Argumente, lokale Dateien
und externe Programme, bevor der Runner die venv anlegt. Erwartete Fehler werden
vom Werkzeug übersetzt gemeldet und beenden mit nonzero. Diese Funktion führt
keine Fachaktion aus. Für weitere Werkzeuge wird kein Bootstrap kopiert.

Der bisherige `dockerhub-readme.sh` bleibt als kompatibler Alias erhalten.
Seine gesamte Umgebungseinrichtung liegt im gemeinsamen Runner.

## CLI-Themes und Abstände

Die drei eigenständigen Dateien MakeLib `colours.mk`, BashLib
`src/colors.lib.sh` und ProjectTools `src/python/colors.py` verwenden dieselbe
Palette und Theme-Auswahl: `classic` (Standard), `ocean`, `earth`, `night`,
`mono`, `sunset`, `forest`, `neon`, `shell`. Ein unbekannter Name verwendet
`classic`. Die Auswahl kann wie bisher in der jeweiligen Datei umgestellt
oder mit `MAKE_THEME` überschrieben werden. Es gibt keine generierte Datei.
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
geben Beschreibungstexte wie bisher unverändert aus. Einrückungen sind weiterhin
**Leerzeichenketten**, Breiten und Abstände nichtnegative Zahlen. Einzelne
Werte vor dem Include/Source beziehungsweise per Umgebung überschreiben.

`THEME_COLOR_GROUP`, `TARGET`, `DESC`, `SERVER`, `DANGER` (jeweils mit dem Präfix
`THEME_COLOR_`) behalten ihre Namen. Hinzu kommen `THEME_COLOR_SUCCESS` und
`THEME_COLOR_WARNING`. Grundfarben und die bisherigen öffentlichen Makros,
Bash-Funktionen und Argumente bleiben verfügbar. Die Standarddarstellung der
Ausgabehelfer folgt jetzt dem gemeinsamen Theme.

Die neuen Bash-/Python-Helfer geben in Pipes, bei `NO_COLOR` und `TERM=dumb`
keine ANSI-Farben aus. Make berücksichtigt `NO_COLOR` und behält seine bisherige
TERM-basierte Farberkennung. Bash-Grundkonstanten bleiben aus Kompatibilität
unveränderte Escape-Strings für `printf '%b'` oder `echo -e`.

Python verwendet `from colors import HelpFormatter, Theme`; der Formatter
liest die Optionen aus argparse. `Theme().line(label, description)` formatiert
eine einzelne Zeile. `styled(text, color, stream)` bleibt für vorhandene
Python-Farbaufrufe und `PROJECTTOOLS_COLOR_*` verfügbar.

Repositoryübergreifender Vergleich aller neun Themes und alter Schnittstellen:

```bash
THEME_MAKE_LIB=/path/to/MakeLib BASH_LIBS=/path/to/BashLib/src \
  python3 -m pytest tests/python/test_cli_themes.py
```
