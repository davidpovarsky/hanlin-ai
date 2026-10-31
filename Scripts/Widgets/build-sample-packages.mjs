import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { widgetSamples } from './samples.mjs';
import { deterministicZip } from './deterministic-zip.mjs';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const outputs = ['Fixtures/Widgets', 'AI_HLYUITests/Fixtures', 'AI_HLYTests/Fixtures/WidgetEngineFixtures.bundle'];
const hashes = [];
for (const sample of widgetSamples) {
  const bytes = deterministicZip(sample.files), name = `${sample.name}.${sample.extension}`;
  for (const output of outputs) {
    const directory = path.join(repoRoot, output);
    await fs.mkdir(directory, { recursive: true });
    await fs.writeFile(path.join(directory, name), bytes);
  }
  hashes.push({ archive: name, sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length,
    engine: sample.engine, expected: sample.expected,
    sources: Object.fromEntries(Object.entries(sample.files).map(([name, value]) => [name, createHash('sha256').update(value).digest('hex')])) });
  console.log(`${name}: ${bytes.length} bytes; ${sample.expected}`);
}
await fs.writeFile(path.join(repoRoot, 'Fixtures/Widgets/SHA256.json'), JSON.stringify(hashes, null, 2) + '\n');
console.log('Archives generated. Import, installation, native rendering and interaction require separate executed tests.');