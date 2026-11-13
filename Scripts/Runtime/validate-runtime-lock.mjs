#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import process from 'node:process';
import { createHash } from 'node:crypto';

const lockPath = process.argv[2] ?? 'RuntimeDependencies.lock.json';
const allowPending = process.argv.includes('--allow-pending-build');
const lock = JSON.parse(await readFile(lockPath, 'utf8'));
const sha256 = /^[a-f0-9]{64}$/;
const sha40 = /^[a-f0-9]{40}$/;

assert(lock.schemaVersion === 1, 'schemaVersion must be 1');
assert(lock.runtimeBundle?.formatVersion === 1, 'runtimeBundle.formatVersion must be 1');
if (lock.runtimeBundle.artifactDependencyHash !== undefined) {
  assert(sha256.test(lock.runtimeBundle.artifactDependencyHash), 'runtimeBundle.artifactDependencyHash must be SHA-256');
  assert(sha256.test(lock.runtimeBundle.nativeInputSHA256 ?? ''), 'runtimeBundle.nativeInputSHA256 is required for artifact reuse');
  assert(sha40.test(lock.runtimeBundle.sourceCommit ?? ''), 'runtimeBundle.sourceCommit is required for artifact reuse');
}

assertRepository(lock.node?.sourceRepository, 'node.sourceRepository');
assert(sha40.test(lock.node?.commit ?? ''), 'node.commit must be a lowercase 40-character SHA');
assert(/^24\.\d+\.\d+$/.test(lock.node?.version ?? ''), 'node.version must be Node 24');
assert(Array.isArray(lock.node?.exportedSymbols), 'node.exportedSymbols must be an array');
assert(lock.node.exportedSymbols.length === 1 && lock.node.exportedSymbols[0] === '_node_start', 'node.exportedSymbols must contain only _node_start');
assertUrlAndHash(lock.node?.sourceArchive, 'node.sourceArchive');
if (lock.node.buildConfiguration) {
  const config = lock.node.buildConfiguration;
  assert(config.wasmInterpreter === 'drumbrake' && config.jitless === true && config.explicitBoundsChecks === true, 'Node interpreter build must retain JITless execution and explicit bounds checks');
  assert(config.pointerCompression === true && config.pointerCompressionSharedCage === true && config.taggedHeapAddressSpaceBytes === 4294967296, 'The pinned DrumBrake build requires the actual compressed-pointer shared-cage representation');
  assert(config.adapter?.path === 'Scripts/Runtime/configure-node-wasm.py', 'Invalid downstream Node build adapter path');
  const adapter = await readFile(new URL(`../../${config.adapter.path}`, import.meta.url), 'utf8');
  assert(createHash('sha256').update(adapter.replaceAll('\r\n', '\n')).digest('hex') === config.adapter.sha256, 'Node build adapter checksum mismatch');
}
for (const patch of lock.node.sourcePatches ?? []) {
  assert(/^Scripts\/Runtime\/Patches\/[A-Za-z0-9._-]+\.json$/.test(patch.path ?? ''), 'Invalid Node source patch path');
  assert(sha256.test(patch.sha256 ?? ''), 'Invalid Node source patch SHA-256');
  assert(sha40.test(patch.upstreamCommit ?? ''), 'Invalid Node source patch upstream commit');
  const bytes = await readFile(new URL(`../../${patch.path}`, import.meta.url));
  assert(createHash('sha256').update(bytes).digest('hex') === patch.sha256, 'Node source patch checksum mismatch');
  const manifest = JSON.parse(bytes);
  assert(manifest.sourceCommit === lock.node.commit, 'Node source patch requires a matching source commit');
  assert(manifest.upstreamCommit === patch.upstreamCommit, 'Node source patch upstream provenance mismatch');
  for (const original of [...(manifest.upstreamPatch ? [manifest.upstreamPatch] : []), ...(manifest.upstreamPatches ?? [])]) {
    assert(/^Scripts\/Runtime\/Patches\/[A-Za-z0-9._-]+\.patch$/.test(original.path ?? ''), 'Invalid original upstream patch path');
    assert(sha256.test(original.sha256 ?? ''), 'Invalid original upstream patch SHA-256');
    const evidence = await readFile(new URL(`../../${original.path}`, import.meta.url));
    assert(createHash('sha256').update(evidence).digest('hex') === original.sha256, 'Original upstream patch checksum mismatch');
  }
}

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
assert(Array.isArray(lock.iosSystem?.linkDependencies), 'iosSystem.linkDependencies must be an array');

