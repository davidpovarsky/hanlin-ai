#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import {
  compareExpectedFile,
  computeAggregateFromRecords,
  createGeneratedOutputs,
  createMetadataOutputs,
  generatedRoot,
  hashBuffer,
  loadPlanFromRepository,
  portableJoin,
  referenceRoot,
  stableJSON,
  writeIfChanged,
} from "./scripting-reference-lib.mjs";

const DECLARATIONS = [
  "global.d.ts",
  "node.d.ts",
  "safari-ext.d.ts",
  "scripting.d.ts",
  "web-fetch.d.ts",
];

function parseArguments(argumentsValue) {
  const result = { source: null, exportedAt: null, check: false };
  for (let index = 0; index < argumentsValue.length; index += 1) {
    const argument = argumentsValue[index];
    if (argument === "--check") {
      result.check = true;
      continue;
    }
    if (argument === "--source" || argument === "--exported-at") {
      const value = argumentsValue[index + 1];
      if (!value) throw new Error(`${argument} requires a value`);
      result[argument === "--source" ? "source" : "exportedAt"] = value;
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${argument}`);
  }
  if (!result.source || !result.exportedAt) {
    throw new Error("Provide --source <directory> and --exported-at <ISO-8601 timestamp>");
  }
  if (Number.isNaN(Date.parse(result.exportedAt))) {
    throw new Error("--exported-at must be an ISO-8601 timestamp with an explicit offset");
  }
  return result;
}

const options = parseArguments(process.argv.slice(2));
const sourceRoot = path.resolve(options.source);
const sourceInfo = await stat(sourceRoot);
if (!sourceInfo.isDirectory()) throw new Error(`Not a directory: ${sourceRoot}`);

const plan = await loadPlanFromRepository();
const exportedAtUTC = new Date(options.exportedAt).toISOString();
const exportRecords = [];

for (const name of DECLARATIONS) {
  const sourcePath = path.join(sourceRoot, name);
  const sourceFileInfo = await stat(sourcePath);
  if (!sourceFileInfo.isFile() || sourceFileInfo.isSymbolicLink?.()) {
    throw new Error(`Declaration source must be a regular file: ${name}`);
  }
  const buffer = await readFile(sourcePath);
  const destinationRelativePath = `Original/Types/${name}`;
  const record = plan.importedFiles.find(
    candidate => candidate.destinationRelativePath === destinationRelativePath,
  );
  if (!record) throw new Error(`Baseline declaration record is missing: ${name}`);
  Object.assign(record, {
    buffer,
    bytes: buffer.length,
    sha256: hashBuffer(buffer),
    modifiedAt: exportedAtUTC,
  });
  exportRecords.push({ name, bytes: buffer.length, sha256: record.sha256 });
}

const aggregateRecords = plan.importedFiles.map(file => ({
  path: file.destinationRelativePath,
  bytes: file.bytes,
  sha256: file.sha256,
}));
plan.aggregateSHA256 = computeAggregateFromRecords(aggregateRecords);
plan.baselineID = `scripting-compat-${options.exportedAt.slice(0, 10)}-${plan.aggregateSHA256.slice(0, 12)}`;
plan.generatedAt = exportedAtUTC;
plan.declarationHeaderVersion = plan.importedFiles
  .find(file => file.destinationRelativePath.endsWith("/scripting.d.ts"))
  .buffer.toString("utf8")
  .match(/\bscripting\s+v([0-9.]+)/i)?.[1] ?? null;
plan.typeExport = {
  schemaVersion: 1,
  exportedAt: options.exportedAt,
  exportedAtUTC,
  sourceDirectoryForImportRecord: sourceRoot,
  sourceDirectoryRole: "read-only-provenance-only",
  declarationSet: exportRecords,
};

const metadataOutputs = await createMetadataOutputs(plan);
metadataOutputs.set(
  "CURRENT_TYPE_EXPORT.json",
  Buffer.from(stableJSON({
    ...plan.typeExport,
    baselineID: plan.baselineID,
    aggregateSHA256: plan.aggregateSHA256,
  })),
);
const generatedOutputs = await createGeneratedOutputs(plan);
const expected = new Map();
for (const name of DECLARATIONS) {
  const record = plan.importedFiles.find(
    candidate => candidate.destinationRelativePath === `Original/Types/${name}`,
  );
  expected.set(portableJoin(referenceRoot, record.destinationRelativePath), record.buffer);
}
for (const [relativePath, buffer] of metadataOutputs) {
  expected.set(path.join(referenceRoot, relativePath), buffer);
}
for (const [relativePath, buffer] of generatedOutputs) {
  expected.set(path.join(generatedRoot, relativePath), buffer);
}

if (options.check) {
  const drift = [];
  for (const [destination, buffer] of expected) {
    const reason = await compareExpectedFile(destination, buffer);
    if (reason) drift.push(`${path.relative(referenceRoot, destination)}: ${reason}`);
  }
  if (drift.length > 0) throw new Error(`Current Scripting type export drift:\n${drift.join("\n")}`);
  console.log(`Current Scripting declarations match ${plan.baselineID}.`);
} else {
  let changed = 0;
  for (const [destination, buffer] of expected) {
    if (await writeIfChanged(destination, buffer)) changed += 1;
  }
  console.log(`Updated Scripting declaration baseline: ${plan.baselineID}`);
  console.log(`Aggregate SHA-256: ${plan.aggregateSHA256}`);
  console.log(`Files written or updated: ${changed}`);
}
