import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
const source = import.meta.dirname;
const root = path.resolve(source, '../..');
const output = path.join(root, 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/window-factory');
const files = new Map();
for (const [input, name] of [['window-factory.mjs', 'index.mjs'], ['window-factory.d.ts', 'index.d.ts'], ['window-host.mjs', 'host.mjs']]) {
  const bytes = await readFile(path.join(source, input), 'utf8');
  const hash = createHash('sha256').update(bytes).digest('hex');
  files.set(name, '// Generated from Scripts/NativeScript/' + input + '; SHA256 ' + hash + '\n' + bytes);
}
files.set('package.json', JSON.stringify({ name: '@hanlin/window-factory', version: '1.0.0',
  private: true, type: 'module', main: 'index.mjs', types: 'index.d.ts' }, null, 2) + '\n');
if (process.argv.includes('--write')) {
  await mkdir(output, { recursive: true });
  for (const [name, bytes] of files) await writeFile(path.join(output, name), bytes);
} else if (process.argv.includes('--check')) {
  for (const [name, bytes] of files) if (await readFile(path.join(output, name), 'utf8') !== bytes) {
    throw new Error('Generated window-factory drift: ' + name);
  }
} else throw new Error('Use --write or --check.');
console.log('PASS: Hanlin window-factory source/declarations generation; native execution remains a separate gate.');
