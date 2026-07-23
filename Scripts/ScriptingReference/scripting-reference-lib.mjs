import { createHash } from "node:crypto";
import {
  lstat,
  mkdir,
  readFile,
  readdir,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const scriptsDirectory = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(scriptsDirectory, "..", "..");
export const referenceRoot = path.join(
  repositoryRoot,
  "Reference",
  "ScriptingCompatibility",
);
export const originalRoot = path.join(referenceRoot, "Original");
export const generatedRoot = path.join(referenceRoot, "Generated");

export const REQUIRED_SOURCE_FILES = [
  {
    source: "dts/scripting.d.ts",
    destination: "Original/Types/scripting.d.ts",
    category: "declaration",
    language: "typescript",
    role: "scripting-module",
  },
  {
    source: "dts/global.d.ts",
    destination: "Original/Types/global.d.ts",
    category: "declaration",
    language: "typescript",
    role: "ambient-globals",
  },
  {
    source: "dts/node.d.ts",
    destination: "Original/Types/node.d.ts",
    category: "declaration",
    language: "typescript",
    role: "node-compatibility",
  },
  {
    source: "dts/web-fetch.d.ts",
    destination: "Original/Types/web-fetch.d.ts",
    category: "declaration",
    language: "typescript",
    role: "web-fetch-compatibility",
  },
  {
    source: "dts/safari-ext.d.ts",
    destination: "Original/Types/safari-ext.d.ts",
    category: "declaration",
    language: "typescript",
    role: "safari-extension-compatibility",
  },
  {
    source: "tsconfig.json",
    destination: "Original/Compiler/tsconfig.json",
    category: "compiler",
    language: "json",
    role: "scripting-original-profile",
  },
  {
    source: "package.json",
    destination: "Original/Compiler/package.json",
    category: "compiler",
    language: "json",
    role: "package-metadata",
  },
  {
    source: "package-lock.json",
    destination: "Original/Compiler/package-lock.json",
    category: "compiler",
    language: "json",
    role: "compiler-lockfile",
  },
];

const SOURCE_TREES = [
  {
    source: "docs",
    destination: "Original/Documentation",
    category: "documentation",
    role: "authorized-documentation",
  },
  {
    source: "scripts",
    destination: "Original/Examples",
    category: "example",
    role: "authorized-project-example",
  },
];

const EXCLUDED_DIRECTORY_NAMES = new Set([
  ".bin",
  ".cache",
  ".git",
  ".idea",
  ".next",
  ".swiftpm",
  ".vscode",
  "build",
  "coverage",
  "deriveddata",
  "dist",
  "node_modules",
  "temp",
  "tmp",
]);

const EXCLUDED_FILE_NAMES = new Set([
  ".DS_Store",
  "Thumbs.db",
]);

const EXCLUDED_EXTENSIONS = new Set([
  ".7z",
  ".bak",
  ".cmd",
  ".dll",
  ".dmg",
  ".exe",
  ".gz",
  ".key",
  ".log",
  ".mobileprovision",
  ".node",
  ".p12",
  ".pem",
  ".pfx",
  ".ps1",
  ".rar",
  ".tar",
  ".temp",
  ".tmp",
  ".zip",
]);

const STRONG_SECRET_PATTERNS = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\bAKIA[0-9A-Z]{16}\b/,
  /\bgh[pousr]_[A-Za-z0-9]{30,}\b/,
  /\bsk-[A-Za-z0-9_-]{32,}\b/,
];

function toPortablePath(value) {
  return value.split(path.sep).join("/");
}

function fromPortablePath(root, value) {
  return path.join(root, ...value.split("/"));
}

function comparePortablePaths(left, right) {
  return left.localeCompare(right, "en", {
    numeric: true,
    sensitivity: "variant",
  });
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function stableSortValue(value) {
  if (Array.isArray(value)) {
    return value.map(stableSortValue);
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort(comparePortablePaths)
        .map((key) => [key, stableSortValue(value[key])]),
    );
  }
  return value;
}

export function stableJSON(value) {
  return `${JSON.stringify(stableSortValue(value), null, 2)}\n`;
}

