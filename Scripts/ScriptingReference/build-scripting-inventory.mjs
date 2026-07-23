#!/usr/bin/env node

import path from "node:path";
import {
  compareExpectedFile,
  createGeneratedOutputs,
  generatedRoot,
  listPortableFiles,
  loadPlanFromRepository,
  parseArguments,
  writeIfChanged,
} from "./scripting-reference-lib.mjs";

async function main() {
  const argumentsValue = parseArguments(process.argv.slice(2));
  const plan = await loadPlanFromRepository();
  const outputs = await createGeneratedOutputs(plan);

  if (argumentsValue.check) {
    const drift = [];
    for (const [relativePath, expectedBuffer] of outputs) {
      const reason = await compareExpectedFile(
        path.join(generatedRoot, relativePath),
        expectedBuffer,
      );
      if (reason) drift.push(`${relativePath}: ${reason}`);
    }
    const expectedPaths = new Set(outputs.keys());
    for (const existingPath of await listPortableFiles(generatedRoot)) {
      if (!expectedPaths.has(existingPath)) {
        drift.push(`${existingPath}: unexpected-file`);
      }
    }
    if (drift.length > 0) {
      throw new Error(`Generated inventory drift:\n${drift.join("\n")}`);
    }
    console.log(`Generated inventories match ${plan.baselineID}.`);
    return;
  }

  let changed = 0;
  for (const [relativePath, buffer] of outputs) {
    if (await writeIfChanged(path.join(generatedRoot, relativePath), buffer)) {
      changed += 1;
    }
  }
  console.log(
    `Generated ${outputs.size} inventories for ${plan.baselineID}; ${changed} file(s) changed.`,
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
