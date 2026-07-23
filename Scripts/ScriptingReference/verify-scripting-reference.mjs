#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import {
  computeAggregateFromRecords,
  hashBuffer,
  listPortableFiles,
  portableJoin,
  referenceRoot,
} from "./scripting-reference-lib.mjs";

const PROHIBITED_COMPONENTS = new Set([
  ".bin",
  ".cache",
  ".git",
  ".idea",
  ".vscode",
  "build",
  "coverage",
  "deriveddata",
  "dist",
  "node_modules",
  "temp",
  "tmp",
]);
const PROHIBITED_EXTENSIONS = new Set([
  ".cmd",
  ".dll",
  ".exe",
  ".node",
  ".ps1",
  ".zip",
]);

async function main() {
  const baseline = JSON.parse(
    await readFile(path.join(referenceRoot, "BASELINE.json"), "utf8"),
  );
  const sums = JSON.parse(
    await readFile(path.join(referenceRoot, "SHA256SUMS.json"), "utf8"),
  );
  if (baseline.schemaVersion !== 1 || sums.schemaVersion !== 1) {
    throw new Error("Unsupported baseline or checksum schema");
  }
  if (!baseline.authorizedForDirectUse) {
    throw new Error("Baseline direct-use authorization is not recorded");
  }
  if (baseline.sourceRootRole !== "provenance-only") {
    throw new Error("Source root must be marked provenance-only");
  }
  if (baseline.aggregateSHA256 !== sums.aggregateSHA256) {
    throw new Error("BASELINE.json and SHA256SUMS.json aggregate hashes differ");
  }

  const failures = [];
  for (const record of sums.files) {
    if (!record.path.startsWith("Original/")) {
      failures.push(`${record.path}: checksum record is outside Original`);
      continue;
    }
    const components = record.path.toLowerCase().split("/");
    if (components.some((component) => PROHIBITED_COMPONENTS.has(component))) {
      failures.push(`${record.path}: prohibited path component`);
    }
    if (PROHIBITED_EXTENSIONS.has(path.posix.extname(record.path).toLowerCase())) {
      failures.push(`${record.path}: prohibited extension`);
    }
    const buffer = await readFile(portableJoin(referenceRoot, record.path)).catch(
      () => null,
    );
    if (!buffer) {
      failures.push(`${record.path}: missing`);
      continue;
    }
    if (buffer.length !== record.bytes) {
      failures.push(`${record.path}: byte length mismatch`);
    }
    const actualHash = hashBuffer(buffer);
    if (actualHash !== record.sha256) {
      failures.push(`${record.path}: SHA-256 mismatch`);
    }
  }

  const expectedOriginalPaths = new Set(
    sums.files.map((record) => record.path.replace(/^Original\//, "")),
  );
  for (const actualPath of await listPortableFiles(
    path.join(referenceRoot, "Original"),
  )) {
    if (!expectedOriginalPaths.has(actualPath)) {
      failures.push(`Original/${actualPath}: untracked baseline file`);
    }
  }

  const computedAggregate = computeAggregateFromRecords(sums.files);
  if (computedAggregate !== sums.aggregateSHA256) {
    failures.push("Aggregate SHA-256 does not match file records");
  }
  if (!baseline.baselineID.endsWith(sums.aggregateSHA256.slice(0, 12))) {
    failures.push("Baseline ID does not contain the aggregate hash prefix");
  }
  if (baseline.fileCounts?.total !== sums.files.length) {
    failures.push("Baseline file count does not match checksum records");
  }

  const generatedNames = [
    "api-inventory.json",
    "symbol-index.json",
    "declaration-graph.json",
    "documentation-index.json",
    "example-index.json",
    "compiler-profile.json",
    "compatibility-matrix.json",
    "diagnostics.json",
  ];
  for (const name of generatedNames) {
    const value = JSON.parse(
      await readFile(path.join(referenceRoot, "Generated", name), "utf8"),
    );
    if (value.baselineID !== baseline.baselineID) {
      failures.push(`Generated/${name}: baseline ID mismatch`);
    }
  }

  if (failures.length > 0) {
    throw new Error(
      `Scripting reference verification failed:\n${failures.join("\n")}`,
    );
  }
  console.log(`Verified baseline: ${baseline.baselineID}`);
  console.log(`Verified files: ${sums.files.length}`);
  console.log(`Aggregate SHA-256: ${sums.aggregateSHA256}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