export function parseArguments(argv, { allowSource = false } = {}) {
  const result = {
    check: false,
    source: process.env.HANLIN_SCRIPTING_REFERENCE_ROOT ?? null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--check") {
      result.check = true;
    } else if (allowSource && argument === "--source") {
      const value = argv[index + 1];
      if (!value) {
        throw new Error("--source requires a path");
      }
      result.source = value;
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return result;
}

async function walkTree(
  root,
  { includeExcluded = false, relativePrefix = "" } = {},
) {
  const files = [];
  const directories = [];
  const excluded = [];

  async function visit(currentDirectory, currentRelative) {
    const entries = await readdir(currentDirectory, { withFileTypes: true });
    entries.sort((left, right) =>
      comparePortablePaths(left.name, right.name),
    );

    for (const entry of entries) {
      const absolutePath = path.join(currentDirectory, entry.name);
      const relativePath = currentRelative
        ? `${currentRelative}/${entry.name}`
        : entry.name;
      const portablePath = toPortablePath(relativePath);
      const info = await lstat(absolutePath);
      if (info.isSymbolicLink()) {
        excluded.push({
          path: portablePath,
          bytes: 0,
          reason: "symbolic-link",
        });
        continue;
      }
      if (entry.isDirectory()) {
        directories.push(portablePath);
        const excludedDirectory = EXCLUDED_DIRECTORY_NAMES.has(
          entry.name.toLowerCase(),
        );
        if (excludedDirectory && !includeExcluded) {
          const nested = await walkTree(absolutePath, {
            includeExcluded: true,
            relativePrefix: portablePath,
          });
          excluded.push(
            ...nested.files.map((file) => ({
              path: file.relativePath,
              bytes: file.bytes,
              reason: `excluded-directory:${entry.name}`,
            })),
          );
          excluded.push(...nested.excluded);
          continue;
        }
        await visit(absolutePath, portablePath);
        continue;
      }
      if (!entry.isFile()) {
        excluded.push({
          path: portablePath,
          bytes: info.size,
          reason: "unsupported-filesystem-entry",
        });
        continue;
      }
      files.push({
        absolutePath,
        relativePath: portablePath,
        bytes: info.size,
        modifiedAt: info.mtime.toISOString(),
      });
    }
  }

  await visit(root, relativePrefix);
  return { files, directories, excluded };
}

function classifyLanguage(relativePath) {
  const extension = path.posix.extname(relativePath).toLowerCase();
  if (extension === ".md") {
    const baseName = path.posix.basename(relativePath).toLowerCase();
    if (baseName === "en.md") return "en";
    if (baseName === "zh.md") return "zh";
    return "markdown";
  }
  if (extension === ".tsx") return "tsx";
  if (extension === ".ts") return "typescript";
  if (extension === ".json") return "json";
  return extension.slice(1) || "unknown";
}

function excludedFileReason(relativePath) {
  const baseName = path.posix.basename(relativePath);
  const lowerName = baseName.toLowerCase();
  if (EXCLUDED_FILE_NAMES.has(baseName)) return "editor-or-system-artifact";
  if (
    lowerName === ".env" ||
    lowerName.startsWith(".env.") ||
    lowerName.includes("credentials")
  ) {
    return "potential-secret";
  }
  const extension = path.posix.extname(lowerName);
  if (EXCLUDED_EXTENSIONS.has(extension)) {
    return `excluded-extension:${extension}`;
  }
  return null;
}

async function readApprovedFile(file, metadata) {
  const exclusionReason = excludedFileReason(file.relativePath);
  if (exclusionReason) {
    return { excluded: { ...file, reason: exclusionReason } };
  }
  const buffer = await readFile(file.absolutePath);
  const textCandidate = [
    ".md",
    ".ts",
    ".tsx",
    ".json",
    ".d.ts",
  ].some((extension) => file.relativePath.toLowerCase().endsWith(extension));
  if (
    textCandidate &&
    STRONG_SECRET_PATTERNS.some((pattern) => pattern.test(buffer.toString("utf8")))
  ) {
    return {
      excluded: { ...file, reason: "strong-secret-pattern" },
    };
  }
  return {
    imported: {
      sourceRelativePath: file.relativePath,
      destinationRelativePath: metadata.destination,
      category: metadata.category,
      language: metadata.language ?? classifyLanguage(file.relativePath),
      role: metadata.role,
      bytes: buffer.length,
      sha256: sha256(buffer),
      modifiedAt: file.modifiedAt,
      buffer,
    },
  };
}

async function collectSourceSummary(sourceRoot) {
  const allEntries = await walkTree(sourceRoot, { includeExcluded: true });
  return {
    fileCount: allEntries.files.length,
    directoryCount: allEntries.directories.length,
    bytes: allEntries.files.reduce((total, file) => total + file.bytes, 0),
    reparsePointCount: allEntries.excluded.filter(
      (entry) => entry.reason === "symbolic-link",
    ).length,
  };
}

async function discoverRequiredCandidates(sourceRoot) {
  const requiredNames = new Set(
    REQUIRED_SOURCE_FILES.map((entry) => path.posix.basename(entry.source)),
  );
  const tree = await walkTree(sourceRoot);
  const candidates = new Map(
    [...requiredNames].map((name) => [name, []]),
  );
  for (const file of tree.files) {
    const name = path.posix.basename(file.relativePath);
    if (!requiredNames.has(name)) continue;
    const buffer = await readFile(file.absolutePath);
    candidates.get(name).push({
      path: file.relativePath,
      bytes: buffer.length,
      sha256: sha256(buffer),
    });
  }
  return Object.fromEntries(
    [...candidates.entries()]
      .sort(([left], [right]) => comparePortablePaths(left, right))
      .map(([name, values]) => [
        name,
        values.sort((left, right) =>
          comparePortablePaths(left.path, right.path),
        ),
      ]),
  );
}

async function validateSourceMapping() {
  const mapping = JSON.parse(
    await readFile(path.join(scriptsDirectory, "source-map.json"), "utf8"),
  );
  if (
    mapping.schemaVersion !== 1 ||
    mapping.selectionPolicy !== "explicit-root-level-canonical-paths"
  ) {
    throw new Error("Unsupported or missing source mapping policy");
  }
  for (const required of REQUIRED_SOURCE_FILES) {
    const name = path.posix.basename(required.source);
    if (mapping.requiredFiles?.[name] !== required.source) {
      throw new Error(
        `source-map.json does not select ${required.source} for ${name}`,
      );
    }
  }
  const expectedTrees = Object.fromEntries(
    SOURCE_TREES.map((tree) => [
      tree.category === "documentation" ? "documentation" : "examples",
      tree.source,
    ]),
  );
  for (const [role, source] of Object.entries(expectedTrees)) {
    if (mapping.trees?.[role] !== source) {
      throw new Error(
        `source-map.json does not select ${source} for ${role}`,
      );
    }
  }
}

export async function createImportPlan(sourceRootArgument) {
  await validateSourceMapping();
  const sourceRoot = path.resolve(sourceRootArgument);
  const sourceInfo = await stat(sourceRoot);
  if (!sourceInfo.isDirectory()) {
    throw new Error(`Source is not a directory: ${sourceRoot}`);
  }

  const sourceSummary = await collectSourceSummary(sourceRoot);
  const requiredCandidates = await discoverRequiredCandidates(sourceRoot);
  const importedFiles = [];
  const excludedFiles = [];

  for (const required of REQUIRED_SOURCE_FILES) {
    const sourcePath = fromPortablePath(sourceRoot, required.source);
    const sourceFileInfo = await stat(sourcePath).catch(() => null);
    if (!sourceFileInfo?.isFile()) {
      throw new Error(`Required source file is missing: ${required.source}`);
    }
    const approved = await readApprovedFile(
      {
        absolutePath: sourcePath,
        relativePath: required.source,
        bytes: sourceFileInfo.size,
        modifiedAt: sourceFileInfo.mtime.toISOString(),
      },
      required,
    );
    if (approved.excluded) {
      throw new Error(
        `Required source file was excluded: ${required.source} (${approved.excluded.reason})`,
      );
    }
    importedFiles.push(approved.imported);
  }

  for (const treeMapping of SOURCE_TREES) {
    const treeRoot = fromPortablePath(sourceRoot, treeMapping.source);
    const treeInfo = await stat(treeRoot).catch(() => null);
    if (!treeInfo?.isDirectory()) {
      throw new Error(`Required source tree is missing: ${treeMapping.source}`);
    }
    const tree = await walkTree(treeRoot);
    excludedFiles.push(
      ...tree.excluded.map((entry) => ({
        ...entry,
        path: `${treeMapping.source}/${entry.path}`,
      })),
    );
    for (const file of tree.files) {
      const sourceRelativePath = `${treeMapping.source}/${file.relativePath}`;
      const destination = `${treeMapping.destination}/${file.relativePath}`;
      const approved = await readApprovedFile(
        { ...file, relativePath: sourceRelativePath },
        {
          destination,
          category: treeMapping.category,
          role: treeMapping.role,
        },
      );
      if (approved.excluded) {
        excludedFiles.push(approved.excluded);
      } else {
        importedFiles.push(approved.imported);
      }
    }
  }

  importedFiles.sort((left, right) =>
    comparePortablePaths(
      left.destinationRelativePath,
      right.destinationRelativePath,
    ),
  );
  excludedFiles.sort((left, right) =>
    comparePortablePaths(left.path, right.path),
  );

  const aggregateHash = createHash("sha256");
  for (const file of importedFiles) {
    aggregateHash.update(file.destinationRelativePath);
    aggregateHash.update("\0");
    aggregateHash.update(file.sha256);
    aggregateHash.update("\0");
    aggregateHash.update(String(file.bytes));
    aggregateHash.update("\n");
  }
  const aggregateSHA256 = aggregateHash.digest("hex");
  const newestSourceTimestamp = importedFiles
    .map((file) => file.modifiedAt)
    .sort()
    .at(-1);
  const baselineDate = newestSourceTimestamp.slice(0, 10);
  const baselineID = `scripting-compat-${baselineDate}-${aggregateSHA256.slice(0, 12)}`;

  const packageMetadata = JSON.parse(
    importedFiles
      .find((file) => file.destinationRelativePath.endsWith("/package.json"))
      .buffer.toString("utf8"),
  );
  const lockMetadata = JSON.parse(
    importedFiles
      .find((file) =>
        file.destinationRelativePath.endsWith("/package-lock.json"),
      )
      .buffer.toString("utf8"),
  );
  const scriptingDeclaration = importedFiles
    .find((file) =>
      file.destinationRelativePath.endsWith("/scripting.d.ts"),
    )
    .buffer.toString("utf8");
  const declarationHeaderVersion =
    scriptingDeclaration.match(/\bscripting\s+v([0-9.]+)/i)?.[1] ?? null;
  const typescriptPackageVersion =
    lockMetadata.packages?.["node_modules/typescript"]?.version ??
    packageMetadata.devDependencies?.typescript ??
    null;

  return {
    sourceRoot,
    sourceSummary,
    requiredCandidates,
    importedFiles,
    excludedFiles,
    aggregateSHA256,
    baselineID,
    generatedAt: newestSourceTimestamp,
    declarationHeaderVersion,
    typescriptPackageVersion,
  };
}

function countBy(items, keyProvider) {
  const counts = {};
  for (const item of items) {
    const key = keyProvider(item);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

function publicFileRecord(file) {
  return {
    path: file.destinationRelativePath,
    sourceRelativePath: file.sourceRelativePath,
    bytes: file.bytes,
    category: file.category,
    language: file.language,
    role: file.role,
    sha256: file.sha256,
  };
}

function markdownReport(plan) {
  const duplicateCandidates = Object.entries(plan.requiredCandidates)
    .filter(([, candidates]) => candidates.length > 1);
  const excludedByReason = countBy(plan.excludedFiles, (file) => file.reason);
  const declarationFiles = plan.importedFiles.filter(
    (file) => file.category === "declaration",
  );
  const documentationFiles = plan.importedFiles.filter(
    (file) => file.category === "documentation",
  );
  const exampleFiles = plan.importedFiles.filter(
    (file) => file.category === "example",
  );

  const lines = [
    "# Scripting Compatibility Import Report",
    "",
    `Baseline: \`${plan.baselineID}\``,
    "",
    "## Result",
    "",
    `- Aggregate SHA-256: \`${plan.aggregateSHA256}\``,
    `- Source files inspected: ${plan.sourceSummary.fileCount}`,
    `- Source directories inspected: ${plan.sourceSummary.directoryCount}`,
    `- Imported files: ${plan.importedFiles.length}`,
    `- Imported bytes: ${plan.importedFiles.reduce((sum, file) => sum + file.bytes, 0)}`,
    `- Declaration files: ${declarationFiles.length}`,
    `- Documentation files: ${documentationFiles.length}`,
    `- Project-example files: ${exampleFiles.length}`,
    `- Excluded files under approved roots: ${plan.excludedFiles.length}`,
    `- Reparse points discovered: ${plan.sourceSummary.reparsePointCount}`,
    "",
    "The canonical source mapping selects the root-level `dts/`, `docs/`,",
    "`scripts/`, `tsconfig.json`, `package.json`, and `package-lock.json`.",
    "The absolute import source is provenance only and is not a runtime dependency.",
    "",
    "## Required files",
    "",
    "| Source | Destination | Bytes | SHA-256 |",
    "| --- | --- | ---: | --- |",
    ...REQUIRED_SOURCE_FILES.map((required) => {
      const file = plan.importedFiles.find(
        (candidate) => candidate.sourceRelativePath === required.source,
      );
      return `| \`${required.source}\` | \`${required.destination}\` | ${file.bytes} | \`${file.sha256}\` |`;
    }),
    "",
    "## Duplicate required-file candidates",
    "",
  ];

  if (duplicateCandidates.length === 0) {
    lines.push("No duplicate required-file candidates were discovered.");
  } else {
    lines.push(
      "Duplicates were resolved by the explicit canonical root-level mapping.",
      "They were not imported as additional baselines.",
      "",
      "| Name | Candidate | Same as selected | SHA-256 |",
      "| --- | --- | --- | --- |",
    );
    for (const [name, candidates] of duplicateCandidates) {
      const selected = REQUIRED_SOURCE_FILES.find(
        (required) => path.posix.basename(required.source) === name,
      );
      const selectedCandidate = candidates.find(
        (candidate) => candidate.path === selected.source,
      );
      for (const candidate of candidates) {
        lines.push(
          `| \`${name}\` | \`${candidate.path}\` | ${candidate.sha256 === selectedCandidate?.sha256 ? "yes" : "no"} | \`${candidate.sha256}\` |`,
        );
      }
    }
  }

  lines.push("", "## Exclusions", "");
  const excludedReasons = Object.entries(excludedByReason).sort(([left], [right]) =>
    comparePortablePaths(left, right),
  );
  if (excludedReasons.length === 0) {
    lines.push("No files inside the approved roots required exclusion.");
  } else {
    lines.push("| Reason | Count |", "| --- | ---: |");
    for (const [reason, count] of excludedReasons) {
      lines.push(`| \`${reason}\` | ${count} |`);
    }
  }
  lines.push(
    "",
    "The source-wide inventory also found non-approved roots and backup artifacts.",
    "They are intentionally outside the canonical mapping. `node_modules`, `.bin`,",
    "platform executables, archives, caches, editor metadata, temporary files,",
    "and secret-bearing files are never copied.",
    "",
    "## Compiler provenance",
    "",
    `- Scripting declaration header: ${plan.declarationHeaderVersion ? `\`${plan.declarationHeaderVersion}\`` : "not present"}`,
    `- Authorized workspace TypeScript package: \`${plan.typescriptPackageVersion}\``,
    "- Hanlin embedded compiler version is recorded in `Generated/compiler-profile.json`.",
    "- Compiler drift is a declared compatibility lane; it is not hidden.",
    "",
    "## Determinism",
    "",
    "File order, JSON key order, hashes, aggregate identity, indexes, and this",
    "report are derived deterministically from the selected source bytes.",
    "`--check` performs no writes and fails when source or repository output drifts.",
    "",
  );
  return `${lines.join("\n")}\n`;
}

export async function createMetadataOutputs(plan) {
  const files = plan.importedFiles.map(publicFileRecord);
  const baseline = {
    schemaVersion: 1,
    baselineID: plan.baselineID,
    aggregateSHA256: plan.aggregateSHA256,
    sourceRootForImportRecord: plan.sourceRoot,
    sourceRootRole: "provenance-only",
    authorizedForDirectUse: true,
    declarationHeaderVersion: plan.declarationHeaderVersion,
    typescriptPackageVersion: plan.typescriptPackageVersion,
    fileCounts: {
      total: files.length,
      byCategory: countBy(files, (file) => file.category),
      byLanguage: countBy(files, (file) => file.language),
    },
    sourceObservations: {
      requiredCandidateCounts: Object.fromEntries(
        Object.entries(plan.requiredCandidates).map(([name, candidates]) => [
          name,
          candidates.length,
        ]),
      ),
      excludedUnderApprovedRoots: plan.excludedFiles.length,
      inspectedFiles: plan.sourceSummary.fileCount,
      inspectedDirectories: plan.sourceSummary.directoryCount,
      reparsePoints: plan.sourceSummary.reparsePointCount,
    },
    generationTimestampPolicy: "latest-imported-source-mtime",
    generatedAt: plan.generatedAt,
  };
  const sums = {
    schemaVersion: 1,
    algorithm: "SHA-256",
    aggregateSHA256: plan.aggregateSHA256,
    files,
  };
  return new Map([
    ["BASELINE.json", Buffer.from(stableJSON(baseline))],
    ["SHA256SUMS.json", Buffer.from(stableJSON(sums))],
    ["IMPORT_REPORT.md", Buffer.from(markdownReport(plan))],
  ]);
}

function extractTitle(text, relativePath) {
  const heading = text.match(/^#\s+(.+)$/m)?.[1]?.trim();
  return heading ?? path.posix.basename(relativePath, path.posix.extname(relativePath));
}

function normalizeSignature(value) {
  return value.replace(/\s+/g, " ").trim();
}

function extractDeclarationSymbols(file, text) {
  const symbols = [];
  const declarationPattern =
    /^\s*(?:export\s+)?(?:declare\s+)?(?:abstract\s+)?(class|interface|enum|namespace|type|function|const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)/;
  const lines = text.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const match = lines[index].match(declarationPattern);
    if (!match) continue;
    const signature = normalizeSignature(lines[index]);
    symbols.push({
      referenceSymbol: match[2],
      referenceCategory: match[1],
      declarationFile: file.destinationRelativePath.replace(
        /^Original\/Types\//,
        "",
      ),
      line: index + 1,
      referenceSignatureHash: sha256(Buffer.from(signature)),
      signature,
    });
  }
  return symbols;
}

function inferExampleEnvironment(relativePath) {
  const lower = relativePath.toLowerCase();
  if (lower.includes("widget")) return "widget";
  if (lower.includes("intent")) return "appIntentBridge";
  if (lower.includes("live_activity") || lower.includes("liveactivity")) {
    return "liveActivity";
  }
  if (lower.includes("assistant_tool")) return "assistantTool";
  if (lower.includes("keyboard")) return "keyboard";
  if (lower.includes("notification")) return "notificationUI";
  if (lower.includes("translation_ui")) return "translationUI";
  return "app";
}

async function readHanlinCompilerVersion() {
  const lockPath = path.join(repositoryRoot, "RuntimeDependencies.lock.json");
  const lock = JSON.parse(await readFile(lockPath, "utf8"));
  return lock.typescript?.version ?? null;
}

function markdownLinks(text) {
  const links = [];
  const pattern = /!?\[[^\]]*]\(([^)]+)\)/g;
  for (const match of text.matchAll(pattern)) {
    links.push(match[1].trim().replace(/^<|>$/g, ""));
  }
  return links;
}

