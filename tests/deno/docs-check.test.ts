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
  // Pflichtdateien: gültig, leer, Markdown ohne oder nur mit Überschrift im Codeblock.
  write(root, "LICENSE", "EUPL 1.2\n");
  write(root, "req/a/b/deep.md", "# Deep\n");
  write(root, "req/empty.md", "  \n");
  write(root, "req/plain.md", "Nur Text, kein Titel.\n");
  write(root, "req/fenced.md", "```\n# kein Titel\n```\n");
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
  // Drei Hinweisboxen in einem README: Hinweis mit Zeilen und Box-Art.
  write(
    root,
    "ui/README.md",
    "# UI\n\n> [!NOTE]\n> a\n\n> [!WARNING]\n> b\n\n> [!TIP]\n> c\n",
  );
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
      "Again [nothing](docs/missing.md).",
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
// Muster mit Alternative und Flag; \bUID\b darf in „PUID“ nicht treffen.
const pattern = run(
  "--root",
  root,
  "--forbid",
  "/\\bp(u|g)id\\b/i|interne IDs",
  "--forbid",
  "/\\bUID\\b/|nur als ganzes Wort",
  `${root}/docs/user.md`,
);
const invalid = run("--root", root, "--forbid", "/[/", `${root}/README.md`);
const alerts = run("--root", root, "--max-alerts", "2", `${root}/ui/README.md`);
const alertsUnlimited = run("--root", root, `${root}/ui/README.md`);
// Nur Pflichtdateien, ohne Dokumente. README.md liegt nur auf der Platte.
const required = run(
  "--root",
  root,
  ...[
    "LICENSE",
    "deep.md",
    "./req/**/deep.md",
    "req/*/deep.md",
    "req/empty.md",
    "req/plain.md|braucht einen Titel",
    "req/fenced.md",
    "README.md",
    "./README.md",
  ].flatMap((entry) => ["--require", entry]),
);

Deno.test("keine Kanarienwerte aus sensiblen oder unversionierten Dateien", () => {
  for (const { output } of [readme, sub, developer, forbidden]) {
    assert(!/CANARY_/.test(output), `Kanarienwert in der Ausgabe:\n${lineFor(output, "CANARY_")}`);
  }
});

Deno.test("Variablen nur aus sensiblen oder unversionierten Dateien gelten als unbekannt", () => {
  for (const name of ["ENV_ONLY_VAR", "SECRETS_ONLY_VAR", "KEY_ONLY_VAR", "UNTRACKED_ONLY_VAR"]) {
    assert(lineFor(readme.output, name).includes("Prüfen"), `${name} sollte unbekannt sein`);
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
    lineFor(readme.output, "make deploy").includes("Prüfen"),
    "make deploy: wegen Einbindung über Variable nur zu prüfen",
  );
  assert(
    lineFor(readme.output, "make leak").includes("Prüfen"),
    "make leak: .env darf nicht als Quelle von Targets gelesen werden",
  );
  assert(!lineFor(readme.output, "make serve"), "make serve in api/ ist belegt (-C und cd)");
  assert(
    lineFor(readme.output, "make nope").includes("Problem"),
    "make -C api nope ist ein Problem",
  );
});

Deno.test("npm, deno task, uv run und cargo im richtigen Verzeichnis", () => {
  assert(!lineFor(readme.output, "npm run build"), "npm run build nach cd frontend ist belegt");
  assert(
    lineFor(readme.output, "npm run missing").includes("Problem"),
    "npm run missing ist ein Problem",
  );
  const deno = lineFor(readme.output, "`deno task fmt`: Es gibt keine deno.json");
  assert(
    deno.includes("Problem") && /Zeile \d+ ·/.test(deno),
    "deno task in der Wurzel ohne deno.json: genau eine Zeile (nach cd tools belegt)",
  );
  const uv = readme.output.split("\n").filter((line) => line.includes("uv run mycli"));
  assert(
    uv.length === 1 && uv[0].includes("Prüfen"),
    "uv run mycli: zu prüfen in der Wurzel, belegt nach cd py",
  );
  assert(!lineFor(readme.output, "uv run pytest"), "pytest ist ein Werkzeug, keine Meldung");
  assert(!lineFor(readme.output, "rtool"), "cargo run --bin rtool ist belegt");
  assert(lineFor(readme.output, "„nope“").includes("Problem"), "cargo run -p nope ist ein Problem");
  assert(
    lineFor(readme.output, "go run ./go").includes("Ungeprüft"),
    "go run wird als ungeprüft gekennzeichnet",
  );
});

Deno.test("Jeder Befund sagt, was zu tun ist", () => {
  const lines = readme.output.split("\n");
  const findings = lines.filter((line) => /^\s{2}(Problem|Prüfen|Ungeprüft)\s/.test(line));
  assert(findings.length > 0, "keine Befunde gefunden");
  for (const finding of findings) {
    const next = lines[lines.indexOf(finding) + 1] ?? "";
    assert(next.trim().startsWith("→ "), `Handlungshinweis fehlt nach:\n${finding}`);
  }
});

Deno.test("Übersicht nennt jedes geprüfte Dokument mit Ergebnis", () => {
  assert(/✗ README\.md\s+\d+ Probleme/.test(readme.output), `Übersicht fehlt:\n${readme.output}`);
  assert(/✓ docs\/development\.md\s+in Ordnung/.test(developer.output), developer.output);
});

