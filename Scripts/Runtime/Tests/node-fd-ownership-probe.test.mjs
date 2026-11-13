import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { probeDescriptorOwnership } from './node-fd-ownership-probe.mjs';

test('one tracked Worker owns 128 real UTF-8 descriptor read/close cycles', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'hanlin-fd-'));
  try {
    const file = path.join(root, 'probe.txt');
    await writeFile(file, 'שלום');
    const report = await probeDescriptorOwnership(file, 'שלום');
    assert.deepEqual(report, { answer: 42, cycles: 128, fdWarningCount: 0, fdWarnings: [] });
    await assert.rejects(probeDescriptorOwnership(file, 'wrong'), /Descriptor read mismatch/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
