/**
 * Tests für src/deno/docs-check.ts an einem kleinen Test-Repo im Temp-Ordner.
 * Das Skript läuft als eigener Prozess mit denselben Deno-Rechten wie im
 * Einsatz.
 *
 * Aufruf:
 *   deno test --allow-read --allow-write --allow-run=git,deno tests/deno/docs-check.test.ts
 *
 * Sensible Dateien enthalten Kanarienwerte (CANARY_…): Sie dürfen in keiner
 * Ausgabe auftauchen, auch nicht, wenn die Datei versioniert ist.
 */

const SCRIPT = new URL("../../src/deno/docs-check.ts", import.meta.url).pathname;

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function write(root: string, path: string, content: string): void {
  const full = `${root}/${path}`;
  Deno.mkdirSync(full.slice(0, full.lastIndexOf("/")), { recursive: true });
  Deno.writeTextFileSync(full, content);
}

function run(...args: string[]): { output: string; code: number } {
  const result = new Deno.Command("deno", {
    args: ["run", "--allow-read", "--allow-run=git", SCRIPT, ...args],
    stdout: "piped",
    stderr: "piped",
  }).outputSync();
  const decoder = new TextDecoder();
  return {
    output: decoder.decode(result.stdout) + decoder.decode(result.stderr),
    code: result.code,
  };
}

/** Zeile der Ausgabe, die den Text nennt, oder ''. */
function lineFor(output: string, needle: string): string {
  return output.split("\n").find((line) => line.includes(needle)) ?? "";
}

function fixture(): string {
  const root = Deno.makeTempDirSync({ prefix: "docs-check-" });
  write(
    root,
    "Makefile",
    "include build.mk\n-include .env\n-include ${DEV_MAKE}/tools.mk\n\ntest: ## Tests\n\techo test\n",
  );
  write(root, "build.mk", "lint:\n\techo lint\n");
  write(root, "api/Makefile", "serve:\n\techo serve\n");
  write(root, "api/README.md", "# API\n\n## Serving\n\n```bash\nmake serve\n```\n");
  write(root, "frontend/package.json", '{"scripts":{"build":"vite build"}}\n');
  write(root, "tools/deno.json", '{"tasks":{"fmt":"deno fmt"}}\n');
  write(
    root,
    "py/pyproject.toml",
    '[project]\nname = "pkg"\n\n[project.scripts]\nmycli = "pkg.cli:main"\n',
  );
  write(
    root,
    "rs/Cargo.toml",
    '[package]\nname = "rcore"\n\n[[bin]]\nname = "rtool"\npath = "src/main.rs"\n',
  );
  write(root, "rs/src/main.rs", 'fn main() { let _ = std::env::var("RUST_VAR"); }\n');
  write(root, "go/go.mod", "module x\n");
  write(root, "go/main.go", 'package main\nimport "os"\nfunc main() { _ = os.Getenv("GO_VAR") }\n');
  write(
    root,
    "docs/guide.md",
    "See [serving](../api/README.md#serving) and [install](../README.md#install).\n",
  );
  // Sensible Dateien, absichtlich versioniert: Auch dann nie lesen.
  write(root, ".env", "ENV_ONLY_VAR=CANARY_ENV\nleak:\n");
  write(root, "config/secrets.yaml", "SECRETS_ONLY_VAR: CANARY_SECRETS\n");
  write(root, "deploy/server.key", "KEY_ONLY_VAR CANARY_KEY\n");
  write(root, ".npmrc", "//registry.npmjs.org/:_authToken=CANARY_NPMRC\n");
  const git = (...args: string[]) =>
    new Deno.Command("git", { args: ["-C", root, ...args], stdout: "null", stderr: "null" })
      .outputSync();
  git("init", "-q");
  git("add", "-A");
  // Unversioniert: liefert keine Projektfakten, ist aber als Dokument prüfbar.
  write(root, "notes.txt", "UNTRACKED_ONLY_VAR=CANARY_UNTRACKED\n");
  // Entwicklerdoku unter docs/: Befehle laufen in der Wurzel, Links gelten ab docs/.
  write(
    root,
    "docs/development.md",
    "# Dev\n\n```bash\nmake test\n```\n\nSee [guide](guide.md).\n",
  );
  // Datierte Entwürfe dürfen interne Angaben enthalten und werden ausgeschlossen.
  write(root, "docs/drafts/plan.md", "# Plan\n\nRuns as PUID 99.\n");
  write(root, "docs/user.md", "# User\n\nSet PUID to change the owner.\n");
  write(
    root,
    "README.md",
    [
      "# Demo",
      "",
      "## Install",
      "",
      "```bash",
      "make test",
      "make lint",
      "make deploy",
      "make leak",
      "make -C api serve",
      "make -C api nope",
      "cd api && make serve",
      "```",
      "",
      "```bash",
      "cd frontend",
      "npm run build",
      "npm run missing",
      "```",
      "",
      "```bash",
      "deno task fmt",
      "uv run mycli",
      "uv run pytest",
      "cargo run --bin rtool",
      "cargo run -p nope",
      "go run ./go",
      "```",
      "",
      // Ein cd gilt wie in der Shell bis zum Ende des Blocks.
      "```bash",
      "cd tools && deno task fmt",
      "deno task fmt",
      "```",
      "",
      "```bash",
      "cd py && uv run mycli",
      "```",
      "",
      "Variables: `GO_VAR`, `RUST_VAR`, `ENV_ONLY_VAR`, `SECRETS_ONLY_VAR`, `KEY_ONLY_VAR`, `UNTRACKED_ONLY_VAR`.",
      "",
      "See [the guide](docs/guide.md) and [nothing](docs/missing.md).",
      "",
    ].join("\n"),
  );
  return root;
}

