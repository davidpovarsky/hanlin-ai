import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  commitInstall,
  installPackage,
} from '../../../../AI_HLY/Downstream/RuntimeCore/Node/Host/package-installer.mjs';

const packageName = '@cablate/mcp-google-map';
const packageVersion = '0.0.53';
const operationID = '11111111-1111-4111-8111-111111111111';
const serverID = '22222222-2222-4222-8222-222222222222';

test('pinned CabLate Google Maps MCP is judged by executed capabilities', { timeout: 180_000 }, async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-cablate-google-map-'));
  try {
    const descriptor = await installPackage({
      root,
      operationID,
      serverID,
      source: { kind: 'npm', name: packageName, version: packageVersion },
      arguments: ['--stdio'],
      signal: new AbortController().signal,
      emit: () => {},
    });
    assert.equal(descriptor.packageName, packageName);
    assert.equal(descriptor.resolvedVersion, packageVersion);
    assert.notEqual(
      descriptor.compatibility.verdict,
      'unsupported',
      JSON.stringify(descriptor.compatibility.findings),
    );
    assert.equal(descriptor.compatibility.blockedAccesses?.length ?? 0, 0);
    assert.ok(
      descriptor.compatibility.runtimeProbePassed
        || descriptor.compatibility.requiresConfiguration,
      JSON.stringify(descriptor.compatibility),
    );
    t.diagnostic(JSON.stringify({
      packageName,
      packageVersion,
      entryPoint: descriptor.compatibility.entryPoint,
      runtimeProbePassed: descriptor.compatibility.runtimeProbePassed,
      internalLoaderRetryCount: descriptor.compatibility.internalLoaderRetryCount,
      requiresConfiguration: descriptor.compatibility.requiresConfiguration,
      childProcessImported: descriptor.compatibility.moduleEdges?.some(
        edge => edge.resolvedPath === 'node:child_process',
      ) ?? false,
    }));
    await commitInstall({ root, operationID, serverID });
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});
