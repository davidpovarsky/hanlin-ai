import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';

const root = path.dirname(fileURLToPath(import.meta.url));
const pin = JSON.parse(await readFile(path.join(root, 'upstream-pin.json'), 'utf8'));
const sourceRoot = path.join(root, '.cache', pin.revision);
for (const source of pin.sources) {
  const bytes = await readFile(path.join(sourceRoot, source.path));
  if (createHash('sha256').update(bytes).digest('hex') !== source.sha256) throw Error(`Cached source drift: ${source.path}`);
}
const result = await esbuild.build({
  entryPoints: [path.join(sourceRoot, 'src/shared/requirements.ts')],
  bundle: true, write: false, metafile: true, platform: 'neutral', format: 'iife',
  globalName: 'HanlinOpenClawOriginalRequirements', target: 'node24.5',
  tsconfigRaw: { compilerOptions: { alwaysStrict: true } },
  minify: true, legalComments: 'none', charset: 'utf8', sourcemap: false
});
const runtimeImports = result.metafile.outputs[Object.keys(result.metafile.outputs)[0]].imports;
if (runtimeImports.length || Object.keys(result.metafile.inputs).length !== 1) throw Error('Unexpected runtime dependency closure');
const body = result.outputFiles[0].contents;
const generated = path.join(root, 'generated'); await mkdir(generated, { recursive: true });
await writeFile(path.join(generated, 'requirements.js'), body);
await writeFile(path.join(generated, 'LICENSE.OpenClaw.txt'), await readFile(path.join(sourceRoot, 'LICENSE')));
const tests = await esbuild.build({
  entryPoints: [path.join(sourceRoot, 'src/shared/requirements.test.ts')],
  bundle: true, write: false, platform: 'neutral', format: 'iife', target: 'node24.5', minify: true,
  tsconfigRaw: { compilerOptions: { alwaysStrict: true } },
  plugins: [{ name: 'original-test-bridge', setup(build) {
    build.onResolve({ filter: /^vitest$/ }, () => ({ path: path.join(root, 'Tests/upstream-shim.mjs') }));
    build.onResolve({ filter: /^\.\/requirements\.js$/ }, () => ({ path: 'original-built-artifact', namespace: 'hanlin-test' }));
    build.onLoad({ filter: /.*/, namespace: 'hanlin-test' }, () => ({
      contents: 'export const evaluateRequirementsFromMetadataWithRemote = globalThis.HanlinOpenClawOriginalRequirements.evaluateRequirementsFromMetadataWithRemote;',
      loader: 'js'
    }));
  }}]
});
await writeFile(path.join(generated, 'upstream-requirements-tests.js'), tests.outputFiles[0].contents);
const nativeContract = await esbuild.build({
  entryPoints: [path.join(root, 'Tests/requirements.test.mjs')], bundle: true, write: false,
  platform: 'node', format: 'esm', target: 'node24.5', minify: false,
  tsconfigRaw: { compilerOptions: { alwaysStrict: true } },
  plugins: [{ name: 'in-process-native-tests', setup(build) {
    build.onResolve({ filter: /^node:test$/ }, () => ({ path: 'test-registry', namespace: 'hanlin-test' }));
    build.onLoad({ filter: /.*/, namespace: 'hanlin-test' }, () => ({
      contents: 'export const test = (name, body) => globalThis.__hanlinMemoryProbeCases.push({name,body});', loader: 'js'
    }));
  }}]
});
await writeFile(path.join(generated, 'native-contract.mjs'), nativeContract.outputFiles[0].contents);
const provenance = {
  repository: pin.repository, tag: pin.tag, revision: pin.revision,
  sources: pin.sources, buildTool: `esbuild@${esbuild.version}`, target: 'node24.5',
  compilerOptions: { alwaysStrict: true },
  artifactSHA256: createHash('sha256').update(body).digest('hex'), artifactBytes: body.length,
  originalTestArtifactSHA256: createHash('sha256').update(tests.outputFiles[0].contents).digest('hex'),
  nativeContractArtifactSHA256: createHash('sha256').update(nativeContract.outputFiles[0].contents).digest('hex'),
  runtimeDependencies: [],
  exports: ['isOsRequirementSatisfied', 'evaluateRequirementsFromMetadataWithRemote'],
  scope: 'Original runtime requirement predicate only. No Hanlin readiness/enablement/install/execution decision.'
};
await writeFile(path.join(generated, 'provenance.json'), JSON.stringify(provenance, null, 2) + '\n');
console.log(JSON.stringify({ status: 'BUILT_ORIGINAL_SUBSET', artifactBytes: body.length, sha256: provenance.artifactSHA256 }));
