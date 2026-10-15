/**
 * docs-check.ts — Nutzerdokumente gegen das Projekt prüfen. Nur lesend, ohne Netz.
 *
 * Prüft je Markdown-Datei: Links und Bilder, Anker im Dokument, Anker, auf die
 * andere Dateien verlinken, Befehle (make, npm run, deno task, uv/poetry run,
 * cargo run), Variablen und Repo-Pfade in Code-Formatierung, vergessene
 * Platzhalter und verbotene Begriffe. Gedacht für den Aufruf über
 * `src/bash/docs-check.sh`, das die Projekt-Config liest; Agenten (Skill
 * readme-conventions) rufen es auch direkt auf.
 *
 * Aufruf (die Deno-Rechte erzwingen „nur lesen, nur git, kein Netz“):
 *   deno run --allow-read --allow-run=git docs-check.ts [OPTIONEN] DATEI|ORDNER...
 *
 * Optionen:
 *   --root DIR             Repository-Wurzel (Standard: aktuelles Verzeichnis)
 *   --forbid EINTRAG       Darf in keinem geprüften Dokument stehen:
 *                          BEGRIFF[|GRUND] (Text, Groß-/Kleinschreibung zählt)
 *                          oder /MUSTER/FLAGS[|GRUND] (regulärer Ausdruck, z. B.
 *                          /\bP[UG]ID\b/ oder /nobody:users/i)
 *   --exclude PFAD         Datei, Ordner oder Muster (relativ zur Wurzel) auslassen
 *   --max-alerts N         Höchstens N Hinweisboxen je Dokument (ohne: keine Grenze)
 *   --require EINTRAG      Pflichtdatei: NAME (irgendwo), PFAD oder MUSTER (* und **)
 *                          ab Root, optional |GRUND; zählt nur versioniert,
 *                          nicht leer und als .md mit Überschrift
 *   --links-only PFAD      Datei, Ordner oder Muster nur auf Links, Bilder und
 *                          Anker prüfen (interne Doku wie AGENTS.md)
 *   --known-variable NAME  Variable gilt als bekannt, optional NAME|GRUND
 *                          (z. B. aus einer nicht versionierten Bibliothek)
 *   --code-variables PFAD  Code (Datei, Ordner, Muster), dessen gelesene
 *                          Umgebungsvariablen ein geprüftes Dokument nennen muss
 *   --internal-variable NAME|GRUND
 *                          Vom Code gelesen, bewusst nicht dokumentiert
 *   --screenshot PFAD      Bild, Ordner oder Muster, dessen Alter geprüft wird
 *   --max-screenshot-age N Hinweis, wenn ein Screenshot laut git zuletzt vor
 *                          mehr als N Tagen geändert wurde (nur mit --screenshot)
 *   --depends BASIS|ABHÄNGIG|TAGE[|GRUND]
 *                          ABHÄNGIG muss BASIS folgen: Ändert sich die Basis
 *                          später, ist das ein Hinweis, nach TAGE Tagen ein
 *                          Problem (0: im selben Commit). Zeiten aus git;
 *                          uncommittete Änderungen zählen als „jetzt“
 *   --depends-hint EINTRAG Wie --depends, aber auch überfällig nur ein Hinweis
 *   --changes BASE[..HEAD] Statt der Prüfung: Kandidaten für den Doku-Abgleich
 *                          zwischen zwei Ständen (HEAD ohne Angabe: HEAD).
 *                          DATEI|ORDNER sind die Dokumente; gelesen wird nur aus git
 *   --ui-catalog PFAD      Mit --changes: Datei oder Muster mit UI-Texten (i18n)
 *   --json                 Mit --changes: Bericht als JSON
 *   --as PFAD              Späterer Ort einer einzelnen Datei im Repo (Entwurf)
 *   --verbose              Auch fehlerfreie Dateien, Zahlenangaben und URLs zeigen
 *
 * DATEI|ORDNER darf auch ein Muster sein (`*` in einem Ordner, `**` beliebig
 * tief, `?` ein Zeichen). Ordner und Muster treffen *.md und *.mdx, die git
 * nicht ignoriert; ein Muster ohne Treffer ist ein Problem. Links gelten relativ zum Ort
 * der Datei. Befehle und Pfade in Code-Formatierung gelten bei einem README
 * relativ zu seinem Verzeichnis (Unterprojekt), sonst relativ zur Wurzel.
 * Befehle werden in dem Verzeichnis geprüft, in dem sie laufen (cd im
 * Codeblock, make -C, npm --prefix; Deno und uv suchen ihre Konfiguration
 * aufwärts).
 *
 * Projektfakten stammen nur aus versionierten Dateien und nie aus sensiblen
 * Dateien (isSensitive: `.env` außer Beispielvarianten, Schlüssel, Zertifikate,
 * Secrets, Token, Zugangs- und Datenbankdateien) – auch nicht über
 * Makefile-Einbindungen.
 *
 * Ausgabe: zuerst jedes geprüfte Dokument mit Ergebnis, dann je Befund
 * Kategorie, Zeilen, was nicht stimmt und was zu tun ist. Kategorien:
 * „Problem“ (Exit-Code 1), „Hinweis“ (ein Mensch entscheidet, kein Fehler), „Ungeprüft“
 * (Befehle eines Ökosystems, das das Skript nicht kennt), „Info“ (nur mit
 * --verbose). --config-name nennt die Config in der Kopfzeile.
 *
 * Tests: deno test --allow-read --allow-write --allow-run=git,deno tests/deno/docs-check.test.ts
 */

const SKIP_DIRS = new Set([
  "node_modules",
  ".git",
  "dist",
  "build",
  "target",
  ".venv",
  "venv",
  "__pycache__",
  ".next",
  ".nuxt",
  "coverage",
  ".cache",
  ".idea",
  ".vscode",
  ".libs",
]);
const DOC_SUFFIXES = new Set([".md", ".mdx"]);
const TEXT_SUFFIXES = new Set([
  ".md",
  ".mdx",
  ".rst",
  ".txt",
  ".xml",
  ".html",
  ".yml",
  ".yaml",
  ".json",
  ".vue",
  ".ts",
  ".tsx",
  ".js",
  ".mjs",
  ".py",
]);
const CODE_SUFFIXES = new Set([
  ".ts",
  ".tsx",
  ".js",
  ".mjs",
  ".cjs",
  ".py",
  ".go",
  ".rs",
  ".sh",
  ".java",
  ".kt",
  ".rb",
  ".php",
]);
// Werkzeuge, die `uv run` / `poetry run` aus der Umgebung starten, ohne Eintrag in pyproject.toml.
const PYTHON_TOOLS = new Set([
  "python",
  "python3",
  "pytest",
  "ruff",
  "mypy",
  "black",
  "pip",
  "uvicorn",
  "gunicorn",
  "flask",
  "alembic",
  "coverage",
  "pre-commit",
  "ipython",
  "jupyter",
]);
// Befehle, für die es keine Prüfung gibt: Sie werden aufgelistet statt stillschweigend durchgelassen.
const UNVERIFIED =
  /^\s*(go\s+(?:run|build|test|install|generate)|mvn|\.\/mvnw|gradle|\.\/gradlew|composer|bundle\s+exec|rake|dotnet|swift\s+(?:run|build|test)|mix|cabal|stack)\b/;
const ENV_EXAMPLES = new Set([".env.example", ".env.sample", ".env.template", "env.example"]);
/**
 * Dateien, die Zugangsdaten, Schlüssel oder persönliche Daten enthalten
 * können. Das Skript öffnet sie nie – weder bei der Suche nach Variablen noch
 * über Makefile-Einbindungen noch als zu prüfendes Dokument. Beispieldateien
 * (ENV_EXAMPLES) bleiben lesbar.
 */
