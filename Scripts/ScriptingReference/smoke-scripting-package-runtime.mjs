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
  const sourceFile = ts.createSourceFile(relative, sourceText, ts.ScriptTarget.ESNext, true);
  for (const statement of sourceFile.statements) {
    if (!ts.isImportDeclaration(statement)
        || statement.moduleSpecifier.text !== "scripting"
        || !statement.importClause?.namedBindings
        || !ts.isNamedImports(statement.importClause.namedBindings)) continue;
    for (const element of statement.importClause.namedBindings.elements) {
      importedScriptingSymbols.add(element.propertyName?.text ?? element.name.text);
    }
  }
  const output = ts.transpileModule(sourceText, {
    fileName: relative,
    compilerOptions: {
      target: ts.ScriptTarget.ESNext,
      module: ts.ModuleKind.CommonJS,
      jsx: ts.JsxEmit.React,
      jsxFactory: "createElement",
      jsxFragmentFactory: "Fragment",
      esModuleInterop: true,
    },
  }).outputText;
  modules.set(relative.replace(/\.(?:tsx?|jsx?)$/i, ".js"), output);
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
    if (entry.name === "__MACOSX" || entry.name === "node_modules") return [];
    const absolute = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(absolute) : [absolute];
  });
}
function count(node) {
  return 1 + (node.children ?? []).reduce((sum, child) => sum + count(child), 0);
}
