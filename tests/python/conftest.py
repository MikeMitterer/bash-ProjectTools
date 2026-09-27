"""Python-Quellverzeichnis auch für importlib-basierte Modultests verfügbar machen."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src/python"))
