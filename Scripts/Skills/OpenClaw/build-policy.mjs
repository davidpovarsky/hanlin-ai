import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';
import ts from 'typescript';

const root = path.dirname(fileURLToPath(import.meta.url));
const pin = JSON.parse(await readFile(path.join(root, 'policy-pin.json'), 'utf8'));
const extracted = path.join(root, '.cache', pin.revision + '-policy-declarations');
const generated = path.join(root, 'generated');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
if (esbuild.version !== pin.buildTools.esbuild || ts.version !== pin.buildTools.typescript) throw Error('Build tool drift');
const dependencies = {};
for (const [name, version] of Object.entries(pin.bundledDependencies)) {
  const bytes = await readFile(path.join(root, 'node_modules', name, 'package.json'));
  const manifest = JSON.parse(bytes);
  if (manifest.version !== version) throw Error('Bundled dependency drift: ' + name);
  const license = await readFile(path.join(root, 'node_modules', name, name === 'semver' ? 'LICENSE' : 'LICENSE.md'));
  await writeFile(path.join(generated, 'LICENSE.' + name + '.txt'), license);
  dependencies[name] = { version, manifestSHA256: digest(bytes), licenseSHA256: digest(license) };
}
const entry = Object.entries(pin.entryExports).map(([file, names]) =>
  'export {' + names.join(',') + '} from ' + JSON.stringify('./' + file) + ';'
).join('\n');
const result = await esbuild.build({
  absWorkingDir: extracted, stdin: { contents: entry, resolveDir: extracted, sourcefile: 'original-policy-entry.ts', loader: 'ts' },
  bundle: true, write: false, metafile: true, platform: 'node', format: 'esm', target: 'node24.5',
  tsconfigRaw: { compilerOptions: { alwaysStrict: true } }, minify: false, legalComments: 'none',
  charset: 'utf8', sourcemap: false, nodePaths: [path.join(root, 'node_modules')]
});
const output = Object.values(result.metafile.outputs)[0];
const runtimeImports = [...new Set(output.imports.map(x => x.path))].sort();
if (runtimeImports.some(x => !pin.permittedRuntimeImports.includes(x))) throw Error('Unclosed runtime dependency');
const exports = Object.values(pin.entryExports).flat().sort();
if (JSON.stringify(output.exports.slice().sort()) !== JSON.stringify(exports)) throw Error('Original export contract drift');
if (Object.keys(result.metafile.inputs).some(x => /(?:^|[/\\])(?:yaml|markdown-core)(?:[/\\])/.test(x))) throw Error('Second YAML/Markdown parser forbidden');
const artifact = result.outputFiles[0].contents;
await mkdir(generated, { recursive: true });
await writeFile(path.join(generated, 'policy.mjs'), artifact);
const closureBytes = await readFile(path.join(generated, 'policy-declaration-closure.json'));
const closure = JSON.parse(closureBytes);
const sourceLedgerBytes = await readFile(path.join(root, pin.sourceLedger));
const provenance = {
  repository: pin.repository, tag: pin.tag, revision: pin.revision, target: 'node24.5',
  buildTools: pin.buildTools, compilerOptions: { alwaysStrict: true },
  sourceLedgerSHA256: digest(sourceLedgerBytes), extractionSHA256: digest(await readFile(path.join(root, 'extract-policy.cjs'))),
  declarationClosureSHA256: digest(closureBytes), retainedDeclarations: closure.retainedDeclarations,
  originalModuleCount: closure.modules.length, artifactSHA256: digest(artifact), artifactBytes: artifact.length,
  runtimeImports, bundledDependencies: dependencies, exports, scope: pin.scope,
  buildInputs: Object.entries(result.metafile.inputs).map(([name, input]) => ({ name: name.replaceAll('\\', '/'), bytes: input.bytes })),
  acceptance: 'BUILD_ONLY; original parity, native integration and device acceptance are separate'
};
await writeFile(path.join(generated, 'policy-provenance.json'), JSON.stringify(provenance, null, 2) + '\n');
console.log(JSON.stringify({ status: 'BUILT_ORIGINAL_POLICY', artifactBytes: artifact.length, sha256: provenance.artifactSHA256, runtimeImports, exports: exports.length }));