const SENSITIVE_NAME = new RegExp(
  [
    String.raw`^\.env(\..+)?$`,
    String.raw`^env$`,
    String.raw`\.env$`,
    String
      .raw`\.(pem|key|crt|cer|der|p12|pfx|jks|keystore|truststore|asc|gpg|kdbx|ovpn|sec|secrets?|token|tfstate|tfvars|sqlite3?|db)$`,
    String.raw`^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$`,
    String.raw`^known_hosts$`,
    String.raw`^authorized_keys$`,
    String.raw`^\.(netrc|npmrc|pypirc|git-credentials|htpasswd|dockercfg|pgpass|my\.cnf)$`,
    String
      .raw`^(secrets?|credentials?|auth|token|tokens|service[-_]?account)([-_.].*)?\.(json|ya?ml|toml|ini|txt|env)$`,
    String.raw`^(kubeconfig|wg\d*\.conf)$`,
    String.raw`\.tfstate\.backup$`,
  ].join("|"),
  "i",
);
const SENSITIVE_DIR = /(^|\/)(\.ssh|\.gnupg|\.aws|\.kube|\.docker|secrets?|\.local-data)(\/|$)/i;
const FENCE = /^\s*(```|~~~)/;
const ALERT = /^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/gm;
const LINK =
  /!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)|<img[^>]+src="([^"]+)"|<a[^>]+href="([^"]+)"|<source[^>]+srcset="([^"\s]+)/g;
const COUNT =
  /\b(?:two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|twenty|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|elf|zwölf|\d+)\s+(?:[\p{L}-]+\s+)?\p{L}+\b/giu;
const UNIT =
  /\b(seconds?|minutes?|hours?|days?|weeks?|months?|years?|pixels?|bytes?|lines?|words?|characters?|times|steps?|ports?|versions?|Sekunden|Minuten|Stunden|Tage[n]?|Wochen|Monate[n]?|Jahre[n]?|Pixel|Bytes?|Zeilen|Wörter[n]?|Zeichen|Schritte[n]?|Versionen)\b/iu;

/**
 * Ausdrückliche Lesezugriffe auf Umgebungsvariablen im Code. Zuweisungen und
 * Shell-Variablen (`$X`) zählen nicht: Sie lesen nicht sicher aus der Umgebung.
 */
const ENV_READS = [
  /process\.env\.([A-Z][A-Z0-9_]+)/g,
  /process\.env\[['"]([A-Z][A-Z0-9_]+)/g,
  /import\.meta\.env\.([A-Z][A-Z0-9_]+)/g,
  /Deno\.env\.get\(['"]([A-Z][A-Z0-9_]+)/g,
  /os\.environ(?:\.get)?\(?\[?['"]([A-Z][A-Z0-9_]+)/g,
  // getenv (Python, PHP, C), Getenv/LookupEnv (Go), System.getenv (Java/Kotlin)
  /[Gg]etenv\(['"]([A-Z][A-Z0-9_]+)/g,
  /LookupEnv\(['"]([A-Z][A-Z0-9_]+)/g,
  // Rust: env::var("X"), env::var_os("X")
  /env::var(?:_os)?\(['"]([A-Z][A-Z0-9_]+)/g,
  // Ruby: ENV["X"], ENV.fetch("X")
  /\bENV(?:\.fetch\(|\[)['"]([A-Z][A-Z0-9_]+)/g,
];

/** Testcode: liefert keine Projektfakten und keine Pflicht zur Doku. */
function isTestPath(path: string): boolean {
  return /(^|\/)(tests?|__tests__|spec)(\/|$)|\.(spec|test)\./.test(path);
}

export function isSensitive(path: string): boolean {
  const name = path.slice(path.lastIndexOf("/") + 1);
  if (ENV_EXAMPLES.has(name)) return false;
  return SENSITIVE_NAME.test(name) || SENSITIVE_DIR.test(path);
}

export interface Project {
  root: string;
  files: string[];
}

/** Make-Targets eines Verzeichnisses, samt fest eingebundener Dateien. */
interface MakeDir {
  targets: Set<string>;
  /** Eine Einbindung nutzt Variablen oder fehlt: Unbekannte Targets sind dann nur verdächtig. */
  unresolved: boolean;
}

interface Facts {
  makeTargets: Map<string, MakeDir>;
  npmScripts: Map<string, Set<string>>;
  denoTasks: Map<string, Set<string>>;
  pythonScripts: Map<string, Set<string>>;
  cargoNames: Set<string>;
  variables: Map<string, Set<string>>;
}

/**
 * Ein verbotener Begriff aus der Projekt-Config, mit optionaler Begründung.
 * `term` ist der Text aus der Config; `pattern` ist gesetzt, wenn er als
 * regulärer Ausdruck (`/muster/flags`) angegeben war.
 */
export interface Forbidden {
  term: string;
  reason: string;
  pattern?: RegExp;
}

/**
 * Liest einen Config-Eintrag: `BEGRIFF[|GRUND]` oder `/MUSTER/FLAGS[|GRUND]`.
 * Beim Muster endet der Ausdruck am ersten `/`, dem nur Flags und dann `|`
 * oder das Ende folgen; so darf das Muster selbst `|` enthalten. Ein `/` im
 * Muster wird als `\/` geschrieben.
 */
export function parseForbidden(entry: string): Forbidden | string {
  const regex = entry.match(/^\/(.+?)\/([dimsuv]*)(?:\|(.*))?$/s);
  if (regex) {
    try {
      return {
        term: `/${regex[1]}/${regex[2]}`,
        reason: (regex[3] ?? "").trim(),
        pattern: new RegExp(regex[1], regex[2]),
      };
    } catch (error) {
      return `ungültiger regulärer Ausdruck ${entry}: ${(error as Error).message}`;
    }
  }
  const [term, ...reason] = entry.split("|");
  return term ? { term, reason: reason.join("|").trim() } : `leerer Begriff: ${entry}`;
}

/**
 * Ein Befund. `problem` lässt die Prüfung scheitern; `check` muss ein Mensch
 * ansehen; `unchecked` kann das Skript nicht prüfen; `info` erscheint nur mit
 * --verbose. `message` sagt, was nicht stimmt, `advice`, was zu tun ist.
 */
export interface Finding {
  lines: number[];
  level: "problem" | "check" | "unchecked" | "info";
  message: string;
  advice: string;
}

// ------------------------------------------------------------ Hilfen

function suffix(path: string): string {
  const dot = path.lastIndexOf(".");
  return dot > path.lastIndexOf("/") ? path.slice(dot).toLowerCase() : "";
}

function baseName(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

function readText(path: string): string {
  try {
    return Deno.readTextFileSync(path);
  } catch {
    return "";
  }
}

/** Prozent-kodierte Linkpfade (z. B. %20) wie der Browser auflösen; kaputte Kodierung bleibt stehen. */
function safeDecode(path: string): string {
  try {
    return decodeURI(path);
  } catch {
    return path;
  }
}

function exists(path: string): boolean {
  try {
    Deno.statSync(path);
    return true;
  } catch {
    return false;
  }
}

function git(root: string, ...args: string[]): string {
  try {
    const output = new Deno.Command("git", {
      args: ["-C", root, ...args],
      stdout: "piped",
      stderr: "null",
    }).outputSync();
    return output.success ? new TextDecoder().decode(output.stdout).trim() : "";
  } catch {
    return "";
  }
}

function normalize(path: string): string {
  const parts: string[] = [];
  for (const part of path.split("/")) {
    if (part === "..") parts.pop();
    else if (part && part !== ".") parts.push(part);
  }
  return parts.join("/");
}

function directoryOf(path: string): string {
  return path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : ".";
}

/** Pfad relativ zu einem Verzeichnis des Repos auflösen; '.' ist die Wurzel. */
function join(directory: string, relative: string): string {
  return normalize(`${directory}/${relative}`) || ".";
}

/**
 * Projektdateien: nur, was git versioniert – unversionierte Dateien können
 * frische Geheimnisse sein, die noch in keinem .gitignore stehen. Ohne git ein
 * begrenzter Lauf ohne Symlinks. Sensible Dateien (isSensitive) fehlen immer.
 */
function listFiles(root: string): string[] {
  const listed = git(root, "ls-files", "--cached");
  if (listed) {
    return [...new Set(listed.split("\n"))]
      .filter((path) => !path.split("/").some((part) => SKIP_DIRS.has(part)) && !isSensitive(path))
      .filter((path) => {
        try {
          const info = Deno.lstatSync(`${root}/${path}`);
          return info.isFile && !info.isSymlink;
        } catch {
          return false;
        }
      })
      .sort();
  }
  const result: string[] = [];
  const walk = (directory: string, depth: number) => {
    for (const entry of Deno.readDirSync(`${root}/${directory}`)) {
      if (entry.isSymlink) continue;
      const path = directory ? `${directory}/${entry.name}` : entry.name;
      if (
        entry.isDirectory && !SKIP_DIRS.has(entry.name) && !entry.name.startsWith(".") &&
        !isSensitive(`${path}/x`) && depth < 4
      ) walk(path, depth + 1);
      else if (entry.isFile && !isSensitive(path)) result.push(path);
    }
  };
  walk("", 0);
  return result.sort();
}

export function loadProject(root = "."): Project {
  const real = Deno.realPathSync(root);
  return { root: real, files: listFiles(real) };
}

/**
 * Targets eines Makefiles und der Dateien, die es mit festem Pfad einbindet.
 * Eingebundene sensible Dateien (z. B. `-include .env`) werden nie geöffnet:
 * Sie enthalten Zugangsdaten und keine Targets.
 */
function readMakefile(root: string, path: string, info: MakeDir, seen: Set<string>): void {
  if (seen.has(path)) return;
  seen.add(path);
  const text = readText(`${root}/${path}`);
  for (const match of text.matchAll(/^([A-Za-z0-9_.-]+(?:[ \t]+[A-Za-z0-9_.-]+)*)[ \t]*:(?!=)/gm)) {
    for (const target of match[1].split(/\s+/)) info.targets.add(target);
  }
  for (const match of text.matchAll(/^[ \t]*-?s?include[ \t]+(.+)$/gm)) {
    for (const file of match[1].trim().split(/\s+/)) {
      if (isSensitive(file)) continue;
      if (/[$*?]/.test(file)) {
        info.unresolved = true;
        continue;
      }
      const included = join(directoryOf(path), file);
      if (exists(`${root}/${included}`)) readMakefile(root, included, info, seen);
      else info.unresolved = true;
    }
  }
}

/** Sehr einfacher TOML-Leser: Schlüssel je Abschnitt, Werte nur als Text. */
function tomlSections(text: string): Map<string, Array<[string, string]>> {
  const sections = new Map<string, Array<[string, string]>>();
  let current = "";
  for (const raw of text.split("\n")) {
    const line = raw.replace(/\s+#.*$/, "").trim();
    const header = line.match(/^\[\[?([^\]]+)\]\]?$/);
    if (header) {
      current = header[1].trim();
      if (!sections.has(current)) sections.set(current, []);
      continue;
    }
    const pair = line.match(/^["']?([\w.-]+)["']?\s*=\s*(.*)$/);
    if (pair) {
      if (!sections.has(current)) sections.set(current, []);
      sections.get(current)!.push([pair[1], pair[2].replace(/^["']|["']$/g, "")]);
    }
  }
  return sections;
}

function collectFacts(project: Project): Facts {
  const makeTargets = new Map<string, MakeDir>();
  const npmScripts = new Map<string, Set<string>>();
  const denoTasks = new Map<string, Set<string>>();
  const pythonScripts = new Map<string, Set<string>>();
  const cargoNames = new Set<string>();
  const variables = new Map<string, Set<string>>();
  const addVariable = (name: string, source: string) => {
    if (!variables.has(name)) variables.set(name, new Set());
    variables.get(name)!.add(source);
  };
  for (const path of project.files) {
    const name = baseName(path);
    const full = `${project.root}/${path}`;
    if (["Makefile", "makefile", "GNUmakefile"].includes(name) || suffix(path) === ".mk") {
      const makefile = readText(full);
      for (const match of makefile.matchAll(/^\s*(?:export\s+)?([A-Z][A-Z0-9_]+)\s*[?:+]?=/gm)) {
        addVariable(match[1], path);
      }
      // Targets je Verzeichnis: `make x` läuft dort, wo das Makefile liegt.
      if (suffix(path) !== ".mk") {
        const directory = directoryOf(path);
        if (!makeTargets.has(directory)) {
          makeTargets.set(directory, { targets: new Set(), unresolved: false });
        }
        readMakefile(project.root, path, makeTargets.get(directory)!, new Set());
      }
    } else if (name === "package.json") {
      try {
        const data = JSON.parse(readText(full));
        npmScripts.set(directoryOf(path), new Set(Object.keys(data.scripts ?? {})));
      } catch { /* kaputtes package.json überspringen */ }
    } else if (name === "deno.json" || name === "deno.jsonc") {
      try {
        const data = JSON.parse(
          readText(full).replace(/^\s*\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, ""),
        );
        denoTasks.set(directoryOf(path), new Set(Object.keys(data.tasks ?? {})));
      } catch { /* kaputte deno.json überspringen */ }
    } else if (name === "pyproject.toml") {
      const sections = tomlSections(readText(full));
      const scripts = [
        ...(sections.get("project.scripts") ?? []),
        ...(sections.get("tool.poetry.scripts") ?? []),
      ];
      pythonScripts.set(directoryOf(path), new Set(scripts.map(([key]) => key)));
    } else if (name === "Cargo.toml") {
      const sections = tomlSections(readText(full));
      for (const key of ["package", "bin"]) {
        for (const [field, value] of sections.get(key) ?? []) {
          if (field === "name") cargoNames.add(value);
        }
      }
    } else if (ENV_EXAMPLES.has(name)) {
      for (const match of readText(full).matchAll(/^\s*([A-Z][A-Z0-9_]+)\s*=/gm)) {
        addVariable(match[1], path);
      }
    }
    const isCode = CODE_SUFFIXES.has(suffix(path)) || name.startsWith("Dockerfile") ||
      /(compose|Procfile)/.test(name);
    if (isCode && !isTestPath(path)) {
      const text = readText(full);
      const patterns = [
        ...ENV_READS,
        /^\s*(?:ENV\s+)?([A-Z][A-Z0-9_]+)=/gm,
        /\$\{?([A-Z][A-Z0-9_]{2,})\b/g,
      ];
      for (const pattern of patterns) {
        for (const match of text.matchAll(pattern)) addVariable(match[1], path);
      }
    }
  }
  return { makeTargets, npmScripts, denoTasks, pythonScripts, cargoNames, variables };
}

/** Anker, auf die andere Dateien in `target` (Pfad im Repo, z. B. api/README.md) verlinken. */
function inboundAnchors(project: Project, target: string): Map<string, Set<string>> {
  const anchors = new Map<string, Set<string>>();
  const name = baseName(target).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  // Anker mit Umlauten, roh (#prüfen) oder kodiert (#pr%C3%BCfen).
  const pattern = new RegExp(`([\\w./-]*${name})#([\\p{L}\\p{N}_%-]+)`, "gu");
  for (const path of project.files) {
    if (!TEXT_SUFFIXES.has(suffix(path)) || path === target) continue;
    const directory = path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "";
    for (const match of readText(`${project.root}/${path}`).matchAll(pattern)) {
      if (normalize(directory ? `${directory}/${match[1]}` : match[1]) !== target) continue;
      const anchor = safeDecode(match[2]);
      if (!anchors.has(anchor)) anchors.set(anchor, new Set());
      anchors.get(anchor)!.add(path);
    }
  }
  return anchors;
}

