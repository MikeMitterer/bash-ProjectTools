# dev-ports.sh — Ports des Dev-Stacks freigeben

[← README](../../README.md)

Stürzt overmind oder eine App ab, belegen übrig gebliebene Prozesse die Ports
weiter, etwa ein uvicorn-Reloader oder ein Vite-Prozess. `make dev-down`
erreicht sie dann nicht mehr, und der nächste `make dev-up` scheitert mit
„address in use“. `dev-ports.sh` zeigt, wer die Ports belegt, und beendet
diese Prozesse samt Kindprozessen.

Voraussetzung: `lsof`. BashLib ist optional; ohne sie läuft das Skript mit
einfachen Farben. So funktioniert `make dev-down` auch in einem frischen Klon
eines öffentlichen Projekts.

## Übersicht

- [Aufruf](#aufruf)
- [So geht `--kill` vor](#so-geht---kill-vor)
- [Einbindung in `dev-down`](#einbindung-in-dev-down)
- [Format `.dev-ports.conf.sh`](#format-dev-portsconfsh)

## Aufruf

Im Projekt-Root:

```bash
dev-ports.sh --example > .dev-ports.conf.sh   # Ports aus Procfile.dev vorschlagen
dev-ports.sh --status                          # ob und von wem die Ports belegt sind
dev-ports.sh --kill --dry-run                  # zeigen, was beendet würde
dev-ports.sh --kill                            # beenden und prüfen, dass die Ports frei sind
dev-ports.sh --kill --port 8000                # nur ein Port, ohne Config
```

`--kill` lässt sich beliebig oft aufrufen, auch gleichzeitig. Ist nichts mehr
zu tun, meldet es die Ports als frei und endet mit Exit-Code 0.

[↑ Übersicht](#übersicht)

## So geht `--kill` vor

1. **overmind- und tmux-Reste dieses Projekts beenden** und eine verwaiste
   `.overmind.sock` entfernen. Sonst meldet der nächste `make dev-up`
   „Overmind is already running“.  
   overmind anderer Projekte bleibt unberührt. Verwaist ist die Datei, wenn
   niemand eine Verbindung annimmt. Die Prüfung braucht `python3`; fehlt es,
   bleibt die Datei vorsichtshalber liegen.
2. **Je Port die lauschenden Prozesse suchen** (`lsof`).
3. **Nur eigene Prozesse beenden, deren Arbeitsverzeichnis im Projekt liegt.**  
   Andere, etwa Docker oder eine App aus einem anderen Projekt, werden
   gemeldet und laufen weiter. `--any-dir` hebt die Projektgrenze auf;
   Prozesse anderer Benutzer bleiben immer unberührt.
4. **SIGTERM an Prozesse und Kindprozesse,** nach `--timeout` Sekunden
   (Vorgabe 5) SIGKILL.
5. **Danach muss jeder Port frei sein,** sonst endet das Skript mit
   Exit-Code 1.

[↑ Übersicht](#übersicht)

## Einbindung in `dev-down`

```make
dev-down: ## Dev-Stack stoppen und Ports freigeben
	-@overmind quit 2>/dev/null || true
	@"$(PROJECT_TOOLS)/bash/dev-ports.sh" --kill
```

Ein `pkill -f overmind` gehört nicht dazu: Es beendet overmind in allen
Projekten.

[↑ Übersicht](#übersicht)

## Format `.dev-ports.conf.sh`

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2034  # von dev-ports.sh gesourct
PORTS=(5173 8000)
```

`--example` findet nur Ports, die im `Procfile.dev` als `--port N` stehen.
Ports aus App-Konfigurationen, etwa von Vite, trägt man von Hand nach.

[↑ Übersicht](#übersicht)
