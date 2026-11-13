import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

// Build-time only: the actual pinned full-ICU Node defines the Unicode version.
// Expand the exact property instead of weakening it to an ASCII control class.
const rootOption=process.argv.indexOf('--root');
const root = rootOption>=0 ? path.resolve(process.argv[rootOption+1]) : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../AI_HLY/Downstream/RuntimeCore/Node/Host');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
if (process.versions.node !== '24.5.0' || process.versions.unicode !== '16.0') {
  throw new Error('Generate with the pinned full-ICU Node 24.5.0 / Unicode 16.0.');
}
const reference = /\p{C}/u;
const ranges = [];
let first = null;
for (let point = 0; point <= 0x110000; point++) {
  const matches = point <= 0x10ffff && reference.test(String.fromCodePoint(point));
  if (matches && first === null) first = point;
  if (!matches && first !== null) { ranges.push([first, point - 1]); first = null; }
}
const escape = point => `\\u{${point.toString(16)}}`;
const expanded = ranges.map(([a,b]) => a === b ? escape(a) : escape(a) + '-' + escape(b)).join('');
const originalPatterns = [String.raw`/['\t\p{C}]/u`, String.raw`/[\t\p{C}]/u`, String.raw`/["$\t\p{C}]/u`];
const replacements = originalPatterns.map(before => ({ before, after: before.replace(String.raw`\p{C}`, expanded) }));
for (const { before, after } of replacements) {
  const original = new RegExp(before.slice(1,-2),'u');
  const compiled = new RegExp(after.slice(1,-2),'u');
  for (let point=0; point<=0x10ffff; point++) {
    const text=String.fromCodePoint(point);
    if (original.test(text)!==compiled.test(text)) throw new Error(`Unicode mismatch at ${point.toString(16)}`);
  }
}
const manifestPath=path.join(root,'host-dependency-patches.json');
const manifest=JSON.parse(await fs.readFile(manifestPath,'utf8'));
const relative='node_modules/@yarnpkg/parsers/lib/shell.js';
const previous=manifest.files.find(item=>item.path===relative);
let original=await fs.readFile(path.join(root,relative),'utf8');
if(previous && hash(original)===previous.patchedSHA256) {
  for(const replacement of previous.replacements) original=original.replace(replacement.after,()=>replacement.before);
}
if(previous && hash(original)!==previous.upstreamSHA256) throw new Error('Unknown published parser source.');
let patched=original;
for(const replacement of replacements) {
  if(patched.split(replacement.before).length!==2) throw new Error('Ambiguous Unicode patch anchor.');
  patched=patched.replace(replacement.before,()=>replacement.after);
}
const lock=JSON.parse(await fs.readFile(path.join(root,'package-lock.json'),'utf8'));
const metadata=lock.packages['node_modules/@yarnpkg/parsers'];
if(metadata.version!=='3.1.0')throw new Error('Unknown parser version.');
const entry={path:relative,package:'@yarnpkg/parsers',version:metadata.version,license:'BSD-2-Clause',
  upstreamTarball:metadata.resolved,upstreamIntegrity:metadata.integrity,
  upstreamSHA256:hash(original),patchedSHA256:hash(patched),replacements,
  generatedUnicode:{node:process.versions.node,unicode:process.versions.unicode,icu:process.versions.icu,
    property:'General_Category=Other',codePointsCompared:0x110000,patternsCompared:replacements.length}};
const license=await fs.readFile(path.join(root,'UNICODE-LICENSE.txt'));
const licenseEntry={path:'UNICODE-LICENSE.txt',license:'Unicode-3.0',source:'https://www.unicode.org/license.txt',sha256:hash(license)};
if(process.argv.includes('--write')) {
  manifest.files=manifest.files.filter(item=>item.path!==relative);manifest.files.push(entry);
  manifest.licenses=[...(manifest.licenses??[]).filter(item=>item.path!==licenseEntry.path),licenseEntry];
  await fs.writeFile(manifestPath,JSON.stringify(manifest,null,2)+'\n');
} else if(JSON.stringify(previous)!==JSON.stringify(entry))throw new Error('Generated Unicode patch metadata differs.');
console.log(JSON.stringify({unicode:process.versions.unicode,patterns:replacements.length,comparedPerPattern:0x110000,
  ranges:ranges.length,upstreamSHA256:entry.upstreamSHA256,patchedSHA256:entry.patchedSHA256}));
