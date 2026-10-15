# pkg-link.sh — npm-Paket lokal oder aus der Registry

[← README](../../README.md)

Wird an einem geteilten Paket und einer App gleichzeitig gearbeitet, muss die
App das lokale Repo sehen, sonst lässt sich vor dem Veröffentlichen nichts
prüfen. Danach muss sie zurück auf die Registry-Fassung. `pkg-link.sh`
schaltet zwischen beidem um, für beliebige Apps und Pakete.

Voraussetzungen: BashLib; `jq`, damit `--example` lokale Repos vorschlägt.

## Übersicht

- [Aufruf](#aufruf)
- [Sicher umschalten](#sicher-umschalten)
- [Format `.pkg-link.conf.sh`](#format-pkg-linkconfsh)

## Aufruf

Im Projekt-Root:

```bash
pkg-link.sh --status                          # woher kommt gerade welches Paket?
pkg-link.sh --link @mmit/ux-foundation        # auf das lokale Repo
pkg-link.sh --unlink --all                    # alles zurück auf die Registry
pkg-link.sh --example > .pkg-link.conf.sh     # Starter-Config (erkennt Pakete)
```

`--example` schlägt jede Abhängigkeit vor, zu der unter
`${DEV_LOCAL}/DevWeb/Production/` ein gleichnamiges Repo liegt.

Nach jedem Umschalten wird `node_modules/.vite` geleert. Sonst liefert der
Dev-Server die vorab optimierte alte Fassung weiter aus, und der Fehler sieht
wie ein fehlender Export aus.

[↑ Übersicht](#übersicht)

## Sicher umschalten

Beim Umschalten von Hand ist genau das schiefgegangen, was das Skript
verhindert: Ein `mv` folgte einem noch bestehenden Symlink und legte die
Sicherung **im fremden Repo** ab; ein interaktives `rm -i`-Alias ließ den
Rückbau still scheitern.

Deshalb laufen alle Dateioperationen über `removeSymlink()` und
`movePathSafely()`. Sie prüfen vorher, dass das Ziel in keiner Form belegt ist
und sein Elternverzeichnis kein Symlink ist. Sicherungen tragen die Endung
`.pkg-link-backup`.

[↑ Übersicht](#übersicht)

## Format `.pkg-link.conf.sh`

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

Der Pfad darf Variablen enthalten, weil die Config gesourct wird. So bleibt
sie auf jedem Rechner gültig.

[↑ Übersicht](#übersicht)
