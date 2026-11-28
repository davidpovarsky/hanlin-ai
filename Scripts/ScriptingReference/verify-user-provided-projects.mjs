#!/usr/bin/env node

import crypto from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const acceptanceRoot = path.join(
  repositoryRoot,
  "Reference/ScriptingCompatibility/Acceptance/UserProvided",
);
const inventory = JSON.parse(await readFile(path.join(acceptanceRoot, "inventory.json"), "utf8"));
const results = JSON.parse(await readFile(
  path.join(acceptanceRoot, "compatibility-results.json"),
  "utf8",
));

if (inventory.schemaVersion !== 1 || inventory.projects.length !== 5) {
  throw new Error("The user-provided acceptance inventory must contain exactly five projects.");
}

const ids = new Set();
for (const project of inventory.projects) {
  if (!project.id || ids.has(project.id)) throw new Error(`Duplicate or empty project id: ${project.id}`);
  ids.add(project.id);
  if (!/^[0-9a-f]{64}$/.test(project.sha256)) throw new Error(`Invalid digest for ${project.id}`);
  const archivePath = path.resolve(acceptanceRoot, project.storedArchive);
  const archiveRoot = `${path.resolve(acceptanceRoot, "OriginalArchives")}${path.sep}`;
  if (!archivePath.startsWith(archiveRoot)) throw new Error(`Archive path escaped immutable storage: ${project.id}`);
  const bytes = await readFile(archivePath);
  const digest = crypto.createHash("sha256").update(bytes).digest("hex");
  if (digest !== project.sha256) throw new Error(`Original archive bytes changed: ${project.id}`);
  if (bytes.byteLength !== project.archiveBytes) throw new Error(`Original archive size changed: ${project.id}`);
}

const resultStages = [
  "typecheck",
  "compileBundle",
  "runtimeLaunch",
  "uiRender",
  "interaction",
  "nativeServices",
  "remainingBlockers",
];
if (results.schemaVersion !== 1 || results.projects.length !== inventory.projects.length) {
  throw new Error("Compatibility results must cover every inventoried project.");
}
const resultIDs = new Set();
for (const result of results.projects) {
  if (!ids.has(result.id) || resultIDs.has(result.id)) {
    throw new Error(`Unknown or duplicate compatibility result: ${result.id}`);
  }
  resultIDs.add(result.id);
  for (const stage of resultStages) {
    if (!(stage in result)) throw new Error(`Missing ${stage} result for ${result.id}`);
  }
}
if (resultIDs.size !== ids.size) throw new Error("Compatibility results do not cover the full inventory.");

console.log(
  `Verified ${inventory.projects.length} untouched user-provided Scripting archives and staged results.`,
);
