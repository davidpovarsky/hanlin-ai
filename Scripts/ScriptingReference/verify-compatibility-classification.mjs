#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const matrix = JSON.parse(await fs.readFile(
  path.join(root, "Reference/ScriptingCompatibility/Generated/compatibility-matrix.json"),
  "utf8",
));
const allowed = new Set(["implemented", "partial", "unsupported-by-platform", "not-yet-implemented"]);
const invalid = matrix.records.filter((record) => !allowed.has(record.status));
if (invalid.length > 0) {
  throw new Error(`Unclassified compatibility records: ${invalid.length}`);
}
for (const record of matrix.records) {
  if (record.status === "partial" && (
    !record.hanlinSymbol
    || record.tests.length === 0
    || record.behaviorDifferences.length === 0
  )) {
    throw new Error(`Incomplete partial classification: ${record.referenceSymbol}`);
  }
  if (record.status === "unsupported-by-platform" && !record.notes) {
    throw new Error(`Unsupported record lacks rationale: ${record.referenceSymbol}`);
  }
  for (const test of record.tests) {
    const info = await fs.stat(path.join(root, test)).catch(() => null);
    if (!info?.isFile()) throw new Error(`Compatibility evidence is missing: ${test}`);
  }
}
const counts = Object.fromEntries([...allowed].map((status) => [
  status,
  matrix.records.filter((record) => record.status === status).length,
]));
console.log(`Compatibility classification verified: ${JSON.stringify(counts)}`);
