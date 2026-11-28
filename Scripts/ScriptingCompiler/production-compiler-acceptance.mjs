#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  cp,
  mkdtemp,
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptRoot, "../..");
const profilePath = path.join(
  repositoryRoot,
  "Packages/HanlinPlatform/Sources/HanlinScriptCompiler/Resources/production-compiler-profile.json",
);
const declarationRoot = path.join(
  repositoryRoot,
  "Packages/HanlinPlatform/Sources/HanlinScriptingSDK/Resources",
);
const declarationNames = [
  "global.d.ts",
  "node.d.ts",
  "safari-ext.d.ts",
  "scripting.d.ts",
  "web-fetch.d.ts",
];
const corpusPath = path.join(scriptRoot, "production-compiler-corpus.json");
const compilerLanes = [
  {
    name: "typecheck",
    version: "7.0.2",
    integrity: "sha512-8FYau96o3NKOhbjKi/qNvG/W5jhzxkbdm5sj9AbZ/5T5sWqn3hJgLfGx27sRKZWTvyzCP8dLRBTf5tBTSRVUNA==",
    root: scriptRoot,
    noEmit: true,
  },
  {
    name: "production-emitter",
    version: "6.0.3",
    integrity: "sha512-y2TvuxSZPDyQakkFRPZHKFm+KKVqIisdg9/CZwm9ftvKXLP8NRWj38/ODjNbr43SsoXqNuAisEf1GdCxqWcdBw==",
    root: path.join(repositoryRoot, "AI_HLY/Downstream/RuntimeCore/Node/Host"),
    noEmit: false,
  },
];

const profile = JSON.parse(await readFile(profilePath, "utf8"));
validateProfile(profile);
for (const lane of compilerLanes) await validateCompilerLane(lane);

const corpus = JSON.parse(await readFile(corpusPath, "utf8"));
if (corpus.schemaVersion !== 1 || !Array.isArray(corpus.discoveryRoots)) {
  throw new Error("Invalid production compiler corpus manifest");
}
const packages = [];
for (const relativeRoot of corpus.discoveryRoots) {
  packages.push(...await discoverPackages(path.join(repositoryRoot, relativeRoot)));
}
if (packages.length === 0) throw new Error("Production compiler corpus is empty");

const temporaryRoot = await mkdtemp(path.join(tmpdir(), "hanlin-production-compiler-"));
const results = [];
try {
  for (const [index, packageRoot] of packages.entries()) {
    const relativePackage = relative(packageRoot);
    const localExpectationPath = path.join(packageRoot, "compiler-acceptance.json");
    const expectation = await fileExists(localExpectationPath)
      ? JSON.parse(await readFile(localExpectationPath, "utf8"))
      : corpus.expectations?.[relativePackage];
    if (!expectation) {
      throw new Error(`Unclassified production compiler fixture: ${relativePackage}`);
    }
    validateExpectation(expectation, relativePackage);

    const workspace = path.join(temporaryRoot, String(index));
    await cp(packageRoot, workspace, { recursive: true });
    await mkdir(path.join(workspace, "virtual"), { recursive: true });
    for (const name of declarationNames) {
      await cp(path.join(declarationRoot, name), path.join(workspace, "virtual", name));
    }
    const manifest = JSON.parse(await readFile(path.join(workspace, "script.json"), "utf8"));
    const sourceFiles = await listSourceFiles(workspace);
    const files = [
      ...sourceFiles,
      ...declarationNames.map(name => `virtual/${name}`),
    ].sort((left, right) => left.localeCompare(right, "en"));
    const laneResults = [];
    for (const lane of compilerLanes) {
      const configuration = {
        compilerOptions: {
          ...profile.compilerOptions,
          noEmit: lane.noEmit,
        },
        files,
      };
      await writeFile(
        path.join(workspace, "tsconfig.json"),
        `${JSON.stringify(configuration, null, 2)}\n`,
      );
      const compilerPath = path.join(lane.root, "node_modules/typescript/bin/tsc");
      const compilation = spawnSync(
        process.execPath,
        [compilerPath, "--project", "tsconfig.json", "--pretty", "false"],
        {
          cwd: workspace,
          encoding: "utf8",
          windowsHide: true,
          maxBuffer: 32 * 1024 * 1024,
        },
      );
      const diagnostics = redact(`${compilation.stdout ?? ""}\n${compilation.stderr ?? ""}`).trim();
      const diagnosticCodes = [...diagnostics.matchAll(/\bTS(\d+):/g)]
        .map(match => Number(match[1]));
      assertExpectedCompilation({
        relativePackage,
        expectation,
        lane,
        status: compilation.status,
        diagnostics,
        diagnosticCodes,
      });
      if (expectation.expected === "success" && !lane.noEmit) {
        const emittedEntrypoint = String(manifest.entry ?? "index.tsx")
          .replace(/\.(?:tsx?|jsx?)$/i, ".js");
        const emittedPath = path.join(workspace, "dist", emittedEntrypoint);
        if (!await fileExists(emittedPath)) {
          throw new Error(`${relativePackage}: production emitter omitted ${emittedEntrypoint}`);
        }
      }
      laneResults.push({
        lane: lane.name,
        compilerVersion: lane.version,
        passed: expectation.expected === "success" ? compilation.status === 0 : compilation.status !== 0,
        diagnosticCodes: [...new Set(diagnosticCodes)].sort((left, right) => left - right),
      });
    }
    results.push({
      package: relativePackage,
      displayName: manifest.name ?? path.basename(packageRoot),
      expected: expectation.expected,
      sourceFileCount: sourceFiles.length,
      lanes: laneResults,
      reason: expectation.reason ?? null,
    });
  }
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}

