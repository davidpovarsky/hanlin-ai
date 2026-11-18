import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const policy = process.argv.includes('--policy');
const offline = process.argv.includes('--offline');
if (process.argv.slice(2).some(x => !['--policy', '--offline'].includes(x))) throw Error('Unknown fetch option');
const pin = JSON.parse(await readFile(path.join(root, policy ? 'policy-pin.json' : 'upstream-pin.json'), 'utf8'));
if (policy) {
  const ledger = JSON.parse(await readFile(path.join(root, pin.sourceLedger), 'utf8'));
  const primitive = JSON.parse(await readFile(path.join(root, 'upstream-pin.json'), 'utf8'));
  if (ledger.revision !== pin.revision || primitive.revision !== pin.revision) throw Error('Source revision mismatch');
  pin.sources = [...new Map([...ledger.sources, ...primitive.sources, ...pin.testSources].map(x => [x.path, x])).values()];
}
const api = suffix => JSON.parse(execFileSync('gh', ['api', `repos/${pin.repository}/${suffix}`],
  { maxBuffer: 4 * 1024 * 1024, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
if (!offline) {
let object = api(`git/ref/tags/${pin.tag}`).object;
const seen = new Set();
while (object.type === 'tag') {
  if (seen.has(object.sha) || seen.size >= 5) throw Error('Cyclic/excessive upstream tag chain');
  seen.add(object.sha); object = api(`git/tags/${object.sha}`).object;
}
if (object.type !== 'commit' || object.sha !== pin.revision) throw Error('Upstream tag retarget/source drift; review required');
}
for (const source of pin.sources) {
  if (!/^[a-zA-Z0-9._/-]+$/.test(source.path) || source.path.split('/').includes('..') || source.path.startsWith('/')) throw Error('Invalid source path');
  const destination = path.join(root, '.cache', pin.revision, source.path);
  let cached;
  try { cached = await readFile(destination); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (cached) {
    const blob = createHash('sha1').update(Buffer.from('blob ' + cached.length + '\0')).update(cached).digest('hex');
    if (blob !== source.gitBlob || createHash('sha256').update(cached).digest('hex') !== source.sha256) throw Error('Cached source drift: ' + source.path);
    continue;
  }
  if (offline) throw Error('Pinned source absent offline: ' + source.path);
  const file = api(`contents/${source.path}?ref=${pin.revision}`);
  if (file.type !== 'file' || file.encoding !== 'base64' || file.size > 1024 * 1024) throw Error('Unsupported source response');
  const bytes = Buffer.from(file.content, 'base64');
  const blob = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  const hash = createHash('sha256').update(bytes).digest('hex');
  if (file.sha !== blob || blob !== source.gitBlob || hash !== source.sha256) throw Error(`Source drift: ${source.path}`);
  await mkdir(path.dirname(destination), { recursive: true }); await writeFile(destination, bytes);
}
console.log(JSON.stringify({ status: 'SOURCE_VERIFIED', tag: pin.tag, revision: pin.revision, sources: pin.sources.length }));
