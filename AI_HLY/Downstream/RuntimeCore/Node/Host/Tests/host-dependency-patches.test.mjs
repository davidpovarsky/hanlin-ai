import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createHash } from 'node:crypto';
import { applyHostDependencyPatches } from '../apply-host-dependency-patches.mjs';

test('actual published Yarn patch is idempotent and refuses changed bytes or versions', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-host-patches-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const source = new URL('../', import.meta.url);
  const manifest = JSON.parse(await fs.readFile(new URL('host-dependency-patches.json', source), 'utf8'));
  await fs.writeFile(path.join(root, 'host-dependency-patches.json'), JSON.stringify(manifest));
  const metadata = path.join(root, 'node_modules', manifest.package, 'package.json');
  await fs.mkdir(path.dirname(metadata), { recursive: true });
  await fs.writeFile(metadata, JSON.stringify({ version: manifest.version }));
  for (const license of manifest.licenses ?? []) {
    await fs.copyFile(new URL(license.path, source), path.join(root, license.path));
  }
  for (const entry of manifest.files) {
    if (entry.package) {
      const file = path.join(root, 'node_modules', entry.package, 'package.json');
      await fs.mkdir(path.dirname(file), { recursive: true });
      await fs.writeFile(file, JSON.stringify({ version: entry.version }));
    }
    let upstream = await fs.readFile(new URL(entry.path, source), 'utf8');
    for (const { before, after } of [...entry.replacements].reverse()) upstream = upstream.replace(after, () => before);
    assert.equal(createHash('sha256').update(upstream).digest('hex'), entry.upstreamSHA256);
    const destination = path.join(root, entry.path);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination, upstream);
  }
  await assert.rejects(applyHostDependencyPatches(root, { checkOnly: true }), /Unaudited/);
  await applyHostDependencyPatches(root);
  await applyHostDependencyPatches(root); // Repeat preparation never patches twice.
  await applyHostDependencyPatches(root, { checkOnly: true });
  const target = path.join(root, manifest.files[0].path);
  const valid = await fs.readFile(target);
  await fs.appendFile(target, '\n// changed dependency\n');
  await assert.rejects(applyHostDependencyPatches(root), /Unaudited/);
  await fs.writeFile(target, valid);
  await fs.writeFile(metadata, JSON.stringify({ version: '0.0.0' }));
  await assert.rejects(applyHostDependencyPatches(root), /version mismatch/);
  await fs.writeFile(metadata, JSON.stringify({ version: manifest.version }));
  const parser = manifest.files.find(entry => entry.package === '@yarnpkg/parsers');
  const parserMetadata = path.join(root, 'node_modules', parser.package, 'package.json');
  await fs.writeFile(parserMetadata, JSON.stringify({ version: '0.0.0' }));
  await assert.rejects(applyHostDependencyPatches(root), /version mismatch/);
  await fs.writeFile(parserMetadata, JSON.stringify({ version: parser.version }));
  await fs.appendFile(path.join(root, manifest.licenses[0].path), 'changed');
  await assert.rejects(applyHostDependencyPatches(root), /license digest mismatch/);
});
