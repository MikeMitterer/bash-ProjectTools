"""Gemeinsame CLI-Farben und Layout; Standardbibliothek, Python 3.9+.

Palette und Themes entsprechen MakeLib/colours.mk und BashLib/colors.lib.sh.
MAKE_THEME auswählbar wie in Make; THEME_* überschreiben einzelne Einstellungen.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import TextIO

# Theme hier auswählen oder beim Aufruf MAKE_THEME=ocean setzen.
DEFAULT_THEME = "classic"
# DEFAULT_THEME = "ocean"
# DEFAULT_THEME = "earth"
# DEFAULT_THEME = "night"
# DEFAULT_THEME = "mono"
# DEFAULT_THEME = "sunset"
# DEFAULT_THEME = "forest"
# DEFAULT_THEME = "neon"
# DEFAULT_THEME = "shell"

PALETTE = {
    "BLACK": 0,
    "RED": 196,
    "GREEN": 10,
    "YELLOW": 11,
    "BLUE": 33,
    "WHITE": 15,
    "ORANGE": 208,
    "BROWN": 94,
    "PURPLE": 164,
    "GREY": 245,
    "DARK_GREY": 245,
    "LIGHT_RED": 203,
    "LIGHT_GREEN": 155,
    "LIGHT_BLUE": 45,
    "LIGHT_PURPLE": 170,
    "LIGHT_CYAN": 123,
    "LIGHT_GRAY": 251,
    "CYAN": 51,
    "STEEL_BLUE": 75,
    "GOLD": 220,
    "CORAL": 203,
    "TAN": 179,
    "OLIVE": 143,
    "AMBER": 208,
    "BRICK": 160,
    "SLATE_BLUE": 111,
    "TEAL": 79,
    "SALMON": 215,
    "HOT_PINK": 197,
    "PINK": 205,
    "CREAM": 223,
    "BRIGHT_RED": 196,
    "DARK_GREEN": 34,
    "LIME": 77,
    "PALE_GREEN": 151,
    "STRAW": 185,
    "TERRACOTTA": 167,
    "MAGENTA": 201,
    "NEON_GREEN": 118,
    "NEON_YELLOW": 226,
}
THEMES = {
    "classic": {
        "GROUP": "YELLOW",
        "TARGET": "BLUE",
        "DESC": "GREEN",
        "SERVER": "ORANGE",
        "DANGER": "RED",
    },
    "ocean": {
        "GROUP": "ORANGE",
        "TARGET": "STEEL_BLUE",
        "DESC": "LIGHT_GREEN",
        "SERVER": "GOLD",
        "DANGER": "CORAL",
    },
    "earth": {
        "GROUP": "ORANGE",
        "TARGET": "TAN",
        "DESC": "OLIVE",
        "SERVER": "AMBER",
        "DANGER": "BRICK",
    },
    "night": {
        "GROUP": "PURPLE",
        "TARGET": "SLATE_BLUE",
        "DESC": "TEAL",
        "SERVER": "SALMON",
        "DANGER": "HOT_PINK",
    },
    "mono": {
        "GROUP": "BOLD+WHITE",
        "TARGET": "WHITE",
        "DESC": "GREY",
        "SERVER": "YELLOW",
        "DANGER": "RED",
    },
    "sunset": {
        "GROUP": "PINK",
        "TARGET": "SALMON",
        "DESC": "CREAM",
        "SERVER": "GOLD",
        "DANGER": "BRIGHT_RED",
    },
    "forest": {
        "GROUP": "DARK_GREEN",
        "TARGET": "LIME",
        "DESC": "PALE_GREEN",
        "SERVER": "STRAW",
        "DANGER": "TERRACOTTA",
    },
    "neon": {
        "GROUP": "MAGENTA",
        "TARGET": "NEON_GREEN",
        "DESC": "NEON_YELLOW",
        "SERVER": "AMBER",
        "DANGER": "BRIGHT_RED",
    },
    "shell": {
        "GROUP": "YELLOW",
        "TARGET": "LIGHT_BLUE",
        "DESC": "LIGHT_GRAY",
        "SERVER": "ORANGE",
        "DANGER": "RED",
    },
}


def number(name: str, default: int, minimum: int = 0) -> int:
    """Begrenzt Layout-Werte; ungültige Eingaben verwenden die Vorgabe."""
    value = os.environ.get(name, str(default))
    return max(minimum, int(value)) if re.fullmatch(r"[0-9]{1,3}", value) else default


def color_code(name: str) -> str:
    """Liefert ANSI-Codes mit den bisherigen Bash-Farbnamen."""
    return "".join(
        "\033[1m" if part == "BOLD" else f"\033[38;5;{PALETTE[part]}m" for part in name.split("+")
    )


class Theme:
    """Liest Theme und Layout beim Aufruf, auch nach geänderter Umgebung."""

    def __init__(self) -> None:
        selected = os.environ.get("MAKE_THEME", DEFAULT_THEME)
        self.name = selected if selected in THEMES else "classic"
        self.indent_group = os.environ.get("THEME_INDENT_GROUP", "  ")
        self.indent_target = os.environ.get("THEME_INDENT_TARGET", "       ")
        self.width_target = number("THEME_WIDTH_TARGET", 22)
        self.column_gap = number("THEME_COLUMN_GAP", 1, 1)
        self.width_help = number("THEME_WIDTH_HELP", 110, 40)
        self.group_spacing = number("THEME_GROUP_SPACING", 1)

    @property
    def description_column(self) -> int:
        """Nullbasierte Position der Beschreibung."""
        return len(self.indent_target) + self.width_target + self.column_gap

    def style(self, text: str, role: str, stream: TextIO | None = None) -> str:
        """Färbt nach Bedeutung; Pipe, NO_COLOR und TERM=dumb bleiben farblos."""
        stream = sys.stdout if stream is None else stream
        if "NO_COLOR" in os.environ or os.environ.get("TERM") == "dumb" or not stream.isatty():
            return text
        roles = dict(
            THEMES[self.name],
            SUCCESS="GREEN",
            VALUE="YELLOW",
            WARNING=THEMES[self.name]["SERVER"],
        )
        prefix = os.environ.get(f"THEME_COLOR_{role}", color_code(roles[role]))
        return f"{prefix}{text}\033[0m" if prefix else text

    def line(self, label: str, description: str, stream: TextIO | None = None) -> str:
        """Richtet wie themeLine in Bash und usageLine in Make zwei Spalten aus."""
        placeholder = re.search(r" ([A-Z][A-Z_]+)$", label)
        if placeholder:
            colored_label = (
                self.style(label[: placeholder.start()], "TARGET", stream)
                + " "
                + self.style(placeholder[1], "VALUE", stream)
            )
        else:
            colored_label = self.style(label, "TARGET", stream)
        prefix = self.indent_target + colored_label
        if len(label) > self.width_target:
            prefix += "\n" + " " * self.description_column
        else:
            prefix += " " * (self.width_target - len(label) + self.column_gap)
        return prefix + self.style(description, "DESC", stream) + "\n"


def styled(text: str, color: str | int, stream: TextIO | None = None) -> str:
    """Kompatibler Einstieg für bisherige Python-Farbnamen und numerische Codes."""
    stream = sys.stdout if stream is None else stream
    if "NO_COLOR" in os.environ or os.environ.get("TERM") == "dumb" or not stream.isatty():
        return text
    if isinstance(color, int):
        prefix = f"\033[38;5;{color}m"
    else:
        prefix = os.environ.get(f"PROJECTTOOLS_COLOR_{color}", color_code(color))
    return f"{prefix}{text}\033[0m" if prefix else text


class HelpFormatter(argparse.RawDescriptionHelpFormatter):
    """Native Parser-Optionen, gemeinsame Spalten und Umbruch vor langen Hilfen."""

    def __init__(self, prog: str, **kwargs: object) -> None:
        self.theme = Theme()
        kwargs.setdefault("width", self.theme.width_help)
        super().__init__(prog, **kwargs)

    def start_section(self, heading: str | None) -> None:
        """Gruppen mit gemeinsamer Einrückung und Theme-Farbe."""
        if heading is not None:
            heading = self.theme.indent_group + self.theme.style(heading, "GROUP")
        super().start_section(heading)

    def _format_action_invocation(self, action: argparse.Action) -> str:
        if not action.option_strings:
            return super()._format_action_invocation(action)
        label = " | ".join(action.option_strings)
        if len(action.option_strings) == 1 and label.startswith("--"):
            label = "     " + label
        if action.nargs != 0:
            if action.nargs == argparse.REMAINDER:
                label += " " + (action.metavar or action.dest.upper()) + " [ARGS ...]"
            else:
                label += " " + self._format_args(action, action.metavar or action.dest.upper())
        return label

    def _format_action(self, action: argparse.Action) -> str:
        label = self._format_action_invocation(action)
        description = self._expand_help(action) if action.help else ""
        width = max(20, self.theme.width_help - self.theme.description_column)
        lines = self._split_lines(description, width) or [""]
        result = self.theme.line(label, lines[0])
        for line in lines[1:]:
            result += " " * self.theme.description_column + self.theme.style(line, "DESC") + "\n"
        for subaction in self._iter_indented_subactions(action):
            result += self._format_action(subaction)
        return result

    def _format_text(self, text: str) -> str:
        result = super()._format_text(text)
        if "\n" not in text:
            return result
        lines = result.splitlines()
        for index, line in enumerate(lines):
            if line.endswith(":") and not line.startswith(" "):
                lines[index] = self.theme.indent_group + self.theme.style(line, "GROUP")
            elif line.startswith("  "):
                lines[index] = self.theme.indent_target + self.theme.style(line.strip(), "SUCCESS")
        return "\n".join(lines) + "\n"

    def format_help(self) -> str:
        """Abstände zwischen Abschnitten aus derselben Theme-Einstellung."""
        text = super().format_help()
        return re.sub(r"\n{2,}", "\n" * (self.theme.group_spacing + 1), text)