/** GitHub-Anker einer Überschrift. */
function slugify(heading: string): string {
  return heading.replace(/<[^>]+>/g, "").trim().toLowerCase()
    .replace(/[`*_~[\]()]/g, "")
    .replace(/[^\p{L}\p{N}\- ]/gu, "")
    .replace(/ /g, "-");
}

/** Zeilen außerhalb von Codeblöcken, mit Zeilennummer. */
function proseLines(text: string): Array<[number, string]> {
  const result: Array<[number, string]> = [];
  let inFence = false;
  text.split("\n").forEach((line, index) => {
    if (FENCE.test(line)) {
      inFence = !inFence;
      return;
    }
    if (!inFence) result.push([index + 1, line]);
  });
  return result;
}

/**
 * Inline-Code und Codeblöcke – dort stehen Befehle, Variablen und Pfade. Das
 * dritte Feld nennt den Codeblock (Nummer ab 0) oder -1 für Inline-Code; ein
 * `cd` gilt bis zum Ende seines Blocks.
 */
function codeSnippets(text: string): Array<[number, string, number]> {
  const result: Array<[number, string, number]> = [];
  let inFence = false;
  let block = -1;
  text.split("\n").forEach((line, index) => {
    if (FENCE.test(line)) {
      inFence = !inFence;
      if (inFence) block++;
      return;
    }
    if (inFence) result.push([index + 1, line, block]);
    else for (const match of line.matchAll(/`([^`]+)`/g)) result.push([index + 1, match[1], -1]);
  });
  return result;
}

/** Kommt der Name in irgendeiner versionierten Nicht-Markdown-Datei vor? Schwacher, aber echter Beleg. */
function mentionedOutsideDocs(name: string, project: Project, cache: Map<string, string>): boolean {
  for (const path of project.files) {
    if ([".md", ".mdx", ".png", ".jpg", ".svg", ".gif", ".webp", ".ico"].includes(suffix(path))) {
      continue;
    }
    if (!cache.has(path)) cache.set(path, readText(`${project.root}/${path}`));
    if (new RegExp(`\\b${name}\\b`).test(cache.get(path)!)) return true;
  }
  return false;
}

/** Nächstes Verzeichnis ab `directory` aufwärts, für das eine Karte Einträge hat (wie Deno und uv suchen). */
function upward<T>(map: Map<string, T>, directory: string): [string, T] | undefined {
  for (let current = directory;; current = directoryOf(current)) {
    if (map.has(current)) return [current, map.get(current)!];
    if (current === ".") return undefined;
  }
}

type Report = (level: Finding["level"], message: string, advice: string) => void;

/** Ort eines Befehls in Worten: „in der Wurzel“ oder „in api/“. */
function inDirectory(directory: string): string {
  return directory === "." ? "in der Wurzel" : `in ${directory}/`;
}

/** Prüft einen einzelnen Befehl gegen das Verzeichnis, in dem er läuft. */
function checkCommand(command: string, directory: string, facts: Facts, report: Report): void {
  const fix = "Befehl korrigieren oder entfernen.";
  for (const match of command.matchAll(/\bmake\s+(?:-C\s+(\S+)\s+)?([A-Za-z0-9_.-]+)/g)) {
    const target = match[2];
    if (target.includes("=") || target.startsWith("-")) continue;
    const makeDirectory = match[1] ? join(directory, match[1]) : directory;
    const info = facts.makeTargets.get(makeDirectory);
    if (!info) {
      report(
        "problem",
        `\`make ${target}\`: Es gibt kein Makefile ${inDirectory(makeDirectory)}.`,
        fix,
      );
    } else if (!info.targets.has(target)) {
      if (info.unresolved) {
        report(
          "check",
          `\`make ${target}\`: Das Target steht nicht im Makefile ${inDirectory(makeDirectory)}. ` +
            "Das Makefile bindet aber Dateien über Variablen ein, die das Skript nicht auflösen kann.",
          `Mit \`make help\` nachsehen, ob es das Target gibt; sonst ${fix.toLowerCase()}`,
        );
      } else {
        report(
          "problem",
          `\`make ${target}\`: Dieses Target gibt es im Makefile ${
            inDirectory(makeDirectory)
          } nicht.`,
          fix,
        );
      }
    }
  }
  for (
    const match of command.matchAll(
      /\bnpm\s+(?:--prefix\s+(\S+)\s+)?run\s+([\w:.-]+)(?:\s+--prefix\s+(\S+))?/g,
    )
  ) {
    const prefix = match[1] ?? match[3];
    const npmDirectory = prefix ? join(directory, prefix) : directory;
    const scripts = facts.npmScripts.get(npmDirectory);
    if (!scripts) {
      report(
        "problem",
        `\`npm run ${match[2]}\`: Es gibt kein package.json ${inDirectory(npmDirectory)}.`,
        fix,
      );
    } else if (!scripts.has(match[2])) {
      report(
        "problem",
        `\`npm run ${match[2]}\`: Dieses Skript steht nicht im package.json ${
          inDirectory(npmDirectory)
        }.`,
        fix,
      );
    }
  }
  for (const match of command.matchAll(/\bdeno\s+task\s+([\w:.-]+)/g)) {
    const found = upward(facts.denoTasks, directory);
    if (!found) {
      report(
        "problem",
        `\`deno task ${match[1]}\`: Es gibt keine deno.json ${
          inDirectory(directory)
        } oder darüber.`,
        fix,
      );
    } else if (!found[1].has(match[1])) {
      report(
        "problem",
        `\`deno task ${match[1]}\`: Dieser Task steht nicht in ${found[0]}/deno.json.`,
        fix,
      );
    }
  }
  for (const match of command.matchAll(/\b(uv|poetry|pdm|hatch)\s+run\s+(?:--\S+\s+)*([\w.-]+)/g)) {
    const name = match[2];
    if (PYTHON_TOOLS.has(name) || /^python\d/.test(name)) continue;
    const found = upward(facts.pythonScripts, directory);
    if (!found || !found[1].has(name)) {
      report(
        "check",
        `\`${match[1]} run ${name}\`: ${name} ist kein Skript in pyproject.toml.`,
        `Prüfen, ob ${name} ein installiertes Werkzeug ist; sonst ${fix.toLowerCase()}`,
      );
    }
  }
  for (
    const match of command.matchAll(/\bcargo\s+run\b[^\n]*?(?:--bin|-p|--package)\s+([\w-]+)/g)
  ) {
    if (!facts.cargoNames.has(match[1])) {
      report(
        "problem",
        `\`cargo run\`: Ein Paket oder Binary „${match[1]}“ gibt es in keiner Cargo.toml.`,
        fix,
      );
    }
  }
  const unverified = command.match(UNVERIFIED);
  if (unverified) {
    const tool = unverified[1].split(/\s+/)[0];
    report(
      "unchecked",
      `\`${
        command.trim().slice(0, 60)
      }\`: ${tool}-Befehle kann das Skript nicht gegen das Projekt prüfen.`,
      "Von Hand prüfen, ob der Befehl noch stimmt.",
    );
  }
}

/** Befehle, Variablen und Repo-Pfade in Code-Formatierung. */
function checkClaims(
  text: string,
  project: Project,
  facts: Facts,
  baseDirectory: string,
  add: (finding: Finding) => void,
): void {
  const cache = new Map<string, string>();
  const topLevel = new Set(project.files.map((path) => path.split("/")[0]));
  const localPrefix = baseDirectory === "." ? "" : `${baseDirectory}/`;
  const localTop = new Set(
    project.files.filter((path) => path.startsWith(localPrefix)).map((path) =>
      path.slice(localPrefix.length).split("/")[0]
    ),
  );
  // Gleiche Meldungen zusammenfassen: ein Befund mit allen Zeilen.
  const byMessage = new Map<string, Finding>();
  const once = (line: number, level: Finding["level"], message: string, advice: string) => {
    const known = byMessage.get(message);
    if (known) {
      if (!known.lines.includes(line)) known.lines.push(line);
      return;
    }
    const finding = { lines: [line], level, message, advice };
    byMessage.set(message, finding);
    add(finding);
  };
  let block = -2;
  let directory: string | undefined = baseDirectory;
  for (const [line, snippet, snippetBlock] of codeSnippets(text)) {
    if (snippetBlock !== block || snippetBlock < 0) {
      block = snippetBlock;
      directory = baseDirectory;
    }
    for (const part of snippet.split(/&&|\|\||;/)) {
      const cd = part.match(/^\s*cd\s+(\S+)\s*$/);
      if (cd) {
        // ~, $VAR, absolute Pfade und `cd -` lassen sich nicht auflösen.
        directory = directory && !/^[~$\/-]/.test(cd[1]) ? join(directory, cd[1]) : undefined;
        continue;
      }
      if (!directory) {
        if (/\b(make|npm|deno|uv|poetry|cargo)\s/.test(part)) {
          once(
            line,
            "unchecked",
            `\`${
              part.trim().slice(0, 60)
            }\`: Der Befehl läuft nach einem \`cd\` in ein Verzeichnis, ` +
              "das das Skript nicht auflösen kann.",
            "Von Hand prüfen, ob der Befehl noch stimmt.",
          );
        }
        continue;
      }
      checkCommand(
        part,
        directory,
        facts,
        (level, message, advice) => once(line, level, message, advice),
      );
    }
    for (const match of snippet.matchAll(/\b([A-Z][A-Z0-9]*_[A-Z0-9_]+)\b/g)) {
      const name = match[1];
      if (facts.variables.has(name) || mentionedOutsideDocs(name, project, cache)) continue;
      once(
        line,
        "check",
        `\`${name}\`: Diese Variable kommt in keiner versionierten Projektdatei vor.`,
        "Prüfen, ob sie aus einer eingebundenen Bibliothek stammt; sonst ist sie veraltet und gehört raus.",
      );
    }
    // Repo-Pfade dürfen relativ zum Ort des Dokuments oder zur Wurzel stehen.
    const pathLike = snippet.trim();
    const inRepo = pathLike.startsWith("./") || topLevel.has(pathLike.split("/")[0]) ||
      localTop.has(pathLike.split("/")[0]);
    if (inRepo && /^(\.\/)?[\w.-]+(\/[\w.-]+)*\/?$/.test(pathLike) && pathLike.includes("/")) {
      const found = [join(baseDirectory, pathLike), normalize(pathLike)].some((path) =>
        exists(`${project.root}/${path}`)
      );
      if (!found) {
        once(
          line,
          "problem",
          `\`${pathLike}\`: Diesen Pfad gibt es im Repository nicht.`,
          "Pfad korrigieren oder entfernen.",
        );
      }
    }
  }
}

/**
 * Projektregeln aus der Config. Grenzwerte gelten nur, wenn das Projekt sie
 * setzt; das Skript bringt keine eigenen mit.
 */
export interface Rules {
  forbidden: Forbidden[];
  /** Höchstzahl farbiger Hinweisboxen (`> [!WARNING]` usw.) je Dokument. */
  maxAlerts?: number;
  /** Variablen, die als bekannt gelten, obwohl keine versionierte Datei sie nennt. */
  knownVariables?: string[];
  /** Nur Links, Bilder und Anker prüfen (interne Doku). */
  linksOnly?: boolean;
  verbose: boolean;
}

/** Gleiche Befunde an mehreren Stellen zu einem Befund mit allen Zeilen zusammenfassen. */
function mergeFindings(findings: Finding[]): Finding[] {
  const merged = new Map<string, Finding>();
  for (const finding of findings) {
    const known = merged.get(`${finding.level}:${finding.message}`);
    if (known) known.lines.push(...finding.lines.filter((line) => !known.lines.includes(line)));
    else merged.set(`${finding.level}:${finding.message}`, finding);
  }
  return [...merged.values()].sort((a, b) => (a.lines[0] ?? 0) - (b.lines[0] ?? 0));
}

