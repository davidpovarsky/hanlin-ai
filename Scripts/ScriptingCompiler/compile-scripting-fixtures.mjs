import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const compilerRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(compilerRoot, "../..");
const fixturesRoot = join(
  repositoryRoot,
  "AI_HLYTests/Fixtures/ScriptingFixtures.bundle",
);
const compilerPath = join(compilerRoot, "node_modules/typescript/bin/tsc");
const compilerPackagePath = join(
  compilerRoot,
  "node_modules/typescript/package.json",
);
const compilerLockPath = join(compilerRoot, "package-lock.json");
const configPath = join(compilerRoot, "tsconfig.phase2a.json");
const declarationPath = join(compilerRoot, "assistant-tool-phase2a.d.ts");
const expectedCompilerVersion = "7.0.2";
const expectedCompilerIntegrity =
  "sha512-8FYau96o3NKOhbjKi/qNvG/W5jhzxkbdm5sj9AbZ/5T5sWqn3hJgLfGx27sRKZWTvyzCP8dLRBTf5tBTSRVUNA==";
const mode = process.argv[2] ?? "--check";
const compilerArguments = [
  "--ignoreConfig",
  "--target", "ES2023",
  "--lib", "ES2023",
  "--module", "commonjs",
  "--strict",
  "--noEmitOnError",
  "--skipLibCheck",
  "--removeComments",
  "--newLine", "lf",
];

if (!["--check", "--write"].includes(mode)) {
  throw new Error("Usage: compile-scripting-fixtures.mjs [--check|--write]");
}

const compilerPackage = JSON.parse(await readFile(compilerPackagePath, "utf8"));
const compilerLock = JSON.parse(await readFile(compilerLockPath, "utf8"));
if (compilerPackage.version !== expectedCompilerVersion) {
  throw new Error(
    `Expected TypeScript ${expectedCompilerVersion}, received ${compilerPackage.version}`,
  );
}
const lockedCompiler = compilerLock.packages?.["node_modules/typescript"];
if (lockedCompiler?.version !== expectedCompilerVersion
    || lockedCompiler?.integrity !== expectedCompilerIntegrity) {
  throw new Error("The TypeScript package lock does not match the authorized compiler artifact.");
}
const versionResult = runCompiler(["--version"], compilerRoot);
if (versionResult.status !== 0 || versionResult.stdout.trim() !== "Version 7.0.2") {
  throw new Error(`Unexpected TypeScript version output: ${versionResult.stdout}`);
}

const configBytes = await readFile(configPath);
const declarationBytes = await readFile(declarationPath);
const configuration = JSON.parse(configBytes);
const expectedOptions = {
  target: "ES2023",
  lib: ["ES2023"],
  module: "commonjs",
  strict: true,
  noEmitOnError: true,
  skipLibCheck: true,
  removeComments: true,
  newLine: "lf",
};
if (JSON.stringify(configuration.compilerOptions) !== JSON.stringify(expectedOptions)) {
  throw new Error("The checked compiler arguments and tsconfig.phase2a.json have diverged.");
}
const compilerConfigurationHash = sha256(Buffer.concat([
  Buffer.from("tsconfig.phase2a.json\0", "utf8"),
  configBytes,
  Buffer.from("\0assistant-tool-phase2a.d.ts\0", "utf8"),
  declarationBytes,
]));
const validFixtureRoot = join(fixturesRoot, "ValidEcho");
const sourcePath = join(validFixtureRoot, "assistant_tool.ts");
const sourceBytes = await readFile(sourcePath);
const temporaryRoot = await mkdtemp(join(tmpdir(), "hanlin-scripting-compile-"));

try {
  const outputPath = join(temporaryRoot, "assistant_tool.js");
  const compileResult = runCompiler([
    ...compilerArguments,
    "--outDir",
    temporaryRoot,
    "--rootDir",
    ".",
    declarationPath,
    "assistant_tool.ts",
  ], validFixtureRoot);
  if (compileResult.status !== 0) {
    throw new Error(redactDiagnostics(compileResult));
  }
  const javaScriptBytes = await readFile(outputPath);
  const definition = JSON.parse(
    await readFile(join(validFixtureRoot, "fixture-definition.json"), "utf8"),
  );
  const manifest = buildManifest({
    definition,
    sourceBytes,
    javaScriptBytes,
    compilerConfigurationHash,
  });
  const expectedJavaScriptPath = join(validFixtureRoot, "assistant_tool.js");
  const expectedManifestPath = join(validFixtureRoot, "hanlin-script.json");
  const manifestBytes = Buffer.from(`${stableJSON(manifest)}\n`, "utf8");

  if (mode === "--write") {
    await writeFile(expectedJavaScriptPath, javaScriptBytes);
    await writeFile(expectedManifestPath, manifestBytes);
  } else {
    await requireEqualFile(expectedJavaScriptPath, javaScriptBytes);
    await requireEqualFile(expectedManifestPath, manifestBytes);
  }

  const invalidRoot = join(compilerRoot, "Fixtures/CompileFailure");
  const invalidResult = runCompiler([
    ...compilerArguments,
    "--outDir",
    join(temporaryRoot, "invalid"),
    "--rootDir",
    ".",
    declarationPath,
    "assistant_tool.ts",
  ], invalidRoot);
  if (invalidResult.status === 0) {
    throw new Error("The compile-failure fixture unexpectedly compiled");
  }
  const rawInvalidDiagnostics = `${invalidResult.stdout ?? ""}\n${invalidResult.stderr ?? ""}`;
  const invalidDiagnostics = redactDiagnostics(invalidResult);
  if (!invalidDiagnostics.includes("assistant_tool.ts")) {
    throw new Error("Compile diagnostics omitted the package-local source file");
  }
  if (rawInvalidDiagnostics.includes(repositoryRoot)) {
    throw new Error("Compile diagnostics leaked the repository absolute path");
  }

  console.log(JSON.stringify({
    compilerLane: "scripting-original",
    compilerVersion: expectedCompilerVersion,
    compilerIntegrity: expectedCompilerIntegrity,
    compilerConfigurationHash,
    sourceSHA256: sha256(sourceBytes),
    javaScriptSHA256: sha256(javaScriptBytes),
    validFixture: relative(repositoryRoot, validFixtureRoot).replaceAll("\\", "/"),
    compileFailureVerified: true,
  }, null, 2));
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}

