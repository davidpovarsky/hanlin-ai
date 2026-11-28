import {readFile, readdir, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [root, packageRoot, archive] = process.argv.slice(2);
if (!root || !packageRoot || !archive) throw new Error('Usage: node archive-public-build.mjs REPOSITORY PREPARED_PACKAGE ARCHIVE');
const {deterministicZip} = await import(pathToFileURL(path.join(root, 'Scripts/Widgets/deterministic-zip.mjs')).href);
const files = {};
async function walk(directory, prefix = '') {
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const relative = prefix ? prefix + '/' + entry.name : entry.name;
    if (entry.isDirectory()) await walk(path.join(directory, entry.name), relative);
    else if (entry.isFile()) files[relative] = await readFile(path.join(directory, entry.name));
    else throw new Error('Unexpected nonregular prepared artifact: ' + relative);
  }
}
await walk(packageRoot);
const bytes = deterministicZip(files);
await writeFile(archive, bytes);
const hash = value => createHash('sha256').update(value).digest('hex');
const receipt = {schemaVersion: 1, operation: 'existing deterministic fixture ZIP writer',
  archive: path.basename(archive), bytes: bytes.length, sha256: hash(bytes),
  writerSHA256: hash(await readFile(path.join(root, 'Scripts/Widgets/deterministic-zip.mjs'))),
  entries: Object.entries(files).map(([name, data]) => ({name, bytes: data.length, sha256: hash(data)})),
  boundary: 'Archive of the actual public authoring checkpoint for evidence. Repository-specific temporary authoring context is recorded separately. Not a distribution example or native import/UI pass; the native gate stages its canonical fresh fixture independently.'};
await writeFile(archive + '.json', JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify({archive, bytes: bytes.length, sha256: receipt.sha256, entryCount: receipt.entries.length}));
