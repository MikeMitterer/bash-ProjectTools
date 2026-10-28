SHELL := bash

.DEFAULT_GOAL := help

WORKSPACE    := $(realpath $(shell pwd))
PROJECT_NAME := $(notdir $(WORKSPACE))

# Dieses Repo ist selbst ProjectTools: Die Targets nehmen immer die Skripte aus
# diesem Checkout, nicht die aus der Umgebung (~/.ci.machine.bashrc). Im
# pre-commit-Hook ist das der vorgemerkte Stand.
PROJECT_TOOLS := $(WORKSPACE)/src

# BashLib: Umgebung, dann .libs/ (make setup), dann der Nachbar im DevBash-Baum
# — derselbe Fallback wie in den Skripten (siehe AGENTS.md).
BASH_LIBS ?= $(or $(wildcard $(WORKSPACE)/.libs/BashLib/src),$(wildcard $(WORKSPACE)/../BashLib/src),$(WORKSPACE)/.libs/BashLib/src)
DEV_MAKE  ?= $(WORKSPACE)/.libs/MakeLib
export BASH_LIBS PROJECT_TOOLS

-include ${DEV_MAKE}/colours.mk
-include ${DEV_MAKE}/tools.mk

# Fallbacks, wenn MakeLib nicht verfügbar ist (frischer Klon ohne .libs/)
YELLOW ?= $(shell printf "\033[38;5;3m")
GREEN  ?= $(shell printf "\033[38;5;2m")
BLUE   ?= $(shell printf "\033[38;5;6m")
RED    ?= $(shell printf "\033[38;5;1m")
WHITE  ?= $(shell printf "\033[38;5;7m")
RESET  ?= $(shell printf "\033[0m")
THEME_COLOR_GROUP   ?= $(YELLOW)
THEME_COLOR_TARGET  ?= $(BLUE)
THEME_COLOR_DESC    ?= $(GREEN)
THEME_COLOR_DANGER  ?= $(RED)
THEME_INDENT_GROUP  ?= $(shell printf '%2s' '')
THEME_INDENT_TARGET ?= $(shell printf '%7s' '')
THEME_WIDTH_TARGET  ?= 22
THEME_COLUMN_GAP    ?= 1
THEME_GROUP_SPACING ?= 1

# Kennzeichnet in der Hilfe Targets, die die private BashLib brauchen. In der
# Target-Beschreibung steht dafür am Ende „— Maintainer“.
MAINTAINER_MARK = $(THEME_COLOR_DANGER)[Maintainer]$(THEME_COLOR_DESC)

# Prüft vor Maintainer-Targets, ob die private BashLib vorhanden ist.
define require_bash_libs
	@test -r "$(BASH_LIBS)/version.lib.sh" || { \
		echo -e "  $(RED)✗$(RESET) Nur für Maintainer: benötigt die private BashLib ($(YELLOW)BASH_LIBS$(RESET))." >&2; \
		exit 1; }
endef

# Interpreter für die Entwicklungs-venv. Die Werkzeuge selbst laufen ab
# Python 3.9; die Tests brauchen eine aktuelle Fassung.
PYTHON_BOOTSTRAP ?= python3.14
VENV := .venv
# Abhängigkeitsdateien der Entwicklungs-venv; requirements-dev.txt bindet die
# des Docker-Hub-Werkzeugs ein. Ist eine neuer als die Stempeldatei, gilt die
# Einrichtung als veraltet.
VENV_REQUIREMENTS := requirements-dev.txt src/python/dockerhub-readme.requirements.txt

