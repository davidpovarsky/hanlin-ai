#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

export function runtimeDependencyHash(value) {
const lock = structuredClone(value);

delete lock.runtimeBundle.sha256;
delete lock.runtimeBundle.verificationStatus;
// Existing artifact provenance identifies its original bundle independently of
// current Host packages. These outputs must not feed their own input identity.
delete lock.runtimeBundle.artifactDependencyHash;
delete lock.runtimeBundle.nativeInputSHA256;
delete lock.runtimeBundle.sourceCommit;
delete lock.node.xcframeworkSha256;
delete lock.node.verificationStatus;
if (lock.iosSystem) {
  delete lock.iosSystem.linkDependencies;
}

return createHash('sha256').update(JSON.stringify(lock)).digest('hex');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const lock = JSON.parse(await readFile(process.argv[2] ?? 'RuntimeDependencies.lock.json', 'utf8'));
  process.stdout.write(`${runtimeDependencyHash(lock)}\n`);
}
