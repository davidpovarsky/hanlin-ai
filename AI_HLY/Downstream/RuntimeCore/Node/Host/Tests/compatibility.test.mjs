import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Arborist from '@npmcli/arborist';
import pacote from 'pacote';
import {
  analyzePackage,
  determineModuleKind,
  inspectArchiveSafety,
} from '../package-compatibility.mjs';
import { runMCPRuntimeProbe } from '../runtime-probe.mjs';
import { installPackage } from '../package-installer.mjs';

const fixtures = fileURLToPath(new URL('./Fixtures', import.meta.url));
const downstreamFixtures = fileURLToPath(
  new URL('./DownstreamFixtures/', import.meta.url),
);

test('unused client stdio and cross-spawn code do not reject the selected server path', async () => {
  const report = await analyzeFixture('false-positive-sdk');
  assert.notEqual(report.verdict, 'unsupported', JSON.stringify(report.findings));
  assert.equal(report.runtimeProbePassed, true);
  assert.ok(report.moduleEdges.some(edge => edge.resolvedPath === 'node_modules/fake-sdk/server/stdio.js'));
  assert.ok(!report.moduleEdges.some(edge => edge.resolvedPath?.includes('client/stdio.js')));
  assert.ok(!report.moduleEdges.some(edge => edge.resolvedPath?.includes('cross-spawn')));
  assert.equal(report.blockedAccesses.length, 0);
});

for (const [name, expectedParent] of [
  ['direct-blocked', 'server.mjs'],
  ['esm-import-only', 'server.mjs'],
  ['transitive-blocked', 'module-a.mjs'],
  ['commonjs-blocked', 'server.cjs'],
  ['dynamic-blocked', 'server.mjs'],
  ['get-builtin-blocked', 'server.mjs'],
]) {
  test(`${name} may import child_process without executing it`, async () => {
    const report = await analyzeFixture(name);
    assert.notEqual(report.verdict, 'unsupported', JSON.stringify(report));
    assert.equal(report.runtimeProbePassed, true);
    assert.equal(report.blockedAccesses.length, 0);
    assert.ok(report.moduleEdges.some(edge => edge.resolvedPath === 'node:child_process'));
    assert.ok(report.moduleEdges.some(edge => edge.parentPath === expectedParent));
  });
}

for (const [name, operation, expectedParent = 'server.mjs'] of [
  ['spawn-call', 'child_process.spawn'],
  ['exec-call', 'child_process.exec'],
  ['exec-file-call', 'child_process.execFile'],
  ['fork-call', 'child_process.fork'],
  ['spawn-sync-call', 'child_process.spawnSync'],
  ['exec-sync-call', 'child_process.execSync'],
  ['exec-file-sync-call', 'child_process.execFileSync'],
  ['child-process-bypass', 'ChildProcess.prototype.spawn'],
  ['fork-child-call', 'child_process._forkChild'],
  ['commonjs-spawn-call', 'child_process.spawn', 'server.cjs'],
  ['get-builtin-call', 'child_process.spawn'],
  ['transitive-call', 'child_process.spawn', 'module-a.mjs'],
]) {
  test(`${name} is rejected when subprocess execution is attempted`, async () => {
    const report = await analyzeFixture(name);
    assert.equal(report.verdict, 'unsupported', JSON.stringify(report));
    const access = report.blockedAccesses.find(
      item => item.code === 'reachable_external_executable',
    );
    assert.ok(access, JSON.stringify(report));
    assert.equal(access.operation, operation);
    assert.equal(access.parentPath, expectedParent);
    assert.ok(access.importChain.includes(expectedParent));
  });
}

for (const [name, expectedParent, code] of [
  ['cluster-blocked', 'server.mjs'],
  ['binding-blocked', 'server.mjs', 'reachable_external_executable'],
  ['process-wrap-blocked', 'server.mjs', 'reachable_external_executable'],
]) {
  test(`${name} is rejected by the Worker runtime policy`, async () => {
    const report = await analyzeFixture(name);
    assert.equal(report.verdict, 'unsupported');
    const access = report.blockedAccesses.find(
      item => item.code === (code ?? 'reachable_blocked_builtin'),
    );
    assert.ok(access, JSON.stringify(report));
    assert.equal(access.parentPath, expectedParent);
    assert.ok(access.importChain.includes(expectedParent));
  });
}

test('unreachable native build material is inventory, not an execution-path rejection', async () => {
  const report = await analyzeFixture('unreachable-native');
  assert.notEqual(report.verdict, 'unsupported', JSON.stringify(report.findings));
  assert.equal(report.runtimeProbePassed, true);
  assert.equal(report.blockedAccesses.length, 0);
  assert.ok(report.findings.some(item => item.code === 'unreachable_blocked_reference' && item.reachable === false));
});

test('bounded concurrent archive scanning preserves serial safety results', async () => {
  const root = path.join(fixtures, 'unreachable-native');
  const serial = await inspectArchiveSafety(root, { directoryConcurrency: 1 });
  const concurrent = await inspectArchiveSafety(root, { directoryConcurrency: 32 });
  assert.deepEqual(concurrent, serial);
});

test('only the selected reachable TypeScript entry is compiled by the Worker loader', async () => {
  const report = await analyzeFixture('typescript-selected');
  assert.notEqual(report.verdict, 'unsupported', JSON.stringify(report.findings));
  assert.equal(report.runtimeProbePassed, true);
  assert.ok(report.findings.some(item => item.code === 'compatible_after_typescript_compilation'));
});

