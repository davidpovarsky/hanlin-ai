#!/usr/bin/env node

import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { repositoryRoot } from "./scripting-reference-lib.mjs";

const execFileAsync = promisify(execFile);
const manifestSchemaPath =
  "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/Resources/" +
  "HanlinAppManifest.schema.json";

function decodeJSONPointerComponent(component) {
  return component.replaceAll("~1", "/").replaceAll("~0", "~");
}

function resolveInternalReference(document, reference) {
  if (reference === "#") return document;
  if (!reference.startsWith("#/")) {
    throw new Error(`Unsupported non-internal JSON Schema reference: ${reference}`);
  }

  return reference
    .slice(2)
    .split("/")
    .map(decodeJSONPointerComponent)
    .reduce((value, component) => {
      if (
        value === null ||
        typeof value !== "object" ||
        !Object.hasOwn(value, component)
      ) {
        throw new Error(`Unresolved JSON Schema reference: ${reference}`);
      }
      return value[component];
    }, document);
}

function collectInternalReferences(value, references = []) {
  if (Array.isArray(value)) {
    for (const item of value) collectInternalReferences(item, references);
    return references;
  }
  if (value === null || typeof value !== "object") return references;

  for (const [key, child] of Object.entries(value)) {
    if (key === "$ref") {
      if (typeof child !== "string") {
        throw new Error("JSON Schema $ref values must be strings");
      }
      references.push(child);
    } else {
      collectInternalReferences(child, references);
    }
  }
  return references;
}

async function listVersionableJSONFiles() {
  const { stdout } = await execFileAsync(
    "git",
    [
      "ls-files",
      "-z",
      "--cached",
      "--others",
      "--exclude-standard",
      "--",
      "*.json",
    ],
    {
      cwd: repositoryRoot,
      encoding: "buffer",
      maxBuffer: 64 * 1024 * 1024,
    },
  );
  return stdout
    .toString("utf8")
    .split("\0")
    .filter(Boolean)
    .sort((left, right) => left.localeCompare(right, "en"));
}

async function main() {
  const jsonPaths = await listVersionableJSONFiles();
  const parsedDocuments = new Map();
  const failures = [];

  for (const relativePath of jsonPaths) {
    try {
      const contents = await readFile(
        path.join(repositoryRoot, ...relativePath.split("/")),
        "utf8",
      );
      parsedDocuments.set(relativePath, JSON.parse(contents));
    } catch (error) {
      failures.push(
        `${relativePath}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  const schema = parsedDocuments.get(manifestSchemaPath);
  if (!schema) {
    failures.push(`${manifestSchemaPath}: schema was not parsed`);
  } else {
    if (schema.$schema !== "https://json-schema.org/draft/2020-12/schema") {
      failures.push(`${manifestSchemaPath}: expected Draft 2020-12`);
    }
    if (
      schema.$defs === null ||
      typeof schema.$defs !== "object" ||
      Array.isArray(schema.$defs)
    ) {
      failures.push(`${manifestSchemaPath}: $defs must be an object`);
    }

    try {
      const references = collectInternalReferences(schema);
      for (const reference of references) {
        resolveInternalReference(schema, reference);
      }
      console.log(`Resolved internal JSON Schema references: ${references.length}`);
      console.log(
        `JSON Schema definitions: ${Object.keys(schema.$defs ?? {}).length}`,
      );
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    }
  }

  if (failures.length > 0) {
    throw new Error(`JSON validation failed:\n${failures.join("\n")}`);
  }

  console.log(`Validated versionable JSON files: ${jsonPaths.length}`);
  console.log(`Validated manifest schema: ${manifestSchemaPath}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
