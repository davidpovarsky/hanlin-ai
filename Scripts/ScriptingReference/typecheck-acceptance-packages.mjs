#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "../..");
const defaultTypeRoot = path.join(repositoryRoot, "Reference/ScriptingCompatibility/Original/Types");
const compilerRoot = path.join(repositoryRoot, "Scripts/ScriptingCompiler");
const compilerPath = path.join(compilerRoot, "node_modules/typescript/bin/tsc");
const compilerPackagePath = path.join(compilerRoot, "node_modules/typescript/package.json");
const declarationNames = [
  "global.d.ts",
  "node.d.ts",
  "safari-ext.d.ts",
  "scripting.d.ts",
  "web-fetch.d.ts",
];

const options = parseArguments(process.argv.slice(2));
const typeRoot = path.resolve(options.types ?? defaultTypeRoot);
const compilerPackage = JSON.parse(await readFile(compilerPackagePath, "utf8"));
if (compilerPackage.version !== "7.0.2") {
  throw new Error(`Acceptance typecheck requires TypeScript 7.0.2, found ${compilerPackage.version}`);
}

const packageRoots = await discoverPackageRoots(path.resolve(options.directory));
if (packageRoots.length === 0) throw new Error("No package roots containing script.json were found");
const temporaryRoot = await mkdtemp(path.join(tmpdir(), "hanlin-scripting-acceptance-"));
const results = [];

try {
  for (let index = 0; index < packageRoots.length; index += 1) {
    const packageRoot = packageRoots[index];
    const sourceFiles = await listSourceFiles(packageRoot);
    const scriptManifest = JSON.parse(await readFile(path.join(packageRoot, "script.json"), "utf8"));
    const config = {
      compilerOptions: {
        target: "ESNext",
        lib: ["ESNext"],
        allowJs: true,
        checkJs: false,
        strict: true,
        esModuleInterop: true,
        allowSyntheticDefaultImports: true,
        forceConsistentCasingInFileNames: true,
        noFallthroughCasesInSwitch: true,
        module: "CommonJS",
        resolveJsonModule: true,
        skipLibCheck: true,
        jsx: "react",
        jsxFactory: "createElement",
        jsxFragmentFactory: "Fragment",
        paths: { scripting: [path.join(typeRoot, "scripting.d.ts")] },
        noEmit: true,
      },
      files: [
        ...declarationNames.map(name => path.join(typeRoot, name)),
        ...sourceFiles,
      ],
    };
    const configPath = path.join(temporaryRoot, `${index}.json`);
    await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`);
    const result = spawnSync(process.execPath, [compilerPath, "--project", configPath, "--pretty", "false"], {
      cwd: packageRoot,
      encoding: "utf8",
      windowsHide: true,
      maxBuffer: 16 * 1024 * 1024,
    });
    const diagnostics = `${result.stdout ?? ""}\n${result.stderr ?? ""}`
      .replaceAll(repositoryRoot, "<repository>")
      .replaceAll(path.resolve(options.directory), "<acceptance>")
      .replaceAll("\\", "/")
      .trim();
    results.push({
      displayName: scriptManifest.name ?? path.basename(packageRoot),
      root: path.relative(path.resolve(options.directory), packageRoot).replaceAll("\\", "/"),
      sourceFileCount: sourceFiles.length,
      passed: result.status === 0,
      diagnostics,
    });
  }
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}

console.log(JSON.stringify({
  schemaVersion: 1,
  compilerVersion: compilerPackage.version,
  declarationFiles: declarationNames,
  packageCount: results.length,
  passed: results.every(result => result.passed),
  packages: results,
}, null, 2));

if (results.some(result => !result.passed)) process.exitCode = 1;

function parseArguments(argumentsValue) {
  const directoryIndex = argumentsValue.indexOf("--directory");
  if (directoryIndex < 0 || !argumentsValue[directoryIndex + 1]) {
    throw new Error("Usage: typecheck-acceptance-packages.mjs --directory <extracted-packages-root>");
  }
  const typesIndex = argumentsValue.indexOf("--types");
  if (typesIndex >= 0 && !argumentsValue[typesIndex + 1]) {
    throw new Error("--types requires a directory");
  }
  const expectedLength = typesIndex >= 0 ? 4 : 2;
  if (argumentsValue.length !== expectedLength) throw new Error("Unknown acceptance typecheck arguments");
  return {
    directory: argumentsValue[directoryIndex + 1],
    types: typesIndex >= 0 ? argumentsValue[typesIndex + 1] : null,
  };
}

async function discoverPackageRoots(root) {
  const roots = [];
  async function visit(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    if (entries.some(entry => entry.isFile() && entry.name === "script.json")) {
      roots.push(directory);
      return;
    }
    for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name, "en"))) {
      if (!entry.isDirectory() || entry.name === "__MACOSX" || entry.name === "node_modules") continue;
      await visit(path.join(directory, entry.name));
    }
  }
  const info = await stat(root);
  if (!info.isDirectory()) throw new Error(`Not a directory: ${root}`);
  await visit(root);
  return roots.sort((left, right) => left.localeCompare(right, "en"));
}

async function listSourceFiles(root) {
  const files = [];
  async function visit(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.name === "__MACOSX" || entry.name === "node_modules") continue;
      const absolutePath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        await visit(absolutePath);
      } else if (entry.isFile() && /\.(?:[cm]?[jt]sx?)$/i.test(entry.name) && !entry.name.endsWith(".d.ts")) {
        files.push(absolutePath);
      }
    }
  }
  await visit(root);
  return files.sort((left, right) => left.localeCompare(right, "en"));
}
