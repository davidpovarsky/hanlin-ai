#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, readFile, rm, stat } from "node:fs/promises";
import path from "node:path";
import {
  computeAggregateFromRecords,
  createGeneratedOutputs,
  createMetadataOutputs,
  generatedRoot,
  hashBuffer,
  listPortableFiles,
  loadPlanFromRepository,
  portableJoin,
  referenceRoot,
  stableJSON,
  writeIfChanged,
} from "./scripting-reference-lib.mjs";

function parseArguments(values) {
  const result = { source: null, archive: null, importedAt: null };
  for (let index = 0; index < values.length; index += 1) {
    const argument = values[index];
    const key = {
      "--source": "source",
      "--archive": "archive",
      "--imported-at": "importedAt",
    }[argument];
    if (!key || !values[index + 1]) throw new Error(`Unknown or incomplete argument: ${argument}`);
    result[key] = values[index + 1];
    index += 1;
  }
  if (!result.source || !result.archive || !result.importedAt) {
    throw new Error("Provide --source <directory> --archive <zip> --imported-at <ISO-8601 timestamp>");
  }
  if (Number.isNaN(Date.parse(result.importedAt))) {
    throw new Error("--imported-at must be an ISO-8601 timestamp");
  }
  return result;
}

function language(relativePath) {
  const name = path.posix.basename(relativePath).toLowerCase();
  const extension = path.posix.extname(name);
  if (name === "en.md") return "en";
  if (name === "zh.md") return "zh";
  if (extension === ".tsx") return "tsx";
  if (extension === ".ts") return "typescript";
  if (extension === ".json") return "json";
  return "markdown";
}

const options = parseArguments(process.argv.slice(2));
const sourceRoot = path.resolve(options.source);
const archivePath = path.resolve(options.archive);
if (!(await stat(sourceRoot)).isDirectory()) throw new Error(`Not a directory: ${sourceRoot}`);
if (!(await stat(archivePath)).isFile()) throw new Error(`Not a file: ${archivePath}`);

const files = await listPortableFiles(sourceRoot);
if (files.length === 0 || files.length > 5_000) throw new Error("Documentation file count is invalid");
const importedAtUTC = new Date(options.importedAt).toISOString();
const documentationRecords = [];
let totalBytes = 0;
for (const relativePath of files) {
  if (!/^[\x20-\x7E\u0080-\u{10FFFF}]+$/u.test(relativePath)) {
    throw new Error(`Documentation path contains control characters: ${relativePath}`);
  }
  const extension = path.posix.extname(relativePath).toLowerCase();
  if (![".md", ".tsx", ".ts", ".json"].includes(extension)) {
    throw new Error(`Unsupported documentation file type: ${relativePath}`);
  }
  const buffer = await readFile(portableJoin(sourceRoot, relativePath));
  if (buffer.length > 4 * 1_024 * 1_024) throw new Error(`Documentation file is too large: ${relativePath}`);
  totalBytes += buffer.length;
  if (totalBytes > 64 * 1_024 * 1_024) throw new Error("Documentation tree is too large");
  documentationRecords.push({
    destinationRelativePath: `Original/Documentation/${relativePath}`,
    sourceRelativePath: `docs/${relativePath}`,
    category: "documentation",
    language: language(relativePath),
    role: "authorized-documentation",
    bytes: buffer.length,
    sha256: hashBuffer(buffer),
    modifiedAt: importedAtUTC,
    buffer,
  });
}

const plan = await loadPlanFromRepository();
const currentDocumentationCount = plan.importedFiles.filter(file => file.category === "documentation").length;
const previousDocumentationCount =
  plan.documentationImport?.sourceArchiveForImportRecord === archivePath
    ? plan.documentationImport.previousDocumentationFileCount
    : currentDocumentationCount;
plan.importedFiles = [
  ...plan.importedFiles.filter(file => file.category !== "documentation"),
  ...documentationRecords,
].sort((left, right) => left.destinationRelativePath.localeCompare(right.destinationRelativePath, "en"));
plan.sourceSummary.fileCount = plan.importedFiles.length;
plan.sourceSummary.bytes = plan.importedFiles.reduce((sum, file) => sum + file.bytes, 0);
plan.aggregateSHA256 = computeAggregateFromRecords(plan.importedFiles.map(file => ({
  path: file.destinationRelativePath,
  bytes: file.bytes,
  sha256: file.sha256,
})));
plan.baselineID = `scripting-compat-${options.importedAt.slice(0, 10)}-${plan.aggregateSHA256.slice(0, 12)}`;
plan.generatedAt = importedAtUTC;
const archive = await readFile(archivePath);
plan.documentationImport = {
  schemaVersion: 1,
  importedAt: options.importedAt,
  importedAtUTC,
  sourceArchiveForImportRecord: archivePath,
  sourceArchiveRole: "read-only-provenance-only",
  sourceArchiveBytes: archive.length,
  sourceArchiveSHA256: createHash("sha256").update(archive).digest("hex"),
  previousDocumentationFileCount: previousDocumentationCount,
  documentationFileCount: documentationRecords.length,
  documentationBytes: totalBytes,
};

const metadataOutputs = await createMetadataOutputs(plan);
if (plan.typeExport) {
  metadataOutputs.set(
    "CURRENT_TYPE_EXPORT.json",
    Buffer.from(stableJSON({
      ...plan.typeExport,
      baselineID: plan.baselineID,
      aggregateSHA256: plan.aggregateSHA256,
    })),
  );
}
metadataOutputs.set(
  "CURRENT_DOCUMENTATION_IMPORT.json",
  Buffer.from(stableJSON({
    ...plan.documentationImport,
    baselineID: plan.baselineID,
    aggregateSHA256: plan.aggregateSHA256,
  })),
);
const generatedOutputs = await createGeneratedOutputs(plan);
const documentationRoot = path.resolve(referenceRoot, "Original", "Documentation");
const expectedDocumentationRoot = path.join(path.resolve(referenceRoot), "Original", "Documentation");
if (documentationRoot !== expectedDocumentationRoot) throw new Error("Documentation target validation failed");
await rm(documentationRoot, { recursive: true, force: true });
await mkdir(documentationRoot, { recursive: true });
for (const record of documentationRecords) {
  await writeIfChanged(portableJoin(referenceRoot, record.destinationRelativePath), record.buffer);
}
for (const [relativePath, buffer] of metadataOutputs) {
  await writeIfChanged(path.join(referenceRoot, relativePath), buffer);
}
for (const [relativePath, buffer] of generatedOutputs) {
  await writeIfChanged(path.join(generatedRoot, relativePath), buffer);
}

console.log(`Updated Scripting documentation baseline: ${plan.baselineID}`);
console.log(`Aggregate SHA-256: ${plan.aggregateSHA256}`);
console.log(`Documentation files: ${documentationRecords.length}`);
console.log(`Documentation bytes: ${totalBytes}`);
console.log(`Archive SHA-256: ${plan.documentationImport.sourceArchiveSHA256}`);
