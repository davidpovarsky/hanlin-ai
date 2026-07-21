#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import process from 'node:process';

const lockPath = process.argv[2] ?? 'RuntimeDependencies.lock.json';
const lock = JSON.parse(await readFile(lockPath, 'utf8'));

delete lock.runtimeBundle.sha256;
delete lock.runtimeBundle.verificationStatus;
delete lock.node.xcframeworkSha256;
delete lock.node.verificationStatus;

process.stdout.write(`${createHash('sha256').update(JSON.stringify(lock)).digest('hex')}\n`);