const root = fixture();
const readme = run("--root", root, `${root}/README.md`);
const sub = run("--root", root, `${root}/api/README.md`);
const developer = run("--root", root, `${root}/docs/development.md`);
const forbidden = run(
  "--root",
  root,
  "--forbid",
  "PUID|nicht in Nutzerdoku",
  "--exclude",
  "docs/drafts",
  `${root}/docs`,
);
const draft = run("--root", root, "--as", "docs/new.md", `${root}/notes.txt`);

Deno.test("keine Kanarienwerte aus sensiblen oder unversionierten Dateien", () => {
  for (const { output } of [readme, sub, developer, forbidden]) {
    assert(!/CANARY_/.test(output), `Kanarienwert in der Ausgabe:\n${lineFor(output, "CANARY_")}`);
  }
});

Deno.test("Variablen nur aus sensiblen oder unversionierten Dateien gelten als unbekannt", () => {
  for (const name of ["ENV_ONLY_VAR", "SECRETS_ONLY_VAR", "KEY_ONLY_VAR", "UNTRACKED_ONLY_VAR"]) {
    assert(lineFor(readme.output, name).includes("?"), `${name} sollte unbekannt sein`);
  }
});

Deno.test("Go- und Rust-Variablen werden erkannt", () => {
  assert(!lineFor(readme.output, "GO_VAR"), "GO_VAR fälschlich gemeldet");
  assert(!lineFor(readme.output, "RUST_VAR"), "RUST_VAR fälschlich gemeldet");
});

Deno.test("Make je Verzeichnis, mit Einbindungen", () => {
  assert(!lineFor(readme.output, "make test"), "make test ist belegt");
  assert(!lineFor(readme.output, "make lint"), "make lint kommt aus build.mk");
  assert(
    lineFor(readme.output, "make deploy").includes("?"),
    "make deploy: wegen Einbindung über Variable nur Hinweis",
  );
  assert(
    lineFor(readme.output, "make leak").includes("?"),
    "make leak: .env darf nicht als Quelle von Targets gelesen werden",
  );
  assert(!lineFor(readme.output, "make serve"), "make serve in api/ ist belegt (-C und cd)");
  assert(lineFor(readme.output, "make nope").includes("!"), "make -C api nope ist ein Fehler");
});

Deno.test("npm, deno task, uv run und cargo im richtigen Verzeichnis", () => {
  assert(!lineFor(readme.output, "npm run build"), "npm run build nach cd frontend ist belegt");
  assert(lineFor(readme.output, "npm run missing").includes("!"), "npm run missing ist ein Fehler");
  const denoErrors = readme.output.split("\n").filter((line) =>
    line.includes("deno task fmt – keine deno.json")
  );
  assert(
    denoErrors.length === 1,
    "deno task in der Wurzel ohne deno.json: genau ein Fehler (nach cd tools belegt)",
  );
  const uvWarnings = readme.output.split("\n").filter((line) => line.includes("uv run mycli"));
  assert(
    uvWarnings.length === 1 && uvWarnings[0].includes("?"),
    "uv run mycli: Hinweis in der Wurzel, belegt nach cd py",
  );
  assert(!lineFor(readme.output, "uv run pytest"), "pytest ist ein Werkzeug, keine Meldung");
  assert(!lineFor(readme.output, "rtool"), "cargo run --bin rtool ist belegt");
  assert(
    lineFor(readme.output, "cargo run … nope").includes("!"),
    "cargo run -p nope ist ein Fehler",
  );
  assert(
    lineFor(readme.output, "go run ./go").includes("~"),
    "go run wird als ungeprüft gekennzeichnet",
  );
});

Deno.test("Links: vorhandene Datei ok, fehlende Datei ist ein Problem", () => {
  assert(!lineFor(readme.output, "docs/guide.md"), "docs/guide.md existiert");
  assert(lineFor(readme.output, "docs/missing.md").includes("!"), "docs/missing.md fehlt");
  assert(readme.code === 1, "Probleme ergeben Exit-Code 1");
});

Deno.test("Unter-README: Anker und Befehle relativ zu api/", () => {
  assert(
    sub.code === 0 && sub.output.includes("0 Probleme"),
    `api/README.md sollte bestehen:\n${sub.output}`,
  );
  assert(
    !lineFor(readme.output, "#install"),
    "Wurzel-README: eingehender Anker #install ist vorhanden",
  );
});

Deno.test("Dokument unter docs/: Befehle relativ zur Wurzel, Links relativ zu docs/", () => {
  assert(developer.code === 0, `docs/development.md sollte bestehen:\n${developer.output}`);
});

Deno.test("Verbotene Begriffe mit Grund, ausgeschlossene Ordner bleiben außen vor", () => {
  assert(
    lineFor(forbidden.output, "PUID").includes("nicht in Nutzerdoku"),
    "Grund fehlt in der Meldung",
  );
  assert(forbidden.output.includes("docs/user.md"), "docs/user.md enthält PUID");
  assert(!forbidden.output.includes("docs/drafts/plan.md"), "docs/drafts ist ausgeschlossen");
  assert(
    forbidden.output.includes("3 Dokumente geprüft"),
    `Ordner docs/ sollte drei Dokumente liefern:\n${forbidden.output}`,
  );
});

Deno.test("Entwurf mit --as wird am späteren Ort geprüft", () => {
  assert(
    draft.output.includes("1 Dokument geprüft"),
    `--as prüft genau eine Datei:\n${draft.output}`,
  );
});

Deno.test("Aufräumen", () => {
  Deno.removeSync(root, { recursive: true });
});
