#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const manifest = JSON.parse(await fs.readFile(path.join(
  root,
  "Reference/ScriptingCompatibility/Acceptance/acceptance-packages.json",
), "utf8"));
const argumentsValue = process.argv.slice(2);
const directoryIndex = argumentsValue.indexOf("--directory");
if (directoryIndex >= 0 && !argumentsValue[directoryIndex + 1]) {
  throw new Error("--directory requires a path.");
}
const directory = directoryIndex >= 0 ? path.resolve(argumentsValue[directoryIndex + 1]) : null;
const allowMissing = argumentsValue.includes("--allow-missing");

if (manifest.schemaVersion !== 1 || manifest.packages.length !== 6) {
  throw new Error("Acceptance manifest must describe exactly six packages.");
}
const missing = [];
const verified = [];
for (const fixture of manifest.packages) {
  if (fixture.sha256 !== null && !/^[0-9a-f]{64}$/.test(fixture.sha256)) {
    throw new Error(`Invalid acceptance digest: ${fixture.fileName}`);
  }
  if (!directory) continue;
  const source = path.join(directory, fixture.fileName);
  const bytes = await fs.readFile(source).catch(() => null);
  if (!bytes) {
    missing.push(fixture.fileName);
    continue;
  }
  const digest = crypto.createHash("sha256").update(bytes).digest("hex");
  if (!fixture.sha256) throw new Error(`Attached package lacks an authorized digest: ${fixture.fileName}`);
  if (digest !== fixture.sha256) throw new Error(`Acceptance package bytes changed: ${fixture.fileName}`);
  verified.push(fixture.fileName);
}
console.log(`Acceptance inputs verified: ${verified.length}; missing: ${missing.length}`);
for (const name of missing) console.log(`MISSING ${name}`);
if (missing.length > 0 && !allowMissing) process.exitCode = 2;
