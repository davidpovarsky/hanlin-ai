import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {pathToFileURL} from 'node:url';
import {runMiniAppOperation, readMiniAppSDK} from '../miniapp-authoring.mjs';

const compilerLocation = process.env.HANLIN_AUTHORING_TYPESCRIPT ?? 'typescript';
const ts = (await import(compilerLocation)).default;
const compilerPackage = path.dirname(createRequire(import.meta.url).resolve(
  compilerLocation.startsWith('file:') ? new URL('../package.json', compilerLocation).pathname : 'typescript/package.json'));

async function fixture(t, engine = 'nativescript') {
  const root = await fs.mkdtemp(path.join(process.env.HANLIN_AUTHORING_TMP ?? os.tmpdir(), 'hanlin-authoring-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  const project = path.join(root, 'project');
  await fs.mkdir(path.join(sdk, 'original', 'node_modules'), {recursive: true});
  await fs.mkdir(project);
  await fs.symlink(compilerPackage, path.join(sdk, 'original', 'node_modules', 'typescript'), 'dir');
  await fs.writeFile(path.join(sdk, 'original', 'package.json'), JSON.stringify({private: true}));
  await fs.writeFile(path.join(sdk, 'miniapp-sdk.json'), JSON.stringify({
    schemaVersion: 1, engines: {[engine]: {
      toolingRoot: 'original', packageVersions: {typescript: ts.version, '@nativescript/core': '9.1.0', '@nativescript/ios': '9.1.0'},
      docs: ['guide.md']
    }}
  }));
  await fs.writeFile(path.join(sdk, 'guide.md'), 'Original declarations are available through the SDK.');
  await fs.writeFile(path.join(project, 'package.json'), JSON.stringify({name: 'authoring-test', version: '1.0.0'}));
  await fs.writeFile(path.join(project, 'script.json'), JSON.stringify({
    name: 'Authoring test', version: '1.0.0',
    hanlinRuntime: engine === 'scriptwidget' ? 'scripting-jsc' : 'hanlin-' + engine,
    ...(engine === 'scriptwidget' ? {widgetEngine: 'scriptwidget', hanlinWidget: {abiVersion: 1, sourceFormat: 'tsx', families: ['systemSmall'], actions: []}} : {}),
    entrypoints: [{id: 'share', kind: 'share', sourcePath: 'nativescript/app/bundle.mjs'}]
  }));
  await fs.writeFile(path.join(project, 'hanlin.authoring.json'), JSON.stringify({
    schemaVersion: 1, engine, entry: engine === 'scriptwidget' ? 'widget.tsx' : 'index.ts',
    resources: ['data.json']
  }));
  await fs.writeFile(path.join(project, 'data.json'), '{"actual":"resource"}');
  await fs.writeFile(path.join(project, 'tsconfig.json'), JSON.stringify({
    compilerOptions: {strict: true, module: 'ESNext', moduleResolution: 'Bundler', target: 'ES2022',
      noEmit: true, skipLibCheck: false}, include: ['*.ts', '*.tsx']
  }));
  const entry = path.join(project, engine === 'scriptwidget' ? 'widget.tsx' : 'index.ts');
  await fs.writeFile(entry, 'export const answer: number = 42;\n');
  const run = (operation, extra = {}) => runMiniAppOperation({operation, engine, projectRoot: project, ...extra}, {sdkRoot: sdk, compiler: ts});
  return {root, sdk, project, entry, run};
}

test('real TypeScript reports semantic errors with original source locations', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.entry, 'export const good: number = 1;\nexport const bad: number = "wrong";\n');
  const result = await f.run('validate');
  assert.equal(result.succeeded, false);
  const error = result.diagnostics.find(item => item.code === 'TS2322');
  assert.ok(error, JSON.stringify(result));
  assert.equal(error.file, 'index.ts');
  assert.equal(error.line, 2);
  assert.ok(error.column > 0 && error.endColumn > error.column);
  assert.equal(result.sdk.compilerVersion, ts.version);
});

test('validation uses actual original package declarations from the supplied SDK', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.entry, 'import type {CompilerOptions} from "typescript";\nexport const options: CompilerOptions = {target: "invented"};\n');
  const report = await f.run('validate');
  assert.equal(report.succeeded, false);
  assert.ok(report.diagnostics.some(item => item.code === 'TS2322' && item.message.includes('ScriptTarget')), JSON.stringify(report));
  assert.ok(!report.diagnostics.some(item => item.code === 'TS2307'), JSON.stringify(report));
});

