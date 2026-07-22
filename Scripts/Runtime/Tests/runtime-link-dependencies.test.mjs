#!/usr/bin/env node

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const runtimeDirectory = path.dirname(testDirectory);
const repositoryRoot = path.resolve(runtimeDirectory, '..', '..');
const lockPath = path.join(repositoryRoot, 'RuntimeDependencies.lock.json');
const packagePath = path.join(repositoryRoot, 'Packages', 'IOSSystemLite', 'Package.swift');
const manifestPath = path.join(repositoryRoot, 'AI_HLY', 'Downstream', 'RuntimeCore', 'Resources', 'RuntimeManifest.json');
const hashScript = path.join(runtimeDirectory, 'compute-runtime-dependency-hash.mjs');
const packageValidationScript = path.join(runtimeDirectory, 'validate-ios-system-package.mjs');
const expectedHash = '7d967563db0809a4efa0f07b75d6b5928379a3b6f3aafb886899a79f59512a93';

test('IOSSystemLite matches every locked component and application-link dependency', () => {
  const output = execFileSync(process.execPath, [packageValidationScript, lockPath, packagePath], { encoding: 'utf8' });
  assert.match(output, /8 IOSSystemLite binary targets/);
});

test('IOSSystemLite validation rejects missing target dependency membership', async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), 'ios-system-package-'));
  try {
    const mutatedPackage = (await readFile(packagePath, 'utf8')).replace('"libssh2", ', '');
    const temporaryPackage = path.join(temporaryDirectory, 'Package.swift');
    await writeFile(temporaryPackage, mutatedPackage);
    assert.throws(
      () => execFileSync(process.execPath, [packageValidationScript, lockPath, temporaryPackage], { encoding: 'utf8', stdio: 'pipe' }),
      /IOSSystemLite target does not depend on libssh2/,
    );
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test('runtime manifest distinguishes application-link dependencies from bundled components', async () => {
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  const iosSystem = manifest.runtimes.find(runtime => runtime.id === 'ios-system');
  assert.deepEqual(Object.keys(iosSystem.componentHashes).sort(), ['awk', 'curl_ios', 'files', 'ios_system', 'tar', 'text']);
  assert.deepEqual(Object.keys(iosSystem.linkDependencyHashes).sort(), ['libssh2', 'openssl']);
  assert.deepEqual(iosSystem.linkDependencies.map(dependency => dependency.name).sort(), ['libssh2', 'openssl']);
  assert.ok(iosSystem.linkDependencies.every(dependency => dependency.role === 'application-link-dependency'));
  assert.ok(iosSystem.linkDependencies.every(dependency => dependency.distribution === 'resolved-and-embedded-during-application-build'));
});

test('application-link metadata does not alter RuntimeCore bundle identity', async () => {
  const lock = JSON.parse(await readFile(lockPath, 'utf8'));
  assert.equal(computeHash(lockPath), expectedHash);

  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), 'runtime-hash-'));
  try {
    lock.iosSystem.linkDependencies[0].license += ' verified metadata change';
    lock.iosSystem.linkDependencies.push({ name: 'metadata-only' });
    const modifiedPath = path.join(temporaryDirectory, 'link-metadata.json');
    await writeFile(modifiedPath, JSON.stringify(lock));
    assert.equal(computeHash(modifiedPath), expectedHash);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test('Node and Python dependency changes still alter RuntimeCore bundle identity', async () => {
  const original = JSON.parse(await readFile(lockPath, 'utf8'));
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), 'runtime-hash-inputs-'));
  try {
    const nodeLock = structuredClone(original);
    nodeLock.node.version = '24.5.1';
    const nodePath = path.join(temporaryDirectory, 'node.json');
    await writeFile(nodePath, JSON.stringify(nodeLock));
    assert.notEqual(computeHash(nodePath), expectedHash);

    const pythonLock = structuredClone(original);
    pythonLock.python.version = '3.14.7';
    const pythonPath = path.join(temporaryDirectory, 'python.json');
    await writeFile(pythonPath, JSON.stringify(pythonLock));
    assert.notEqual(computeHash(pythonPath), expectedHash);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

function computeHash(candidatePath) {
  return execFileSync(process.execPath, [hashScript, candidatePath], { encoding: 'utf8' }).trim();
}
