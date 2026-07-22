import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { commitInstall, installPackage } from '../package-installer.mjs';

const source = { kind: 'npm', name: '@modelcontextprotocol/server-everything', version: '2026.7.4' };
const operationID = '11111111-1111-4111-8111-111111111111';
const serverID = '22222222-2222-4222-8222-222222222222';

test('pinned server-everything follows only its stdio server execution path', { timeout: 180_000 }, async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-server-everything-'));
  try {
    const descriptor = await installPackage({
      root,
      operationID,
      serverID,
      source,
      entryPointOverride: 'dist/index.js',
      arguments: ['stdio'],
      signal: new AbortController().signal,
      emit: () => {},
    });
    const report = descriptor.compatibility;
    assert.notEqual(report.verdict, 'unsupported', JSON.stringify(report.findings));
    assert.equal(report.runtimeProbePassed, true);
    assert.ok(report.runtimeProbeToolCount > 0);
    assert.ok(report.moduleEdges.some(edge => edge.specifier === '@modelcontextprotocol/sdk/server/stdio.js'));
    assert.ok(!report.moduleEdges.some(edge => edge.specifier === '@modelcontextprotocol/sdk/client/stdio.js'));
    assert.ok(!report.moduleEdges.some(edge => edge.resolvedPath?.includes('cross-spawn')));
    assert.ok(!report.moduleEdges.some(edge => edge.resolvedPath === 'node:child_process'));
    assert.equal(report.blockedAccesses.length, 0);
    const persistedGraph = JSON.stringify(report.moduleEdges);
    assert.ok(!persistedGraph.includes(descriptor.packageRoot));
    assert.ok(!persistedGraph.includes('file://'));
    t.diagnostic(JSON.stringify({
      entryPoint: report.entryPoint,
      treeFileCount: report.treeFileCount,
      reachableModuleCount: report.reachableModuleCount,
      resolvedModuleCount: report.resolvedModuleCount,
      runtimeProbeDuration: report.runtimeProbeDuration,
      runtimeProbeToolCount: report.runtimeProbeToolCount,
      clientStdioLoaded: false,
      crossSpawnLoaded: false,
      childProcessResolved: false,
    }));

    const crossSpawn = path.join(descriptor.packageRoot, 'node_modules', 'cross-spawn', 'index.js');
    await fs.access(crossSpawn);
    await commitInstall({ root, operationID, serverID });
  } catch (error) {
    error.message = `Pinned npm integration failed independently of deterministic fixtures: ${error.message}`;
    throw error;
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});
