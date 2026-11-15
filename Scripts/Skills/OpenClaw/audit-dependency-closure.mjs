// Read-only upstream graph experiment. This never executes its unresolved output.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = path.dirname(fileURLToPath(import.meta.url));
const pin = JSON.parse(await readFile(path.join(root, 'dependency-audit.json'), 'utf8'));
const productionPin = JSON.parse(await readFile(path.join(root, 'upstream-pin.json'), 'utf8'));
if (pin.revision !== productionPin.revision || pin.repository !== productionPin.repository) throw Error('Audit/source revision mismatch');
const sources = new Map(pin.sources.map(source => [source.path, source]));
const loaded = new Set();
const sourceRoot = path.join(root, '.cache', pin.revision);
const offline = process.argv.includes('--offline');
const contents = Object.entries(pin.entryExports).map(([file, names]) => `export {${names.join(',')}} from ${JSON.stringify('./' + file)};`).join(' ');
const result = await build({
  absWorkingDir: root, stdin: { contents, resolveDir: sourceRoot, loader: 'ts' },
  bundle: true, write: false, metafile: true, platform: 'node', format: 'esm',
  target: 'node24.5', treeShaking: true, tsconfigRaw: { compilerOptions: { alwaysStrict: true } },
  plugins: [{ name: 'pinned-exploratory-graph', setup(builder) {
    builder.onResolve({ filter: /.*/ }, args => {
      if (args.path.startsWith('node:')) return { path: args.path, external: true };
      let name;
      if (args.path.startsWith('.')) name = path.posix.normalize(path.posix.join(args.importer ? path.posix.dirname(args.importer) : '', args.path));
      else if (args.path.startsWith('@openclaw/normalization-core')) name = 'packages/normalization-core/src/' + (args.path.split('/').slice(2).join('/') || 'index') + '.ts';
      else return { path: args.path, external: true };
      for (const candidate of [name, name.replace(/\.js$/, '.ts'), name.replace(/\.mjs$/, '.mts'), `${name}.ts`, `${name}/index.ts`]) {
        if (sources.has(candidate)) return { path: candidate, namespace: 'original' };
      }
      throw Error(`Audit source graph changed: ${name}`);
    });
    builder.onLoad({ filter: /.*/, namespace: 'original' }, async args => {
      const source = sources.get(args.path);
      if (!source || args.path.startsWith('/') || args.path.split('/').includes('..')) throw Error('Invalid source path');
      const file = path.join(sourceRoot, args.path);
      let bytes;
      try { bytes = await readFile(file); }
      catch (error) {
        if (error.code !== 'ENOENT' || offline) throw error;
        const response = JSON.parse(execFileSync('gh', ['api', `repos/${pin.repository}/git/blobs/${source.gitBlob}`], { encoding: 'utf8', maxBuffer: 4_000_000 }));
        bytes = Buffer.from(response.content, 'base64');
        await mkdir(path.dirname(file), { recursive: true }); await writeFile(file, bytes);
      }
      if (bytes.length !== source.bytes || createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex') !== source.gitBlob || createHash('sha256').update(bytes).digest('hex') !== source.sha256) throw Error(`Audit source drift: ${args.path}`);
      loaded.add(args.path);
      return { contents: bytes.toString('utf8'), loader: /\.[mt]ts$|\.ts$/.test(args.path) ? 'ts' : 'js' };
    });
  }}]
});
const output = Object.values(result.metafile.outputs)[0];
const observed = {
  parsedSourceCount: loaded.size, retainedInputCount: Object.keys(output.inputs).length,
  bundleBytes: result.outputFiles[0].contents.length,
  bundleSHA256: createHash('sha256').update(result.outputFiles[0].contents).digest('hex'),
  externalImportPaths: [...new Set(output.imports.map(item => item.path))].sort()
};
if (JSON.stringify(observed) !== JSON.stringify(pin.observed)) throw Error(`Dependency audit drift: ${JSON.stringify(observed)}`);
console.log(JSON.stringify({ status: 'VERIFIED_PARTIAL_GRAPH_ONLY', ...observed }));