# ─── Hilfe ───────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Alle verfügbaren Befehle anzeigen
	@echo
	@echo "Please use \`make <$(THEME_COLOR_GROUP)target$(RESET)>' where <target> is one of"
	@echo
	@echo "Project: $(THEME_COLOR_GROUP)$(PROJECT_NAME)$(RESET)"
	@echo
	@grep -hE '^(##@|[a-zA-Z0-9_-]+:.*?## )' $(MAKEFILE_LIST) | \
	  awk 'function row(label, description) { \
	      sub(/ — Maintainer$$/, " $(MAINTAINER_MARK)", description); \
	      printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%s$(RESET)", label; \
	      padding = $(THEME_WIDTH_TARGET) - length(label) + $(THEME_COLUMN_GAP); \
	      if (length(label) > $(THEME_WIDTH_TARGET)) { printf "\n$(THEME_INDENT_TARGET)"; padding = $(THEME_WIDTH_TARGET) + $(THEME_COLUMN_GAP) }; \
	      printf "%*s$(THEME_COLOR_DESC)%s$(RESET)\n", padding, "", description \
	    }; BEGIN {FS = ":.*## "}; \
	    /^##@/ { for (i=0; i<$(THEME_GROUP_SPACING); i++) printf "\n"; heading=substr($$0, 4); sub(/^[[:space:]]+/, "", heading); printf "$(THEME_INDENT_GROUP)$(THEME_COLOR_GROUP)%s$(RESET)\n", heading; next }; \
	    /## / { row($$1, $$2) }'
	@echo

.PHONY: info
info: ## Umgebungsvariablen anzeigen
	@echo
	@echo "    $(YELLOW)PROJECT_NAME$(RESET)     = $(BLUE)$(PROJECT_NAME)$(RESET)"
	@echo "    $(YELLOW)WORKSPACE$(RESET)        = $(BLUE)$(WORKSPACE)$(RESET)"
	@echo "    $(YELLOW)PROJECT_TOOLS$(RESET)    = $(BLUE)$(PROJECT_TOOLS)$(RESET)"
	@echo "    $(YELLOW)BASH_LIBS$(RESET)        = $(BLUE)$(BASH_LIBS)$(RESET)"
	@echo "    $(YELLOW)DEV_MAKE$(RESET)         = $(BLUE)$(DEV_MAKE)$(RESET)"
	@echo "    $(YELLOW)PYTHON_BOOTSTRAP$(RESET) = $(BLUE)$(PYTHON_BOOTSTRAP)$(RESET)"
	@echo

.PHONY: hints
hints: ## Nützliche Links und Hinweise anzeigen
	@for ((i=0; i<$(THEME_GROUP_SPACING); i++)); do echo; done
	@echo "$(THEME_INDENT_GROUP)$(THEME_COLOR_GROUP)Erster Start$(RESET)"
	@printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%-$(THEME_WIDTH_TARGET)s$(RESET)%$(THEME_COLUMN_GAP)s$(THEME_COLOR_DESC)%s$(RESET)\n" "1. Setup" "" "make setup"
	@printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%-$(THEME_WIDTH_TARGET)s$(RESET)%$(THEME_COLUMN_GAP)s$(THEME_COLOR_DESC)%s$(RESET)\n" "2. Prüfen" "" "make test && make lint"
	@for ((i=0; i<$(THEME_GROUP_SPACING); i++)); do echo; done
	@echo "$(THEME_INDENT_GROUP)$(THEME_COLOR_GROUP)Konsum in anderen Projekten$(RESET)"
	@printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%-$(THEME_WIDTH_TARGET)s$(RESET)%$(THEME_COLUMN_GAP)s$(THEME_COLOR_DESC)%s$(RESET)\n" "Installieren" "" "pipx install 'git+https://github.com/MikeMitterer/bash-ProjectTools.git@vX.Y.Z'"
	@printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%-$(THEME_WIDTH_TARGET)s$(RESET)%$(THEME_COLUMN_GAP)s$(THEME_COLOR_DESC)%s$(RESET)\n" "Umgebung" "" "PROJECT_TOOLS=$(WORKSPACE)/src"
	@printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%-$(THEME_WIDTH_TARGET)s$(RESET)%$(THEME_COLUMN_GAP)s$(THEME_COLOR_DESC)%s$(RESET)\n" "Projekt-Symlink" "" ".libs/ProjectTools (setup-libs.sh im Projekt)"
	@for ((i=0; i<$(THEME_GROUP_SPACING); i++)); do echo; done
	@echo "$(THEME_INDENT_GROUP)$(THEME_COLOR_GROUP)Links$(RESET)"
	@printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%-$(THEME_WIDTH_TARGET)s$(RESET)%$(THEME_COLUMN_GAP)s$(THEME_COLOR_DESC)%s$(RESET)\n" "GitHub" "" "https://github.com/MikeMitterer/bash-ProjectTools"
	@echo