Deno.test("Links: vorhandene Datei ok, fehlende Datei ist ein Problem", () => {
  assert(!lineFor(readme.output, "docs/guide.md"), "docs/guide.md existiert");
  assert(
    lineFor(readme.output, "docs/missing.md").includes("Problem"),
    "docs/missing.md fehlt",
  );
  assert(
    readme.output.split("\n").filter((line) => line.includes("Link auf docs/missing.md")).length ===
        1 &&
      /Zeilen \d+, \d+ · Link auf docs\/missing\.md/.test(readme.output),
    "gleicher toter Link an zwei Stellen: ein Befund mit beiden Zeilen",
  );
  assert(readme.code === 1, "Probleme ergeben Exit-Code 1");
});

Deno.test("Unter-README: Anker und Befehle relativ zu api/", () => {
  assert(
    sub.code === 0 && sub.output.includes("keine Probleme"),
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
    lineFor(forbidden.output, "„PUID“").includes("Grund: nicht in Nutzerdoku"),
    "Grund fehlt in der Meldung",
  );
  assert(forbidden.output.includes("docs/user.md"), "docs/user.md enthält PUID");
  assert(!forbidden.output.includes("docs/drafts/plan.md"), "docs/drafts ist ausgeschlossen");
  assert(forbidden.output.includes("Ausgenommen: docs/drafts"), "Ausnahme wird genannt");
  assert(
    forbidden.output.includes("3 Dokumente geprüft"),
    `Ordner docs/ sollte drei Dokumente liefern:\n${forbidden.output}`,
  );
});

Deno.test("Entwurf mit --as wird am späteren Ort geprüft", () => {
  assert(
    draft.output.includes("1 Dokument geprüft") && draft.output.includes("docs/new.md (Entwurf"),
    `--as prüft genau eine Datei am späteren Ort:\n${draft.output}`,
  );
});

Deno.test("Verbotene Muster als regulärer Ausdruck, mit Treffer und Grund", () => {
  const hit = lineFor(pattern.output, "Verbotener Text");
  assert(
    hit.includes("„PUID“") && hit.includes("interne IDs") && hit.includes("Muster /"),
    `Treffer, Muster oder Grund fehlt:\n${pattern.output}`,
  );
  assert(!pattern.output.includes("nur als ganzes Wort"), "\\bUID\\b darf in PUID nicht treffen");
  assert(pattern.code === 1, "Treffer ergibt Exit-Code 1");
});

Deno.test("Ungültiger regulärer Ausdruck bricht mit Exit-Code 2 ab", () => {
  assert(invalid.code === 2, `Exit-Code 2 erwartet, war ${invalid.code}`);
  assert(invalid.output.includes("ungültiger regulärer Ausdruck"), invalid.output);
});

Deno.test("Hinweisboxen: Grenze nur aus der Config, Meldung mit Zeilen und Box-Art", () => {
  assert(!alertsUnlimited.output.includes("Hinweisboxen"), "ohne --max-alerts keine Grenze");
  const hint = lineFor(alerts.output, "Hinweisboxen");
  assert(
    hint.includes("Prüfen") && hint.includes("Zeilen 3, 6, 9") &&
      hint.includes("3 farbige Hinweisboxen ([!NOTE], [!WARNING], [!TIP])") &&
      hint.includes("höchstens 2"),
    `Zeilen, Box-Art oder Grenze fehlen:\n${alerts.output}`,
  );
  assert(alerts.code === 0, "zu prüfende Stellen lassen die Prüfung nicht scheitern");
});

Deno.test("Pflichtdateien: Name irgendwo, Pfad, Muster mit * und **", () => {
  assert(/✓ LICENSE\s+vorhanden/.test(required.output), `LICENSE fehlt:\n${required.output}`);
  assert(/✓ deep\.md\s+req\/a\/b\/deep\.md/.test(required.output), "Name ohne Pfad: irgendwo");
  assert(
    /✓ \.\/req\/\*\*\/deep\.md\s+req\/a\/b\/deep\.md/.test(required.output),
    "** beliebig tief",
  );
  assert(lineFor(required.output, "req/*/deep.md").includes("fehlt"), "* ist genau ein Ordner");
  assert(/✓ README\.md\s+api\/README\.md/.test(required.output), "README.md ohne Pfad: irgendwo");
  assert(!required.output.includes("Dokumentprüfung"), "ohne Dokumente kein Dokumentblock");
});

Deno.test("Pflichtdateien: unversioniert, leer oder Markdown ohne Überschrift zählt nicht", () => {
  assert(
    lineFor(required.output, "✗ ./README.md").includes("fehlt im Repository"),
    "unversioniert",
  );
  assert(lineFor(required.output, "req/empty.md").includes("ist leer"), "leere Datei");
  const plain = lineFor(required.output, "req/plain.md");
  assert(
    plain.includes("keine Überschrift") && plain.includes("Grund: braucht einen Titel"),
    plain,
  );
  assert(
    lineFor(required.output, "req/fenced.md").includes("keine Überschrift"),
    "Codeblock zählt nicht",
  );
  assert(required.output.includes("9 Pflichtdateien geprüft · 5 Probleme"), required.output);
  assert(required.code === 1, "fehlende Pflichtdateien ergeben Exit-Code 1");
});

Deno.test("Aufräumen", () => {
  Deno.removeSync(root, { recursive: true });
});
