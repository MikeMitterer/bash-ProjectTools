# npm-publish.sh — npm-Paket veröffentlichen

[← README](../../README.md)

`npm-publish.sh` ersetzt das bloße `npm publish` überall dort, wo
veröffentlicht wird: anmelden, prüfen, hochladen, nachsehen. Es braucht keine
Config.

Voraussetzungen: BashLib und `npm`.

## Übersicht

- [Aufruf](#aufruf)
- [Drei Fallen, die das Skript abräumt](#drei-fallen-die-das-skript-abräumt)
- [Grenzen](#grenzen)

## Aufruf

- **`--publish`** ist der ganze Vorgang.
- **`--ensure`** stellt nur die Anmeldung sicher, etwa um private
  Abhängigkeiten zu installieren oder in CI.
- **`--status`** berichtet nur und taugt dort, wo kein Browser aufgehen darf.

Die Registry ermittelt das Skript selbst: `publishConfig.registry` schlägt die
Scope-Einstellung, diese die globale.

Einbindung in ein Makefile:

```makefile
publish: ##R Paket veröffentlichen  [CONFIRM=yes]
	@test "$(CONFIRM)" = "yes" || \
	  (echo "${ORANGE}Sicherheitscheck: make $@ CONFIRM=yes${NC}" && exit 1)
	@bash $(PROJECT_TOOLS)/bash/npm-publish.sh --publish $(NPM_ARGS)
```

Was die [Positivliste](#grenzen) erlaubt, geht unverändert an `npm publish`
weiter, deshalb das `$(NPM_ARGS)`:

```bash
make publish CONFIRM=yes NPM_ARGS=--otp=123456
```

[↑ Übersicht](#übersicht)

## Drei Fallen, die das Skript abräumt

1. **Niemand angemeldet.** Die Registry antwortet bei einem **privaten** Paket
   mit `404 Not Found` statt `401`; sie verrät dessen Existenz nicht. Die
   Meldung zeigt dann auf den Paketnamen, und man prüft Scope, Schreibweise und
   `publishConfig`, während bloß der Token abgelaufen ist.
2. **Die Version liegt schon oben.** Das wird vorher und ungecacht geprüft,
   statt hinterher aus einer Fehlermeldung erraten.
3. **`409 Conflict — Failed to save packument`.** Registry-seitig und meist
   vorübergehend; der mitgelieferte Erklärungstext passt fast nie. Das Skript
   sieht nach, ob das Paket trotz des Fehlers oben liegt, und versucht es sonst
   erneut.

[↑ Übersicht](#übersicht)

## Grenzen

Jede dieser Grenzen war einmal eine echte Fehlfunktion.

| Grenze | Warum |
|---|---|
| **stdout des Uploads bleibt unangetastet** | npm bricht seine OTP-Abfrage ab, sobald `stdin` **oder** `stdout` kein TTY ist (npm 11). Ein Einfangen der Ausgabe schaltet die Zwei-Faktor-Anmeldung stumm ab, eine `tee`-Pipeline genauso. Eingefangen wird nur stderr; dort stehen npms Fehlerzeilen ohnehin. |
| **Wiederholt wird nur bei exaktem `E409`** | Die bloße Zeichenfolge `409` steht auch in einem Paketnamen oder einer URL. npm endet bei jedem HTTP-Fehler mit Exit-Code `1`. |
| **„nicht vorhanden“ ≠ „nicht feststellbar“** | Ein Ausfall der Abfrage, eine unlesbare Antwort und ein `E404` sind **kein** sicheres „gibt es nicht“; `E404` heißt bei einem privaten Paket auch „du darfst nicht“. In allen drei Fällen behauptet das Skript weder „ist noch frei“ noch „liegt nicht oben“, und `--status` wird **nicht grün**. |
| **Ein Ziel für alle Schritte** | Ein `--registry` unter den durchgereichten Argumenten verschöbe sonst nur den Upload, während Anmeldung, Vor- und Nachprüfung die alte Registry befragen. Es wird deshalb für alle Schritte übernommen. |
| **Durchgereicht wird eine Positivliste** | `--otp`, `--tag`, `--access`, `--registry`, `--provenance`/`--no-provenance`, jeweils in beiden Schreibweisen. Alles andere wird abgelehnt: `npm publish ./anderes-paket` lud sonst ein anderes Paket hoch als das geprüfte, `--dry-run` gar keines, und beide Male meldete der Wrapper Erfolg. Was hier fehlt, gehört in einen direkten `npm publish`-Aufruf. |
| **Ein Wert darf keine Option sein** | Sonst schluckt eine Wertoption das verbotene Token: Aus `--otp --dry-run` liest npm `otp=--dry-run` und `dry-run=false`, aus dem Trockenlauf wird ein **echter Upload**. Leere `--option=`-Werte werden ebenso abgelehnt. |
| **Keine Wiederholung bei Lifecycle-Skripten** | Jeder neue Versuch startet `npm publish` samt `prepublishOnly`, `prepack`, `prepare`, `postpack`, `publish` und `postpublish` neu. Erklärt die `package.json` einen davon, bricht das Skript nach dem ersten Versuch ab und nennt ihn. |

[↑ Übersicht](#übersicht)
