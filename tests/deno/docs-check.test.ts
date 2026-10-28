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

/** Zeitpunkt vor so vielen Tagen. */
function daysAgo(days: number): Date {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000);
}

/**
 * Committet die Pfade (alle gestagten ohne Angabe) mit Autor- und
 * Commit-Zeit `when`. So lassen sich alte Stände ohne Warten herstellen.
 */
function commitAt(repo: string, when: Date, ...paths: string[]): void {
  const result = new Deno.Command("git", {
    args: [
      "-C",
      repo,
      "-c",
      "user.name=Test",
      "-c",
      "user.email=t@example.invalid",
      "commit",
      "-q",
      "-m",
      "test",
      ...(paths.length ? ["--", ...paths] : []),
    ],
    env: { GIT_AUTHOR_DATE: when.toISOString(), GIT_COMMITTER_DATE: when.toISOString() },
    stdout: "null",
    stderr: "piped",
  }).outputSync();
  if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
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
  // Von git ignoriert: Muster und Ordner dürfen sie nicht treffen.
  write(root, ".gitignore", "gen/\n");
  write(root, "gen/out.md", "# Erzeugt\n");
  // Sensible Dateien, absichtlich versioniert: Auch dann nie lesen.
  write(root, ".env", "ENV_ONLY_VAR=CANARY_ENV\nleak:\n");
  write(root, "config/secrets.yaml", "SECRETS_ONLY_VAR: CANARY_SECRETS\n");
  write(root, "deploy/server.key", "KEY_ONLY_VAR CANARY_KEY\n");
  write(root, ".npmrc", "//registry.npmjs.org/:_authToken=CANARY_NPMRC\n");
  // Eingehende Anker mit Umlauten, roh und kodiert; einer zeigt ins Leere.
  // Versioniert, denn eingehende Anker stammen nur aus versionierten Dateien.
  write(
    root,
    "notes/links.md",
    "[a](../AGENTS.md#bauen-und-prüfen) [b](../AGENTS.md#bauen-und-pr%C3%BCfen) " +
      "[c](../AGENTS.md#größe-fehlt)\n",
  );
  // Code, dessen Umgebungsvariablen dokumentiert sein müssen: eine
  // dokumentiert, eine nicht, eine intern; Zuweisung und Test zählen nicht.
  write(
    root,
    "svc/server.ts",
    "const port = process.env.SVC_PORT\nconst x = process.env.SVC_HIDDEN\n" +
      "const y = import.meta.env.SVC_INTERNAL\n",
  );
  write(root, "svc/run.py", 'import os\nos.environ["SVC_CHILD"] = "1"\n');
  write(root, "svc/server.test.ts", "const t = process.env.SVC_TEST_ONLY\n");
  write(root, "svcdocs/config.md", "# Config\n\n`SVC_PORT` sets the port.\n");
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
  write(root, "docs/user.md", "# User\n\nSet PUID and PGID to change the owner.\n");
  // Interne Regeln: nur Links prüfen, verbotene Begriffe und Platzhalter sind erlaubt.
  write(
    root,
    "AGENTS.md",
    "# Regeln\n\nPUID bleibt intern. TODO später.\n\n`make nope` und `INTERNAL_VAR`.\n\n" +
      "Siehe [Setup](README.md#install), [alt](docs/old.md) und [weg](#nirgends).\n\n" +
      `Absolut: [da](${root}/LICENSE), [fort](/nirgends/plan.md).\n\n## Bauen und prüfen\n`,
  );
  // Screenshots: eines neu (uncommittet), eines vor 100 Tagen committet, eines
  // von git ignoriert; der UI-Code, den sie zeigen, vor 50 Tagen. Verglichen
  // wird mit dem Code laut git, nicht mit dem Tagesdatum oder Dateidatum.
  write(root, "shots/fresh.png", "png");
  write(root, "shots/old.png", "png");
  write(root, "gen/ignored.png", "png");
  write(root, "app/view.vue", "<template>Ansicht</template>\n");
  git("add", "shots/old.png", "app/view.vue");
  commitAt(root, daysAgo(100), "shots/old.png");
  commitAt(root, daysAgo(50), "app/view.vue");
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
const linksOnly = run("--root", root, "--forbid", "PUID", "--links-only", "AGENTS.md");
// README.md vollständig und als Nur-Link-Dokument: Die vollständige Prüfung gilt.
const both = run("--root", root, "--links-only", "README.md", `${root}/README.md`);
const known = run(
  "--root",
  root,
  "--known-variable",
  "UNTRACKED_ONLY_VAR|aus einer Bibliothek",
  `${root}/README.md`,
);
const knownTarget = run(
  "--root",
  root,
  "--known-make-target",
  "deploy|aus einer eingebundenen Bibliothek",
  `${root}/README.md`,
);
const shots = run(
  "--root",
  root,
  "--screenshot",
  "app|shots|Oberfläche",
  "--screenshot",
  "app|gen/*.png",
);
// Ausnahmen von der Altersprüfung: vorhanden muss das Bild sein, sein Alter zählt nicht.
const shotsExcluded = run(
  "--root",
  root,
  "--screenshot",
  "app|shots|Oberfläche",
  "--screenshot-exclude",
  "shots/o*.png",
);
const shotsExcludedMissing = run(
  "--root",
  root,
  "--screenshot",
  "app|shots",
  "--screenshot-exclude",
  "shots/logo.png",
);
const shotsOldFormat = run("--root", root, "--screenshot", "shots");
const shotsAgeLimit = run(
  "--root",
  root,
  "--screenshot",
  "app|shots",
  "--max-screenshot-age",
  "60",
);
const codeVariables = run(
  "--root",
  root,
  "--code-variables",
  "svc",
  "--code-variables",
  "nirgends",
  "--internal-variable",
  "SVC_INTERNAL|nur für Entwickler",
  "--internal-variable",
  "SVC_GONE|früher gebraucht",
  "svcdocs",
);
const alerts = run("--root", root, "--max-alerts", "2", `${root}/ui/README.md`);
const alertsUnlimited = run("--root", root, `${root}/ui/README.md`);
// Muster in DOCS und EXCLUDE; req/a/* schließt req/a/b/deep.md über seinen Ordner aus.
const globs = run(
  "--root",
  root,
  "--exclude",
  "req/a/*",
  "req/**/*.md",
  "gen/**/*.md",
  "nix/*.md",
);
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
    assert(lineFor(readme.output, name).includes("Hinweis"), `${name} sollte unbekannt sein`);
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
    lineFor(readme.output, "make deploy").includes("Hinweis"),
    "make deploy: wegen Einbindung über Variable nur zu prüfen",
  );
  assert(
    lineFor(readme.output, "make leak").includes("Hinweis"),
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
    uv.length === 1 && uv[0].includes("Hinweis"),
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
  const findings = lines.filter((line) => /^\s{2}(Problem|Hinweis|Ungeprüft)\s/.test(line));
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
  assert(
    lineFor(pattern.output, "„PGID“").includes("Verbotener Text"),
    "zweiter Treffer in derselben Zeile wird auch gemeldet",
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
    hint.includes("Hinweis") && hint.includes("Zeilen 3, 6, 9") &&
      hint.includes("3 farbige Hinweisboxen ([!NOTE], [!WARNING], [!TIP])") &&
      hint.includes("höchstens 2"),
    `Zeilen, Box-Art oder Grenze fehlen:\n${alerts.output}`,
  );
  assert(alerts.code === 0, "Hinweise lassen die Prüfung nicht scheitern");
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

Deno.test("DOCS und EXCLUDE mit Mustern; ignorierte Dateien zählen nicht", () => {
  assert(
    globs.output.includes("3 Dokumente geprüft"),
    `req/**/*.md ohne req/a/…:\n${globs.output}`,
  );
  assert(!globs.output.includes("req/a/b/deep.md"), "Ausschluss über Ordner-Muster");
  assert(
    lineFor(globs.output, "gen/**/*.md").includes("Muster trifft keine Markdown-Datei"),
    "von git ignorierte Dateien zählen nicht",
  );
  assert(lineFor(globs.output, "nix/*.md").includes("Muster trifft keine"), "Muster ohne Treffer");
  assert(globs.code === 1, "Muster ohne Treffer ist ein Problem");
});

Deno.test("Nur-Link-Dokumente: tote Links und Anker, sonst nichts", () => {
  assert(
    lineFor(linksOnly.output, "AGENTS.md").includes("(nur Links)"),
    `Übersicht nennt die Prüfart:\n${linksOnly.output}`,
  );
  assert(lineFor(linksOnly.output, "docs/old.md").includes("Problem"), "toter Link");
  assert(lineFor(linksOnly.output, "#nirgends").includes("Problem"), "fehlender Anker");
  for (const ignored of ["PUID", "Platzhalter", "make nope", "INTERNAL_VAR"]) {
    assert(!lineFor(linksOnly.output, ignored).includes("·"), `${ignored} wird nicht geprüft`);
  }
  assert(linksOnly.code === 1, "tote Links lassen die Prüfung scheitern");
  assert(!linksOnly.output.includes("#bauen-und-pr"), `Umlaut-Anker erkannt:\n${linksOnly.output}`);
  assert(
    lineFor(linksOnly.output, "#größe-fehlt").includes("notes/links.md"),
    "fehlender Umlaut-Anker vollständig genannt",
  );
  assert(!linksOnly.output.includes("LICENSE"), "vorhandener absoluter Pfad ist in Ordnung");
  assert(lineFor(linksOnly.output, "/nirgends/plan.md").includes("Problem"), "absolut und fehlt");
  assert(
    !lineFor(both.output, "README.md").includes("(nur Links)") &&
      lineFor(both.output, "make deploy").includes("Hinweis"),
    "doppelt genannt: vollständige Prüfung",
  );
});

Deno.test("Bekannte Variablen aus der Config gelten als vorhanden", () => {
  assert(!known.output.includes("`UNTRACKED_ONLY_VAR`"), known.output);
  assert(lineFor(known.output, "ENV_ONLY_VAR").includes("Hinweis"), "andere bleiben unbekannt");
  const bad = run("--root", root, "--known-variable", "kein name", `${root}/README.md`);
  assert(bad.code === 2 && bad.output.includes("Variablennamen"), bad.output);
});

Deno.test("Bekannte Make-Targets aus der Config gelten als vorhanden", () => {
  assert(!lineFor(knownTarget.output, "make deploy"), knownTarget.output);
  assert(
    lineFor(knownTarget.output, "make nope").includes("Problem"),
    "andere fehlende Targets bleiben ein Problem",
  );
  assert(
    lineFor(knownTarget.output, "make leak").includes("Hinweis"),
    "andere unklare Targets bleiben ein Hinweis",
  );
  const bad = run("--root", root, "--known-make-target", "kein target", `${root}/README.md`);
  assert(bad.code === 2 && bad.output.includes("Target"), bad.output);
});

Deno.test("Screenshots: mit dem UI-Code verglichen, nicht mit dem Tagesdatum", () => {
  assert(
    shots.output.includes("Screenshots: 2, verglichen mit dem UI-Code"),
    shots.output,
  );
  // Das Dateidatum zählt nicht: frisch geschrieben, aber vor 100 Tagen committet.
  assert(
    Deno.statSync(`${root}/shots/old.png`).mtime!.getTime() > daysAgo(1).getTime(),
    "Dateidatum ist neu",
  );
  assert(lineFor(shots.output, "shots/fresh.png").includes("aktuell (uncommittet)"), shots.output);
  const old = lineFor(shots.output, "shots/old.png");
  assert(old.includes("?") && old.includes("Code geändert"), `altes Bild:\n${shots.output}`);
  assert(old.includes("Oberfläche"), "Grund genannt");
  assert(shots.output.includes("neu aufnehmen"), "sagt, was zu tun ist");
  assert(shots.output.includes("docs-check.sh --ack shots/old.png"), "nennt die Quittung");
  assert(
    lineFor(shots.output, "gen/*.png").includes("trifft kein Bild"),
    "ignorierte zählen nicht",
  );
  assert(shots.output.includes("2 Screenshots geprüft · 1 Problem · 1 Hinweis"), shots.output);
  assert(
    shotsOldFormat.code === 2 && shotsOldFormat.output.includes("UI-CODE|BILDER"),
    shotsOldFormat.output,
  );
  assert(
    shotsAgeLimit.code === 2 && shotsAgeLimit.output.includes("entfällt"),
    shotsAgeLimit.output,
  );
});

Deno.test("Screenshots: Ausnahmen müssen da sein, ihr Alter zählt nicht", () => {
  assert(shotsExcluded.code === 0, shotsExcluded.output);
  assert(
    shotsExcluded.output.includes("Screenshots: 2, verglichen mit dem UI-Code"),
    shotsExcluded.output,
  );
  const old = lineFor(shotsExcluded.output, "shots/old.png");
  assert(old.includes("vorhanden (ohne Altersprüfung)"), `ausgenommen:\n${shotsExcluded.output}`);
  assert(old.includes("Oberfläche"), "Grund genannt");
  assert(!shotsExcluded.output.includes("Code geändert"), shotsExcluded.output);
  assert(
    lineFor(shotsExcluded.output, "shots/fresh.png").includes("aktuell (uncommittet)"),
    shotsExcluded.output,
  );
  assert(
    shotsExcluded.output.includes("2 Screenshots geprüft · keine Probleme"),
    shotsExcluded.output,
  );
  // Fehlt ein ausgenommenes Bild, ist das ein Problem; die übrigen prüft die
  // Altersprüfung wie bisher.
  assert(shotsExcludedMissing.code === 1, shotsExcludedMissing.output);
  const missing = lineFor(shotsExcludedMissing.output, "shots/logo.png");
  assert(missing.includes("✗") && missing.includes("fehlt"), shotsExcludedMissing.output);
  assert(shotsExcludedMissing.output.includes("SCREENSHOTS_EXCLUDE"), "nennt den Schlüssel");
  assert(
    lineFor(shotsExcludedMissing.output, "shots/old.png").includes("Code geändert"),
    shotsExcludedMissing.output,
  );
});

Deno.test("Variablen aus dem Code müssen dokumentiert oder intern sein", () => {
  const out = codeVariables.output;
  assert(lineFor(out, "SVC_PORT").includes("dokumentiert in svcdocs/config.md"), out);
  const hidden = lineFor(out, "SVC_HIDDEN");
  assert(
    hidden.includes("in keinem Dokument genannt") && hidden.includes("svc/server.ts"),
    `undokumentiert mit Fundstelle:\n${out}`,
  );
  assert(lineFor(out, "SVC_INTERNAL").includes("intern: nur für Entwickler"), "intern mit Grund");
  assert(!out.includes("SVC_CHILD"), "Zuweisung liest nicht");
  assert(!out.includes("SVC_TEST_ONLY"), "Tests zählen nicht");
  assert(lineFor(out, "SVC_GONE").includes("liest sie nicht mehr"), "veralteter Eintrag");
  assert(lineFor(out, "nirgends").includes("trifft keine Codedatei"), "Eintrag ohne Code");
  assert(
    out.includes("3 Code-Variablen geprüft · 2 Probleme · 1 Hinweis"),
    `Zählung:\n${out}`,
  );
  assert(codeVariables.code === 1, "undokumentierte Variable lässt die Prüfung scheitern");
  const withoutDocs = run("--root", root, "--code-variables", "svc", "--require", "LICENSE");
  assert(withoutDocs.code === 2, "ohne Dokumente kein Lauf");
});

/**
 * Zwei Commits: Der zweite ändert eine Variable (README-Stelle mitgeändert),
 * führt eine neue ein, benennt ein Make-Target und einen UI-Text um, ohne die
 * Doku dazu anzupassen.
 */
function changesFixture(): string {
  const repo = Deno.makeTempDirSync({ prefix: "docs-check-changes-" });
  const git = (...args: string[]) =>
    new Deno.Command("git", {
      args: ["-C", repo, "-c", "user.name=Test", "-c", "user.email=t@example.invalid", ...args],
      stdout: "null",
      stderr: "null",
    }).outputSync();
  write(repo, "Makefile", "serve: ## Server starten\n\techo serve\n");
  write(repo, "src/app.ts", "const url = process.env.APP_URL ?? 'http://a'\n");
  write(repo, "src/i18n/en.ts", "export default { save: 'Save changes', quit: 'Quit' }\n");
  write(
    repo,
    "README.md",
    "# App\n\nSet `APP_URL` to the server.\n\n\n\n\n\nRun `make serve`.\n\n" +
      "\n\n\n\n\n\nClick _Save changes_ when done.\n",
  );
  write(repo, "notes/internal.md", "`APP_URL` intern\n");
  git("init", "-q");
  git("add", "-A");
  git("commit", "-q", "-m", "chore: Anfang");
  write(repo, "Makefile", "run: ## Server starten\n\techo run\n");
  write(
    repo,
    "src/app.ts",
    "const url = process.env.APP_URL ?? 'http://b'\nconst key = process.env.APP_KEY\n",
  );
  write(repo, "src/i18n/en.ts", "export default { save: 'Save', quit: 'Quit' }\n");
  write(
    repo,
    "README.md",
    "# App\n\nSet `APP_URL` to the server address.\n\n\n\n\n\nRun `make serve`.\n\n" +
      "\n\n\n\n\n\nClick _Save changes_ when done.\n",
  );
  git("add", "-A");
  git("commit", "-q", "-m", "feat(api): Schlüssel aus der Umgebung lesen");
  return repo;
}

Deno.test("Doku-Abgleich: Kandidaten zwischen zwei Ständen", () => {
  const repo = changesFixture();
  try {
    const json = run(
      "--root",
      repo,
      "--changes",
      "HEAD~1..HEAD",
      "--ui-catalog",
      "src/i18n/*.ts",
      "--json",
      "README.md",
    );
    assert(json.code === 0, `Kandidaten sind keine Fehler:\n${json.output}`);
    const report = JSON.parse(json.output);
    const find = (kind: string, name: string) =>
      report.candidates.find((c: { kind: string; name: string }) =>
        c.kind === kind && c.name === name
      );
    assert(
      find("variable", "APP_URL")?.status === "covered",
      "geänderte README-Zeile: mitgeändert",
    );
    assert(find("variable", "APP_KEY")?.status === "no-doc", "neue Variable ohne Doku-Stelle");
    const serve = find("make-target", "serve");
    assert(serve?.status === "open" && serve.hits[0].line === 9, "umbenanntes Target, Doku alt");
    const save = find("ui-text", "Save changes");
    assert(save?.status === "open" && save.hits[0].line === 17, "alter UI-Text in der Doku");
    assert(!find("ui-text", "Quit"), "unveränderter Text ist kein Kandidat");
    assert(find("feat", "feat(api): Schlüssel aus der Umgebung lesen"), "feat-Commit genannt");
    assert(
      !report.candidates.some((c: { hits: Array<{ file: string }> }) =>
        c.hits.some((hit) => hit.file.startsWith("notes/"))
      ),
      "nur die angegebenen Dokumente",
    );
    const text = run("--root", repo, "--changes", "HEAD~1", "README.md");
    assert(
      text.output.includes("Offen:") && text.output.includes("make-target") === false,
      text.output,
    );
    assert(text.output.includes("Make-Target") && text.output.includes("README.md:9"), text.output);
    const bad = run("--root", repo, "--changes", "nirgends..HEAD", "README.md");
    assert(bad.code === 2 && bad.output.includes("„nirgends“"), bad.output);
  } finally {
    Deno.removeSync(repo, { recursive: true });
  }
});

/**
 * Basis und abhängige Dateien mit Commits zu festen Zeitpunkten: vor 10 Tagen
 * alles, vor 5 Tagen nur Basisdateien, dazu uncommittete Änderungen.
 */
function dependsFixture(): string {
  const repo = Deno.makeTempDirSync({ prefix: "docs-check-depends-" });
  new Deno.Command("git", { args: ["-C", repo, "init", "-q"] }).outputSync();
  const stage = () => new Deno.Command("git", { args: ["-C", repo, "add", "-A"] }).outputSync();
  for (const name of ["same", "recent", "late", "hint", "zero", "both", "dir"]) {
    write(repo, `${name}/base.md`, "# Basis\n");
    write(repo, `${name}/dependent.md`, "# Abhängig\n");
  }
  write(repo, "dir/i18n/en.ts", "export default {}\n");
  stage();
  commitAt(repo, daysAgo(10));
  // Gleichzeitig nachgezogen: derselbe Commit.
  write(repo, "same/base.md", "# Basis\n\nneu\n");
  write(repo, "same/dependent.md", "# Abhängig\n\nneu\n");
  // Nur die Basis geändert, vor 5 Tagen.
  for (const name of ["recent", "late", "hint"]) write(repo, `${name}/base.md`, "# Basis 2\n");
  write(repo, "dir/i18n/en.ts", "export default { a: 1 }\n");
  stage();
  commitAt(repo, daysAgo(5));
  // Uncommittet: Basis allein, Basis und abhängige Datei zusammen.
  write(repo, "zero/base.md", "# Basis 3\n");
  write(repo, "both/base.md", "# Basis 3\n");
  write(repo, "both/dependent.md", "# Abhängig 3\n");
  return repo;
}

/** Abhängigkeiten aus dependsFixture, wie sie die Config übergäbe. */
const DEPENDS_ARGS = [
  "--depends",
  "same/base.md|same/dependent.md|0|derselbe Commit",
  "--depends",
  "recent/base.md|recent/dependent.md|30",
  "--depends",
  "late/base.md|late/dependent.md|2|Übersetzung",
  "--depends-hint",
  "hint/base.md|hint/dependent.md|2",
  "--depends",
  "zero/base.md|zero/dependent.md|0|erzeugt",
  "--depends",
  "both/base.md|both/dependent.md|0",
  "--depends",
  "dir/i18n|dir/dependent.md|30|Ordner als Basis",
  "--depends",
  "same/base.md|nirgends.md|3",
];

/** Wie run(), aber mit Schreibrecht für die Quittungen (--ack). */
function runWithAck(repo: string, ...args: string[]): { output: string; code: number } {
  const result = new Deno.Command("deno", {
    args: [
      "run",
      "--allow-read",
      "--allow-run=git",
      `--allow-write=${Deno.realPathSync(repo)}/.docs-check.ack`,
      SCRIPT,
      "--root",
      repo,
      ...DEPENDS_ARGS,
      ...args,
    ],
    stdout: "piped",
    stderr: "piped",
  }).outputSync();
  const decoder = new TextDecoder();
  return {
    output: decoder.decode(result.stdout) + decoder.decode(result.stderr),
    code: result.code,
  };
}

Deno.test("Abhängige Dokumente: Zeiten aus git, Frist in Tagen", () => {
  const repo = dependsFixture();
  try {
    const result = run("--root", repo, ...DEPENDS_ARGS);
    const output = result.output;
    assert(output.includes("Abhängige Dokumente: 8"), output);
    assert(lineFor(output, "same/dependent.md").includes("nachgezogen"), output);
    assert(lineFor(output, "both/dependent.md").includes("nachgezogen (uncommittet)"), output);
    const recent = lineFor(output, "recent/dependent.md");
    assert(
      recent.includes("?") && recent.includes("Frist") && !recent.includes("überfällig"),
      output,
    );
    const late = lineFor(output, "late/dependent.md");
    assert(
      late.includes("✗") && late.includes("überfällig") && late.includes("Übersetzung"),
      output,
    );
    const hint = lineFor(output, "hint/dependent.md");
    assert(
      hint.includes("?") && hint.includes("überfällig"),
      `DEPENDS_HINT bleibt Hinweis:\n${output}`,
    );
    const zero = lineFor(output, "zero/dependent.md");
    assert(zero.includes("✗") && zero.includes("Basis geändert uncommittet"), output);
    assert(zero.includes("gehört in denselben Commit"), output);
    assert(output.includes("git diff HEAD -- zero/base.md"), "uncommittete Basis: git diff");
    assert(output.includes("git log -p --since="), "committete Basis: git log");
    assert(output.includes("docs-check.sh --ack late/dependent.md"), "nennt die Quittung");
    assert(lineFor(output, "dir/dependent.md").includes("?"), "Ordner als Basis");
    assert(lineFor(output, "nirgends.md").includes("fehlt"), output);
    assert(output.includes("8 Abhängigkeiten geprüft · 3 Probleme · 3 Hinweise"), output);
    assert(result.code === 1, "überfällige Abhängigkeit scheitert");
    const bad = run("--root", repo, "--depends", "a.md|b.md|bald");
    assert(bad.code === 2 && bad.output.includes("ganze Zahl von Tagen"), bad.output);
  } finally {
    Deno.removeSync(repo, { recursive: true });
  }
});

Deno.test("Quittung: gilt bis zum nächsten Commit der Basis", () => {
  const repo = dependsFixture();
  try {
    const ack = runWithAck(repo, "--ack", "late/dependent.md", "--ack", "zero/dependent.md");
    assert(ack.code === 1, `Frist 0 lässt sich nicht quittieren:\n${ack.output}`);
    assert(lineFor(ack.output, "late/dependent.md").includes("quittiert für Stand"), ack.output);
    assert(lineFor(ack.output, "zero/dependent.md").includes("denselben Commit"), ack.output);
    const file = Deno.readTextFileSync(`${repo}/.docs-check.ack`);
    assert(/^late\/dependent\.md\|late\/base\.md\|[0-9a-f]{40}\|\d{4}-/m.test(file), file);
    assert(!file.includes("zero/"), "abgelehnte Quittung fehlt in der Datei");

    const after = run("--root", repo, ...DEPENDS_ARGS);
    assert(lineFor(after.output, "late/dependent.md").includes("quittiert am"), after.output);
    assert(after.output.includes("2 Probleme · 3 Hinweise"), after.output);

    // Uncommittete Basis: erst committen.
    write(repo, "recent/base.md", "# Basis 4\n");
    const pending = runWithAck(repo, "--ack", "recent/dependent.md");
    assert(pending.code === 1 && pending.output.includes("erst committen"), pending.output);

    // Neuer Commit der Basis: Die Quittung gilt nicht mehr, der Hinweis kommt zurück.
    write(repo, "late/base.md", "# Basis 5\n");
    new Deno.Command("git", { args: ["-C", repo, "add", "late/base.md"] }).outputSync();
    commitAt(repo, daysAgo(0), "late/base.md");
    const again = run("--root", repo, ...DEPENDS_ARGS);
    const late = lineFor(again.output, "late/dependent.md");
    assert(late.includes("?") && !late.includes("quittiert"), again.output);

    // --ack-all quittiert alles, was geht, und behält fremde Zeilen.
    Deno.writeTextFileSync(
      `${repo}/.docs-check.ack`,
      `${Deno.readTextFileSync(`${repo}/.docs-check.ack`)}fremd.md|x.md|abc|2026-01-01\n`,
    );
    const all = runWithAck(repo, "--ack-all");
    assert(all.output.includes("quittiert für Stand"), all.output);
    const rewritten = Deno.readTextFileSync(`${repo}/.docs-check.ack`);
    assert(rewritten.includes("fremd.md|x.md|abc"), "fremde Quittung bleibt");
    assert(
      rewritten.split("\n").filter((line) => line.startsWith("late/")).length === 1,
      rewritten,
    );
  } finally {
    Deno.removeSync(repo, { recursive: true });
  }
});

Deno.test("Sprachfassungen: Gliederung und übernommene Teile je Abschnitt", () => {
  const repo = Deno.makeTempDirSync({ prefix: "docs-check-translation-" });
  new Deno.Command("git", { args: ["-C", repo, "init", "-q"] }).outputSync();
  const english = [
    "# App",
    "",
    "English · [Deutsch](README.de.md)",
    "",
    "## Setup",
    "",
    "Run `make dev` and read the [guide](docs/guide.md) and the",
    "[provider",
    "declaration](LICENSING.md). See [License](#license).",
    "",
    "```mermaid",
    "flowchart LR",
    "  a[Browser] --> b[Server]",
    "```",
    "",
    "```bash",
    "make dev",
    "```",
    "",
    "## License",
    "",
    "Licensed under the [EUPL](LICENSE).",
    "",
  ].join("\n");
  const german = [
    "# App",
    "",
    "[English](README.md) · Deutsch",
    "",
    "## Einrichten",
    "",
    "Starte `make dev` und lies die [Anleitung](docs/guide.md) und die",
    "[Anbieter-",
    "erklärung](LICENSING.md). Siehe [Lizenz](#lizenz).",
    "",
    "```mermaid",
    "flowchart LR",
    "  a[Browser] --> b[Dienst]",
    "```",
    "",
    "```bash",
    "make dev",
    "```",
    "",
    "## Lizenz",
    "",
    "Steht unter der [EUPL](LICENSE).",
    "",
  ].join("\n");
  write(repo, "ok/README.md", english);
  write(repo, "ok/README.de.md", german);
  // Ein Link fehlt, ein Absatz mehr, anderer Codeblock.
  write(repo, "drift/README.md", english);
  write(
    repo,
    "drift/README.de.md",
    german.replace(" und die\n[Anbieter-\nerklärung](LICENSING.md)", ".\n\nNeuer Absatz")
      .replace("```bash\nmake dev", "```bash\nmake start"),
  );
  // Ein Abschnitt mehr: die Gliederung weicht ab.
  write(repo, "toc/README.md", english);
  write(repo, "toc/README.de.md", german.replace("## Lizenz", "## Extra\n\nText.\n\n## Lizenz"));
  write(repo, "single/README.md", english);
  new Deno.Command("git", { args: ["-C", repo, "add", "-A"] }).outputSync();
  commitAt(repo, daysAgo(1));
  try {
    const ok = run("--root", repo, "--translation", "ok/README.md|ok/README.de.md|deutsch");
    assert(ok.code === 0, `gleiche Fassungen bestehen:\n${ok.output}`);
    assert(
      lineFor(ok.output, "ok/README.md ↔ ok/README.de.md").includes("gleich gegliedert"),
      `Übersetzte Anker, Sprachzeile, Mermaid und umbrochene Links zählen nicht:\n${ok.output}`,
    );

    const drift = run("--root", repo, "--translation", "drift/README.md|drift/README.de.md");
    assert(drift.code === 1, `Abweichung ist ein Problem:\n${drift.output}`);
    assert(
      lineFor(drift.output, "Link nur in drift/README.md").includes("LICENSING.md"),
      `fehlender Link genannt:\n${drift.output}`,
    );
    assert(lineFor(drift.output, "Absätze: 3 gegen 4") !== "", `Absätze gezählt:\n${drift.output}`);
    assert(
      lineFor(drift.output, "Codeblöcke weichen ab") !== "",
      `geänderter Codeblock genannt:\n${drift.output}`,
    );

    const toc = run("--root", repo, "--translation", "toc/README.md|toc/README.de.md");
    assert(toc.code === 1, `andere Gliederung ist ein Problem:\n${toc.output}`);
    assert(
      lineFor(toc.output, "Gliederung weicht ab").includes(
        "toc/README.de.md (4): # App · ## Einrichten · ## Extra · ## Lizenz",
      ),
      `beide Gliederungen genannt:\n${toc.output}`,
    );

    const single = run("--root", repo, "--translation", "single/README.md|single/README.de.md");
    assert(
      single.code === 1 && lineFor(single.output, "single/README.de.md fehlt") !== "",
      `fehlende Fassung ist ein Problem:\n${single.output}`,
    );

    const same = run("--root", repo, "--translation", "ok/README.md|./ok/README.md");
    assert(same.code === 2, `Original gleich Übersetzung ist ein Fehler:\n${same.output}`);
  } finally {
    Deno.removeSync(repo, { recursive: true });
  }
});

Deno.test("Aufräumen", () => {
  Deno.removeSync(root, { recursive: true });
});
