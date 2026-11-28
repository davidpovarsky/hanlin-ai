#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const compilerRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(compilerRoot, "../..");
const packageRoot = join(repositoryRoot, "Packages/HanlinQuickJS");
const inventoryPath = join(packageRoot, "SHA256SUMS.json");
const inventory = JSON.parse(await readFile(inventoryPath, "utf8"));

if (inventory.schemaVersion !== 1) {
  throw new Error("QuickJS source inventory schemaVersion must be 1.");
}
if (inventory.upstream?.tag !== "v0.16.1"
    || inventory.upstream?.commit !== "954dc53628e36891f93c359aa60895c2ae3dac6b") {
  throw new Error("QuickJS source inventory does not match the authorized pin.");
}

for (const [relativePath, expected] of Object.entries(inventory.files ?? {})) {
  if (!/^[a-f0-9]{64}$/.test(expected)) {
    throw new Error(`Invalid SHA-256 for ${relativePath}.`);
  }
  const data = await readFile(join(packageRoot, relativePath));
  const actual = createHash("sha256").update(data).digest("hex");
  if (actual !== expected) {
    throw new Error(`QuickJS source integrity mismatch for ${relativePath}.`);
  }
}

process.stdout.write(
  `Verified ${Object.keys(inventory.files).length} QuickJS-NG v0.16.1 vendored files.\n`
);
