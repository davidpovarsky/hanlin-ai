#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import process from 'node:process';

const lockPath = process.argv[2] ?? 'RuntimeDependencies.lock.json';
const packagePath = process.argv[3] ?? 'Packages/IOSSystemLite/Package.swift';
const lock = JSON.parse(await readFile(lockPath, 'utf8'));
const swiftPackage = await readFile(packagePath, 'utf8');
const targetMatch = swiftPackage.match(
  /\.target\s*\(\s*name:\s*"IOSSystemLite"\s*,\s*dependencies:\s*\[([\s\S]*?)\]\s*,\s*resources:/,
);

assert(targetMatch, 'IOSSystemLite target dependency list was not found');
const targetDependencies = [...targetMatch[1].matchAll(/"([^"]+)"/g)].map(match => match[1]);
assert(new Set(targetDependencies).size === targetDependencies.length, 'IOSSystemLite target dependencies must be unique');

const binaryTargets = new Map();
for (const match of swiftPackage.matchAll(
  /\.binaryTarget\s*\(\s*name:\s*"([^"]+)"\s*,\s*url:\s*"([^"]+)"\s*,\s*checksum:\s*"([a-f0-9]{64})"\s*\)/g,
)) {
  const [, name, url, checksum] = match;
  assert(!binaryTargets.has(name), `Duplicate binary target declaration: ${name}`);
  binaryTargets.set(name, { url, checksum });
}

const lockedDependencies = [
  ...(lock.iosSystem?.components ?? []),
  ...(lock.iosSystem?.linkDependencies ?? []),
];
assert(lockedDependencies.length > 0, 'No iosSystem dependencies were found in the runtime lock');

for (const dependency of lockedDependencies) {
  const target = binaryTargets.get(dependency.name);
  assert(target, `IOSSystemLite is missing binary target ${dependency.name}`);
  assert(target.url === dependency.url, `IOSSystemLite URL does not match the lock for ${dependency.name}`);
  assert(target.checksum === dependency.sha256, `IOSSystemLite checksum does not match the lock for ${dependency.name}`);
  assert(targetDependencies.includes(dependency.name), `IOSSystemLite target does not depend on ${dependency.name}`);
}

for (const requiredName of ['libssh2', 'openssl']) {
  assert(binaryTargets.has(requiredName), `IOSSystemLite must declare ${requiredName}`);
  assert(targetDependencies.includes(requiredName), `IOSSystemLite target must depend on ${requiredName}`);
}

process.stdout.write(`Validated ${lockedDependencies.length} IOSSystemLite binary targets and complete curl_ios link closure.\n`);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
