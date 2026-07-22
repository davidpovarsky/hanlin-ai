import { promises as fs } from 'node:fs';
import path from 'node:path';

const [
  sourceRoot = 'AI_HLY/Downstream/RuntimeCore',
  catalogPath = 'AI_HLY/Downstream/RuntimeCore/Resources/RuntimeLocalizable.xcstrings',
  namespace = 'RuntimeL10n',
] = process.argv.slice(2);
const catalog = JSON.parse(await fs.readFile(catalogPath, 'utf8'));
const requiredLocales = ['en', 'he', 'zh-Hans'];
const keys = new Set();
const dynamicKeys = [
  'App restart required', 'Executing', 'Failed', 'Health Check', 'Linked', 'Not prepared',
  'Prepare', 'Preparing', 'Ready', 'Shared', 'Unavailable',
  'Process text with the linked BSD awk implementation.', 'Read workspace files.',
  'Copy workspace files.', 'Transfer data over HTTPS when network access is approved.',
  'Search text in workspace files.', 'Read the beginning of workspace files.',
  'Create links inside the workspace.', 'List workspace files.', 'Create workspace directories.',
  'Move workspace files.', 'Inspect a workspace link.', 'Remove workspace files.',
  'Remove empty workspace directories.', 'Transform text with BSD sed.', 'Sort text.',
  'Inspect workspace file metadata.', 'Read the end of workspace files.',
  'Create or extract archives in the workspace.', 'Create or update workspace files.',
  'Translate text characters.', 'Filter repeated text lines.', 'Remove one workspace link or file.',
  'Count lines, words, or bytes.'
];
if (namespace === 'RuntimeL10n') dynamicKeys.forEach(key => keys.add(key));

const escapedNamespace = namespace.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const localizationCall = new RegExp(`${escapedNamespace}\\.(?:string|format)\\(\\s*"((?:[^"\\\\]|\\\\.)*)"`, 'g');

for (const file of await swiftFiles(sourceRoot)) {
  const source = await fs.readFile(file, 'utf8');
  for (const match of source.matchAll(localizationCall)) {
    keys.add(JSON.parse(`"${match[1]}"`));
  }
}

const failures = [];
for (const key of [...keys].sort()) {
  const entry = catalog.strings?.[key];
  if (!entry) { failures.push(`missing key: ${key}`); continue; }
  for (const locale of requiredLocales) {
    const unit = entry.localizations?.[locale]?.stringUnit;
    if (!unit?.value || unit.state !== 'translated') failures.push(`missing ${locale}: ${key}`);
  }
}
if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log(`Validated ${keys.size} ${namespace} localization keys for ${requiredLocales.join(', ')}.`);

async function swiftFiles(root) {
  const output = [];
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    for (const entry of await fs.readdir(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) stack.push(absolute);
      else if (entry.isFile() && entry.name.endsWith('.swift')) output.push(absolute);
    }
  }
  return output;
}