# ─── Precheck ────────────────────────────────────────────────────────────────

# Ohne `##`: nicht in der Hilfe, läuft aber als Abhängigkeit von status,
# version und tag-*.
.PHONY: precheck
precheck:
	$(require_bash_libs)

# ─── Setup ───────────────────────────────────────────────────────────────────

##@ Setup

# Idempotent: vorhandene Links bleiben; die .venv wird nur neu abgeglichen,
# wenn eine Abhängigkeitsdatei neuer ist als die Stempeldatei.
.PHONY: setup
setup: $(VENV)/.installed ## .libs-Symlinks, Git-Hooks und Python-.venv einrichten
	@if [[ -r "$(BASH_LIBS)/tools.lib.sh" ]]; then \
		./scripts/setup-libs.sh --install; \
	else \
		echo -e "  $(YELLOW)⚠$(RESET) BashLib nicht verfügbar — .libs-Verlinkung übersprungen (nur Maintainer-Targets brauchen sie)"; \
	fi
	@git config core.hooksPath .githooks

# Stempeldatei: nur setup legt sie an. Nicht .venv/bin/python als Ziel nehmen;
# es ist ein Link aufs System-Python und hätte dessen Zeitstempel.
$(VENV)/.installed: $(VENV_REQUIREMENTS)
	@command -v $(PYTHON_BOOTSTRAP) >/dev/null || { echo -e "  $(RED)✗$(RESET) $(PYTHON_BOOTSTRAP) fehlt (PYTHON_BOOTSTRAP=… überschreibt)" >&2; exit 1; }
	@test -x $(VENV)/bin/python || $(PYTHON_BOOTSTRAP) -m venv $(VENV)
	@$(VENV)/bin/python -m pip install -q --disable-pip-version-check -r requirements-dev.txt
	@touch "$@"

# Prüf-Targets richten nichts ein; setup ist der einzige Weg (worktree_setup).
.PHONY: require-setup
require-setup:
	@$(MAKE) --no-print-directory -q $(VENV)/.installed 2>/dev/null || { \
		echo -e "  $(RED)✗$(RESET) Nicht eingerichtet oder veraltet: $(YELLOW)make setup$(RESET)" >&2; \
		exit 1; }

# ─── Status ──────────────────────────────────────────────────────────────────

##@ Status

.PHONY: status
status: precheck ## Git-Status des Repos und offene Blocker-Issues — Maintainer
	@bash "$(PROJECT_TOOLS)/bash/repo-status.sh" --show

# ─── Tests ───────────────────────────────────────────────────────────────────

##@ Tests

.PHONY: test
test: docs-check require-setup test-bash test-deno test-python ## Alle Tests — Doku, Bash, Deno, Python

.PHONY: docs-check
docs-check: ## Nutzerdoku gegen das Projekt prüfen (Links, Befehle, Variablen)
	@if [[ -r "$(PROJECT_TOOLS)/bash/docs-check.sh" ]]; then \
		"$(PROJECT_TOOLS)/bash/docs-check.sh" --run; \
	else \
		echo -e "  $(YELLOW)⚠$(RESET) ProjectTools nicht verfügbar — Doku nicht geprüft"; \
	fi

.PHONY: test-bash
test-bash: ## Bash-Testsuiten (tests/bash) mit der Bash aus dem PATH
	@./scripts/test-bash.sh --run

