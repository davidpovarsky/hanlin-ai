#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import process from 'node:process';

const lockPath = process.argv[2] ?? 'RuntimeDependencies.lock.json';
const allowPending = process.argv.includes('--allow-pending-build');
const lock = JSON.parse(await readFile(lockPath, 'utf8'));
const sha256 = /^[a-f0-9]{64}$/;
const sha40 = /^[a-f0-9]{40}$/;

assert(lock.schemaVersion === 1, 'schemaVersion must be 1');
assert(lock.runtimeBundle?.formatVersion === 1, 'runtimeBundle.formatVersion must be 1');
assertRepository(lock.node?.sourceRepository, 'node.sourceRepository');
assert(sha40.test(lock.node?.commit ?? ''), 'node.commit must be a lowercase 40-character SHA');
assert(/^24\.\d+\.\d+$/.test(lock.node?.version ?? ''), 'node.version must be Node 24');
assertUrlAndHash(lock.node?.sourceArchive, 'node.sourceArchive');
assertRepository(lock.python?.sourceRepository, 'python.sourceRepository');
assert(sha40.test(lock.python?.commit ?? ''), 'python.commit must be a lowercase 40-character SHA');
assert(/^3\.14\.\d+$/.test(lock.python?.version ?? ''), 'python.version must be Python 3.14');
assertUrlAndHash(lock.python?.archive, 'python.archive');
assert(lock.typescript?.package === 'typescript', 'typescript.package must be typescript');
assertExactVersion(lock.typescript?.version, 'typescript.version');
assertIntegrity(lock.typescript?.integrity, 'typescript.integrity');
assertRepository(lock.iosSystem?.sourceRepository, 'iosSystem.sourceRepository');
assert(sha40.test(lock.iosSystem?.commit ?? ''), 'iosSystem.commit must be a lowercase 40-character SHA');
assert(Array.isArray(lock.iosSystem?.components) && lock.iosSystem.components.length > 0, 'iosSystem.components must not be empty');

for (const component of lock.iosSystem.components) {
  assert(typeof component.name === 'string' && component.name.length > 0, 'ios_system component name is required');
  assertUrlAndHash(component, `iosSystem.components.${component.name}`);
  assert(Number.isSafeInteger(component.size) && component.size > 0, `iosSystem.components.${component.name}.size must be positive`);
}

for (const [name, dependency] of Object.entries(lock.nodeHostPackages ?? {})) {
  assertExactVersion(dependency.version, `nodeHostPackages.${name}.version`);
  assertIntegrity(dependency.integrity, `nodeHostPackages.${name}.integrity`);
  assert(typeof dependency.license === 'string' && dependency.license.length > 0, `nodeHostPackages.${name}.license is required`);
}

const pending = lock.runtimeBundle?.verificationStatus !== 'verified'
  || lock.node?.verificationStatus !== 'verified'
  || !sha256.test(lock.runtimeBundle?.sha256 ?? '')
  || !sha256.test(lock.node?.xcframeworkSha256 ?? '');

if (pending && !allowPending) {
  throw new Error('Runtime binary verification is pending. Build and smoke-test the pinned Node XCFramework before finalizing the lock.');
}

process.stdout.write(`Validated ${lockPath}${pending ? ' (source pins only; binary verification pending)' : ''}.\n`);

function assertUrlAndHash(value, label) {
  assert(value && typeof value === 'object', `${label} is required`);
  const url = new URL(value.url);
  assert(url.protocol === 'https:', `${label}.url must use HTTPS`);
  assert(sha256.test(value.sha256 ?? ''), `${label}.sha256 must be a lowercase SHA-256`);
}

function assertRepository(value, label) {
  const url = new URL(value);
  assert(url.protocol === 'https:' && url.hostname === 'github.com', `${label} must be an HTTPS GitHub repository`);
}

function assertExactVersion(value, label) {
  assert(/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(value ?? ''), `${label} must be an exact version`);
}

function assertIntegrity(value, label) {
  assert(/^sha512-[A-Za-z0-9+/]+={0,2}$/.test(value ?? ''), `${label} must be an npm sha512 integrity value`);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
