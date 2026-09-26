"""Lokale README-Konvertierung und die äußere Docker-Hub-HTTP-Grenze."""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import httpx
import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "src/python/dockerhub-readme.py"
SPEC = importlib.util.spec_from_file_location("dockerhub_readme", SCRIPT)
upload = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(upload)


def test_markdown_links_werden_umgeschrieben_code_bleibt_erhalten() -> None:
    """Pandoc liest echte Markdown-Strukturen einschließlich Referenzlinks."""
    source = """# Titel

![Bild](images/chart.png)
[Anleitung](docs/guide.md#setup)
[Datei](<docs/a (b).md>)
[Web](https://example.org/a)
[Mail](mailto:hello@example.org)
[Hier](#titel)
[Referenz][guide]

[guide]: docs/guide.md

`[Code](docs/no.md)`

```markdown
![Code](images/no.png)
```

| Name | Wert |
|---|---|
| Preis | 1 |
"""
    result = upload.prepare_readme(source, "example/project", "master")
    assert "https://raw.githubusercontent.com/example/project/master/images/chart.png" in result
    assert "https://github.com/example/project/blob/master/docs/guide.md#setup" in result
    assert "docs/a%20%28b%29.md" in result
    assert "https://example.org/a" in result
    assert "mailto:hello@example.org" in result
    assert "](#titel)" in result
    assert "`[Code](docs/no.md)`" in result
    assert "![Code](images/no.png)" in result
    assert "|" in result and "Preis" in result


def test_groesse_wird_nach_der_linkerweiterung_geprueft() -> None:
    with pytest.raises(upload.UploadError, match="25000.*AGENTS.md"):
        upload.prepare_readme("ä" * 12501, "owner/repo", "master")


def test_upload_liest_das_ergebnis_zurueck_und_erhaelt_kurzbeschreibung() -> None:
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        assert request.url.host == "hub.docker.com"
        if request.method == "POST":
            assert json.loads(request.content) == {
                "identifier": "user",
                "secret": "private-token",
            }
            return httpx.Response(200, json={"access_token": "bearer-token"})
        if request.method == "PATCH":
            assert request.headers["authorization"] == "Bearer bearer-token"
            assert json.loads(request.content) == {"full_description": "# README"}
            return httpx.Response(200, json={})
        return httpx.Response(200, json={"full_description": "# README"})

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        upload.publish(client, "# README", "owner/repo", "user", "private-token", None)
    assert [request.method for request in calls] == ["POST", "PATCH", "GET"]


@pytest.mark.parametrize("failure", ["login", "patch", "readback"])
def test_fehler_enthalten_keine_geheimnisse(failure: str) -> None:
    """Auch eine Serverantwort, die den Token wiederholt, wird nicht ausgegeben."""

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST":
            return (
                httpx.Response(401, text="private-token")
                if failure == "login"
                else httpx.Response(200, json={"access_token": "private-token"})
            )
        if request.method == "PATCH":
            return httpx.Response(403 if failure == "patch" else 200, text="private-token")
        return httpx.Response(200, json={"full_description": "different"})

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(upload.UploadError) as caught:
            upload.publish(client, "expected", "owner/repo", "user", "private-token", None)
    assert "private-token" not in str(caught.value)


@pytest.mark.parametrize(
    "repository,ref", [("alice/project-one", "main"), ("bob/project-two", "release")]
)
def test_cli_arbeitet_im_angegebenen_projekt(tmp_path: Path, repository: str, ref: str) -> None:
    project = tmp_path / "project"
    (project / "docs").mkdir(parents=True)
    (project / "docs/overview.md").write_text("![Bild](../images/chart.png)\n[Anleitung](guide.md)")
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--preview",
            "--project-dir",
            str(project),
            "--github-repository",
            repository,
            "--ref",
            ref,
            "--readme",
            "docs/overview.md",
            "--token-file",
            str(tmp_path / "missing-token"),
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    content = (project / "docker/preview/README.md").read_text()
    assert f"https://raw.githubusercontent.com/{repository}/{ref}/images/chart.png" in content
    assert f"https://github.com/{repository}/blob/{ref}/docs/guide.md" in content


def test_origin_wird_aus_dem_verbraucherprojekt_gelesen(tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(tmp_path),
            "remote",
            "add",
            "origin",
            "git@github.com:example/consumer.git",
        ],
        check=True,
    )
    assert upload.github_repository(tmp_path) == "example/consumer"


def test_cli_zu_langes_readme_verweist_auf_projektregeln(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("ä" * 12501, encoding="utf-8")
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--preview",
            "--project-dir",
            str(tmp_path),
            "--github-repository",
            "example/project",
            "--ref",
            "main",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert "25000" in result.stderr and "AGENTS.md" in result.stderr
    assert not (tmp_path / "docker/preview/README.md").exists()