# Die Skripte müssen auch unter /bin/bash 3.2 (macOS) laufen.
.PHONY: test-bash32
test-bash32: ## Bash-Testsuiten unter /bin/bash 3.2 (macOS)
	@./scripts/test-bash.sh --bash32

.PHONY: test-deno
test-deno: ## Deno-Tests der Doku-Prüfung
	@deno test --allow-read --allow-write --allow-run=git,deno tests/deno/

.PHONY: test-python
test-python: require-setup ## Python-Tests (pytest, .venv aus make setup)  [ARGS="-k name"]
	@$(VENV)/bin/python -m pytest -q tests/python $(ARGS)

# Shellcheck nur für Bash-Skripte: changelog.sh und dockerhub-readme.sh sind
# Links auf den Python-Einstieg py-run.py.
.PHONY: lint
lint: require-setup ## Shellcheck, deno lint und Ruff
	@grep -lE '^#!/usr/bin/env bash' src/bash/*.sh tests/bash/*.sh scripts/*.sh .githooks/* | xargs shellcheck
	@deno lint -q
	@$(VENV)/bin/ruff check -q src/python tests/python
	@echo -e "  $(GREEN)✓$(RESET) Lint sauber"

# Löscht nur Erzeugtes (Caches, Reste von Paket-Builds); .venv und .libs/ bleiben.
.PHONY: clean
clean: ## Test- und Lint-Caches und Build-Reste löschen
	@find src tests -type d \( -name __pycache__ -o -name '*.egg-info' \) -prune -exec rm -rf {} +
	@rm -rf .pytest_cache .ruff_cache build
	@echo -e "  $(GREEN)✓$(RESET) aufgeräumt"

# ─── Versionierung ───────────────────────────────────────────────────────────

# Nach versioning-conventions (templates/versioning.mk): Die Version steht in
# pyproject.toml; lesen und erhöhen nur über BashLib (readProjectVersion,
# semVerBump).

##@ Versionierung

.PHONY: version
version: precheck ## Aktuelle Version anzeigen (Versionsdatei + git tag) — Maintainer
	@echo
	@VER=$$(source "$${BASH_LIBS}/version.lib.sh" 2>/dev/null && readProjectVersion 2>/dev/null); \
	 [[ -z "$$VER" ]] && VER='nicht gesetzt'; \
	 TAG=$$(git describe --tags --abbrev=0 2>/dev/null || echo 'kein Tag'); \
	 echo "    $(YELLOW)version$(RESET)      = $(BLUE)$$VER$(RESET)"; \
	 echo "    $(YELLOW)git tag$(RESET)      = $(BLUE)$$TAG$(RESET)"
	@echo

.PHONY: tags
tags: ## Letzte 10 Tags mit Message anzeigen
	@echo
	@git tag --sort=-version:refname -n1 | head -10 | \
	  awk '{printf "    $(BLUE)%-28s$(RESET) $(GREEN)%s$(RESET)\n", $$1, substr($$0, index($$0,$$2))}'
	@echo

.PHONY: tag-major
tag-major: precheck ## Version committen, taggen UND pushen — Major (X.y.z → X+1.0.0)  [MSG="..."] — Maintainer
	source "$${BASH_LIBS}/version.lib.sh" && semVerBump major auto "" "$${MSG:-}"

.PHONY: tag-minor
tag-minor: precheck ## Version committen, taggen UND pushen — Minor (x.Y.z → x.Y+1.0)  [MSG="..."] — Maintainer
	source "$${BASH_LIBS}/version.lib.sh" && semVerBump minor auto "" "$${MSG:-}"

.PHONY: tag-patch
tag-patch: precheck ## Version committen, taggen UND pushen — Patch (x.y.Z → x.y.Z+1)  [MSG="..."] — Maintainer
	source "$${BASH_LIBS}/version.lib.sh" && semVerBump patch auto "" "$${MSG:-}"