function runCompiler(arguments_, cwd) {
  return spawnSync(process.execPath, [compilerPath, ...arguments_], {
    cwd,
    encoding: "utf8",
    windowsHide: true,
  });
}

function redactDiagnostics(result) {
  return `${result.stdout ?? ""}\n${result.stderr ?? ""}`
    .replaceAll(repositoryRoot, "<repository>")
    .replaceAll("\\", "/")
    .trim();
}

function buildManifest({
  definition,
  sourceBytes,
  javaScriptBytes,
  compilerConfigurationHash,
}) {
  const sourceDigest = sha256(sourceBytes);
  const compiledDigest = sha256(javaScriptBytes);
  const manifest = {
    descriptorRevision: 1,
    displayName: localized(definition.displayName),
    entrypoint: {
      compiledIntegrity: integrity(compiledDigest),
      compiledPath: "assistant_tool.js",
      compilerConfigurationHash,
      compilerLane: "scripting-original",
      compilerProvenance: {
        bundlerConfigurationHash: compilerConfigurationHash,
        bundlerVersion: "hanlin-fixture-bundler-1.0.0",
        emitterConfigurationHash: compilerConfigurationHash,
        emitterVersion: expectedCompilerVersion,
        runtimeEngineVersion: "Apple",
        typecheckCompilerVersion: expectedCompilerVersion,
        typecheckConfigurationHash: compilerConfigurationHash,
      },
      compilerVersion: expectedCompilerVersion,
      documentKind: "assistantTool",
      exportedTools: definition.tools.map((tool) => ({
        id: tool.id,
        inputSchema: schemaDocument(tool.inputSchema),
        outputSchema: schemaDocument(tool.outputSchema),
        requiredCapabilities: [],
        requiresApproval: false,
        risk: "passive",
        summary: localized(tool.summary),
        title: localized(tool.title),
      })),
      sourceIntegrity: integrity(sourceDigest),
      sourcePath: "assistant_tool.ts",
    },
    packageID: definition.packageID,
    runtime: {
      abiVersion: "1.0",
      capabilities: {
        asyncHostCalls: true,
        extensionSafe: true,
        filesystem: "capabilityBroker",
        hardInterruption: false,
        hardMemoryLimit: false,
        hardStackLimit: false,
        modules: true,
        network: "capabilityBroker",
        persistentContext: true,
        scriptUI: true,
        trustedCodeOnly: false,
      },
      cancellation: {
        deadlineEnforcement: false,
        interruptibleExecution: false,
      },
      engine: "JavaScriptCore",
      engineVersion: "Apple",
      kind: "javaScriptCore",
      minimumTrust: "localUnverified",
      profile: "scripting-jsc",
    },
    schemaVersion: "1.0",
    version: definition.version,
  };
  const packageDigest = sha256(Buffer.from(
    JSON.stringify(sortRecursively(manifest)),
    "utf8",
  ));
  return { ...manifest, integrity: integrity(packageDigest) };
}

function schemaDocument(root) {
  return {
    dialect: "https://json-schema.org/draft/2020-12/schema",
    findings: [],
    root: taggedJSON({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      ...root,
    }),
  };
}

function taggedJSON(value) {
  if (value === null) return { type: "null" };
  if (typeof value === "boolean") return { type: "bool", value };
  if (typeof value === "string") return { type: "string", value };
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      throw new Error("Fixture schema numbers must be exact integers");
    }
    return { type: "integer", value: String(value) };
  }
  if (Array.isArray(value)) {
    return { type: "array", value: value.map(taggedJSON) };
  }
  const members = Object.entries(value)
    .sort(([left], [right]) => Buffer.from(left).compare(Buffer.from(right)))
    .map(([key, member]) => ({ key, value: taggedJSON(member) }));
  return { type: "object", value: members };
}

function localized(value) {
  return { fallbackLocale: "en", values: { en: value } };
}

function integrity(digest) {
  return { algorithm: "sha256", digest };
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function stableJSON(value) {
  return JSON.stringify(sortRecursively(value), null, 2);
}

function sortRecursively(value) {
  if (Array.isArray(value)) return value.map(sortRecursively);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right, "en"))
        .map(([key, member]) => [key, sortRecursively(member)]),
    );
  }
  return value;
}

async function requireEqualFile(path, expected) {
  const actual = await readFile(path);
  if (!actual.equals(expected)) {
    throw new Error(`${relative(repositoryRoot, path)} is stale; run npm run generate`);
  }
}
