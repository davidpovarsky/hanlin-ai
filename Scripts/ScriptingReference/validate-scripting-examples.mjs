#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import {
  hashBuffer,
  portableJoin,
  referenceRoot,
} from "./scripting-reference-lib.mjs";

async function main() {
  const exampleIndex = JSON.parse(
    await readFile(
      path.join(referenceRoot, "Generated", "example-index.json"),
      "utf8",
    ),
  );
  const failures = [];
  const origins = {};
  const environments = {};
  for (const example of exampleIndex.examples) {
    origins[example.fixtureOrigin] = (origins[example.fixtureOrigin] ?? 0) + 1;
    environments[example.environment] =
      (environments[example.environment] ?? 0) + 1;
    const buffer = await readFile(
      portableJoin(referenceRoot, example.repositoryPath),
    ).catch(() => null);
    if (!buffer) {
      failures.push(`${example.repositoryPath}: missing`);
      continue;
    }
    if (hashBuffer(buffer) !== example.contentSHA256) {
      failures.push(`${example.repositoryPath}: content hash mismatch`);
    }
    if (example.stages?.located !== "passed") {
      failures.push(`${example.repositoryPath}: located stage is not passed`);
    }
    const laterStages = Object.entries(example.stages).filter(
      ([name]) => name !== "located",
    );
    if (laterStages.some(([, status]) => status !== "notRun")) {
      failures.push(
        `${example.repositoryPath}: Phase 0 must not claim unexecuted fixture stages`,
      );
    }
  }
  if (failures.length > 0) {
    throw new Error(`Example index validation failed:\n${failures.join("\n")}`);
  }
  console.log(`Indexed fixtures: ${exampleIndex.examples.length}`);
  console.log(`Fixture origins: ${JSON.stringify(origins)}`);
  console.log(`Execution contexts: ${JSON.stringify(environments)}`);
  console.log(
    "Compilation, launch, rendering, interaction, native API, and cleanup stages remain truthfully notRun until their gated implementations exist.",
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
