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
 *   --exclude PFAD         Datei oder Ordner (relativ zur Wurzel) auslassen
 *   --as PFAD              Späterer Ort einer einzelnen Datei im Repo (Entwurf)
 *   --verbose              Auch fehlerfreie Dateien, Zahlenangaben und URLs zeigen
 *
 * Ordner werden nach *.md und *.mdx durchsucht. Links gelten relativ zum Ort
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
 * Zeichen: `!` Problem (Exit-Code 1), `?` von Hand prüfen, `~` Ökosystem, das
 * das Skript nicht prüft.
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

/** Ein Befund: `!` Problem, `?` von Hand prüfen, `~` nicht prüfbar, `i` Information. */
export interface Finding {
  line: number;
  marker: "!" | "?" | "~" | "i";
  message: string;
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
    if (isCode && !/(^|\/)(tests?|__tests__|spec)(\/|$)|\.(spec|test)\./.test(path)) {
      const text = readText(full);
      const patterns = [
        /process\.env\.([A-Z][A-Z0-9_]+)/g,
        /process\.env\[['"]([A-Z][A-Z0-9_]+)/g,
        /Deno\.env\.get\(['"]([A-Z][A-Z0-9_]+)/g,
        /os\.environ(?:\.get)?\(?\[?['"]([A-Z][A-Z0-9_]+)/g,
        // getenv (Python, PHP, C), Getenv/LookupEnv (Go), System.getenv (Java/Kotlin)
        /[Gg]etenv\(['"]([A-Z][A-Z0-9_]+)/g,
        /LookupEnv\(['"]([A-Z][A-Z0-9_]+)/g,
        // Rust: env::var("X"), env::var_os("X")
        /env::var(?:_os)?\(['"]([A-Z][A-Z0-9_]+)/g,
        // Ruby: ENV["X"], ENV.fetch("X")
        /\bENV(?:\.fetch\(|\[)['"]([A-Z][A-Z0-9_]+)/g,
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
  const pattern = new RegExp(`([\\w./-]*${name})#([\\w-]+)`, "g");
  for (const path of project.files) {
    if (!TEXT_SUFFIXES.has(suffix(path)) || path === target) continue;
    const directory = path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "";
    for (const match of readText(`${project.root}/${path}`).matchAll(pattern)) {
      if (normalize(directory ? `${directory}/${match[1]}` : match[1]) !== target) continue;
      if (!anchors.has(match[2])) anchors.set(match[2], new Set());
      anchors.get(match[2])!.add(path);
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

type Report = (marker: Finding["marker"], message: string) => void;

/** Prüft einen einzelnen Befehl gegen das Verzeichnis, in dem er läuft. */
function checkCommand(command: string, directory: string, facts: Facts, report: Report): void {
  const where = (dir: string) => (dir === "." ? "der Wurzel" : dir);
  for (const match of command.matchAll(/\bmake\s+(?:-C\s+(\S+)\s+)?([A-Za-z0-9_.-]+)/g)) {
    const target = match[2];
    if (target.includes("=") || target.startsWith("-")) continue;
    const makeDirectory = match[1] ? join(directory, match[1]) : directory;
    const info = facts.makeTargets.get(makeDirectory);
    if (!info) report("!", `make ${target} – kein Makefile in ${where(makeDirectory)}`);
    else if (!info.targets.has(target)) {
      if (info.unresolved) {
        report(
          "?",
          `make ${target} – nicht im Makefile in ${
            where(makeDirectory)
          }; es bindet Dateien über Variablen ein, prüfen`,
        );
      } else {report(
          "!",
          `make ${target} – kein solches Target im Makefile in ${where(makeDirectory)}`,
        );}
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
    if (!scripts) report("!", `npm run ${match[2]} – kein package.json in ${where(npmDirectory)}`);
    else if (!scripts.has(match[2])) {
      report("!", `npm run ${match[2]} – kein Skript im package.json in ${where(npmDirectory)}`);
    }
  }
  for (const match of command.matchAll(/\bdeno\s+task\s+([\w:.-]+)/g)) {
    const found = upward(facts.denoTasks, directory);
    if (!found) {
      report("!", `deno task ${match[1]} – keine deno.json in ${where(directory)} oder darüber`);
    } else if (!found[1].has(match[1])) {
      report("!", `deno task ${match[1]} – kein Task in ${found[0]}/deno.json`);
    }
  }
  for (const match of command.matchAll(/\b(uv|poetry|pdm|hatch)\s+run\s+(?:--\S+\s+)*([\w.-]+)/g)) {
    const name = match[2];
    if (PYTHON_TOOLS.has(name) || /^python\d/.test(name)) continue;
    const found = upward(facts.pythonScripts, directory);
    if (!found || !found[1].has(name)) {
      report(
        "?",
        `${
          match[1]
        } run ${name} – kein Skript in pyproject.toml; Werkzeug aus der Umgebung? prüfen`,
      );
    }
  }
  for (
    const match of command.matchAll(/\bcargo\s+run\b[^\n]*?(?:--bin|-p|--package)\s+([\w-]+)/g)
  ) {
    if (!facts.cargoNames.has(match[1])) {
      report(
        "!",
        `cargo run … ${match[1]} – kein solches Paket oder Binary in einer Cargo.toml`,
      );
    }
  }
  const unverified = command.match(UNVERIFIED);
  if (unverified) {
    report(
      "~",
      `${command.trim().slice(0, 80)} – ${
        unverified[1].split(/\s+/)[0]
      }-Befehle prüft dieses Skript nicht`,
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
  const seen = new Set<string>();
  // Jede Meldung nur einmal, auch wenn der Befehl mehrfach im Dokument steht.
  const once = (line: number, marker: Finding["marker"], message: string) => {
    if (seen.has(`${marker}:${message}`)) return;
    seen.add(`${marker}:${message}`);
    add({ line, marker, message });
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
            "?",
            `${part.trim().slice(0, 60)} – läuft in unbekanntem Verzeichnis (cd), nicht geprüft`,
          );
        }
        continue;
      }
      checkCommand(part, directory, facts, (marker, message) => once(line, marker, message));
    }
    for (const match of snippet.matchAll(/\b([A-Z][A-Z0-9]*_[A-Z0-9_]+)\b/g)) {
      const name = match[1];
      if (seen.has(`var:${name}`)) continue;
      seen.add(`var:${name}`);
      if (facts.variables.has(name) || mentionedOutsideDocs(name, project, cache)) continue;
      add({
        line,
        marker: "?",
        message: `${name} – im Projekt nicht gefunden; externe Bibliothek oder erfunden? prüfen`,
      });
    }
    // Repo-Pfade dürfen relativ zum Ort des Dokuments oder zur Wurzel stehen.
    const pathLike = snippet.trim();
    const inRepo = pathLike.startsWith("./") || topLevel.has(pathLike.split("/")[0]) ||
      localTop.has(pathLike.split("/")[0]);
    if (inRepo && /^(\.\/)?[\w.-]+(\/[\w.-]+)*\/?$/.test(pathLike) && pathLike.includes("/")) {
      const found = [join(baseDirectory, pathLike), normalize(pathLike)].some((path) =>
        exists(`${project.root}/${path}`)
      );
      if (!found) once(line, "!", `${pathLike} – Pfad gibt es im Repository nicht`);
    }
  }
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
  forbidden: Forbidden[] = [],
  verbose = false,
): Finding[] {
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
      const [pathPart, anchor] = link.split("#");
      if (!pathPart) {
        if (anchor && !slugs.has(anchor)) {
          add({ line: index + 1, marker: "!", message: `Anker fehlt im Dokument: #${anchor}` });
        }
      } else if (!exists(`${project.root}/${join(home, safeDecode(pathPart))}`)) {
        add({ line: index + 1, marker: "!", message: `Datei fehlt: ${link}` });
      }
    }
  });

  for (const [anchor, sources] of [...inboundAnchors(project, target)].sort()) {
    if (!slugs.has(anchor)) {
      add({
        line: 0,
        marker: "!",
        message: `Überschrift für #${anchor} fehlt; verlinkt aus ${
          [...sources].sort().slice(0, 3).join(", ")
        }`,
      });
    }
  }

  // Ein README eines Unterprojekts beschreibt sein Verzeichnis, andere
  // Dokumente (z. B. docs/development.md) beschreiben das Projekt von der Wurzel aus.
  checkClaims(text, project, collectFacts(project), isReadme ? home : ".", add);

  if (isReadme) {
    const alerts = [...text.matchAll(ALERT)].length;
    if (alerts > 2) {
      add({
        line: 0,
        marker: "?",
        message: `${alerts} Hinweisboxen; mehr als 2 entwerten jede einzelne`,
      });
    }
  }

  for (const { term, reason, pattern } of forbidden) {
    lines.forEach((content, index) => {
      const hit = pattern ? content.match(pattern)?.[0] : content.includes(term) ? term : undefined;
      if (hit === undefined) return;
      const shown = pattern
        ? `verbotenes Muster ${term} („${hit}“)`
        : `verbotener Begriff „${term}“`;
      add({
        line: index + 1,
        marker: "!",
        message: `${shown}${reason ? ` – ${reason}` : ""}`,
      });
    });
  }

  lines.forEach((content, index) => {
    if (/\b(TODO|FIXME|TBD|lorem ipsum)\b|<your[ -]|\[insert /i.test(content)) {
      add({ line: index + 1, marker: "!", message: `Platzhalter: ${content.trim().slice(0, 80)}` });
    }
  });

  if (verbose) {
    for (const [line, content] of prose) {
      for (const match of content.matchAll(COUNT)) {
        if (!UNIT.test(match[0])) {
          add({ line, marker: "i", message: `Zahlenangabe, gegen die Quelle prüfen: ${match[0]}` });
        }
      }
    }
    for (const url of [...new Set(text.match(/https?:\/\/[^\s)"'>`]+/g) ?? [])].sort()) {
      add({ line: 0, marker: "i", message: `externe URL: ${url}` });
    }
  }

  return findings.sort((a, b) => a.line - b.line);
}

/** Markdown-Dateien eines Ordners (relativ zur Wurzel), ohne Symlinks und sensible Dateien. */
function markdownFiles(root: string, directory: string): string[] {
  const result: string[] = [];
  for (const entry of Deno.readDirSync(`${root}/${directory}`)) {
    const path = `${directory}/${entry.name}`;
    if (entry.isSymlink || isSensitive(path)) continue;
    if (entry.isDirectory && !SKIP_DIRS.has(entry.name)) result.push(...markdownFiles(root, path));
    else if (entry.isFile && DOC_SUFFIXES.has(suffix(entry.name))) result.push(path);
  }
  return result.sort();
}

/** Dateien und Ordner (relativ zur Wurzel) zu einer Liste von Dokumenten, ohne ausgeschlossene Pfade. */
export function expandDocuments(
  root: string,
  inputs: string[],
  excludes: string[],
): { documents: string[]; missing: string[] } {
  const excluded = excludes.map(normalize);
  const isExcluded = (path: string) =>
    excluded.some((prefix) => path === prefix || path.startsWith(`${prefix}/`));
  const documents: string[] = [];
  const missing: string[] = [];
  for (const input of inputs) {
    const path = normalize(input);
    let info: Deno.FileInfo;
    try {
      info = Deno.statSync(`${root}/${path}`);
    } catch {
      missing.push(input);
      continue;
    }
    const found = info.isDirectory ? markdownFiles(root, path) : isSensitive(path) ? [] : [path];
    for (const document of found) {
      if (!isExcluded(document) && !documents.includes(document)) documents.push(document);
    }
  }
  return { documents, missing };
}

// ------------------------------------------------------------ Kommandozeile

interface Options {
  root: string;
  forbidden: Forbidden[];
  excludes: string[];
  placement?: string;
  verbose: boolean;
  inputs: string[];
}

function parseArgs(args: string[]): Options | string {
  const options: Options = { root: ".", forbidden: [], excludes: [], verbose: false, inputs: [] };
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
      else if (arg.startsWith("--")) return `unbekannte Option: ${arg}`;
      else options.inputs.push(arg);
    } catch (error) {
      return (error as Error).message;
    }
  }
  if (!options.inputs.length) return "keine Datei und kein Ordner angegeben";
  if (options.placement && options.inputs.length !== 1) return "--as gilt nur für genau eine Datei";
  return options;
}

function main(args: string[]): number {
  const options = parseArgs(args);
  if (typeof options === "string") {
    console.error(`Fehler: ${options}`);
    console.error(
      "Aufruf: docs-check.ts [--root DIR] [--forbid BEGRIFF|/MUSTER/[|GRUND]] [--exclude PFAD] [--as PFAD] [--verbose] DATEI|ORDNER...",
    );
    return 2;
  }
  const project = loadProject(options.root);
  // Ein Entwurf (--as) liegt außerhalb des Repos und wird unter seinem Pfad gelesen.
  const targets: Array<[string, string]> = [];
  let missingCount = 0;
  if (options.placement) {
    targets.push([options.inputs[0], options.placement]);
  } else {
    const { documents, missing } = expandDocuments(
      project.root,
      options.inputs.map((input) => relativeToRoot(project.root, input)),
      options.excludes,
    );
    for (const path of missing) console.log(`! ${path} – Datei oder Ordner fehlt`);
    missingCount = missing.length;
    for (const document of documents) targets.push([`${project.root}/${document}`, document]);
  }

  let problems = missingCount;
  let hints = 0;
  for (const [path, placement] of targets) {
    const findings = checkDocument(path, project, placement, options.forbidden, options.verbose);
    const fileProblems = findings.filter((finding) => finding.marker === "!").length;
    problems += fileProblems;
    hints += findings.filter((finding) => finding.marker === "?" || finding.marker === "~").length;
    if (!findings.length && !options.verbose) continue;
    console.log(
      `\n${normalize(placement)}${
        fileProblems ? `  (${count(fileProblems, "Problem", "Probleme")})` : ""
      }`,
    );
    for (const { line, marker, message } of findings) {
      console.log(`  ${marker} ${line ? `${line}: ` : ""}${message}`);
    }
  }
  console.log(
    `\n${count(targets.length, "Dokument", "Dokumente")} geprüft · ${
      count(problems, "Problem", "Probleme")
    } · ${count(hints, "Hinweis", "Hinweise")}`,
  );
  if (problems || hints) {
    console.log("! = Problem, ? = von Hand prüfen, ~ = nicht prüfbares Ökosystem");
  }
  return problems ? 1 : 0;
}

/** Zahl mit passender Einzahl oder Mehrzahl. */
function count(value: number, one: string, many: string): string {
  return `${value} ${value === 1 ? one : many}`;
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
