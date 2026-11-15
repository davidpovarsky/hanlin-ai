import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const pin = JSON.parse(await readFile(path.join(root, 'upstream-pin.json'), 'utf8'));
const api = suffix => JSON.parse(execFileSync('gh', ['api', `repos/${pin.repository}/${suffix}`],
  { maxBuffer: 4 * 1024 * 1024, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
let object = api(`git/ref/tags/${pin.tag}`).object;
const seen = new Set();
while (object.type === 'tag') {
  if (seen.has(object.sha) || seen.size >= 5) throw Error('Cyclic/excessive upstream tag chain');
  seen.add(object.sha); object = api(`git/tags/${object.sha}`).object;
}
if (object.type !== 'commit' || object.sha !== pin.revision) throw Error('Upstream tag retarget/source drift; review required');
for (const source of pin.sources) {
  if (!/^[a-zA-Z0-9._/-]+$/.test(source.path) || source.path.split('/').includes('..') || source.path.startsWith('/')) throw Error('Invalid source path');
  const file = api(`contents/${source.path}?ref=${pin.revision}`);
  if (file.type !== 'file' || file.encoding !== 'base64' || file.size > 1024 * 1024) throw Error('Unsupported source response');
  const bytes = Buffer.from(file.content, 'base64');
  const blob = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  const hash = createHash('sha256').update(bytes).digest('hex');
  if (file.sha !== blob || blob !== source.gitBlob || hash !== source.sha256) throw Error(`Source drift: ${source.path}`);
  const destination = path.join(root, '.cache', pin.revision, source.path);
  await mkdir(path.dirname(destination), { recursive: true }); await writeFile(destination, bytes);
}
console.log(JSON.stringify({ status: 'SOURCE_VERIFIED', tag: pin.tag, revision: pin.revision, sources: pin.sources.length }));
