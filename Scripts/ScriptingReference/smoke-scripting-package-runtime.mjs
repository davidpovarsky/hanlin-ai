import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import ts from "../../AI_HLY/Downstream/RuntimeCore/Node/Host/node_modules/typescript/lib/typescript.js";

if (!process.argv[2]) {
  throw new Error("Usage: smoke-scripting-package-runtime.mjs <extracted-package-root>");
}
const packageRoot = path.resolve(process.argv[2]);
const repositoryRoot = path.resolve(import.meta.dirname, "../..");
const modules = new Map();
const importedScriptingSymbols = new Set();

for (const file of walk(packageRoot)) {
  if (!/\.(?:tsx?|jsx?)$/i.test(file) || file.endsWith(".d.ts")) continue;
  const relative = path.relative(packageRoot, file).replaceAll("\\", "/");
  const sourceText = fs.readFileSync(file, "utf8");
  const transpilation = ts.transpileModule(sourceText, {
    fileName: relative,
    reportDiagnostics: true,
    compilerOptions: {
      target: ts.ScriptTarget.ESNext,
      module: ts.ModuleKind.CommonJS,
      jsx: ts.JsxEmit.React,
      jsxFactory: "createElement",
      jsxFragmentFactory: "Fragment",
      esModuleInterop: true,
    },
  });
  const errors = (transpilation.diagnostics ?? []).filter(diagnostic =>
    diagnostic.category === ts.DiagnosticCategory.Error
  );
  if (errors.length > 0) {
    throw new Error(ts.formatDiagnostics(errors, {
      getCanonicalFileName: value => value,
      getCurrentDirectory: () => packageRoot,
      getNewLine: () => "\n",
    }));
  }
  collectRuntimeScriptingSymbols(transpilation.outputText, importedScriptingSymbols);
  modules.set(relative.replace(/\.(?:tsx?|jsx?)$/i, ".js"), transpilation.outputText);
}

const registration = JSON.parse(fs.readFileSync(path.join(
  repositoryRoot,
  "Packages/HanlinPlatform/Sources/HanlinScriptingSDK/Resources/runtime-registration.json"
), "utf8"));
const runtimeStates = new Map(registration.records.map(record => [record.symbol, record.state]));
const rejectedImports = [...importedScriptingSymbols].filter(symbol => runtimeStates.get(symbol) === "unsupported");
if (rejectedImports.length > 0) {
  throw new Error(`Acceptance imports remain runtime-unsupported: ${rejectedImports.join(", ")}`);
}

const swift = fs.readFileSync(path.join(
  repositoryRoot,
  "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingApplicationSession.swift"
), "utf8");
const quotes = '"'.repeat(3);
const marker = `static let bootstrap = #${quotes}`;
const start = swift.indexOf(marker) + marker.length;
const bootstrap = swift.slice(start, swift.indexOf(`${quotes}#`, start));
const storage = new Map();
let rendered;
globalThis.__hanlinNativeRender = json => { rendered = JSON.parse(json); };
globalThis.__hanlinNativeStorageGet = key => JSON.stringify(
  storage.has(key)
    ? { allowed: true, found: true, json: storage.get(key) }
    : { allowed: true, found: false }
);
globalThis.__hanlinNativeStorageSet = (key, json) => { storage.set(key, json); return true; };
globalThis.__hanlinNativeStorageClear = () => { storage.clear(); return true; };
globalThis.__hanlinNativeStorageRemove = key => storage.delete(key);
globalThis.__hanlinNativeStorageContains = key => storage.has(key);
globalThis.__hanlinNativeStorageKeys = () => JSON.stringify({ allowed: true, keys: [...storage.keys()] });
globalThis.__hanlinNativeStorageGetData = () => JSON.stringify({ allowed: true, found: false });
globalThis.__hanlinNativeStorageSetData = () => true;
globalThis.__hanlinNativeFileInfo = () => JSON.stringify({
  ok: true,
  value: {
    documentsDirectory: "/documents",
    appGroupDocumentsDirectory: "/app-group",
    temporaryDirectory: "/temporary",
    scriptsDirectory: "/scripts",
    isiCloudEnabled: false,
    isWebDAVAvailable: false,
  },
});
globalThis.__hanlinNativeFileSync = () => JSON.stringify({
  ok: false,
  error: { name: "Error", code: "unavailable_in_smoke", message: "Filesystem I/O was not requested by this smoke fixture." },
});
globalThis.__hanlinNativeAsync = (id) => queueMicrotask(() => globalThis.__hanlinResolveNative(
  id,
  JSON.stringify({
    ok: false,
    error: { name: "Error", code: "unavailable_in_smoke", message: "Native async I/O was not requested by this smoke fixture." },
  }),
));
globalThis.__hanlinCancelNative = () => {};
vm.runInThisContext(bootstrap, { filename: "hanlin-scripting-ui-runtime.js" });

const cache = new Map();
function normalize(value) {
  const output = [];
  for (const part of value.split("/")) {
    if (!part || part === ".") continue;
    if (part === "..") output.pop();
    else output.push(part);
  }
  return output.join("/");
}
function resolve(from, specifier) {
  if (specifier === "scripting") return specifier;
  const base = from.split("/").slice(0, -1).join("/");
  const candidate = normalize(`${base}/${specifier}`);
  return [candidate, `${candidate}.js`, `${candidate}/index.js`].find(value => modules.has(value));
}
function load(specifier, from = "") {
  if (specifier === "scripting") return globalThis;
  const id = from ? resolve(from, specifier) : specifier;
  if (!id || !modules.has(id)) throw new Error(`Unresolved runtime module: ${specifier} from ${from}`);
  if (cache.has(id)) return cache.get(id).exports;
  const module = { exports: {} };
  cache.set(id, module);
  const factory = vm.runInThisContext(`(function(require,module,exports){${modules.get(id)}\n})`, { filename: id });
  factory(value => load(value, id), module, module.exports);
  return module.exports;
}
load("index.js");
if (!globalThis.__hanlinHasPresentedUI || !rendered) throw new Error("Package did not render ScriptUI");
console.log(JSON.stringify({
  emittedModuleCount: modules.size,
  importedScriptingSymbolCount: importedScriptingSymbols.size,
  rootKind: rendered.kind,
  renderedNodeCount: count(rendered),
  presented: globalThis.__hanlinHasPresentedUI,
}));

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    if (entry.name === "__MACOSX" || entry.name === "node_modules" || entry.name.startsWith("._")) return [];
    const absolute = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(absolute) : [absolute];
  });
}
function count(node) {
  return 1 + (node.children ?? []).reduce((sum, child) => sum + count(child), 0);
}

function collectRuntimeScriptingSymbols(outputText, symbols) {
  const aliases = [...outputText.matchAll(
    /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\(["']scripting["']\)/g,
  )].map(match => match[1]);
  for (const alias of aliases) {
    const escaped = alias.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    for (const match of outputText.matchAll(new RegExp(`\\b${escaped}\\.([A-Za-z_$][\\w$]*)`, "g"))) {
      symbols.add(match[1]);
    }
  }
  for (const match of outputText.matchAll(
    /\b(?:const|let|var)\s*\{([^}]+)\}\s*=\s*require\(["']scripting["']\)/g,
  )) {
    for (const binding of match[1].split(",")) {
      const importedName = binding.trim().split(/\s*:\s*/)[0];
      if (/^[A-Za-z_$][\w$]*$/.test(importedName)) symbols.add(importedName);
    }
  }
}