test('NativeScript package emits a runnable ESM graph and retains exact editable sources', async t => {
  const f = await fixture(t);
  const source = 'import {sum} from "./helper";\nexport const answer: number = sum(40, 2);\nexport const later = () => import("./helper");\n';
  await fs.writeFile(f.entry, source);
  await fs.writeFile(path.join(f.project, 'helper.ts'), 'export function sum(a: number, b: number): number { return a + b; }\n');
  const report = await f.run('build');
  assert.equal(report.succeeded, true, JSON.stringify(report));
  const stage = report.preparedPackagePath;
  assert.equal(await fs.readFile(path.join(stage, 'source', 'index.ts'), 'utf8'), source);
  assert.equal(await fs.readFile(path.join(stage, 'nativescript/app/modules/data.json'), 'utf8'), '{"actual":"resource"}');
  const script = JSON.parse(await fs.readFile(path.join(stage, 'script.json')));
  assert.equal(script.entry, 'nativescript/app/bundle.mjs');
  assert.equal(script.entrypoints[0].id, 'share');
  const runtimePackage = JSON.parse(await fs.readFile(path.join(stage, 'nativescript/app/package.json')));
  assert.deepEqual(runtimePackage.hanlinNativeScript.plugins, {});
  const authoring = JSON.parse(await fs.readFile(path.join(stage, 'hanlin.authoring.json')));
  assert.equal(authoring.sourceRoot, 'source');
  assert.equal(authoring.sourceHashes['index.ts'].length, 64);
  const module = await import(pathToFileURL(path.join(stage, 'nativescript/app/modules/index.js')).href);
  assert.equal(module.answer, 42);
  assert.equal((await module.later()).sum(1, 2), 3);
  const map = JSON.parse(await fs.readFile(path.join(stage, 'nativescript/app/modules/index.js.map')));
  assert.equal(map.sourcesContent[0], source);
});

test('import rechecks retained source and ignores a stale successful report', async t => {
  const f = await fixture(t);
  const build = await f.run('build');
  assert.equal(build.succeeded, true, JSON.stringify(build));
  await fs.writeFile(path.join(build.preparedPackagePath, 'source/index.ts'), 'export const answer: number = "broken";\n');
  const check = await f.run('validate', {projectRoot: build.preparedPackagePath});
  assert.equal(check.succeeded, false);
  assert.ok(check.diagnostics.some(item => item.code === 'TS2322'));
});

test('ScriptWidget keeps original source and its explicit ABI declaration', async t => {
  const f = await fixture(t, 'scriptwidget');
  const source = await fs.readFile(f.entry, 'utf8');
  const report = await f.run('build');
  assert.equal(report.succeeded, true, JSON.stringify(report));
  assert.equal(await fs.readFile(path.join(report.preparedPackagePath, 'widget.tsx'), 'utf8'), source);
  assert.equal(await fs.readFile(path.join(report.preparedPackagePath, 'source/widget.tsx'), 'utf8'), source);
  const script = JSON.parse(await fs.readFile(path.join(report.preparedPackagePath, 'script.json')));
  assert.equal(script.widgetEngine, 'scriptwidget');
  assert.equal(script.hanlinWidget.abiVersion, 1);
});

test('failed typecheck emits no package', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.entry, 'export const answer: boolean = 42;\n');
  const report = await f.run('build');
  assert.equal(report.succeeded, false);
  assert.equal(report.preparedPackagePath, undefined);
  await assert.rejects(fs.stat(path.join(f.project, '.hanlin-build')), {code: 'ENOENT'});
});

test('a requested existing output directory is preserved', async t => {
  const f = await fixture(t);
  const outputDirectory = path.join(f.root, 'existing');
  await fs.mkdir(outputDirectory);
  await fs.writeFile(path.join(outputDirectory, 'keep.txt'), 'keep');
  const report = await f.run('build', {outputDirectory});
  assert.equal(report.succeeded, false);
  assert.equal(await fs.readFile(path.join(outputDirectory, 'keep.txt'), 'utf8'), 'keep');
});

