"""Projektübergreifende Vorgaben und statische Ermittlung des Upload-Ziels."""

import importlib.util
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "src/python/dockerhub-readme.py"
SPEC = importlib.util.spec_from_file_location("dockerhub_defaults", SCRIPT)
upload = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(upload)


@pytest.fixture(autouse=True)
def clean_environment(monkeypatch):
    """Persönliche Image-Einstellungen dürfen Testprojekte nicht beeinflussen."""
    for name in ("DOCKERHUB_REPOSITORY", "IMAGE_NAME"):
        monkeypatch.delenv(name, raising=False)


@pytest.mark.parametrize("name", ["stockinfo", "stockportfolio"])
def test_ziel_aus_buildscript_ohne_ausfuehrung(tmp_path, name):
    (tmp_path / "docker").mkdir()
    (tmp_path / "docker/build.sh").write_text(
        f'readonly NAMESPACE="mangolila"\nreadonly NAME="{name}"\nexit 99\n'
    )
    assert upload.discover_repository(tmp_path) == f"mangolila/{name}"


def test_makefile_und_registry_tag(tmp_path):
    (tmp_path / "Makefile").write_text("IMAGE_NAME ?= docker.io/mangolila/stockinfo:latest\n")
    assert upload.discover_repository(tmp_path) == "mangolila/stockinfo"


def test_umgebungswert_hat_vorrang(tmp_path, monkeypatch):
    (tmp_path / "Makefile").write_text("IMAGE_NAME = other/project\n")
    monkeypatch.setenv("DOCKERHUB_REPOSITORY", "index.docker.io/team/project:latest")
    assert upload.discover_repository(tmp_path) == "team/project"


@pytest.mark.parametrize("value", [None, "ghcr.io/team/project", "$(shell touch sentinel)"])
def test_fehlende_fremde_und_berechnete_ziele_werden_abgewiesen(tmp_path, value):
    if value:
        (tmp_path / "Makefile").write_text(f"IMAGE_NAME = {value}\n")
    with pytest.raises(upload.UploadError, match="--repository"):
        upload.discover_repository(tmp_path)
    assert not (tmp_path / "sentinel").exists()


def test_widerspruch_benoetigt_explizites_ziel(tmp_path, monkeypatch):
    (tmp_path / "Makefile").write_text("IMAGE_NAME = team/project\n")
    monkeypatch.setenv("IMAGE_NAME", "other/project")
    with pytest.raises(upload.UploadError, match="--repository"):
        upload.discover_repository(tmp_path)
    (tmp_path / "README.md").write_text("# Test\n")
    token = tmp_path / "token"
    token.write_text("fake-test-token")
    options = upload.parse_args(
        [
            "--publish",
            "--project-dir",
            str(tmp_path),
            "--repository",
            "explicit/project",
            "--token-file",
            str(token),
        ]
    )
    upload.validate_inputs(options)
    assert options.repository == "explicit/project"


def test_vorgaben_fuer_branch_und_vorschau():
    options = upload.parse_args(["--preview"])
    assert options.ref == "master"
    assert options.output == Path("docker/preview/README.md")
