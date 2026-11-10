import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const hash = data => createHash('sha256').update(data).digest('hex');

/** Apply only the exact audited published dependency; mismatches fail closed. */
export async function applyHostDependencyPatches(root = import.meta.dirname, { checkOnly = false } = {}) {
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'host-dependency-patches.json'), 'utf8'));
  const metadata = JSON.parse(await fs.readFile(path.join(root, 'node_modules', manifest.package, 'package.json'), 'utf8'));
  if (metadata.version !== manifest.version) throw new Error('Host dependency patch version mismatch.');
  for (const license of manifest.licenses ?? []) {
    const file = path.resolve(root, license.path);
    if (!file.startsWith(path.resolve(root) + path.sep) || hash(await fs.readFile(file)) !== license.sha256) {
      throw new Error('Host dependency license digest mismatch.');
    }
  }
  for (const entry of manifest.files) {
    if (entry.package) {
      const dependency = JSON.parse(await fs.readFile(path.join(root, 'node_modules', entry.package, 'package.json'), 'utf8'));
      if (dependency.version !== entry.version) throw new Error('Host dependency patch version mismatch.');
    }
    const target = path.resolve(root, entry.path);
    if (!target.startsWith(path.resolve(root, 'node_modules') + path.sep)) throw new Error('Invalid dependency patch path.');
    const original = await fs.readFile(target);
    if (hash(original) === entry.patchedSHA256) continue;
    if (checkOnly || hash(original) !== entry.upstreamSHA256) throw new Error(`Unaudited dependency patch input: ${entry.path}`);
    let contents = original.toString('utf8');
    for (const { before, after } of entry.replacements) {
      if (contents.split(before).length !== 2) throw new Error(`Ambiguous dependency patch anchor: ${entry.path}`);
      contents = contents.replace(before, () => after);
    }
    if (hash(contents) !== entry.patchedSHA256) throw new Error(`Dependency patch output digest mismatch: ${entry.path}`);
    await fs.writeFile(target, contents);
  }
  return { package: manifest.package, version: manifest.version, files: manifest.files.length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(await applyHostDependencyPatches(import.meta.dirname, { checkOnly: process.argv.includes('--check') })));
}
