#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import process from 'node:process';

const lockPath = process.argv[2] ?? 'RuntimeDependencies.lock.json';
const lock = JSON.parse(await readFile(lockPath, 'utf8'));

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

process.stdout.write(`${createHash('sha256').update(JSON.stringify(lock)).digest('hex')}\n`);
