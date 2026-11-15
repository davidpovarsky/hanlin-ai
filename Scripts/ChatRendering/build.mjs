import {build} from 'esbuild';
import {readFile, writeFile, mkdir, readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(root, '../../AI_HLY/Downstream/ChatPresentation/CodeFences/Resources');
await mkdir(output, {recursive: true});
await build({entryPoints: [path.join(root, 'renderer.mjs')], outfile: path.join(output, 'HanlinCodeFenceRenderer.js'),
  bundle: true, format: 'iife', platform: 'browser', target: ['safari18'], minify: true,
  legalComments: 'external', sourcemap: false, charset: 'utf8'});
const diffCSS = await readFile(path.join(root, 'node_modules/diff2html/bundles/css/diff2html.min.css'), 'utf8');
await writeFile(path.join(output, 'HanlinCodeFenceRenderer.css'), diffCSS + '\n' + await readFile(path.join(root, 'renderer.css'), 'utf8'));
const lock = JSON.parse(await readFile(path.join(root, 'package-lock.json'), 'utf8'));
const notices = [];
for (const [location, descriptor] of Object.entries(lock.packages)) {
  if (!location || descriptor.dev) continue;
  const folder = path.join(root, location);
  const names = await readdir(folder);
  const license = names.find(name => /^licen[sc]e(?:[._-].*)?$/i.test(name));
  if (license) notices.push(`\n--- ${location}: ${descriptor.version} ---\n` + await readFile(path.join(folder, license), 'utf8'));
}
await writeFile(path.join(output, 'HanlinCodeFenceThirdPartyLicenses.txt'), notices.join('\n'));
const files = [];
for (const name of (await readdir(output)).sort()) {
  if (name === 'HanlinCodeFenceAssets.json') continue;
  const data = await readFile(path.join(output, name));
  files.push({name, bytes: data.length, sha256: createHash('sha256').update(data).digest('hex')});
}
await writeFile(path.join(output, 'HanlinCodeFenceAssets.json'), JSON.stringify({schemaVersion: 1,
  mermaid: lock.packages['node_modules/mermaid'].version, diff2html: lock.packages['node_modules/diff2html'].version,
  source: 'Pinned npm packages with package-lock integrity; no remote runtime code', files}, null, 2) + '\n');
process.stdout.write(JSON.stringify({files, totalBytes: files.reduce((sum, file) => sum + file.bytes, 0)}) + '\n');
