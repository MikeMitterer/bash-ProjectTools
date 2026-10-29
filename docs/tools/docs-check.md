# docs-check.sh — Dokumentation gegen das Projekt prüfen

[← README](../../README.md)

Dokumentation veraltet still: Ein Target wird umbenannt, ein Ordner zieht um,
eine interne Kennung soll nicht mehr in der Nutzerdoku stehen. Eine Regel in
`AGENTS.md` hilft nur, wenn gerade jemand die betroffene Datei liest.
`docs-check.sh` prüft alle Nutzerdokumente bei jedem Lauf, etwa als Teil von
`make test`.

Voraussetzung: Deno 2; als pipx-Paket installiert (Befehl `docs-check`, siehe
[README](../../README.de.md#schnellstart)) bringt ProjectTools Deno mit. Fehlt
Deno, bricht das Skript mit Exit-Code 1 ab und nennt beide Wege. BashLib ist
optional; ohne sie läuft das Skript mit einfachen Farben.

## Übersicht

- [Was geprüft wird](#was-geprüft-wird)
- [Aufruf](#aufruf)
- [Ausgabe](#ausgabe)
- [Direkter Aufruf der Deno-Prüfung](#direkter-aufruf-der-deno-prüfung)
- [Format `.docs-check.conf.sh`](#format-docs-checkconfsh)
- [Doku-Abgleich zwischen zwei Ständen](#doku-abgleich-zwischen-zwei-ständen---changes-versuch)

## Was geprüft wird

Je Markdown-Datei:

- **Links und Bilder** auf Dateien im Repo, Anker im Dokument und Anker, auf
  die andere Dateien verlinken.
- **Befehle in Code-Formatierung** gegen das Projekt: `make` (je Verzeichnis,
  mit Einbindungen), `npm run`, `deno task`, `uv`/`poetry run`, `cargo run`,
  jeweils in dem Verzeichnis, in dem der Befehl läuft (`cd` im Codeblock,
  `make -C`, `npm --prefix`).
- **Variablen und Repo-Pfade** in Code-Formatierung.
- **Verbotene Begriffe** aus der Config und vergessene Platzhalter.

Dazu, wenn die Config es verlangt: **interne Doku** wie `AGENTS.md` nur auf
tote Links und Anker (`LINKS_ONLY`), ob **Screenshots** älter sind als der
UI-Code, den sie zeigen (`SCREENSHOTS`), ob **abhängige Dateien** wie Übersetzungen oder erzeugte
Vorschauen ihrer Basis gefolgt sind (`DEPENDS`), ob **Sprachfassungen**
gleich gegliedert sind und dieselben Links und denselben Code enthalten
(`TRANSLATIONS`) und ob jede
**Umgebungsvariable, die der Code liest**, in der Doku steht
(`CODE_VARIABLES`).

[↑ Übersicht](#übersicht)

## Aufruf

Im Projekt-Root:

```bash
docs-check.sh --example > .docs-check.conf.sh   # README-Dateien, docs/ und Pflichtdateien vorschlagen
docs-check.sh --run                              # alle Dokumente aus der Config
docs-check.sh --run README.md                    # nur diese Datei
docs-check.sh --ack docs/images/dashboard.png    # angesehen, nichts zu tun
```

[↑ Übersicht](#übersicht)

## Ausgabe

Die Ausgabe nennt zuerst jedes geprüfte Dokument mit seinem Ergebnis und die
ausgenommenen Pfade, dann je Befund Kategorie, Zeilen, was nicht stimmt und
was zu tun ist:

```text
Dokumentprüfung: 4 Dokumente laut .docs-check.conf.sh
Ausgenommen: docs/superpowers, docs/README.template.md

  ? README.md                                1 Hinweis
  ✓ docker/README.md                         in Ordnung
  ✓ unraid/README.md                         in Ordnung
  ✓ docs/stockinfo-integration-proposal.md   in Ordnung

README.md
  Hinweis    Zeilen 27, 66, 115, 136 · 4 farbige Hinweisboxen ([!IMPORTANT], [!NOTE], [!WARNING], [!TIP]); die Config erlaubt höchstens 2 (MAX_ALERTS).
             → Nur die wirklich wichtigen behalten oder MAX_ALERTS in der Config anpassen.

Ergebnis: 4 Dokumente geprüft · keine Probleme · 1 Hinweis zum Ansehen
Hinweise sind keine Fehler, die Prüfung ist bestanden. Ob du etwas änderst, entscheidest du.
```

| Kategorie | Bedeutung |
|---|---|
| **Problem** | Stimmt nicht mit dem Projekt überein; Exit-Code 1 |
| **Hinweis** | Kann stimmen, ein Mensch entscheidet; kein Fehler, Exit-Code bleibt 0 |
| **Ungeprüft** | Befehle eines Ökosystems, das das Skript nicht prüft (Go, Maven, Gradle u. a.) |
| **Info** | Nur mit `--verbose`: Zahlenangaben und externe URLs zum Gegenprüfen |

[↑ Übersicht](#übersicht)

## Direkter Aufruf der Deno-Prüfung

Die Prüfung macht `src/deno/docs-check.ts` (Deno 2), nur lesend, nur `git`,
ohne Netz. Projektfakten liest sie nur aus versionierten Dateien und nie aus
Dateien mit Zugangsdaten (`.env` außer Beispieldateien, Schlüssel, Secrets,
Token u. a.), auch nicht über Makefile-Einbindungen. Agenten rufen sie auch
direkt auf, etwa der Skill `docs-conventions` für einen Entwurf an anderer
Stelle:

```bash
deno run --allow-read --allow-run=git src/deno/docs-check.ts --as README.md /pfad/zum/entwurf.md
```

[↑ Übersicht](#übersicht)

## Format `.docs-check.conf.sh`

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2034  # von docs-check.sh gesourct

# ─── Welche Dokumente geprüft werden ───────────────────────────────────────────

# Inhaltlich zu prüfende Dokumente: Datei, Ordner (alle *.md darin) oder Muster.
DOCS=(
    "README.md"
    "docker/README.md"
    "docs"
    "**/fixtures/**/README.md"
)

# Nur auf Links, Bilder und Anker geprüft (interne Doku).
LINKS_ONLY=(
    "AGENTS.md"
    "_tickets/README.md"
)

# Aus DOCS und LINKS_ONLY ausgenommen: Datei, Ordner samt Inhalt oder Muster.
EXCLUDE=(
    "docs/superpowers"
    "docs/**/draft-*.md"
)

# ─── Was in den Dokumenten stehen darf ─────────────────────────────────────────

# Text oder regulärer Ausdruck, je optional mit "|<grund>".
# Ein Eintrag je Zusammenhang, damit jeder seinen eigenen Grund hat.
FORBIDDEN=(
    # Interne Umgebungsvariablen, in jeder Schreibweise
    "/\bP(U|G)ID\b/i|interne Variablen, nicht in Nutzerdoku"
    # Standardnutzer als Zahl und als Name
    "/\b99:100\b|\bnobody:users\b/i|Standard-IDs, nicht in Nutzerdoku"
)

# Optional: höchstens so viele farbige Hinweisboxen je Dokument.
MAX_ALERTS=2

# ─── Variablen zwischen Doku und Code ──────────────────────────────────────────

# Variablen, die keine versionierte Datei nennt, je optional mit "|<grund>".
KNOWN_VARIABLES=(
    "NO_COLOR|Standard der Kommandozeile, schaltet Farben ab"
)

# Make-Targets, die kein Makefile im Projekt enthält, je optional mit "|<grund>".
KNOWN_MAKE_TARGETS=(
    "dev-up|aus MakeLib, über .libs/MakeLib eingebunden"
)

# Optional: Code, dessen gelesene Umgebungsvariablen dokumentiert sein müssen.
CODE_VARIABLES=(
    "api/src"
    "docker"
)

# Vom Code gelesen, bewusst nicht dokumentiert, je mit "|<grund>".
INTERNAL_VARIABLES=(
    "DEBUG_SQL|nur für die Fehlersuche im Code"
)

# ─── Dateien, die es geben muss ────────────────────────────────────────────────

# Dateien, die es geben muss, je optional mit "|<grund>".
REQUIRED=(
    "LICENSE"                                # ohne "/": irgendwo im Projekt
    "./README.md"                            # mit "/": genau dort
    "docs/user-guide.md|im README verlinkt"
    "./docs/**/*-design.md"                  # Muster: mindestens ein Treffer
)

# ─── Abhängige Dateien und Screenshots ─────────────────────────────────────────

# Optional: Screenshots und der UI-Code, den sie zeigen, je
# "<ui-code>|<bilder>|<grund>"; UI-Code mit Komma für mehrere Pfade.
SCREENSHOTS=(
    "frontend/src/views,frontend/src/components|docs/images|Oberfläche"
)
# Optional: Bilder aus SCREENSHOTS ohne Altersprüfung, nur auf Vorhandensein geprüft.
SCREENSHOTS_EXCLUDE=(
    "docs/images/logo.png"
    "docs/images/diagrams"
)

# Optional: abhängige Dateien, je "<basis>|<abhängig>|<tage>|<grund>".
DEPENDS=(
    "docker/README.md|docker/preview/README.md|0|erzeugt"
    "README.md|README.de.md|3|deutsche Fassung"
)
# Gleiches Format, auch überfällig nur ein Hinweis.
DEPENDS_HINT=(
    "frontend/src/i18n|docs/user-guide.md|30|Bedienelemente im Wortlaut der App"
)

# Optional: Sprachfassungen, je "<original>|<übersetzung>|<grund>".
TRANSLATIONS=(
    "README.md|README.de.md|deutsche Fassung"
)
```

**Pfade und Muster (`DOCS`, `LINKS_ONLY`, `EXCLUDE`, `REQUIRED`, `SCREENSHOTS`, `SCREENSHOTS_EXCLUDE`, `DEPENDS`, `CODE_VARIABLES`):** Pfade gelten ab dem
Projekt-Root, ein führendes `./` ist erlaubt. Muster schreiben sich wie in
`.gitignore`:

| Zeichen | Bedeutung | Beispiel |
|---|---|---|
| `*` | beliebige Zeichen innerhalb eines Ordners | `docs/*.md` |
| `**` | beliebig viele Ordner | `docs/**/*.md`, `**/README.md` |
| `?` | genau ein Zeichen | `docs/v?.md` |

Ordner und Muster in `DOCS` treffen nur Markdown-Dateien, die git nicht
ignoriert, also versionierte und neue, aber keine erzeugten Vorschauen oder
lokalen Notizen. Ein Muster ohne Treffer ist ein Problem. Ein Muster in
`EXCLUDE` darf auch einen Ordner treffen (`docs/drafts-*` schließt alles
darin aus).

**Verbotener Text (`FORBIDDEN`):** Geprüft wird jede Zeile der Dokumente aus
`DOCS`, auch in Codeblöcken; jeder Treffer ist ein Problem. Ein Eintrag hat
eine von zwei Formen, jeweils optional mit `|<grund>`:

- **Text** wie `"PUID"`: genau dieser Text, Groß-/Kleinschreibung zählt. Er
  trifft auch innerhalb von Wörtern, `"UID"` also auch `PUID`.
- **Regulärer Ausdruck** wie `"/\bP(U|G)ID\b/i"`, in JavaScript-Syntax:
  `\b` Wortgrenze, `(a|b)` Alternative, `\d+` Ziffern; Flag `i` für beliebige
  Groß-/Kleinschreibung. Das Muster darf `|` enthalten; es endet am ersten
  `/`, dem nur Flags und dann `|grund` oder das Zeilenende folgen. Ein `/` im
  Muster wird als `\/` geschrieben. Ein ungültiger Ausdruck bricht mit
  Exit-Code 2 ab.

Die Meldung nennt Zeilen, gefundenen Text und Grund. In Bash-Strings mit
doppelten Anführungszeichen bleiben `\b` und `\d` erhalten; `$` und Backticks
brauchen einen Backslash davor.

**Nur Links (`LINKS_ONLY`):** für interne Doku, die verbotene Begriffe,
Make-Targets oder Platzhalter nennen darf, etwa Projektregeln und Tickets.
Geprüft werden nur Links und Bilder auf Dateien im Repo und Anker; ein toter
Link ist ein Problem. Ein veralteter Verweis fällt so nur auf, wenn er als
Markdown-Link geschrieben ist, nicht als Fließtext wie „siehe README,
Abschnitt Setup“. Steht eine Datei auch in `DOCS`, gilt die
vollständige Prüfung.

**Bekannte Variablen (`KNOWN_VARIABLES`):** Eine Variable in
Code-Formatierung, die in keiner versionierten Datei vorkommt, ergibt einen
Hinweis. Stammt sie aus einer eingebundenen, nicht versionierten Bibliothek
(etwa unter `.libs/`) oder ist sie ein allgemeiner Standard wie `NO_COLOR`,
gehört sie hierher, damit derselbe Hinweis nicht bei jedem Lauf wiederkommt.

**Bekannte Make-Targets (`KNOWN_MAKE_TARGETS`):** `make ZIEL` in der Doku
muss im Makefile des Verzeichnisses stehen, in dem der Befehl läuft. Ein
Target aus einer eingebundenen, nicht versionierten Bibliothek (etwa MakeLib
unter `.libs/`) findet die Prüfung dort nicht. Steht es hier, gilt es in jedem
Verzeichnis mit Makefile als vorhanden; alle anderen fehlenden Targets meldet
die Prüfung weiter. Je Eintrag `"TARGET|grund"`, etwa
`"dev-up|aus MakeLib"`.

**Variablen aus dem Code (`CODE_VARIABLES`, `INTERNAL_VARIABLES`):** Die
Gegenrichtung zu den Variablen in der Doku. Jede Umgebungsvariable, die der
Code in diesen Pfaden ausdrücklich liest (`process.env.X`,
`import.meta.env.X`, `Deno.env.get("X")`, `os.environ["X"]`, `getenv("X")`
u. a.), muss in mindestens einem Dokument aus `DOCS` stehen; sonst ist das
ein Problem. So fällt eine neue Variable beim ersten Testlauf auf. Tests und
Zuweisungen (`os.environ["X"] = …`) zählen nicht. Was bewusst nicht in die
Doku gehört, steht mit Grund in `INTERNAL_VARIABLES`; liest der Code einen
solchen Eintrag nicht mehr, gibt es einen Hinweis.

**Grenzwert (`MAX_ALERTS`)** setzt nur das Projekt: Ohne Eintrag prüft das
Skript die Zahl der Hinweisboxen nicht.

**Screenshots (`SCREENSHOTS`):** Ein Eintrag
`"<ui-code>|<bilder>|<grund>"` verbindet Bilder (`.png`, `.jpg`, `.gif`,
`.webp`, `.svg`, ohne von git ignorierte) mit dem Code, den sie zeigen. Der
UI-Code ist eine Datei, ein Ordner oder ein Muster, mehrere mit Komma; welche
Ordner das sind, legt jedes Projekt selbst fest. Hat sich der UI-Code nach
einem Bild geändert, nennt die Ausgabe das Bild als Hinweis; die Prüfung
scheitert daran nicht. Verglichen wird nicht mit dem Tagesdatum: Ein altes
Bild ist richtig, solange sich die Oberfläche nicht geändert hat. Maßgeblich
ist der letzte Commit, uncommittete Änderungen zählen als „jetzt“; das
Dateidatum zählt nicht, weil Klon, Branchwechsel, Merge und Stash es neu
setzen. Ein Eintrag ohne Bild ist ein Problem. Das frühere
`MAX_SCREENSHOT_AGE_DAYS` entfällt; ist es gesetzt, bricht das Skript mit
Exit-Code 2 ab.

**Ausnahmen von der Altersprüfung (`SCREENSHOTS_EXCLUDE`):** Manche Bilder
ändern sich nicht mit dem UI-Code, etwa Logos, Diagramme oder Aufnahmen
fremder Oberflächen. Ein Eintrag nimmt solche Bilder aus `SCREENSHOTS` von der
Altersprüfung aus: Datei, Ordner samt Inhalt oder Muster, geschrieben wie in
`EXCLUDE`. Die Ausgabe führt sie als „vorhanden (ohne Altersprüfung)“, egal wie
alt sie gegenüber dem UI-Code sind; quittieren muss man sie nie. Vorhanden
sein müssen sie weiter: Trifft ein Eintrag kein Bild aus `SCREENSHOTS`, ist
das ein Problem.

**Pflichtdateien (`REQUIRED`):** Ein Eintrag ohne `/` gilt für den Dateinamen
an beliebiger Stelle im Projekt (`README.md` trifft auch `api/README.md`); mit
`/` gilt er ab dem Projekt-Root, `./README.md` meint nur das README im Root.
Eine Datei zählt nur, wenn sie **versioniert** ist (eine Datei nur auf der
Platte fehlt im Repository) und **nicht leer**; eine `.md`-Datei braucht
zusätzlich mindestens eine Überschrift (`# Titel`) außerhalb von Codeblöcken.
Fehlt eine Pflichtdatei, ist das ein Problem. Pflichtdateien,
`LINKS_ONLY`, Screenshots, `DEPENDS`, `TRANSLATIONS` und `CODE_VARIABLES` prüft `--run` nur
ohne Pfadangabe, also beim Lauf über die ganze Config.

**Abhängige Dateien (`DEPENDS`, `DEPENDS_HINT`):** Manche Dateien müssen einer
anderen bald nach deren Änderung folgen, etwa eine Übersetzung ihrem Original
oder eine erzeugte Vorschau ihrer Quelle. Ein Eintrag
`"<basis>|<abhängig>|<tage>|<grund>"` vergleicht die letzten Änderungen beider
Pfade; die Basis darf ein Ordner sein. Die Zeiten kommen aus git wie bei den
Screenshots: Commit-Zeit, uncommittete und gestagte Änderungen zählen als
„jetzt“. Landen beide im selben Commit, ist alles in Ordnung.

| Stand | Ergebnis |
|---|---|
| Abhängige Datei gleich alt oder jünger | in Ordnung |
| Basis jünger, Frist (`<tage>` ab der Basisänderung) läuft noch | Hinweis |
| Basis jünger, Frist vorbei; bei `0` sofort | Problem, bei `DEPENDS_HINT` Hinweis |
| Basis oder abhängige Datei fehlt | Problem |

Die Meldung nennt den Befehl, der die Änderungen der Basis zeigt.

**Sprachfassungen (`TRANSLATIONS`):** `DEPENDS` merkt nur, dass das
Original jünger ist als die Übersetzung, nicht, ob beide noch dasselbe sagen.
Ein Eintrag `"<original>|<übersetzung>|<grund>"` vergleicht deshalb den
Aufbau: dieselbe Folge von Überschriftenebenen und je Abschnitt dieselben
Linkziele und Bilder, denselben Inline-Code, dieselben Codeblöcke, gleich
viele Hinweisboxen, Anker im Dokument und Absätze. Jede Abweichung ist ein
Problem; eine Quittung gibt es dafür nicht.

Was sich übersetzen darf, zählt nicht: Linktexte, Anker im eigenen Dokument
(nur ihre Anzahl), die Sprachzeile mit Links auf die beiden Fassungen und die
Beschriftungen in Mermaid-Diagrammen (nur die Anzahl der Diagramme). Ob der
übersetzte Text dasselbe sagt, prüft das nicht; dafür bleibt `DEPENDS` mit
Frist. Beispiel: Fehlt in `README.de.md` im Abschnitt „Lizenz“ der Link auf
`LICENSING.md`, meldet die Prüfung „Link nur in README.md: LICENSING.md“.

**Quittung (`--ack`):** Nicht jede Änderung der Basis verlangt etwas, etwa
ein Tippfehler im README oder eine Codeänderung, die die Oberfläche nicht
berührt. Wer das geprüft hat, quittiert, statt die abhängige Datei sinnlos
anzufassen:

```bash
docs-check.sh --ack docs/images/dashboard.png   # ein Bild oder eine Datei
docs-check.sh --ack docs/images                 # alle offenen in diesem Ordner
docs-check.sh --ack                             # alle offenen Rückstände
```

Das schreibt je Paar den letzten Commit der Basis nach `.docs-check.ack` im
Projekt-Root (`abhängig|basis|commit|datum`); die Datei wird mitcommittet.
Solange die Basis keinen neueren Commit hat, gilt der Rückstand als erledigt,
auch ein überfälliges `DEPENDS`. Mit dem nächsten Commit der Basis kommt der
Hinweis zurück, und überholte Zeilen fallen beim nächsten `--ack` weg. Nicht
quittieren lassen sich Einträge mit Frist `0` (neu erzeugen statt
quittieren) und uncommittete Basen (erst committen). Die Prüfung darf beim
Quittieren nur diese eine Datei schreiben.

[↑ Übersicht](#übersicht)

## Doku-Abgleich zwischen zwei Ständen (`--changes`, Versuch)

`docs-check.ts --changes BASE[..HEAD]` prüft nicht, sondern sammelt
**Kandidaten** für den Doku-Abgleich einer Änderung: Bezeichner aus den
geänderten Codezeilen (gelesene Umgebungsvariablen, Make-Targets,
npm-Skripte, alte Texte aus den UI-Katalogen, Pfade geänderter Dateien,
`feat`-Commits) und die Stellen in den angegebenen Dokumenten, die sie
nennen. Gelesen wird nur aus git, nicht aus dem Arbeitsbaum; so lässt sich
jeder frühere Merge genauso auswerten wie ein laufender Branch.

```bash
deno run --allow-read --allow-run=git src/deno/docs-check.ts --root . \
    --changes master..HEAD --ui-catalog 'frontend/src/i18n/*.ts' \
    --exclude docs/superpowers README.md docker/README.md docs
```

Je Kandidat nennt die Ausgabe den Status: **offen** (die Doku nennt den
Bezeichner, keine dieser Stellen wurde mitgeändert), **ohne Doku-Stelle**
oder **mitgeändert** (eine Fundstelle liegt höchstens drei Zeilen neben einer
geänderten Zeile). Mit `--json` entsteht dieselbe Liste maschinenlesbar, als
Eingabe für einen Agenten, der je Kandidat entscheidet. Kandidaten sind keine
Fehler; der Exit-Code ist 0. Ob und wie das in `make test` oder den
Ticket-Abschluss kommt, klärt ein Versuch in DocBench.

[↑ Übersicht](#übersicht)