test('SDK discovery reads its real manifest and requested documentation', async t => {
  const f = await fixture(t);
  const manifest = await readMiniAppSDK(f.sdk, {engine: 'nativescript'});
  assert.equal(manifest.selectedEngine.packageVersions.typescript, ts.version);
  assert.equal(manifest.manifestSHA256.length, 64);
  assert.equal(manifest.files, undefined);
  assert.equal(manifest.inventory.resource, 'miniapp-sdk.json');
  assert.ok(manifest.selectedEngine.packageResources.some(item => item.name === 'typescript' && item.types.endsWith('typescript.d.ts')));
  const doc = await readMiniAppSDK(f.sdk, {resource: 'guide.md'});
  assert.match(doc.content, /Original declarations/);
  await assert.rejects(readMiniAppSDK(f.sdk, {resource: '../project/index.ts'}), /leaves/);
});

test('bundle-only imports do not receive a fabricated source typecheck pass', async t => {
  const f = await fixture(t);
  await fs.rm(path.join(f.project, 'hanlin.authoring.json'));
  const report = await f.run('validate');
  assert.equal(report.succeeded, false);
  assert.match(report.diagnostics[0].message, /source entry/);
});

test('modified compiled output is rejected even when retained TypeScript is still valid', async t => {
  const f = await fixture(t);
  const report = await f.run('build');
  assert.equal(report.succeeded, true, JSON.stringify(report));
  await fs.appendFile(path.join(report.preparedPackagePath, 'nativescript/app/bundle.mjs'), '\nthrow new Error("changed");\n');
  const check = await f.run('validate', {projectRoot: report.preparedPackagePath});
  assert.equal(check.succeeded, false);
  assert.ok(check.diagnostics.some(item => item.code === 'MINIAPP_COMPILED_OUTPUT_CHANGED'));
});


test('the real CLI archives and revalidates retained source, diagnostics and output identity', async t => {
  const f = await fixture(t);
  const cli = fileURLToPath(new URL('../../../../../../Scripts/MiniApps/miniapp.mjs', import.meta.url));
  const archive = path.join(f.root, 'MiniApp.hanlinNativeScript');
  const reportPath = path.join(f.root, 'report.json');
  const build = spawnSync(process.execPath, [cli, 'build', '--engine', 'nativescript', '--sdk', f.sdk,
    '--project', f.project, '--archive', archive, '--report', reportPath], {
      encoding: 'utf8', env: {...process.env, HANLIN_AUTHORING_TYPESCRIPT: compilerLocation}
    });
  assert.equal(build.status, 0, build.stderr + build.stdout);
  const report = JSON.parse(await fs.readFile(reportPath));
  assert.equal(report.archivePath, archive);
  const extracted = path.join(f.root, 'imported');
  const unpack = spawnSync('python3', ['-c',
    'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])', archive, extracted], {encoding: 'utf8'});
  assert.equal(unpack.status, 0, unpack.stderr);
  const check = await f.run('validate', {projectRoot: extracted});
  assert.equal(check.succeeded, true, JSON.stringify(check));
  const map = JSON.parse(await fs.readFile(path.join(extracted, 'nativescript/app/modules/index.js.map')));
  assert.equal(map.sourcesContent[0], await fs.readFile(f.entry, 'utf8'));
});


test('compiler-used sources named build or dist survive source retention and archive revalidation', async t => {
  const f = await fixture(t);
  await fs.mkdir(path.join(f.project, 'src/build'), {recursive: true});
  await fs.mkdir(path.join(f.project, 'dist'), {recursive: true});
  await fs.writeFile(path.join(f.project, 'src/build/config.ts'), 'export const left: number = 40;\n');
  await fs.writeFile(path.join(f.project, 'dist/authored.ts'), 'export const right: number = 2;\n');
  await fs.writeFile(f.entry, 'import {left} from "./src/build/config";\nimport {right} from "./dist/authored";\nexport const answer: number = left + right;\n');
  const report = await f.run('build');
  assert.equal(report.succeeded, true, JSON.stringify(report));
  assert.match(await fs.readFile(path.join(report.preparedPackagePath, 'source/src/build/config.ts'), 'utf8'), /40/);
  assert.match(await fs.readFile(path.join(report.preparedPackagePath, 'source/dist/authored.ts'), 'utf8'), /2/);
  const checked = await f.run('validate', {projectRoot: report.preparedPackagePath});
  assert.equal(checked.succeeded, true, JSON.stringify(checked));
});