const iosSystemNames = new Set();

for (const component of lock.iosSystem.components) {
  assertName(component.name, 'ios_system component');
  assert(!iosSystemNames.has(component.name), `Duplicate iosSystem dependency name: ${component.name}`);
  iosSystemNames.add(component.name);
  assertUrlAndHash(component, `iosSystem.components.${component.name}`);
  assert(Number.isSafeInteger(component.size) && component.size > 0, `iosSystem.components.${component.name}.size must be positive`);
}

const pinnedLinkDependencies = new Map([
  ['libssh2', {
    sourceRepository: 'https://github.com/holzschu/libssh2-apple',
    release: 'v1.11.0',
    url: 'https://github.com/holzschu/libssh2-apple/releases/download/v1.11.0/libssh2-dynamic.xcframework.zip',
    sha256: 'cacfe1789b197b727119f7e32f561eaf9acc27bf38cd19975b74fce107f868a6',
  }],
  ['openssl', {
    sourceRepository: 'https://github.com/holzschu/openssl-apple',
    release: 'v1.1.1w',
    url: 'https://github.com/holzschu/openssl-apple/releases/download/v1.1.1w/openssl-dynamic.xcframework.zip',
    sha256: '329e8317cf9bee8e138da5d032330a7a1bd2473cf44c9c083cb2f0636abb8b80',
  }],
]);

assert(lock.iosSystem.linkDependencies.length === pinnedLinkDependencies.size, 'iosSystem.linkDependencies must contain exactly libssh2 and openssl');
for (const dependency of lock.iosSystem.linkDependencies) {
  assertName(dependency.name, 'ios_system link dependency');
  assert(!iosSystemNames.has(dependency.name), `Duplicate iosSystem dependency name: ${dependency.name}`);
  iosSystemNames.add(dependency.name);
  assertUrlAndHash(dependency, `iosSystem.linkDependencies.${dependency.name}`);
  assert(Number.isSafeInteger(dependency.size) && dependency.size > 0, `iosSystem.linkDependencies.${dependency.name}.size must be positive`);
  assertRepository(dependency.sourceRepository, `iosSystem.linkDependencies.${dependency.name}.sourceRepository`);
  assertNonEmptyExactString(dependency.release, `iosSystem.linkDependencies.${dependency.name}.release`);
  assertNonEmptyExactString(dependency.license, `iosSystem.linkDependencies.${dependency.name}.license`);

  const expected = pinnedLinkDependencies.get(dependency.name);
  assert(expected, `Unknown iosSystem link dependency: ${dependency.name}`);
  for (const field of ['sourceRepository', 'release', 'url', 'sha256']) {
    assert(dependency[field] === expected[field], `iosSystem.linkDependencies.${dependency.name}.${field} does not match the pinned curl_ios closure`);
  }
}

for (const requiredName of pinnedLinkDependencies.keys()) {
  assert(iosSystemNames.has(requiredName), `iosSystem.linkDependencies must include ${requiredName}`);
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

function assertName(value, label) {
  assertNonEmptyExactString(value, `${label} name`);
}

function assertNonEmptyExactString(value, label) {
  assert(typeof value === 'string' && value.length > 0 && value === value.trim(), `${label} must be an exact non-empty string`);
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
