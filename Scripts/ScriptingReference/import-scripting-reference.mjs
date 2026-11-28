#!/usr/bin/env node

import { mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import {
  compareExpectedFile,
  createGeneratedOutputs,
  createImportPlan,
  createMetadataOutputs,
  generatedRoot,
  listPortableFiles,
  parseArguments,
  portableJoin,
  referenceRoot,
  writeIfChanged,
} from "./scripting-reference-lib.mjs";

function fail(message) {
  console.error(`Scripting reference import failed: ${message}`);
  process.exitCode = 1;
}

async function compareOutputSet(root, expectedOutputs) {
  const drift = [];
  for (const [relativePath, expectedBuffer] of expectedOutputs) {
    const destination = path.join(root, ...relativePath.split("/"));
    const reason = await compareExpectedFile(destination, expectedBuffer);
    if (reason) drift.push({ path: relativePath, reason });
  }
  const expectedPaths = new Set(expectedOutputs.keys());
  const existingPaths = await listPortableFiles(root);
  for (const existingPath of existingPaths) {
    if (!expectedPaths.has(existingPath)) {
      drift.push({ path: existingPath, reason: "unexpected-file" });
    }
  }
  return drift;
}

async function main() {
  const argumentsValue = parseArguments(process.argv.slice(2), {
    allowSource: true,
  });
  if (!argumentsValue.source) {
    throw new Error(
      "Provide --source <path> or set HANLIN_SCRIPTING_REFERENCE_ROOT",
    );
  }

  const plan = await createImportPlan(argumentsValue.source);
  const metadataOutputs = await createMetadataOutputs(plan);
  const generatedOutputs = await createGeneratedOutputs(plan);
  const originalOutputs = new Map(
    plan.importedFiles.map((file) => [
      file.destinationRelativePath.replace(/^Original\//, ""),
      file.buffer,
    ]),
  );

  if (argumentsValue.check) {
    const drift = [
      ...(await compareOutputSet(
        path.join(referenceRoot, "Original"),
        originalOutputs,
      )).map((entry) => ({ ...entry, area: "Original" })),
      ...(await compareOutputSet(
        generatedRoot,
        generatedOutputs,
      )).map((entry) => ({ ...entry, area: "Generated" })),
    ];
    for (const [relativePath, expectedBuffer] of metadataOutputs) {
      const reason = await compareExpectedFile(
        path.join(referenceRoot, relativePath),
        expectedBuffer,
      );
      if (reason) {
        drift.push({ area: "Reference", path: relativePath, reason });
      }
    }
    if (drift.length > 0) {
      for (const entry of drift) {
        console.error(`${entry.area}/${entry.path}: ${entry.reason}`);
      }
      throw new Error(`${drift.length} drift item(s) detected`);
    }
    console.log(
      `Scripting reference ${plan.baselineID} matches source and generated output.`,
    );
    return;
  }

  const existingBaseline = await readFile(
    path.join(referenceRoot, "BASELINE.json"),
    "utf8",
  )
    .then(JSON.parse)
    .catch(() => null);
  if (
    existingBaseline &&
    existingBaseline.aggregateSHA256 !== plan.aggregateSHA256
  ) {
    throw new Error(
      "Authorized source bytes changed. Refusing to overwrite the existing baseline identity; use the explicit baseline-update workflow introduced in Phase 14.",
    );
  }

  await mkdir(referenceRoot, { recursive: true });
  let changed = 0;
  for (const file of plan.importedFiles) {
    const destination = portableJoin(referenceRoot, file.destinationRelativePath);
    if (await writeIfChanged(destination, file.buffer)) changed += 1;
  }
  for (const [relativePath, buffer] of metadataOutputs) {
    if (await writeIfChanged(path.join(referenceRoot, relativePath), buffer)) {
      changed += 1;
    }
  }
  for (const [relativePath, buffer] of generatedOutputs) {
    if (await writeIfChanged(path.join(generatedRoot, relativePath), buffer)) {
      changed += 1;
    }
  }

  const postWriteDrift = [
    ...(await compareOutputSet(
      path.join(referenceRoot, "Original"),
      originalOutputs,
    )).map((entry) => ({ ...entry, area: "Original" })),
    ...(await compareOutputSet(
      generatedRoot,
      generatedOutputs,
    )).map((entry) => ({ ...entry, area: "Generated" })),
  ];
  if (postWriteDrift.length > 0) {
    throw new Error(
      `Import output contains stale or unexpected files:\n${postWriteDrift
        .map((entry) => `${entry.area}/${entry.path}: ${entry.reason}`)
        .join("\n")}`,
    );
  }

  console.log(`Imported baseline: ${plan.baselineID}`);
  console.log(`Aggregate SHA-256: ${plan.aggregateSHA256}`);
  console.log(`Imported files: ${plan.importedFiles.length}`);
  console.log(`Files written or updated: ${changed}`);
  console.log(
    `Excluded files under approved roots: ${plan.excludedFiles.length}`,
  );
}

main().catch((error) => fail(error instanceof Error ? error.message : String(error)));
