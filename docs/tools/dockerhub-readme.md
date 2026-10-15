# dockerhub-readme.sh — README nach Docker Hub übertragen

[← README](../../README.md)

`dockerhub-readme.sh` überträgt die Container-Beschreibung eines Projekts
(Vorgabe `docker/README.md`) in die Repository-Übersicht auf Docker Hub.
Relative Bild- und Dokumentlinks werden dabei zu absoluten GitHub-URLs; das
Quell-README bleibt unverändert.

Voraussetzungen: Python 3.11+ und Pandoc. Die Pakete richtet
[py-run.sh](py-run.md) beim ersten Aufruf in einer eigenen Werkzeug-venv ein;
dafür kann Netz nötig sein.

## Übersicht

- [Aufruf](#aufruf)
- [Quelle und Ziel](#quelle-und-ziel)
- [Upload und Zugangsdaten](#upload-und-zugangsdaten)
- [Einbindung nach dem Image-Push](#einbindung-nach-dem-image-push)

## Aufruf

Im Verbraucherprojekt:

```bash
./.libs/ProjectTools/src/bash/dockerhub-readme.sh --preview
./.libs/ProjectTools/src/bash/dockerhub-readme.sh --publish
```

Ohne Argumente erscheint die Hilfe, ohne die Umgebung zu verändern. Den Link
direkt ausführen, nicht mit `bash dockerhub-readme.sh`: Sein Ziel ist ein
Python-Skript.

Die Vorschau schreibt `docker/preview/README.md` ins Verbraucherprojekt;
`--output` wählt einen anderen Pfad. Sie braucht keinen Docker-Hub-Token.

[↑ Übersicht](#übersicht)

## Quelle und Ziel

- **`--project-dir`** wählt das Verbraucherprojekt (Vorgabe:
  Arbeitsverzeichnis), **`--readme`** dessen Quelldatei (Vorgabe:
  `docker/README.md`).  
  Fehlt die Quelle, bricht das Skript ab; es fällt nicht auf das
  Projekt-README zurück.
- **`--ref`** nennt einen bereits veröffentlichten GitHub-Branch oder Commit
  (Vorgabe `master`), **`--github-repository owner/repository`** überschreibt
  die Ermittlung aus `origin`.
- **Bilder und Links** relativ zur Quelldatei angeben, etwa
  `../images/example.png` aus `docker/README.md`. Sie werden aus dem
  GitHub-Repository geladen. Raw-HTML-Links werden nicht umgeschrieben; dafür
  absolute URLs verwenden.
- **Docker-Hub-Ziel:** aus `DOCKERHUB_REPOSITORY`, sonst aus `IMAGE_NAME`
  (Umgebung oder Makefile) und `NAMESPACE` + `NAME` in `docker/build.sh`.  
  Gelesen werden nur literale Zuweisungen; kein Buildskript wird ausgeführt.
  Bei widersprüchlichen oder fehlenden Werten `--repository namespace/name`
  angeben; dieser Parameter hat Vorrang. Fremde Registries werden abgewiesen.

Die konvertierte Fassung darf höchstens 25.000 UTF-8-Bytes umfassen. Ist sie
größer, endet schon die Vorschau mit Fehler; abgeschnitten wird nichts.

[↑ Übersicht](#übersicht)

## Upload und Zugangsdaten

Der Upload liest den Token aus `--token-file`, sonst aus `DOCKER_PW_FILE`,
sonst aus `${DOCKER_CONFIG:-$HOME/.docker}/dockerhub.sec`. Der Benutzer ist
standardmäßig der Namespace; für Organisationen `--username` angeben. Ein
Personal Access Token braucht die Berechtigung „Read, Write, Delete“.

Zugangsdaten gehen nur an Docker Hub. Sie werden weder protokolliert noch als
Prozessargumente weitergereicht.

`--description` setzt optional die Kurzbeschreibung; sonst bleibt sie
erhalten. Nach dem Upload liest das Skript die gespeicherten Werte zur
Kontrolle zurück und zeigt die Repository-URL zum Öffnen im Browser.

[↑ Übersicht](#übersicht)

## Einbindung nach dem Image-Push

Ein Verbraucher ruft das Skript erst nach einem erfolgreichen Push zu Docker
Hub auf und übernimmt den Exit-Code; bei anderen Registries entfällt der
Aufruf.

`DOCKER_README_AFTER_PUSH=1` ergänzt bei einem Uploadfehler den Hinweis, dass
das Image bereits veröffentlicht ist. Der Upload lässt sich dann separat
wiederholen.

[↑ Übersicht](#übersicht)
