<div align="center">

# ProjectTools

**Shared development scripts for projects in the DevBash ecosystem**

[Tools](#tools) · [Quick start](#quick-start) · [Configuration](#configuration) · [Development](docs/development.md)

English · [Deutsch](README.de.md)

</div>

ProjectTools collects scripts that several projects need in the same way:
repository status, documentation checks, freeing the ports of the dev stack,
switching and publishing npm packages, changelog and Docker Hub description.

Projects install ProjectTools with pipx as a versioned package; the commands
`docs-check`, `repo-status` and `changelog` are then on the PATH. Calling the
scripts directly from a working copy via `PROJECT_TOOLS` remains possible.

| Repo | Purpose | Consumption |
|---|---|---|
| BashLib | Reusable Bash functions | `source` via `BASH_LIBS` |
| BashTools | Tools independent of projects | Deploy to `/usr/local/bin` |
| **ProjectTools** | Project-related development scripts | `pipx install` with a version; otherwise directly via `PROJECT_TOOLS` or the symlink `.libs/ProjectTools` |

## Contents

- [Tools](#tools)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Development](#development)
- [Further documentation](#further-documentation)
- [License](#license)

## Tools

A project composes its Make target `status` and its other targets from these
scripts.

| Script | Purpose | Config |
|---|---|---|
| [`repo-status.sh`](docs/tools/repo-status.md) | Git status of all workspace repos as a table, plus open blocker issues | `.repo-status.conf.sh` |
| [`docs-check.sh`](docs/tools/docs-check.md) | Check user documentation against the project: links, anchors, commands, variables, forbidden terms, screenshots, dependent files | `.docs-check.conf.sh` |
| [`dev-ports.sh`](docs/tools/dev-ports.md) | Show the ports of the dev stack and free them together with their processes | `.dev-ports.conf.sh` |
| [`pkg-link.sh`](docs/tools/pkg-link.md) | Switch an npm package between the local repo and the registry | `.pkg-link.conf.sh` |
| [`npm-publish.sh`](docs/tools/npm-publish.md) | Publish an npm package: log in, check, upload, verify | — |
| [`dockerhub-readme.sh`](docs/tools/dockerhub-readme.md) | Transfer the container README with absolute GitHub links to Docker Hub | Options |
| [`changelog.py`](docs/tools/changelog.md) | `CHANGELOG.md` from release tags and Conventional Commits | Options |
| [`py-run.sh`](docs/tools/py-run.md) | Start Python tools, with their own venv if needed | — |

The Bash scripts live in `src/bash/`, the Python tools in `src/python/`.
`dev-ports.sh` and `docs-check.sh` also run without BashLib; the other Bash
scripts need it.

[↑ Contents](#contents)

## Quick start

Requirements: Bash, Git, Python 3.10 or later and
[pipx](https://pipx.pypa.io/); plus whatever each tool's document lists.

**Install** with a fixed release tag. Tags follow the scheme
`vX.Y.Z+YYMMDD.HHMM.hash`, and pipx needs the
full tag. In a working copy `make hints` shows the latest one; without a
working copy, this command does:

```bash
git ls-remote --tags --refs --sort=-v:refname https://github.com/MikeMitterer/bash-ProjectTools.git | head -1
```

Install with it, replacing `<release-tag>` with the tag:

```bash
pipx install 'git+https://github.com/MikeMitterer/bash-ProjectTools.git@<release-tag>'
projecttools --version
```

Afterwards `docs-check`, `repo-status`, `changelog` and `projecttools` are on
the PATH. The package brings BashLib and Deno as dependencies; it needs
neither `.libs/` nor `PROJECT_TOOLS`. A `BASH_LIBS` that is already set takes
precedence over the bundled BashLib.

**Update:** run `pipx install --force` with the new full tag. `pipx upgrade`
stays on the installed tag and brings no new version. If you work on
ProjectTools itself, install the working copy with
`pipx install -e <checkout>`; changes to the scripts then take effect without
reinstalling.

**Without installation**, `PROJECT_TOOLS` points to `src/` of this repo. A
project also creates the symlink `.libs/ProjectTools` and sets in its
Makefile:

```makefile
PROJECT_TOOLS ?= $(WORKSPACE)/.libs/ProjectTools/src
```

A script needs its config in the project root once and then runs directly.
Using the repo status as an example:

```bash
"$PROJECT_TOOLS/bash/repo-status.sh" --example > .repo-status.conf.sh
"$PROJECT_TOOLS/bash/repo-status.sh" --show
```

Installed, the same calls are `repo-status --example` and
`repo-status --show`. How the scripts are wired into Make targets is
described in each tool document. The project copy of `setup-libs.sh`, which
creates `.libs/ProjectTools`, is superseded by the installation.

[↑ Contents](#contents)

## Configuration

**Each script reads its config from the working directory.** The name follows
the script: `repo-status.sh` reads `.repo-status.conf.sh`; the extension
`.conf` without `.sh` works as well. `--config <file>` selects a different
file.

The config is a Bash snippet that the script sources and then validates. It
therefore contains only assignments and belongs in the respective project
repo.

Every script writes a valid starter config with `--example`; review it once
afterwards. The keys are described in the tool document, section “Format”.

[↑ Contents](#contents)

## Development

Setting up from the checkout, Make targets, tests and project layout are
described in the [developer documentation](docs/development.md) (German).

[↑ Contents](#contents)

## Further documentation

- [Tool documents](docs/tools/): invocation, workflow and config format for
  each script, linked in the [Tools](#tools) table.
- [Python package for project environments](docs/python-package.md): use the
  modules under `projecttools` in another project's venv.
- [CLI themes and spacing](docs/cli-themes.md): shared colours and layout of
  MakeLib, BashLib and ProjectTools.

[↑ Contents](#contents)

## License

Copyright © 2026 Michael Mitterer. **MangoLila GmbH** is the provider and
licensor.

ProjectTools is licensed under the **[EUPL 1.2](LICENSE)**, version 1.2 only.
It permits personal and commercial use, changes, redistribution, sale and
hosting without a paid license.

If you redistribute ProjectTools or a changed version, or offer it as a
network service, keep the copyright and license notices, mark your changes
and provide the corresponding source under the license's copyleft rules.

The warranty and liability exclusions in EUPL Articles 7 and 8 also apply to
consumers, as far as the law permits. Mandatory rights remain unaffected,
including liability for intent, gross negligence, personal injury and product
liability. No additional guarantee is given.

Contact: **office@MangoLila.at**.

Details: [LICENSE](LICENSE) · [German license text](LICENSE.de.txt) ·
[Provider and consumer declaration](LICENSING.md)

[↑ Contents](#contents)