console.log(JSON.stringify({
  schemaVersion: 1,
  profile: relative(profilePath),
  libraries: profile.compilerOptions.lib,
  declarationFiles: declarationNames,
  compilerLanes: compilerLanes.map(({ name, version, integrity }) => ({ name, version, integrity })),
  packageCount: results.length,
  passed: true,
  packages: results,
}, null, 2));

function validateProfile(value) {
  const options = value?.compilerOptions;
  if (value?.schemaVersion !== 1
      || JSON.stringify(options?.lib) !== JSON.stringify(["ESNext"])
      || JSON.stringify(options?.types) !== JSON.stringify([])
      || options?.strict !== true
      || options?.skipLibCheck !== true
      || options?.moduleResolution !== "Bundler"
      || JSON.stringify(options?.paths?.scripting) !== JSON.stringify(["./virtual/scripting.d.ts"])) {
    throw new Error("The production compiler profile is not the fail-closed Scripting profile");
  }
  for (const forbidden of ["DOM", "WebWorker", "ScriptHost"]) {
    if (options.lib.some(value => value.toLowerCase() === forbidden.toLowerCase())) {
      throw new Error(`Browser library ${forbidden} polluted the production compiler profile`);
    }
  }
}

async function validateCompilerLane(lane) {
  const packageDocument = JSON.parse(
    await readFile(path.join(lane.root, "node_modules/typescript/package.json"), "utf8"),
  );
  const lock = JSON.parse(await readFile(path.join(lane.root, "package-lock.json"), "utf8"));
  const locked = lock.packages?.["node_modules/typescript"];
  if (packageDocument.version !== lane.version
      || locked?.version !== lane.version
      || locked?.integrity !== lane.integrity) {
    throw new Error(`${lane.name} compiler identity or integrity mismatch`);
  }
}

function validateExpectation(expectation, packageName) {
  if (!["success", "failure"].includes(expectation.expected)) {
    throw new Error(`${packageName}: invalid compiler expectation`);
  }
  if (expectation.expected === "failure"
      && (!Array.isArray(expectation.diagnosticCodes) || expectation.diagnosticCodes.length === 0)) {
    throw new Error(`${packageName}: expected failure lacks diagnostic codes`);
  }
}

function assertExpectedCompilation({
  relativePackage,
  expectation,
  lane,
  status,
  diagnostics,
  diagnosticCodes,
}) {
  if (expectation.expected === "success" && status !== 0) {
    throw new Error(`${relativePackage} failed ${lane.name}:\n${diagnostics}`);
  }
  if (expectation.expected === "failure") {
    if (status === 0) throw new Error(`${relativePackage} unexpectedly passed ${lane.name}`);
    for (const code of expectation.diagnosticCodes) {
      if (!diagnosticCodes.includes(code)) {
        throw new Error(`${relativePackage} ${lane.name} omitted TS${code}:\n${diagnostics}`);
      }
    }
  }
}

async function discoverPackages(root) {
  const roots = [];
  async function visit(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    if (entries.some(entry => entry.isFile() && entry.name === "script.json")) {
      roots.push(directory);
      return;
    }
    for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name, "en"))) {
      if (!entry.isDirectory() || ["__MACOSX", "node_modules"].includes(entry.name)) continue;
      await visit(path.join(directory, entry.name));
    }
  }
  if (!(await stat(root)).isDirectory()) throw new Error(`Corpus root is not a directory: ${relative(root)}`);
  await visit(root);
  return roots.sort((left, right) => left.localeCompare(right, "en"));
}

async function listSourceFiles(root) {
  const files = [];
  async function visit(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (["__MACOSX", "dist", "node_modules", "virtual"].includes(entry.name)) continue;
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        await visit(absolute);
      } else if (entry.isFile()
          && (/\.(?:[cm]?[jt]sx?)$/i.test(entry.name)
            || (entry.name.endsWith(".json")
              && !["script.json", "compiler-acceptance.json", "tsconfig.json"].includes(entry.name)))) {
        files.push(path.relative(root, absolute).replaceAll("\\", "/"));
      }
    }
  }
  await visit(root);
  return files.sort((left, right) => left.localeCompare(right, "en"));
}

async function fileExists(value) {
  try {
    return (await stat(value)).isFile();
  } catch {
    return false;
  }
}

function relative(value) {
  return path.relative(repositoryRoot, value).replaceAll("\\", "/");
}

function redact(value) {
  return value
    .replaceAll(repositoryRoot, "<repository>")
    .replaceAll("\\", "/");
}
