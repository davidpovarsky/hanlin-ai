import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { commitInstall, installPackage } from '../package-installer.mjs';

const packages = [
  {
    name: '@modelcontextprotocol/server-sequential-thinking',
    version: '2026.7.4',
    operationID: '31111111-1111-4111-8111-111111111111',
    serverID: '32222222-2222-4222-8222-222222222222',
  },
  {
    name: '@modelcontextprotocol/server-memory',
    version: '2026.7.4',
    operationID: '41111111-1111-4111-8111-111111111111',
    serverID: '42222222-2222-4222-8222-222222222222',
  },
];

for (const fixture of packages) {
  test(`${fixture.name} installs with canonical relocatable paths`, { timeout: 180_000 }, async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-regression-'));
    try {
      const descriptor = await installPackage({
        root,
        operationID: fixture.operationID,
        serverID: fixture.serverID,
        source: { kind: 'npm', name: fixture.name, version: fixture.version },
        entryPointOverride: 'dist/index.js',
        arguments: [],
        signal: new AbortController().signal,
        emit: () => {},
      });
      const canonicalRoot = path.join(root, 'packages', 'mcp', fixture.serverID);
      assert.equal(descriptor.packageRoot, canonicalRoot);
      assert.equal(descriptor.entryPointRelativePath, 'dist/index.js');
      assert.equal(descriptor.entryPoint, path.join(canonicalRoot, 'dist', 'index.js'));
      assert.equal(descriptor.compatibility.runtimeProbePassed, true);
      assert.ok(descriptor.compatibility.runtimeProbeToolCount > 0);
      await fs.access(path.join(canonicalRoot, 'package.json'));
      await fs.access(descriptor.entryPoint);
      await commitInstall({
        root,
        operationID: fixture.operationID,
        serverID: fixture.serverID,
      });
      t.diagnostic(JSON.stringify({
        packageName: descriptor.packageName,
        version: descriptor.resolvedVersion,
        entryPointRelativePath: descriptor.entryPointRelativePath,
        toolCount: descriptor.compatibility.runtimeProbeToolCount,
      }));
    } finally {
      await fs.rm(root, { recursive: true, force: true });
    }
  });
}