test('a native addon actually resolved by the selected entry is rejected', async () => {
  const report = await analyzeFixture('reachable-native');
  assert.equal(report.verdict, 'unsupported');
  assert.ok(report.blockedAccesses.some(item => item.code === 'reachable_native_addon'));
});

test('archive safety rejects a symlink that escapes packageRoot', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-unsafe-link-'));
  const outside = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-outside-'));
  try {
    await fs.writeFile(path.join(root, 'package.json'), '{}');
    await fs.writeFile(path.join(outside, 'target.js'), 'export default 1;');
    try {
      await fs.symlink(path.join(outside, 'target.js'), path.join(root, 'escape.js'), 'file');
    } catch (error) {
      if (process.platform === 'win32' && error.code === 'EPERM') {
        t.skip('Windows Developer Mode is unavailable; the macOS CI fixture enforces symlink rejection.');
        return;
      }
      throw error;
    }
    const result = await inspectArchiveSafety(root);
    assert.ok(result.findings.some(item => item.code === 'archive_unsafe_symlink' && item.severity === 'unsupported'));
  } finally {
    await fs.rm(root, { recursive: true, force: true });
    await fs.rm(outside, { recursive: true, force: true });
  }
});

test('canonical parent aliases do not make a contained entry point appear to escape', async t => {
  const sandbox = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-canonical-root-'));
  const realParent = path.join(sandbox, 'real-parent');
  const aliasParent = path.join(sandbox, 'alias-parent');
  const realPackage = path.join(realParent, 'package');
  try {
    await fs.mkdir(realPackage, { recursive: true });
    await fs.cp(path.join(fixtures, 'false-positive-sdk'), realPackage, { recursive: true });
    try {
      await fs.symlink(realParent, aliasParent, process.platform === 'win32' ? 'junction' : 'dir');
    } catch (error) {
      if (process.platform === 'win32' && error.code === 'EPERM') {
        t.skip('Windows Developer Mode is unavailable; macOS CI exercises canonical parent aliases.');
        return;
      }
      throw error;
    }
    const packageRoot = path.join(aliasParent, 'package');
    const manifest = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
    const report = await analyzePackage(packageRoot, manifest, {
      entryPoint: path.join(packageRoot, 'server.mjs'),
      moduleKind: 'esm',
      runtimeProbe: () => runMCPRuntimeProbe({
        packageRoot,
        entryPoint: path.join(packageRoot, 'server.mjs'),
        moduleKind: 'esm',
        workspace: path.join(sandbox, 'workspace'),
      }),
    });
    assert.notEqual(report.verdict, 'unsupported', JSON.stringify(report.findings));
  } finally {
    await fs.rm(sandbox, { recursive: true, force: true });
  }
});

test('execution-path analysis requires an explicit selected entry point', async () => {
  const root = path.join(fixtures, 'false-positive-sdk');
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'));
  await assert.rejects(analyzePackage(root, manifest), /selected entry point/i);
});

test('the production installer rejects executed child_process and preserves the prior package', { timeout: 60_000 }, async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-negative-install-'));
  const cache = path.join(root, 'fixture-cache');
  const archive = path.join(root, 'spawn-call.tgz');
  const operationID = '11111111-1111-4111-8111-111111111111';
  const serverID = '22222222-2222-4222-8222-222222222222';
  const finalRoot = path.join(root, 'packages', 'mcp', serverID);
  try {
    const spawnFixture = await fixtureDirectory('spawn-call');
    await fs.mkdir(finalRoot, { recursive: true });
    await fs.writeFile(path.join(finalRoot, 'prior-version'), 'preserved');
    await fs.writeFile(archive, await pacote.tarball(`file:${spawnFixture}`, {
      Arborist,
      cache,
      ignoreScripts: true,
    }));
    await assert.rejects(installPackage({
      root,
      operationID,
      serverID,
      source: { kind: 'file', path: archive },
      signal: new AbortController().signal,
      emit: () => {},
    }), /child_process/);
    assert.equal(await fs.readFile(path.join(finalRoot, 'prior-version'), 'utf8'), 'preserved');
    await assert.rejects(fs.access(path.join(root, 'staging', operationID)), error => error.code === 'ENOENT');
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});

async function analyzeFixture(name) {
  const packageRoot = await fixtureDirectory(name);
  const manifest = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
  const entryPoint = path.resolve(packageRoot, manifest.main);
  const moduleKind = determineModuleKind(entryPoint, manifest);
  return analyzePackage(packageRoot, manifest, {
    entryPoint,
    moduleKind,
    runtimeProbe: () => runMCPRuntimeProbe({
      packageRoot,
      entryPoint,
      moduleKind,
      timeoutMilliseconds: 5_000,
    }),
  });
}

async function fixtureDirectory(name) {
  const local = path.join(fixtures, name);
  try {
    await fs.access(path.join(local, 'package.json'));
    return local;
  } catch {
    const downstream = path.join(downstreamFixtures, name);
    try {
      await fs.access(path.join(downstream, 'package.json'));
      return downstream;
    } catch {
      throw new Error(`Missing downstream MCP fixture: ${name}`);
    }
  }
}