function resolveDocumentationLink(documentPath, link) {
  const withoutTitle = link.split(/\s+["'][^"']*["']$/)[0];
  const target = withoutTitle.split("#")[0];
  if (!target || /^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith("//")) {
    return null;
  }
  const decoded = decodeURIComponent(target);
  return path.posix.normalize(
    path.posix.join(path.posix.dirname(documentPath), decoded),
  );
}

export async function createGeneratedOutputs(plan) {
  const hanlinCompilerVersion = await readHanlinCompilerVersion();
  const declarationFiles = plan.importedFiles.filter(
    (file) => file.category === "declaration",
  );
  const documentationFiles = plan.importedFiles.filter(
    (file) => file.category === "documentation",
  );
  const projectExampleFiles = plan.importedFiles.filter(
    (file) => file.category === "example",
  );

  const symbols = declarationFiles
    .flatMap((file) =>
      extractDeclarationSymbols(file, file.buffer.toString("utf8")),
    )
    .sort((left, right) =>
      comparePortablePaths(
        `${left.referenceSymbol}\0${left.declarationFile}\0${left.line}`,
        `${right.referenceSymbol}\0${right.declarationFile}\0${right.line}`,
      ),
    );

  const declarationGraph = {
    schemaVersion: 1,
    baselineID: plan.baselineID,
    parser: "hanlin-phase0-declaration-lexer-v1",
    files: declarationFiles.map((file) => ({
      path: file.destinationRelativePath,
      bytes: file.bytes,
      sha256: file.sha256,
      lineCount: file.buffer.toString("utf8").split(/\r?\n/).length,
      imports: [
        ...file.buffer
          .toString("utf8")
          .matchAll(/from\s+["']([^"']+)["']/g),
      ]
        .map((match) => match[1])
        .filter((value, index, values) => values.indexOf(value) === index)
        .sort(comparePortablePaths),
    })),
  };

  const documentationPaths = new Set(
    documentationFiles.map((file) =>
      file.destinationRelativePath.replace(/^Original\/Documentation\//, ""),
    ),
  );
  const brokenLinks = [];
  const rootRelativeLinkFallbacks = [];
  const documentationIndex = documentationFiles.map((file) => {
    const relativePath = file.destinationRelativePath.replace(
      /^Original\/Documentation\//,
      "",
    );
    const text = file.buffer.toString("utf8");
    const resolvedLinks = [];
    if (relativePath.toLowerCase().endsWith(".md")) {
      for (const link of markdownLinks(text)) {
        let resolved;
        try {
          resolved = resolveDocumentationLink(relativePath, link);
        } catch {
          brokenLinks.push({
            document: relativePath,
            link,
            reason: "invalid-percent-encoding",
          });
          continue;
        }
        if (resolved && !documentationPaths.has(resolved)) {
          const rootRelative = resolveDocumentationLink("", link);
          if (rootRelative && documentationPaths.has(rootRelative)) {
            rootRelativeLinkFallbacks.push({
              document: relativePath,
              link,
              resolved: rootRelative,
            });
            resolved = rootRelative;
          } else {
            brokenLinks.push({
              document: relativePath,
              link,
              resolved,
              reason: "missing-relative-and-documentation-root-target",
            });
          }
        }
        if (resolved) resolvedLinks.push(resolved);
      }
    }
    return {
      path: relativePath,
      title: extractTitle(text, relativePath),
      language: file.language,
      bytes: file.bytes,
      sha256: file.sha256,
      links: resolvedLinks.sort(comparePortablePaths),
    };
  });

  const fixtureFiles = [
    ...documentationFiles
      .filter((file) => /\.(ts|tsx)$/i.test(file.destinationRelativePath))
      .map((file) => ({ file, fixtureOrigin: "documentation" })),
    ...projectExampleFiles
      .filter((file) => /\.(ts|tsx)$/i.test(file.destinationRelativePath))
      .map((file) => ({ file, fixtureOrigin: "project" })),
  ];
  fixtureFiles.sort((left, right) =>
    comparePortablePaths(
      left.file.destinationRelativePath,
      right.file.destinationRelativePath,
    ),
  );
  const exampleIndex = fixtureFiles.map(({ file, fixtureOrigin }) => ({
    sourceRelativePath: file.sourceRelativePath,
    repositoryPath: file.destinationRelativePath,
    contentSHA256: file.sha256,
    fixtureOrigin,
    environment: inferExampleEnvironment(file.destinationRelativePath),
    expectedEntryPoint: path.posix.basename(file.destinationRelativePath),
    requiredDeclarations: ["scripting"],
    requiredCapabilities: [],
    requiredEntitlement: null,
    compilerLanes: [
      {
        id: "scripting-original",
        version: plan.typescriptPackageVersion,
        status: "notRun",
      },
      {
        id: "hanlin-embedded",
        version: hanlinCompilerVersion,
        status: "notRun",
      },
    ],
    stages: {
      located: "passed",
      parsed: "notRun",
      compiled: "notRun",
      bundleResolved: "notRun",
      launched: "notRun",
      rendered: "notRun",
      interactive: "notRun",
      nativeAPIComplete: "notRun",
      cleanupComplete: "notRun",
    },
    compatibilityStatus: "planned",
    exclusionReason: null,
  }));

  const symbolByNormalizedName = new Map();
  for (const symbol of symbols) {
    const key = symbol.referenceSymbol.toLowerCase();
    if (!symbolByNormalizedName.has(key)) symbolByNormalizedName.set(key, []);
    symbolByNormalizedName.get(key).push(symbol);
  }
  const symbolIndex = symbols.map((symbol) => {
    const normalizedSymbol = symbol.referenceSymbol
      .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
      .replace(/[-\s]+/g, "_")
      .toLowerCase();
    const documents = documentationIndex
      .filter((document) => {
        const folder = document.path.split("/").at(-2) ?? "";
        return (
          folder.replace(/[-\s]+/g, "_").toLowerCase() === normalizedSymbol ||
          document.title.toLowerCase() === symbol.referenceSymbol.toLowerCase()
        );
      })
      .map((document) => document.path)
      .sort(comparePortablePaths);
    return { ...symbol, documents };
  });

  const duplicateSymbols = [...symbolByNormalizedName.entries()]
    .filter(([, values]) => values.length > 1)
    .map(([symbol, values]) => ({
      normalizedSymbol: symbol,
      declarations: values.map((value) => ({
        file: value.declarationFile,
        line: value.line,
        category: value.referenceCategory,
      })),
    }));

  const compatibilityMatrix = symbolIndex.map((symbol) => ({
    referenceSymbol: symbol.referenceSymbol,
    referenceCategory: symbol.referenceCategory,
    referenceSignatureHash: symbol.referenceSignatureHash,
    declarationFile: symbol.declarationFile,
    declarationLine: symbol.line,
    declaredByScripting: true,
    hanlinSymbol: null,
    hanlinAPIVersion: null,
    implementedByHanlin: false,
    behaviorMatched: false,
    verifiedByFixture: false,
    status: "planned",
    behaviorDifferences: [],
    requiredCapability: null,
    requiredEntitlement: null,
    allowedOrigins: [],
    allowedContexts: [],
    tests: [],
    notes: "Phase 0 declaration obligation; runtime support is not claimed.",
  }));

  const diagnostics = {
    schemaVersion: 1,
    baselineID: plan.baselineID,
    generatedBy: "Hanlin Phase 0 inventory tooling",
    summary: {
      declarationFiles: declarationFiles.length,
      declarationSymbols: symbols.length,
      documentationFiles: documentationFiles.length,
      documentationMarkdownEnglish: documentationFiles.filter(
        (file) => file.language === "en",
      ).length,
      documentationMarkdownChinese: documentationFiles.filter(
        (file) => file.language === "zh",
      ).length,
      fixtures: exampleIndex.length,
      brokenDocumentationLinks: brokenLinks.length,
      documentationRootRelativeFallbacks: rootRelativeLinkFallbacks.length,
      duplicateSymbolNames: duplicateSymbols.length,
      ambiguousRequiredSourceNames: Object.values(
        plan.requiredCandidates,
      ).filter((values) => values.length > 1).length,
    },
    compilerVersionDifference: {
      scriptingOriginal: plan.typescriptPackageVersion,
      hanlinEmbedded: hanlinCompilerVersion,
      differs: plan.typescriptPackageVersion !== hanlinCompilerVersion,
      resolution: "tracked-as-separate-compatibility-lanes",
    },
    brokenDocumentationLinks: brokenLinks,
    documentationRootRelativeFallbacks: rootRelativeLinkFallbacks,
    duplicateSymbols,
    declarationDocumentationNotes: [
      "Phase 0 uses a deterministic declaration lexer, not the TypeScript language service.",
      "A missing document link does not imply a missing runtime implementation.",
      "Phase 6 replaces lexical indexing with compiler-backed symbol and signature analysis.",
    ],
  };

  const compilerProfile = {
    schemaVersion: 1,
    baselineID: plan.baselineID,
    profiles: [
      {
        id: "scripting-original",
        source: "Original/Compiler/tsconfig.json",
        immutable: true,
        declarations: declarationFiles.map((file) =>
          file.destinationRelativePath.replace(/^Original\//, ""),
        ),
        typescriptVersion: plan.typescriptPackageVersion,
        runtimePackagingStatus: "metadata-only-in-phase-0",
      },
      {
        id: "hanlin-embedded",
        source: "RuntimeDependencies.lock.json",
        immutable: false,
        typescriptVersion: hanlinCompilerVersion,
        runtimePackagingStatus: "existing-runtime-compiler",
      },
    ],
    driftPolicy: {
      hideDifferences: false,
      phase0Action: "record",
      phase6Action: "run-separate-conformance-lanes",
    },
  };

  const apiInventory = {
    schemaVersion: 1,
    baselineID: plan.baselineID,
    parser: "hanlin-phase0-declaration-lexer-v1",
    symbolCount: symbolIndex.length,
    symbols: symbolIndex.map((symbol) => ({
      name: symbol.referenceSymbol,
      category: symbol.referenceCategory,
      signatureHash: symbol.referenceSignatureHash,
      declarationFile: symbol.declarationFile,
      line: symbol.line,
    })),
  };

  return new Map([
    ["api-inventory.json", Buffer.from(stableJSON(apiInventory))],
    ["symbol-index.json", Buffer.from(stableJSON({
      schemaVersion: 1,
      baselineID: plan.baselineID,
      symbols: symbolIndex,
    }))],
    ["declaration-graph.json", Buffer.from(stableJSON(declarationGraph))],
    ["documentation-index.json", Buffer.from(stableJSON({
      schemaVersion: 1,
      baselineID: plan.baselineID,
      documents: documentationIndex,
    }))],
    ["example-index.json", Buffer.from(stableJSON({
      schemaVersion: 1,
      baselineID: plan.baselineID,
      examples: exampleIndex,
    }))],
    ["compiler-profile.json", Buffer.from(stableJSON(compilerProfile))],
    ["compatibility-matrix.json", Buffer.from(stableJSON({
      schemaVersion: 1,
      baselineID: plan.baselineID,
      records: compatibilityMatrix,
    }))],
    ["diagnostics.json", Buffer.from(stableJSON(diagnostics))],
  ]);
}

export async function writeIfChanged(destination, buffer) {
  const existing = await readFile(destination).catch(() => null);
  if (existing?.equals(buffer)) return false;
  await mkdir(path.dirname(destination), { recursive: true });
  await writeFile(destination, buffer);
  return true;
}

export async function compareExpectedFile(destination, expectedBuffer) {
  const existing = await readFile(destination).catch(() => null);
  if (!existing) return "missing";
  return existing.equals(expectedBuffer) ? null : "content-drift";
}

export async function listPortableFiles(root) {
  const info = await stat(root).catch(() => null);
  if (!info?.isDirectory()) return [];
  const tree = await walkTree(root);
  return tree.files.map((file) => file.relativePath).sort(comparePortablePaths);
}

export async function loadPlanFromRepository() {
  const baseline = JSON.parse(
    await readFile(path.join(referenceRoot, "BASELINE.json"), "utf8"),
  );
  const sums = JSON.parse(
    await readFile(path.join(referenceRoot, "SHA256SUMS.json"), "utf8"),
  );
  const importedFiles = [];
  for (const record of sums.files) {
    const buffer = await readFile(
      fromPortablePath(referenceRoot, record.path),
    );
    importedFiles.push({
      destinationRelativePath: record.path,
      sourceRelativePath: record.sourceRelativePath,
      category: record.category,
      language: record.language,
      role: record.role,
      bytes: record.bytes,
      sha256: record.sha256,
      modifiedAt: baseline.generatedAt,
      buffer,
    });
  }
  return {
    sourceRoot: baseline.sourceRootForImportRecord,
    sourceSummary: {
      fileCount: baseline.fileCounts.total,
      directoryCount: 0,
      bytes: importedFiles.reduce((sum, file) => sum + file.bytes, 0),
      reparsePointCount: 0,
    },
    requiredCandidates: Object.fromEntries(
      REQUIRED_SOURCE_FILES.map((required) => {
        const name = path.posix.basename(required.source);
        const count =
          baseline.sourceObservations?.requiredCandidateCounts?.[name] ?? 1;
        return [
          name,
          Array.from({ length: count }, (_, index) => ({
            path: index === 0 ? required.source : `recorded-alternative-${index}`,
          })),
        ];
      }),
    ),
    importedFiles,
    excludedFiles: [],
    aggregateSHA256: baseline.aggregateSHA256,
    baselineID: baseline.baselineID,
    generatedAt: baseline.generatedAt,
    declarationHeaderVersion: baseline.declarationHeaderVersion,
    typescriptPackageVersion: baseline.typescriptPackageVersion,
  };
}

export function computeAggregateFromRecords(records) {
  const aggregateHash = createHash("sha256");
  for (const file of [...records].sort((left, right) =>
    comparePortablePaths(left.path, right.path),
  )) {
    aggregateHash.update(file.path);
    aggregateHash.update("\0");
    aggregateHash.update(file.sha256);
    aggregateHash.update("\0");
    aggregateHash.update(String(file.bytes));
    aggregateHash.update("\n");
  }
  return aggregateHash.digest("hex");
}

export function hashBuffer(buffer) {
  return sha256(buffer);
}

export function portableJoin(root, relativePath) {
  return fromPortablePath(root, relativePath);
}