/**
 * Prüft ein Dokument. `placement` ist sein Ort im Repo (für einen Entwurf an
 * anderer Stelle der spätere Ort): Links gelten relativ zu diesem Ort,
 * eingehende Anker für genau diese Datei.
 */
export function checkDocument(
  path: string,
  project: Project,
  placement: string,
  rules: Rules = { forbidden: [], verbose: false },
): Finding[] {
  const { forbidden, verbose } = rules;
  const findings: Finding[] = [];
  const add = (finding: Finding) => findings.push(finding);
  const text = readText(path);
  const lines = text.split("\n");
  const prose = proseLines(text);
  const target = normalize(placement);
  const home = directoryOf(target);
  const isReadme = /^readme\.mdx?$/i.test(baseName(target));

  const slugs = new Set<string>();
  for (const [, content] of prose) {
    const match = content.match(/^#{1,6}\s+(.*)$/);
    if (!match) continue;
    const slug = slugify(match[1]);
    let unique = slug;
    for (let index = 1; slugs.has(unique); index++) unique = `${slug}-${index}`;
    slugs.add(unique);
  }
  for (const match of text.matchAll(/<a\s+(?:name|id)="([^"]+)"/g)) slugs.add(match[1]);

  lines.forEach((content, index) => {
    for (const match of content.matchAll(LINK)) {
      const link = match[1] ?? match[2] ?? match[3] ?? match[4];
      if (/^(https?:|mailto:|data:)/.test(link)) continue;
      const [pathPart, rawAnchor] = link.split("#");
      const anchor = rawAnchor && safeDecode(rawAnchor);
      // Absolute Pfade zeigen aus dem Repo heraus und gelten, wie sie dastehen.
      const linked = pathPart.startsWith("/")
        ? safeDecode(pathPart)
        : `${project.root}/${join(home, safeDecode(pathPart))}`;
      if (!pathPart) {
        if (anchor && !slugs.has(anchor)) {
          add({
            lines: [index + 1],
            level: "problem",
            message: `Link auf #${anchor}: Im Dokument gibt es keine Überschrift dazu.`,
            advice: "Link an die Überschrift anpassen oder die Überschrift wiederherstellen.",
          });
        }
      } else if (!exists(linked)) {
        add({
          lines: [index + 1],
          level: "problem",
          message: `${
            /^(!|<img|<source)/.test(match[0]) ? "Bild" : "Link"
          } auf ${link}: Die Datei gibt es nicht.`,
          advice: "Pfad korrigieren, Datei anlegen oder Link entfernen.",
        });
      }
    }
  });

  for (const [anchor, sources] of [...inboundAnchors(project, target)].sort()) {
    if (!slugs.has(anchor)) {
      add({
        lines: [],
        level: "problem",
        message: `Überschrift für #${anchor} fehlt, obwohl ${
          [...sources].sort().slice(0, 3).join(", ")
        } darauf verlinkt.`,
        advice: "Überschrift wiederherstellen oder den Link in der anderen Datei anpassen.",
      });
    }
  }

  if (rules.linksOnly) return mergeFindings(findings);

  // Variablen aus der Config gelten wie solche aus versionierten Dateien.
  const facts = collectFacts(project);
  for (const name of rules.knownVariables ?? []) {
    if (!facts.variables.has(name)) facts.variables.set(name, new Set());
    facts.variables.get(name)!.add("Config");
  }
  // Ein README eines Unterprojekts beschreibt sein Verzeichnis, andere
  // Dokumente (z. B. docs/development.md) beschreiben das Projekt von der Wurzel aus.
  checkClaims(text, project, facts, isReadme ? home : ".", add);

  // Grenze für Hinweisboxen nur, wenn die Projekt-Config eine setzt.
  if (rules.maxAlerts !== undefined) {
    const alerts = [...text.matchAll(ALERT)].map((match) => ({
      line: text.slice(0, match.index).split("\n").length,
      kind: `[!${match[1]}]`,
    }));
    if (alerts.length > rules.maxAlerts) {
      add({
        lines: alerts.map((alert) => alert.line),
        level: "check",
        message: `${alerts.length} farbige Hinweisboxen (${
          alerts.map((alert) => alert.kind).join(", ")
        }); die Config erlaubt höchstens ${rules.maxAlerts} (MAX_ALERTS).`,
        advice: "Nur die wirklich wichtigen behalten oder MAX_ALERTS in der Config anpassen.",
      });
    }
  }

  for (const { term, reason, pattern } of forbidden) {
    // Jeder verschiedene Treffer einzeln, auch mehrere in derselben Zeile.
    const global = pattern
      ? new RegExp(pattern.source, `${pattern.flags.replace("g", "")}g`)
      : undefined;
    const hits = new Map<string, number[]>();
    lines.forEach((content, index) => {
      const found = global
        ? [...content.matchAll(global)].map((match) => match[0]).filter(Boolean)
        : content.includes(term)
        ? [term]
        : [];
      for (const hit of new Set(found)) {
        const hitLines = hits.get(hit) ?? [];
        if (!hitLines.includes(index + 1)) hits.set(hit, [...hitLines, index + 1]);
      }
    });
    for (const [hit, hitLines] of hits) {
      add({
        lines: hitLines,
        level: "problem",
        message: `Verbotener Text „${hit}“${pattern ? ` (Muster ${term})` : ""}${
          reason ? `. Grund: ${reason}` : ""
        }.`,
        advice: "Stelle umformulieren; laut Projekt-Config gehört der Text nicht in diese Doku.",
      });
    }
  }

  lines.forEach((content, index) => {
    if (/\b(TODO|FIXME|TBD|lorem ipsum)\b|<your[ -]|\[insert /i.test(content)) {
      add({
        lines: [index + 1],
        level: "problem",
        message: `Platzhalter: „${content.trim().slice(0, 70)}“.`,
        advice: "Ausfüllen oder entfernen.",
      });
    }
  });

  if (verbose) {
    for (const [line, content] of prose) {
      for (const match of content.matchAll(COUNT)) {
        if (!UNIT.test(match[0])) {
          add({
            lines: [line],
            level: "info",
            message: `Zahlenangabe „${match[0]}“.`,
            advice: "Gegen die Quelle prüfen; Zahlen veralten leicht.",
          });
        }
      }
    }
    for (const url of [...new Set(text.match(/https?:\/\/[^\s)"'>`]+/g) ?? [])].sort()) {
      add({
        lines: [],
        level: "info",
        message: `Externe URL ${url}.`,
        advice: "Prüfen, ob sie noch erreichbar ist.",
      });
    }
  }

  return mergeFindings(findings);
}

/**
 * Markdown-Dateien eines Ordners (relativ zur Wurzel, "" ist die Wurzel),
 * ohne Symlinks und sensible Dateien.
 */
function markdownFiles(root: string, directory: string): string[] {
  const result: string[] = [];
  for (const entry of Deno.readDirSync(`${root}/${directory}`)) {
    const path = directory ? `${directory}/${entry.name}` : entry.name;
    if (entry.isSymlink || isSensitive(path)) continue;
    if (entry.isDirectory && !SKIP_DIRS.has(entry.name)) result.push(...markdownFiles(root, path));
    else if (entry.isFile && DOC_SUFFIXES.has(suffix(entry.name))) result.push(path);
  }
  return result.sort();
}

/**
 * Markdown-Dateien, die Ordner und Muster treffen dürfen: versionierte und
 * neue, aber keine von git ignorierten (erzeugte Vorschauen, lokale Notizen).
 * Ohne git alle Markdown-Dateien auf der Platte.
 */
function candidateDocuments(root: string): string[] {
  const listed = git(root, "ls-files", "--cached", "--others", "--exclude-standard");
  if (!listed) return markdownFiles(root, "");
  return [...new Set(listed.split("\n"))]
    .filter((path) =>
      DOC_SUFFIXES.has(suffix(path)) && !isSensitive(path) &&
      !path.split("/").some((part) => SKIP_DIRS.has(part)) && exists(`${root}/${path}`)
    )
    .sort();
}

/** Enthält der Pfad ein Glob-Muster (`*`, `**`, `?`)? */
function isGlob(path: string): boolean {
  return /[*?]/.test(path);
}

/**
 * Dateien, Ordner und Glob-Muster (relativ zur Wurzel) zu einer Liste von
 * Dokumenten, ohne ausgeschlossene Pfade. Ein Muster trifft Markdown-Dateien
 * auf der Platte; ohne Treffer gilt es wie ein fehlender Pfad. Ein
 * Ausschluss ist ein Pfad (Datei oder Ordner samt Inhalt) oder ein Muster,
 * das die Datei oder einen ihrer Ordner trifft.
 */
export function expandDocuments(
  root: string,
  inputs: string[],
  excludes: string[],
): { documents: string[]; missing: Array<{ input: string; reason: string }> } {
  const excluded = excludes.map((entry) => normalize(entry));
  const isExcluded = (path: string) =>
    excluded.some((entry) => {
      if (!isGlob(entry)) return path === entry || path.startsWith(`${entry}/`);
      const matcher = globToRegExp(entry);
      const parts = path.split("/");
      return parts.some((_, index) => matcher.test(parts.slice(0, index + 1).join("/")));
    });
  const documents: string[] = [];
  const missing: Array<{ input: string; reason: string }> = [];
  let candidates: string[] | undefined;
  const add = (found: string[]) => {
    for (const document of found) {
      if (!isExcluded(document) && !documents.includes(document)) documents.push(document);
    }
  };
  for (const input of inputs) {
    const path = normalize(input);
    if (isGlob(path)) {
      candidates ??= candidateDocuments(root);
      const matcher = globToRegExp(path);
      const found = candidates.filter((document) => matcher.test(document));
      if (!found.length) missing.push({ input, reason: "Muster trifft keine Markdown-Datei" });
      add(found);
      continue;
    }
    let info: Deno.FileInfo;
    try {
      info = Deno.statSync(`${root}/${path}`);
    } catch {
      missing.push({ input, reason: "Datei oder Ordner fehlt" });
      continue;
    }
    if (info.isDirectory) {
      candidates ??= candidateDocuments(root);
      add(candidates.filter((document) => path === "" || document.startsWith(`${path}/`)));
    } else if (!isSensitive(path)) add([path]);
  }
  return { documents, missing };
}

// ------------------------------------------------------------ Pflichtdateien

/** Eine Pflichtdatei aus der Config: Name, Pfad oder Muster, mit optionalem Grund. */
export interface Required {
  entry: string;
  reason: string;
  matcher: RegExp;
}

/** Ergebnis einer Pflichtdatei: gültige Treffer oder warum es keinen gibt. */
export interface RequiredResult {
  required: Required;
  found: string[];
  /** Gesetzt, wenn kein gültiger Treffer existiert. */
  failure?: string;
}

/**
 * Glob als regulärer Ausdruck: `**` beliebig viele Ordner, `*` beliebige
 * Zeichen ohne `/`, `?` ein Zeichen ohne `/`.
 */
function globToRegExp(glob: string): RegExp {
  let pattern = "";
  for (let index = 0; index < glob.length; index++) {
    const char = glob[index];
    if (char === "*" && glob[index + 1] === "*") {
      const slash = glob[index + 2] === "/";
      pattern += slash ? "(?:.*/)?" : ".*";
      index += slash ? 2 : 1;
    } else if (char === "*") pattern += "[^/]*";
    else if (char === "?") pattern += "[^/]";
    else pattern += char.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  }
  return new RegExp(`^${pattern}$`);
}

/**
 * Liest einen Config-Eintrag `NAME|PFAD|MUSTER[|GRUND]`. Ohne `/` gilt der
 * Eintrag für den Dateinamen an beliebiger Stelle im Projekt, mit `/` für den
 * Pfad ab dem Projekt-Root; `./README.md` meint also nur das README im Root.
 */
export function parseRequired(entry: string): Required | string {
  const [raw, ...reason] = entry.split("|");
  const path = raw.trim().replace(/^\.\//, "");
  if (!path) return `leere Pflichtdatei: ${entry}`;
  const anywhere = !raw.trim().includes("/");
  const glob = globToRegExp(path);
  return {
    entry: raw.trim(),
    reason: reason.join("|").trim(),
    matcher: anywhere ? new RegExp(glob.source.replace(/^\^/, "(?:^|/)")) : glob,
  };
}

/**
 * Warum eine vorhandene Datei nicht als Pflichtdatei zählt: leer, oder als
 * Markdown ohne Überschrift. `undefined` heißt gültig.
 */
function invalidReason(project: Project, path: string): string | undefined {
  const text = readText(`${project.root}/${path}`);
  if (!text.trim()) return "ist leer";
  if (
    DOC_SUFFIXES.has(suffix(path)) &&
    !proseLines(text).some(([, line]) => /^#{1,6}\s+\S/.test(line))
  ) {
    return "hat keine Überschrift (z. B. „# Titel“)";
  }
  return undefined;
}

/**
 * Prüft Pflichtdateien gegen die versionierten Dateien des Projekts. Eine
 * Datei, die nur auf der Platte liegt, zählt nicht: Im Repository fehlt sie.
 */
export function checkRequired(project: Project, required: Required[]): RequiredResult[] {
  return required.map((item) => {
    const matches = project.files.filter((path) => item.matcher.test(path));
    if (!matches.length) {
      return {
        required: item,
        found: [],
        failure: "fehlt im Repository (nicht versioniert oder nicht vorhanden)",
      };
    }
    const valid = matches.filter((path) => !invalidReason(project, path));
    if (valid.length) return { required: item, found: valid };
    return {
      required: item,
      found: [],
      failure: `${matches[0]} ${invalidReason(project, matches[0])}`,
    };
  });
}

/** Eine Umgebungsvariable, die der Code liest, und wo die Doku sie nennt. */
export interface CodeVariableResult {
  name: string;
  /** Codedateien, die sie lesen. */
  readIn: string[];
  /** Dokumente, die sie nennen. */
  documentedIn: string[];
  /** Grund aus INTERNAL_VARIABLES, wenn sie bewusst nicht dokumentiert wird. */
  internal?: string;
}

/**
 * Umgebungsvariablen, die der Code in den Einträgen (Datei, Ordner oder
 * Muster; nur versionierte Dateien ohne Tests) liest, mit den Dokumenten, die
 * sie nennen. `staleInternal` sind Einträge aus INTERNAL_VARIABLES, die der
 * Code nicht mehr liest; `missing` Einträge ohne Codedatei.
 */
export function checkCodeVariables(
  project: Project,
  entries: string[],
  internal: Array<{ name: string; reason: string }>,
  documents: string[],
): { results: CodeVariableResult[]; staleInternal: string[]; missing: string[] } {
  const code = project.files.filter((path) =>
    (CODE_SUFFIXES.has(suffix(path)) || baseName(path).startsWith("Dockerfile")) &&
    !isTestPath(path)
  );
  const readIn = new Map<string, Set<string>>();
  const missing: string[] = [];
  for (const entry of entries) {
    const wanted = normalize(entry);
    const matcher = isGlob(wanted) ? globToRegExp(wanted) : undefined;
    const found = code.filter((path) =>
      matcher ? matcher.test(path) : path === wanted || path.startsWith(`${wanted}/`)
    );
    if (!found.length) missing.push(entry);
    for (const path of found) {
      const text = readText(`${project.root}/${path}`);
      for (const pattern of ENV_READS) {
        for (const match of text.matchAll(pattern)) {
          // Eine Zuweisung (os.environ["X"] = …) setzt die Variable für
          // gestartete Prozesse, liest sie aber nicht.
          const end = match.index! + match[0].length;
          if (/^['"]?\]?\s*=(?!=)/.test(text.slice(end, end + 8))) continue;
          if (!readIn.has(match[1])) readIn.set(match[1], new Set());
          readIn.get(match[1])!.add(path);
        }
      }
    }
  }
  const texts = documents.map((path) => [path, readText(`${project.root}/${path}`)] as const);
  const results = [...readIn.keys()].sort().map((name) => {
    const word = new RegExp(`(^|[^A-Za-z0-9_])${name}([^A-Za-z0-9_]|$)`);
    return {
      name,
      readIn: [...readIn.get(name)!].sort(),
      documentedIn: texts.filter(([, text]) => word.test(text)).map(([path]) => path),
      internal: internal.find((item) => item.name === name)?.reason,
    };
  });
  const staleInternal = internal.map((item) => item.name).filter((name) => !readIn.has(name));
  return { results, staleInternal, missing };
}

// ------------------------------------------------------------ Änderungen

/**
 * Ein Kandidat für den Doku-Abgleich: ein Bezeichner, den eine Änderung im
 * Code betrifft, und die Doku-Stellen, die ihn nennen. Ob die Doku angepasst
 * werden muss, entscheidet ein Mensch oder Agent; das Skript findet nur die
 * Stellen.
 */
export interface ChangeCandidate {
  kind: "variable" | "make-target" | "npm-script" | "ui-text" | "path" | "feat";
  name: string;
  /** Geänderte Codedateien, in denen der Bezeichner vorkommt (bei feat: Commit). */
  sources: string[];
  /**
   * Doku-Stellen im Ausgangsstand; `changed`, wenn die Änderung die Zeile
   * oder ihre Umgebung (±3 Zeilen) selbst angepasst hat.
   */
  hits: Array<{ file: string; line: number; changed: boolean }>;
  /** Dokumente mit Treffern, die die Änderung selbst mitgeändert hat. */
  changedDocs: string[];
  status: "covered" | "open" | "no-doc";
}

export interface ChangeReport {
  base: string;
  head: string;
  codeFiles: string[];
  changedDocs: string[];
  candidates: ChangeCandidate[];
}

/** Textstellen, die beim Vergleich nicht als UI-Text gelten. */
const UI_TEXT_MIN = 4;

/** Datei- und Musterauswahl wie bei DOCS, angewandt auf eine Dateiliste. */
function selectPaths(paths: string[], inputs: string[], excludes: string[]): string[] {
  const matches = (path: string, entry: string) => {
    const wanted = normalize(entry);
    if (wanted === "" || wanted === ".") return true;
    if (isGlob(wanted)) {
      const matcher = globToRegExp(wanted);
      const parts = path.split("/");
      return parts.some((_, index) => matcher.test(parts.slice(0, index + 1).join("/")));
    }
    return path === wanted || path.startsWith(`${wanted}/`);
  };
  return paths.filter((path) =>
    inputs.some((entry) => matches(path, entry)) &&
    !excludes.some((entry) => matches(path, entry))
  );
}

/** Geänderte Zeilen je Datei aus `git diff -U0`, getrennt nach entfernt und neu. */
function diffLines(
  root: string,
  base: string,
  head: string,
  files: string[],
): Map<string, { removed: string[]; added: string[] }> {
  const result = new Map<string, { removed: string[]; added: string[] }>();
  if (!files.length) return result;
  const diff = git(root, "diff", "-U0", "--no-color", "--no-ext-diff", base, head, "--", ...files);
  let current: { removed: string[]; added: string[] } | undefined;
  for (const line of diff.split("\n")) {
    const header = line.match(/^diff --git a\/(.+) b\/(.+)$/);
    if (header) {
      current = { removed: [], added: [] };
      result.set(header[2], current);
    } else if (current && line.startsWith("-") && !line.startsWith("---")) {
      current.removed.push(line.slice(1));
    } else if (current && line.startsWith("+") && !line.startsWith("+++")) {
      current.added.push(line.slice(1));
    }
  }
  return result;
}

/** npm-Skripte einer package.json in einem Stand, leer ohne Datei. */
function npmScriptsAt(root: string, rev: string, path: string): Set<string> {
  try {
    return new Set(Object.keys(JSON.parse(git(root, "show", `${rev}:${path}`)).scripts ?? {}));
  } catch {
    return new Set();
  }
}

/**
 * Sucht Kandidaten für den Doku-Abgleich zwischen zwei Ständen. Gelesen wird
 * nur aus git (`base` und `head`), nicht aus dem Arbeitsbaum; so lässt sich
 * jeder frühere Merge genauso prüfen wie ein laufender Branch.
 *
 * Bezeichner aus geänderten Codezeilen: gelesene Umgebungsvariablen,
 * Make-Targets, npm-Skripte, alte Texte aus den UI-Katalogen (`uiCatalogs`),
 * Pfade geänderter Dateien und `feat`-Commits. Für jeden Bezeichner die
 * Stellen in den Dokumenten des Ausgangsstands, die ihn nennen.
 */
export function findChangeCandidates(
  root: string,
  base: string,
  head: string,
  docInputs: string[],
  excludes: string[],
  uiCatalogs: string[],
): ChangeReport {
  const changed = git(root, "diff", "--name-only", "--no-renames", base, head).split("\n")
    .filter(Boolean);
  const baseFiles = git(root, "ls-tree", "-r", "--name-only", base).split("\n").filter(Boolean);
  const headFiles = git(root, "ls-tree", "-r", "--name-only", head).split("\n").filter(Boolean);
  const isDoc = (path: string) => DOC_SUFFIXES.has(suffix(path));
  const docsAtBase = selectPaths(baseFiles.filter(isDoc), docInputs, excludes)
    .filter((path) => !isSensitive(path));
  const docsAtHead = selectPaths(headFiles.filter(isDoc), docInputs, excludes);
  const docSet = new Set([...docsAtBase, ...docsAtHead]);
  const changedDocs = changed.filter((path) => docSet.has(path));
  const codeFiles = changed.filter((path) =>
    !isDoc(path) && !isTestPath(path) && !isSensitive(path) &&
    !path.split("/").some((part) => SKIP_DIRS.has(part))
  );
  const catalogs = new Set(uiCatalogs.length ? selectPaths(codeFiles, uiCatalogs, []) : []);

  // Bezeichner sammeln: Art und Name → Quellen.
  const found = new Map<
    string,
    { kind: ChangeCandidate["kind"]; name: string; sources: Set<string> }
  >();
  const note = (kind: ChangeCandidate["kind"], name: string, source: string) => {
    const key = `${kind}:${name}`;
    if (!found.has(key)) found.set(key, { kind, name, sources: new Set() });
    found.get(key)!.sources.add(source);
  };
  const lines = diffLines(root, base, head, codeFiles);
  for (const path of codeFiles) {
    note("path", path, path);
    const { removed, added } = lines.get(path) ?? { removed: [], added: [] };
    const changedText = [...removed, ...added].join("\n");
    for (const pattern of ENV_READS) {
      for (const match of changedText.matchAll(pattern)) note("variable", match[1], path);
    }
    const name = baseName(path);
    if (["Makefile", "makefile", "GNUmakefile"].includes(name) || suffix(path) === ".mk") {
      for (const line of [...removed, ...added]) {
        const target = line.match(/^([A-Za-z0-9][\w.-]*)\s*:(?!=)/);
        if (target && !target[1].startsWith(".")) note("make-target", target[1], path);
      }
    }
    if (name === "package.json") {
      const scripts = new Set([
        ...npmScriptsAt(root, base, path),
        ...npmScriptsAt(root, head, path),
      ]);
      for (const line of [...removed, ...added]) {
        const key = line.match(/^\s*"([^"]+)"\s*:/);
        if (key && scripts.has(key[1])) note("npm-script", key[1], path);
      }
    }
    if (catalogs.has(path)) {
      // Alter Wortlaut eines geänderten oder entfernten Textes: Steht er in
      // der Doku, beschreibt sie die Oberfläche womöglich nicht mehr richtig.
      const after = git(root, "show", `${head}:${path}`);
      for (const line of removed) {
        for (const match of line.matchAll(/(['"`])((?:(?!\1)[^\\]|\\.)+)\1/g)) {
          const text = match[2];
          if (text.length >= UI_TEXT_MIN && /\p{L}/u.test(text) && !after.includes(text)) {
            note("ui-text", text, path);
          }
        }
      }
    }
  }
  for (const line of git(root, "log", "--format=%h%x09%s", `${base}..${head}`).split("\n")) {
    const [hash, subject] = line.split("\t");
    if (subject && /^feat(\(.*\))?!?:/.test(subject)) note("feat", subject, hash);
  }

  // Geänderte Zeilenbereiche je Dokument im Ausgangsstand (aus den Hunk-Köpfen).
  const docRanges = new Map<string, Array<[number, number]>>();
  if (changedDocs.length) {
    const diff = git(
      root,
      "diff",
      "-U0",
      "--no-color",
      "--no-ext-diff",
      base,
      head,
      "--",
      ...changedDocs,
    );
    let file = "";
    for (const line of diff.split("\n")) {
      const header = line.match(/^diff --git a\/(.+) b\/(.+)$/);
      if (header) file = header[1];
      const hunk = line.match(/^@@ -(\d+)(?:,(\d+))? /);
      if (hunk && file) {
        const start = Number(hunk[1]);
        const length = hunk[2] === undefined ? 1 : Number(hunk[2]);
        if (!docRanges.has(file)) docRanges.set(file, []);
        docRanges.get(file)!.push([start, start + Math.max(length, 1) - 1]);
      }
    }
  }
  const NEAR = 3;
  const touchedLine = (file: string, line: number) =>
    (docRanges.get(file) ?? []).some(([from, to]) => line >= from - NEAR && line <= to + NEAR);

  // Doku-Stellen im Ausgangsstand je Bezeichner.
  const docTexts = docsAtBase.map((path) =>
    [path, git(root, "show", `${base}:${path}`).split("\n")] as const
  );
  const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const candidates: ChangeCandidate[] = [...found.values()].map(({ kind, name, sources }) => {
    const hits: Array<{ file: string; line: number; changed: boolean }> = [];
    if (kind !== "feat") {
      const pattern = kind === "ui-text" || kind === "path"
        ? new RegExp(escape(name))
        : kind === "make-target"
        ? new RegExp(`\\bmake\\s+(?:-\\S+\\s+)*${escape(name)}(?![\\w.-])`)
        : kind === "npm-script"
        ? new RegExp(`\\brun\\s+${escape(name)}(?![\\w:.-])|\`${escape(name)}\``)
        : new RegExp(`(^|[^A-Za-z0-9_])${escape(name)}([^A-Za-z0-9_]|$)`);
      for (const [file, text] of docTexts) {
        text.forEach((content, index) => {
          if (pattern.test(content)) {
            hits.push({ file, line: index + 1, changed: touchedLine(file, index + 1) });
          }
        });
      }
    }
    const touched = [...new Set(hits.filter((hit) => hit.changed).map((hit) => hit.file))];
    return {
      kind,
      name,
      sources: [...sources].sort(),
      hits,
      changedDocs: touched,
      status: !hits.length ? "no-doc" : touched.length ? "covered" : "open",
    };
  });
  // Pfade ohne Doku-Stelle sind kein Kandidat: Fast jede Änderung betrifft Dateien.
  return {
    base,
    head,
    codeFiles,
    changedDocs,
    candidates: candidates.filter((candidate) =>
      candidate.kind !== "path" || candidate.hits.length > 0
    ),
  };
}

const KIND_LABELS: Record<ChangeCandidate["kind"], string> = {
  "variable": "Variable",
  "make-target": "Make-Target",
  "npm-script": "npm-Skript",
  "ui-text": "UI-Text",
  "path": "Pfad",
  "feat": "Feature-Commit",
};

/** Gibt den Bericht für Menschen aus. */
function printChangeReport(report: ChangeReport, paint: (code: string, text: string) => string) {
  console.log(
    paint("1", `Doku-Abgleich ${report.base}..${report.head}`) +
      `: ${count(report.codeFiles.length, "Codedatei", "Codedateien")} geändert, ` +
      `${count(report.changedDocs.length, "Dokument", "Dokumente")} geändert` +
      (report.changedDocs.length ? ` (${report.changedDocs.join(", ")})` : ""),
  );
  const order: ChangeCandidate["status"][] = ["open", "no-doc", "covered"];
  const titles = {
    "open": "Offen: Die Doku nennt den Bezeichner, keine dieser Stellen wurde mitgeändert",
    "no-doc": "Ohne Doku-Stelle: Kein Dokument nennt den Bezeichner",
    "covered": "Mitgeändert: Mindestens eine Stelle (±3 Zeilen) wurde in dieser Änderung angepasst",
  };
  for (const status of order) {
    const group = report.candidates.filter((candidate) => candidate.status === status);
    if (!group.length) continue;
    console.log(`\n${paint(status === "open" ? "33" : "1", titles[status])}\n`);
    for (const candidate of group) {
      const where = candidate.hits.slice(0, 4).map((hit) =>
        `${hit.file}:${hit.line}${hit.changed ? " (geändert)" : ""}`
      ).join(", ") +
        (candidate.hits.length > 4 ? ` (+${candidate.hits.length - 4})` : "");
      console.log(
        `  ${KIND_LABELS[candidate.kind].padEnd(14)} ${candidate.name.slice(0, 70)}` +
          `  ← ${candidate.sources.slice(0, 2).join(", ")}`,
      );
      if (where) {
        console.log(`  ${" ".repeat(14)} Doku: ${where}`);
      }
    }
  }
  const of = (status: ChangeCandidate["status"]) =>
    report.candidates.filter((candidate) => candidate.status === status).length;
  console.log(
    `\nErgebnis: ${count(report.candidates.length, "Kandidat", "Kandidaten")} · ` +
      `${of("open")} offen · ${of("no-doc")} ohne Doku-Stelle · ${of("covered")} mitgeändert`,
  );
  console.log(
    "Kandidaten sind keine Fehler: Ob die Doku angepasst werden muss, entscheidet, wer die Änderung kennt.",
  );
}

const IMAGE_SUFFIXES = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]);
const DAY_MS = 24 * 60 * 60 * 1000;

/** Letzte Änderung eines Pfads nach git. */
export interface Change {
  /** Millisekunden seit 1970; bei uncommitteten Änderungen der Prüfzeitpunkt. */
  time: number;
  /** Uncommittet, gestagt oder neu: zählt als „jetzt“. */
  pending: boolean;
}

/**
 * Wann sich eine Datei oder ein Ordner zuletzt geändert hat. Uncommittete,
 * gestagte und neue, nicht ignorierte Dateien gelten als „jetzt“; sonst zählt
 * die Commit-Zeit des letzten Commits, der den Pfad ändert. Das Dateidatum
 * taugt dafür nicht: Klon, Branchwechsel, Merge und Stash setzen es neu.
 * `undefined`, wenn der Pfad fehlt oder git ihn nicht kennt.
 */
export function lastChange(root: string, path: string, now = Date.now()): Change | undefined {
  if (!exists(`${root}/${path}`)) return undefined;
  if (git(root, "status", "--porcelain", "--untracked-files=all", "--", path)) {
    return { time: now, pending: true };
  }
  const seconds = Number(git(root, "log", "-1", "--format=%ct", "--", path));
  return seconds ? { time: seconds * 1000, pending: false } : undefined;
}

/** Kalendertag einer Änderung oder „uncommittet“. */
function changeLabel(change: Change): string {
  return change.pending ? "uncommittet" : new Date(change.time).toISOString().slice(0, 10);
}

/** Alter eines Screenshots nach seiner letzten Änderung laut git. */
export interface ScreenshotResult {
  path: string;
  changed: Date;
  ageDays: number;
  tooOld: boolean;
}

/**
 * Bilder, die die Einträge treffen (Datei, Ordner samt Unterordnern oder
 * Muster), mit ihrem Alter. Gesucht wird unter den Dateien, die git nicht
 * ignoriert, also auch unter neu aufgenommenen. Einträge ohne Treffer stehen
 * in `missing`.
 */
export function checkScreenshots(
  project: Project,
  entries: string[],
  maxAgeDays: number,
  now = Date.now(),
): { results: ScreenshotResult[]; missing: string[] } {
  const listed = git(project.root, "ls-files", "--cached", "--others", "--exclude-standard");
  const images = [...new Set(listed ? listed.split("\n") : project.files)]
    .filter((path) => IMAGE_SUFFIXES.has(suffix(path).toLowerCase()) && !isSensitive(path))
    .filter((path) => exists(`${project.root}/${path}`));
  const paths = new Set<string>();
  const missing: string[] = [];
  for (const entry of entries) {
    const wanted = normalize(entry);
    const matcher = isGlob(wanted) ? globToRegExp(wanted) : undefined;
    const found = images.filter((path) =>
      matcher ? matcher.test(path) : path === wanted || path.startsWith(`${wanted}/`)
    );
    if (!found.length) missing.push(entry);
    for (const path of found) paths.add(path);
  }
  const results = [...paths].sort().map((path) => {
    const changed = new Date(lastChange(project.root, path, now)?.time ?? now);
    const ageDays = Math.max(0, Math.floor((now - changed.getTime()) / DAY_MS));
    return { path, changed, ageDays, tooOld: ageDays > maxAgeDays };
  });
  return { results, missing };
}

/** Ein Dokument, das einem anderen bald nach dessen Änderung folgen muss. */
export interface Dependency {
  base: string;
  dependent: string;
  /** Tage, die die abhängige Datei hinter der Basis liegen darf; 0: derselbe Commit. */
  maxLagDays: number;
  reason: string;
  /** Aus DEPENDS_HINT: auch überfällig nur ein Hinweis. */
  hintOnly: boolean;
}

/**
 * Liest `BASIS|ABHÄNGIG|TAGE[|GRUND]`. Die Basis darf auch ein Ordner sein,
 * etwa die i18n-Kataloge, von denen ein Handbuch abhängt.
 */
export function parseDependency(entry: string, hintOnly: boolean): Dependency | string {
  const [base, dependent, days, ...reason] = entry.split("|").map((part) => part.trim());
  if (!base || !dependent) return `Abhängigkeit braucht BASIS|ABHÄNGIG|TAGE: ${entry}`;
  const maxLagDays = Number(days);
  if (!days || !Number.isInteger(maxLagDays) || maxLagDays < 0) {
    return `Abhängigkeit braucht eine ganze Zahl von Tagen ab 0: ${entry}`;
  }
  const clean = (path: string) => path.replace(/^\.\//, "").replace(/\/+$/, "");
  return {
    base: clean(base),
    dependent: clean(dependent),
    maxLagDays,
    reason: reason.join("|"),
    hintOnly,
  };
}

/** Stand einer Abhängigkeit. */
export interface DependencyResult {
  dependency: Dependency;
  /** Pfad, den es nicht gibt oder den git nicht kennt. */
  missing?: string;
  base?: Change;
  dependent?: Change;
  /** Die Basis hat sich nach der abhängigen Datei geändert. */
  behind: boolean;
  /** Bis dahin muss die abhängige Datei nachgezogen sein. */
  due?: number;
  /** Frist überschritten; bei `maxLagDays` 0 sofort. */
  overdue: boolean;
}

/**
 * Vergleicht je Abhängigkeit die letzten Änderungen laut git (lastChange).
 * Ändern sich beide im selben Commit oder sind beide uncommittet, ist die
 * abhängige Datei nachgezogen.
 */
export function checkDependencies(
  root: string,
  dependencies: Dependency[],
  now = Date.now(),
): DependencyResult[] {
  return dependencies.map((dependency) => {
    const base = lastChange(root, dependency.base, now);
    const dependent = lastChange(root, dependency.dependent, now);
    if (!base || !dependent) {
      return {
        dependency,
        missing: base ? dependency.dependent : dependency.base,
        base,
        dependent,
        behind: false,
        overdue: false,
      };
    }
    const behind = base.time > dependent.time;
    const due = base.time + dependency.maxLagDays * DAY_MS;
    return { dependency, base, dependent, behind, due, overdue: behind && now >= due };
  });
}

// ------------------------------------------------------------ Kommandozeile

interface Options {
  root: string;
  forbidden: Forbidden[];
  required: Required[];
  maxAlerts?: number;
  excludes: string[];
  knownVariables: string[];
  linksOnlyInputs: string[];
  screenshots: string[];
  maxScreenshotAge?: number;
  dependencies: Dependency[];
  codeVariables: string[];
  internalVariables: Array<{ name: string; reason: string }>;
  changes?: { base: string; head: string };
  uiCatalogs: string[];
  json: boolean;
  placement?: string;
  verbose: boolean;
  configName?: string;
  inputs: string[];
}

function parseArgs(args: string[]): Options | string {
  const options: Options = {
    root: ".",
    forbidden: [],
    required: [],
    excludes: [],
    knownVariables: [],
    linksOnlyInputs: [],
    screenshots: [],
    dependencies: [],
    codeVariables: [],
    internalVariables: [],
    uiCatalogs: [],
    json: false,
    verbose: false,
    inputs: [],
  };
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    const value = () => {
      const next = args[++index];
      if (next === undefined) throw new Error(`${arg} braucht einen Wert`);
      return next;
    };
    try {
      if (arg === "--root") options.root = value();
      else if (arg === "--forbid") {
        const forbidden = parseForbidden(value());
        if (typeof forbidden === "string") return forbidden;
        options.forbidden.push(forbidden);
      } else if (arg === "--exclude") options.excludes.push(value());
      else if (arg === "--as") options.placement = value();
      else if (arg === "--verbose") options.verbose = true;
      else if (arg === "--config-name") options.configName = value();
      else if (arg === "--require") {
        const required = parseRequired(value());
        if (typeof required === "string") return required;
        options.required.push(required);
      } else if (arg === "--max-alerts") {
        const limit = Number(value());
        if (!Number.isInteger(limit) || limit < 0) {
          return "--max-alerts braucht eine ganze Zahl ab 0";
        }
        options.maxAlerts = limit;
      } else if (arg === "--known-variable") {
        const name = value().split("|")[0].trim();
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
          return `--known-variable braucht einen Variablennamen, nicht „${name}“`;
        }
        options.knownVariables.push(name);
      } else if (arg === "--internal-variable") {
        const [name, ...reason] = value().split("|");
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name.trim())) {
          return `--internal-variable braucht einen Variablennamen, nicht „${name.trim()}“`;
        }
        options.internalVariables.push({ name: name.trim(), reason: reason.join("|").trim() });
      } else if (arg === "--changes") {
        const [base, head] = value().split("..");
        if (!base) return "--changes braucht einen Stand, z. B. master oder master..HEAD";
        options.changes = { base, head: head || "HEAD" };
      } else if (arg === "--ui-catalog") options.uiCatalogs.push(value());
      else if (arg === "--json") options.json = true;
      else if (arg === "--code-variables") options.codeVariables.push(value());
      else if (arg === "--links-only") options.linksOnlyInputs.push(value());
      else if (arg === "--screenshot") options.screenshots.push(value());
      else if (arg === "--depends" || arg === "--depends-hint") {
        const dependency = parseDependency(value(), arg === "--depends-hint");
        if (typeof dependency === "string") return dependency;
        options.dependencies.push(dependency);
      } else if (arg === "--max-screenshot-age") {
        const days = Number(value());
        if (!Number.isInteger(days) || days < 1) {
          return "--max-screenshot-age braucht eine ganze Zahl von Tagen ab 1";
        }
        options.maxScreenshotAge = days;
      } else if (arg.startsWith("--")) return `unbekannte Option: ${arg}`;
      else options.inputs.push(arg);
    } catch (error) {
      return (error as Error).message;
    }
  }
  if (options.screenshots.length && options.maxScreenshotAge === undefined) {
    return "--screenshot braucht --max-screenshot-age (Config: MAX_SCREENSHOT_AGE_DAYS)";
  }
  if (!options.screenshots.length && options.maxScreenshotAge !== undefined) {
    return "--max-screenshot-age braucht mindestens ein --screenshot (Config: SCREENSHOTS)";
  }
  if (
    !options.inputs.length && !options.linksOnlyInputs.length && !options.required.length &&
    !options.screenshots.length && !options.dependencies.length
  ) {
    return "keine Datei, kein Ordner, keine Pflichtdatei, kein Screenshot und keine Abhängigkeit angegeben";
  }
  if (options.codeVariables.length && !options.inputs.length) {
    return "--code-variables braucht Dokumente, in denen die Variablen stehen (DOCS)";
  }
  if (options.placement && options.inputs.length !== 1) return "--as gilt nur für genau eine Datei";
  return options;
}

const LABELS: Record<Finding["level"], string> = {
  problem: "Problem",
  check: "Hinweis",
  unchecked: "Ungeprüft",
  info: "Info",
};

/** ANSI-Farben nur im Terminal und ohne NO_COLOR. */
function painter(): (code: string, text: string) => string {
  const enabled = Deno.stdout.isTerminal() && !Deno.env.get("NO_COLOR");
  return (code, text) => (enabled ? `\x1b[${code}m${text}\x1b[0m` : text);
}

/** Zahl mit passender Einzahl oder Mehrzahl. */
function count(value: number, one: string, many: string): string {
  return `${value} ${value === 1 ? one : many}`;
}

/** Kurzfassung der Befunde eines Dokuments, z. B. „1 Problem, 2 Hinweise“. */
function tally(findings: Finding[]): string {
  const parts: string[] = [];
  const of = (level: Finding["level"]) =>
    findings.filter((finding) => finding.level === level).length;
  if (of("problem")) parts.push(count(of("problem"), "Problem", "Probleme"));
  if (of("check")) parts.push(count(of("check"), "Hinweis", "Hinweise"));
  if (of("unchecked")) parts.push(`${count(of("unchecked"), "Befehl", "Befehle")} ungeprüft`);
  if (of("info")) parts.push(count(of("info"), "Info", "Infos"));
  return parts.join(", ") || "in Ordnung";
}

function main(args: string[]): number {
  const options = parseArgs(args);
  if (typeof options === "string") {
    console.error(`Fehler: ${options}`);
    console.error(
      "Aufruf: docs-check.ts [--root DIR] [--forbid BEGRIFF|/MUSTER/[|GRUND]] [--exclude PFAD] [--max-alerts N] [--require NAME|PFAD|MUSTER[|GRUND]] [--links-only PFAD] [--known-variable NAME[|GRUND]] [--screenshot PFAD --max-screenshot-age TAGE] [--depends BASIS|ABHÄNGIG|TAGE[|GRUND]] [--depends-hint BASIS|ABHÄNGIG|TAGE[|GRUND]] [--code-variables PFAD] [--internal-variable NAME|GRUND] [--changes BASE[..HEAD] [--ui-catalog PFAD] [--json]] [--as PFAD] [--verbose] DATEI|ORDNER...",
    );
    return 2;
  }
  const paint = painter();
  if (options.changes) {
    if (!options.inputs.length) {
      console.error(
        "Fehler: --changes braucht die Dokumente (DATEI|ORDNER), in denen gesucht wird",
      );
      return 2;
    }
    const root = Deno.realPathSync(options.root);
    for (const rev of [options.changes.base, options.changes.head]) {
      if (!git(root, "rev-parse", "--verify", "--quiet", `${rev}^{commit}`)) {
        console.error(`Fehler: Stand „${rev}“ gibt es nicht`);
        return 2;
      }
    }
    const report = findChangeCandidates(
      root,
      options.changes.base,
      options.changes.head,
      options.inputs.map((input) => relativeToRoot(root, input)),
      options.excludes,
      options.uiCatalogs,
    );
    if (options.json) console.log(JSON.stringify(report, null, 2));
    else printChangeReport(report, paint);
    return 0;
  }
  const project = loadProject(options.root);
  // Ein Entwurf (--as) liegt außerhalb des Repos und wird unter seinem Pfad gelesen.
  // Je Ziel: gelesener Pfad, Ort im Repo und ob nur Links geprüft werden.
  const targets: Array<[string, string, boolean]> = [];
  let missing: Array<{ input: string; reason: string }> = [];
  if (options.placement) {
    targets.push([options.inputs[0], options.placement, false]);
  } else {
    const expand = (inputs: string[]) =>
      expandDocuments(
        project.root,
        inputs.map((input) => relativeToRoot(project.root, input)),
        options.excludes,
      );
    const full = expand(options.inputs);
    const linksOnly = expand(options.linksOnlyInputs);
    missing = [...full.missing, ...linksOnly.missing];
    for (const document of full.documents) {
      targets.push([`${project.root}/${document}`, document, false]);
    }
    // Steht eine Datei in beiden Listen, gilt die vollständige Prüfung.
    for (const document of linksOnly.documents.filter((path) => !full.documents.includes(path))) {
      targets.push([`${project.root}/${document}`, document, true]);
    }
  }
  const results = targets.map(([path, placement, linksOnly]) => ({
    name: options.placement
      ? `${normalize(placement)} (Entwurf ${path})`
      : `${normalize(placement)}${linksOnly ? " (nur Links)" : ""}`,
    findings: checkDocument(path, project, placement, { ...options, linksOnly }),
  }));

  // Übersicht: was geprüft wurde, je Dokument mit Ergebnis.
  const source = options.configName ? ` laut ${options.configName}` : "";
  const checksDocuments = options.inputs.length > 0 || options.linksOnlyInputs.length > 0;
  if (checksDocuments) {
    console.log(
      paint("1", `Dokumentprüfung: ${count(results.length, "Dokument", "Dokumente")}${source}`),
    );
    if (options.excludes.length) console.log(`Ausgenommen: ${options.excludes.join(", ")}`);
    console.log();
  }
  const width = Math.max(
    0,
    ...results.map((result) => result.name.length),
    ...missing.map(({ input }) => input.length),
  );
  for (const { input, reason } of missing) {
    console.log(`  ${paint("31", "✗")} ${input.padEnd(width)}   ${paint("31", reason)}`);
  }
  for (const { name, findings } of results) {
    const failed = findings.some((finding) => finding.level === "problem");
    const open = findings.some((finding) =>
      finding.level === "check" || finding.level === "unchecked"
    );
    const mark = failed ? paint("31", "✗") : open ? paint("33", "?") : paint("32", "✓");
    console.log(`  ${mark} ${name.padEnd(width)}   ${tally(findings)}`);
  }

  // Pflichtdateien: je Eintrag die gefundenen Dateien oder warum keine zählt.
  const requiredResults = checkRequired(project, options.required);
  if (requiredResults.length) {
    console.log(
      `${checksDocuments ? "\n" : ""}${
        paint("1", `Pflichtdateien: ${requiredResults.length}${source}`)
      }\n`,
    );
    const entryWidth = Math.max(...requiredResults.map((result) => result.required.entry.length));
    for (const { required, found, failure } of requiredResults) {
      const name = required.entry.padEnd(entryWidth);
      if (!failure) {
        // Bei einem genauen Pfad nur „vorhanden“, sonst die gefundenen Dateien.
        const exact = found.length === 1 && found[0] === required.entry.replace(/^\.\//, "");
        const shown = exact ? "vorhanden" : found.slice(0, 3).join(", ") +
          (found.length > 3 ? ` (+${found.length - 3} weitere)` : "");
        console.log(`  ${paint("32", "✓")} ${name}   ${shown}`);
        continue;
      }
      console.log(
        `  ${paint("31", "✗")} ${name}   ${paint("31", failure)}${
          required.reason ? ` · Grund: ${required.reason}` : ""
        }`,
      );
      const advice = failure.startsWith("fehlt")
        ? "Datei anlegen und committen; eine Datei nur auf der Platte zählt nicht."
        : failure.includes("Überschrift")
        ? "Eine Überschrift ergänzen, z. B. „# Titel“."
        : "Inhalt ergänzen.";
      console.log(`${" ".repeat(entryWidth + 7)}→ ${advice}`);
    }
  }

  // Screenshots: je Bild Commit-Datum und Alter; zu alte als Hinweis.
  const maxAge = options.maxScreenshotAge ?? 0;
  const screenshots = options.screenshots.length
    ? checkScreenshots(project, options.screenshots, maxAge)
    : { results: [], missing: [] };
  if (options.screenshots.length) {
    console.log(
      `${checksDocuments || requiredResults.length ? "\n" : ""}${
        paint(
          "1",
          `Screenshots: ${screenshots.results.length}${source}, höchstens ${
            count(maxAge, "Tag", "Tage")
          } alt`,
        )
      }\n`,
    );
    const shotWidth = Math.max(
      0,
      ...screenshots.results.map((result) => result.path.length),
      ...screenshots.missing.map((entry) => entry.length),
    );
    for (const entry of screenshots.missing) {
      console.log(
        `  ${paint("31", "✗")} ${entry.padEnd(shotWidth)}   ${paint("31", "trifft kein Bild")}`,
      );
      console.log(
        `${" ".repeat(shotWidth + 7)}→ Eintrag in SCREENSHOTS korrigieren oder entfernen.`,
      );
    }
    for (const { path, changed, ageDays, tooOld } of screenshots.results) {
      const state = `geändert am ${changed.toISOString().slice(0, 10)}, vor ${
        count(ageDays, "Tag", "Tagen")
      }`;
      const mark = tooOld ? paint("33", "?") : paint("32", "✓");
      console.log(
        `  ${mark} ${path.padEnd(shotWidth)}   ${state}${
          tooOld ? paint("33", ` · älter als ${count(maxAge, "Tag", "Tage")}`) : ""
        }`,
      );
      if (tooOld) {
        console.log(
          `${
            " ".repeat(shotWidth + 7)
          }→ Prüfen, ob das Bild die aktuelle Oberfläche zeigt; sonst neu aufnehmen.`,
        );
      }
    }
  }

  // Abhängige Dokumente: Basis später geändert ist ein Hinweis, nach der Frist
  // ein Problem (DEPENDS_HINT: immer nur Hinweis).
  const dependencies = checkDependencies(project.root, options.dependencies);
  const dependencyProblem = (result: DependencyResult) =>
    result.missing !== undefined || (result.overdue && !result.dependency.hintOnly);
  if (dependencies.length) {
    console.log(`\n${paint("1", `Abhängige Dokumente: ${dependencies.length}${source}`)}\n`);
    const pairs = dependencies.map(({ dependency }) =>
      `${dependency.base} → ${dependency.dependent}`
    );
    const pairWidth = Math.max(0, ...pairs.map((pair) => pair.length));
    const advise = (text: string) => console.log(`${" ".repeat(pairWidth + 7)}→ ${text}`);
    dependencies.forEach((result, index) => {
      const { dependency, missing, base, dependent, behind, due, overdue } = result;
      const pair = pairs[index].padEnd(pairWidth);
      const reason = dependency.reason ? ` · ${dependency.reason}` : "";
      if (missing !== undefined) {
        console.log(
          `  ${paint("31", "✗")} ${pair}   ${
            paint("31", `${missing} fehlt oder ist nicht in git`)
          }`,
        );
        advise("Datei anlegen und committen oder Eintrag in DEPENDS korrigieren.");
        return;
      }
      if (!behind) {
        console.log(
          `  ${paint("32", "✓")} ${pair}   nachgezogen (${changeLabel(dependent!)})${reason}`,
        );
        return;
      }
      const state = `Basis geändert ${changeLabel(base!)}, abhängig ${changeLabel(dependent!)}`;
      const deadline = dependency.maxLagDays
        ? `Frist ${new Date(due!).toISOString().slice(0, 10)}`
        : "gehört in denselben Commit";
      const problem = dependencyProblem(result);
      const color = problem ? "31" : "33";
      console.log(
        `  ${paint(color, problem ? "✗" : "?")} ${pair}   ${
          paint(color, `${state} · ${overdue ? "überfällig, " : ""}${deadline}`)
        }${reason}`,
      );
      advise(
        `${dependency.dependent} an ${dependency.base} angleichen und committen. Änderungen: ` +
          (base!.pending
            ? `git diff HEAD -- ${dependency.base}`
            : `git log -p --since=${changeLabel(dependent!)} -- ${dependency.base}`),
      );
    });
  }

  // Umgebungsvariablen aus dem Code: je Variable, wo die Doku sie nennt.
  const codeVariables = options.codeVariables.length
    ? checkCodeVariables(
      project,
      options.codeVariables,
      options.internalVariables,
      targets.filter(([, , linksOnly]) => !linksOnly).map(([, placement]) => normalize(placement)),
    )
    : { results: [], staleInternal: [], missing: [] };
  const undocumented = codeVariables.results.filter((result) =>
    !result.documentedIn.length && result.internal === undefined
  );
  if (options.codeVariables.length) {
    console.log(
      `\n${
        paint(
          "1",
          `Umgebungsvariablen im Code: ${codeVariables.results.length}${source}`,
        )
      }\n`,
    );
    const nameWidth = Math.max(
      0,
      ...codeVariables.results.map((result) => result.name.length),
      ...codeVariables.missing.map((entry) => entry.length),
      ...codeVariables.staleInternal.map((name) => name.length),
    );
    for (const entry of codeVariables.missing) {
      console.log(
        `  ${paint("31", "✗")} ${entry.padEnd(nameWidth)}   ${
          paint("31", "trifft keine Codedatei")
        }`,
      );
      console.log(
        `${" ".repeat(nameWidth + 7)}→ Eintrag in CODE_VARIABLES korrigieren oder entfernen.`,
      );
    }
    for (const { name, readIn, documentedIn, internal } of codeVariables.results) {
      if (documentedIn.length) {
        const shown = documentedIn.slice(0, 3).join(", ") +
          (documentedIn.length > 3 ? ` (+${documentedIn.length - 3} weitere)` : "");
        console.log(`  ${paint("32", "✓")} ${name.padEnd(nameWidth)}   dokumentiert in ${shown}`);
      } else if (internal !== undefined) {
        console.log(
          `  ${paint("32", "✓")} ${name.padEnd(nameWidth)}   intern${
            internal ? `: ${internal}` : ""
          }`,
        );
      } else {
        console.log(
          `  ${paint("31", "✗")} ${name.padEnd(nameWidth)}   ${
            paint("31", "in keinem Dokument genannt")
          } · gelesen in ${readIn.slice(0, 2).join(", ")}`,
        );
        console.log(
          `${
            " ".repeat(nameWidth + 7)
          }→ In der Nutzer- oder Entwicklerdoku beschreiben oder mit Grund in INTERNAL_VARIABLES aufnehmen.`,
        );
      }
    }
    for (const name of codeVariables.staleInternal) {
      console.log(
        `  ${paint("33", "?")} ${name.padEnd(nameWidth)}   ${
          paint("33", "steht in INTERNAL_VARIABLES, der Code liest sie nicht mehr")
        }`,
      );
      console.log(`${" ".repeat(nameWidth + 7)}→ Eintrag aus INTERNAL_VARIABLES entfernen.`);
    }
  }

  // Einzelheiten je Dokument mit Befunden.
  const colors: Record<Finding["level"], string> = {
    problem: "31",
    check: "33",
    unchecked: "36",
    info: "90",
  };
  const labelWidth = Math.max(...Object.values(LABELS).map((label) => label.length));
  const indent = " ".repeat(labelWidth + 4);
  for (const { name, findings } of results) {
    if (!findings.length) continue;
    console.log(`\n${paint("1", name)}`);
    for (const { lines, level, message, advice } of findings) {
      const where = lines.length
        ? `${lines.length === 1 ? "Zeile" : "Zeilen"} ${lines.join(", ")} · `
        : "";
      console.log(
        `  ${paint(colors[level], LABELS[level].padEnd(labelWidth))}  ${where}${message}`,
      );
      console.log(`${indent}→ ${advice}`);
    }
  }

  const all = results.flatMap((result) => result.findings);
  const failedRequired = requiredResults.filter((result) => result.failure).length;
  const checked = [
    ...(checksDocuments ? [count(results.length, "Dokument", "Dokumente")] : []),
    ...(requiredResults.length
      ? [count(requiredResults.length, "Pflichtdatei", "Pflichtdateien")]
      : []),
    ...(options.screenshots.length
      ? [count(screenshots.results.length, "Screenshot", "Screenshots")]
      : []),
    ...(dependencies.length ? [count(dependencies.length, "Abhängigkeit", "Abhängigkeiten")] : []),
    ...(options.codeVariables.length
      ? [count(codeVariables.results.length, "Code-Variable", "Code-Variablen")]
      : []),
  ];
  const problems = all.filter((finding) => finding.level === "problem").length + missing.length +
    failedRequired + screenshots.missing.length + codeVariables.missing.length +
    undocumented.length + dependencies.filter(dependencyProblem).length;
  const open =
    all.filter((finding) => finding.level === "check" || finding.level === "unchecked").length +
    screenshots.results.filter((result) => result.tooOld).length +
    codeVariables.staleInternal.length +
    dependencies.filter((result) => result.behind && !dependencyProblem(result)).length;
  const verdict = problems
    ? paint("31", count(problems, "Problem", "Probleme"))
    : paint("32", "keine Probleme");
  const checkedText = checked.length > 1
    ? `${checked.slice(0, -1).join(", ")} und ${checked[checked.length - 1]}`
    : checked[0];
  console.log(
    `\nErgebnis: ${checkedText} geprüft · ${verdict}` +
      (open ? ` · ${count(open, "Hinweis", "Hinweise")} zum Ansehen` : ""),
  );
  if (open && !problems) {
    console.log(
      "Hinweise sind keine Fehler, die Prüfung ist bestanden. Ob du etwas änderst, entscheidest du.",
    );
  }
  return problems ? 1 : 0;
}

/** Eingabepfad (relativ zum aktuellen Verzeichnis oder absolut) als Pfad relativ zur Wurzel. */
function relativeToRoot(root: string, input: string): string {
  let absolute: string;
  try {
    absolute = Deno.realPathSync(input);
  } catch {
    return input;
  }
  return absolute === root
    ? "."
    : absolute.startsWith(`${root}/`)
    ? absolute.slice(root.length + 1)
    : input;
}

if (import.meta.main) Deno.exit(main([...Deno.args]));
