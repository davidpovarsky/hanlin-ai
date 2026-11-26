import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {pathToFileURL} from 'node:url';
import {runInNewContext} from 'node:vm';
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
      toolingRoot: 'original', typescriptPath: 'original/node_modules/typescript/lib/typescript.js',
      packageVersions: {typescript: ts.version, '@nativescript/core': '9.1.0', '@nativescript/ios': '9.1.0'},
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
  const source = 'import {sum} from "./helper";\nexport {sum} from "./helper";\nexport const answer: number = sum(40, 2);\nexport const later = () => import("./helper");\n';
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
  const app = path.join(stage, 'nativescript/app');
  assert.equal(await fs.readFile(path.join(app, 'bundle.mjs'), 'utf8'), 'import "./modules/index.mjs";\n');
  const emitted = await fs.readFile(path.join(app, 'modules/index.mjs'), 'utf8');
  assert.match(emitted, /import \{ sum \} from "\.\/helper.mjs"/);
  assert.match(emitted, /export \{ sum \} from "\.\/helper.mjs"/);
  assert.match(emitted, /import\("\.\/helper.mjs"\)/);
  assert.match(emitted, /sourceMappingURL=index.mjs.map/);
  await assert.rejects(fs.stat(path.join(app, 'modules/index.js')), {code: 'ENOENT'});
  const module = await import(pathToFileURL(path.join(app, 'modules/index.mjs')).href);
  assert.equal(module.answer, 42);
  assert.equal(module.sum(20, 22), 42);
  assert.equal((await module.later()).sum(1, 2), 3);
  const map = JSON.parse(await fs.readFile(path.join(app, 'modules/index.mjs.map')));
  assert.equal(map.file, 'index.mjs');
  assert.equal(map.sourcesContent[0], source);
});

test('NativeScript preserves authored CommonJS JavaScript and its source-map mode', async t => {
  const f = await fixture(t);
  await fs.rm(f.entry);
  const source = 'module.exports = {answer: 42};\n';
  await fs.writeFile(path.join(f.project, 'index.js'), source);
  await fs.writeFile(path.join(f.project, 'globals.d.ts'), 'declare const module: {exports: {answer: number}};\n');
  const authoringPath = path.join(f.project, 'hanlin.authoring.json');
  const authoring = JSON.parse(await fs.readFile(authoringPath));
  authoring.entry = 'index.js';
  await fs.writeFile(authoringPath, JSON.stringify(authoring));
  const configPath = path.join(f.project, 'tsconfig.json');
  const config = JSON.parse(await fs.readFile(configPath));
  Object.assign(config.compilerOptions, {allowJs: true, checkJs: true});
  config.include = ['*.ts', '*.js'];
  await fs.writeFile(configPath, JSON.stringify(config));
  const report = await f.run('build');
  assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
  const app = path.join(report.preparedPackagePath, 'nativescript/app');
  assert.equal(await fs.readFile(path.join(app, 'bundle.mjs'), 'utf8'), 'import "./modules/index.js";\n');
  const emitted = await fs.readFile(path.join(app, 'modules/index.js'), 'utf8');
  const context = {module: {exports: {}}};
  runInNewContext(emitted, context);
  assert.equal(context.module.exports.answer, 42);
  await assert.rejects(fs.stat(path.join(app, 'modules/index.mjs')), {code: 'ENOENT'});
  const map = JSON.parse(await fs.readFile(path.join(app, 'modules/index.js.map')));
  assert.equal(map.file, 'index.js');
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
  // Runtime host preparation executes this same test from a temporary copy.
  // Its CLI still belongs to the actual repository that prepared the host.
  const repository = process.env.HANLIN_MINIAPP_REPOSITORY_ROOT
    ?? fileURLToPath(new URL('../../../../../../', import.meta.url));
  const cli = path.join(repository, 'Scripts/MiniApps/miniapp.mjs');
  assert.ok((await fs.stat(cli)).isFile(), 'The real repository CLI must exist.');
  const archive = path.join(f.root, 'MiniApp.hanlinNativeScript');
  const reportPath = path.join(f.root, 'report.json');
  const build = spawnSync(process.execPath, [cli, 'build', '--engine', 'nativescript', '--sdk', f.sdk,
    '--project', f.project, '--archive', archive, '--report', reportPath], {
      encoding: 'utf8', cwd: path.join(f.sdk, 'original'),
      env: {...process.env, HANLIN_AUTHORING_TYPESCRIPT: 'typescript'}
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
  // The ordinary CLI must also load the compiler from its supplied SDK without
  // inheriting this test process's optional compiler override.
  const ordinaryEnvironment = {...process.env};
  delete ordinaryEnvironment.HANLIN_AUTHORING_TYPESCRIPT;
  const validate = spawnSync(process.execPath, [cli, 'validate', '--engine', 'nativescript',
    '--sdk', f.sdk, '--project', extracted], {encoding: 'utf8', env: ordinaryEnvironment});
  assert.equal(validate.status, 0, validate.stderr + validate.stdout);
  assert.equal(JSON.parse(validate.stdout).sdk.compilerVersion, ts.version);
  const map = JSON.parse(await fs.readFile(path.join(extracted, 'nativescript/app/modules/index.mjs.map')));
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


test('NativeScript preserves the original npm runtime package rather than leaving an unresolved bare import', async t => {
  const f = await fixture(t);
  await fs.writeFile(path.join(f.project, 'package.json'), JSON.stringify({name: 'original-module-test', dependencies: {typescript: ts.version}}));
  await fs.writeFile(f.entry, 'import original from "typescript";\nexport const actualVersion: string = original.version;\n');
  const report = await f.run('build');
  assert.equal(report.succeeded, true, JSON.stringify(report));
  const app = path.join(report.preparedPackagePath, 'nativescript/app');
  const copied = await fs.readFile(path.join(app, 'node_modules/typescript/lib/typescript.js'));
  assert.deepEqual(copied, await fs.readFile(path.join(compilerPackage, 'lib/typescript.js')));
  const module = await import(pathToFileURL(path.join(app, 'modules/index.mjs')).href);
  assert.equal(module.actualVersion, ts.version);
  await assert.rejects(fs.stat(path.join(app, 'node_modules/@nativescript/core')), {code: 'ENOENT'});
});

async function widgetHostActionManifest(f, parameters) {
  const file = path.join(f.project, 'script.json');
  const script = JSON.parse(await fs.readFile(file, 'utf8'));
  const sourcePath = f.engine === 'expo' ? 'bundle.js' : 'nativescript/app/bundle.mjs';
  script.entrypoints = script.entrypoints.filter(entry => entry.id !== 'widget-target');
  script.entrypoints.push({id: 'widget-target', kind: 'appIntent', sourcePath, exportedSymbol: 'runtime.Echo'});
  script.actions = [{id: 'runtime.Echo', handler: sourcePath}];
  script.widgetEngine = f.engine === 'expo' ? 'expo' : 'scriptwidget';
  await fs.writeFile(path.join(f.project, 'widget.jsx'), '$render(<text>Host action</text>);\n');
  const authorFile = path.join(f.project, 'hanlin.authoring.json');
  const author = JSON.parse(await fs.readFile(authorFile));
  author.resources = [...new Set([...author.resources, 'widget.jsx'])];
  await fs.writeFile(authorFile, JSON.stringify(author));
  script.hanlinWidget = {abiVersion: 1, sourceFormat: 'tsx', families: ['systemSmall'], actions: [
    {id: 'continue', kind: 'hostAction', hostAction: {entrypointID: 'widget-target', actionName: 'runtime.Echo',
      ...(parameters === undefined ? {} : {parameters})}},
    {id: 'local', kind: 'reload'}
  ]};
  await fs.writeFile(file, JSON.stringify(script));
  return script;
}

test('widget Host metadata validates both app engines and preserves ordinary JSON or explicit null through build', async t => {
  const payload = {unicode: 'שלום🙂', values: [true, null, 41], type: 'object', value: {ordinary: 'JSON'}};
  for (const engine of ['nativescript', 'expo']) {
    const f = {...await fixture(t, engine), engine};
    for (const parameters of [payload, null, undefined]) {
      await widgetHostActionManifest(f, parameters);
      const report = await f.run(engine === 'nativescript' ? 'build' : 'validate');
      assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
      if (report.preparedPackagePath) {
        const built = JSON.parse(await fs.readFile(path.join(report.preparedPackagePath, 'script.json')));
        const target = built.hanlinWidget.actions[0].hostAction;
        assert.equal(Object.hasOwn(target, 'parameters'), parameters !== undefined);
        assert.deepEqual(target.parameters, parameters);
        assert.equal(target.actionName, 'runtime.Echo');
        assert.equal(built.hanlinWidget.actions[1].kind, 'reload');
        const widget = await fs.readFile(path.join(f.project, 'widget.jsx'), 'utf8');
        assert.equal(await fs.readFile(path.join(report.preparedPackagePath, 'widget.jsx'), 'utf8'), widget);
        assert.equal(await fs.readFile(path.join(report.preparedPackagePath, 'nativescript/app/modules/widget.jsx'), 'utf8'), widget);
      }
    }
  }
});

test('invalid widget Host declarations return structured diagnostics and never create a package', async t => {
  const f = {...await fixture(t), engine: 'nativescript'};
  const original = await widgetHostActionManifest(f, {challenge: 'actual'});
  const invalid = [
    ['missing target', script => { delete script.hanlinWidget.actions[0].hostAction; }],
    ['widget identity UTF-8 contract', script => { script.hanlinWidget.actions[0].id = 'א'.repeat(129); }],
    ['target identity UTF-8 contract', script => { script.hanlinWidget.actions[0].hostAction.entrypointID = 'א'.repeat(65); }],
    ['local handler conflict', script => { script.hanlinWidget.actions[0].handler = 'local'; }],
    ['local kind conflict', script => { script.hanlinWidget.actions[0].kind = 'reload'; }],
    ['missing entrypoint', script => { script.hanlinWidget.actions[0].hostAction.entrypointID = 'absent'; }],
    ['non-intent entrypoint', script => { script.entrypoints[1].kind = 'share'; }],
    ['duplicate entrypoint', script => { script.entrypoints.push({...script.entrypoints[1]}); }],
    ['undeclared action', script => { script.actions = []; }],
    ['duplicate action', script => { script.actions.push({...script.actions[0]}); }],
    ['wrong handler', script => { script.actions[0].handler = 'another/bundle.mjs'; }],
    ['wrong exported symbol', script => { script.entrypoints[1].exportedSymbol = 'anotherAction'; }],
    ['invalid canonical action ID', script => {
      script.actions[0].id = script.entrypoints[1].exportedSymbol =
        script.hanlinWidget.actions[0].hostAction.actionName = 'two..separators';
    }],
    ['duplicate widget action', script => { script.hanlinWidget.actions.push({...script.hanlinWidget.actions[0]}); }],
    ['native panel', script => {
      script.nativePresentations = {panel: {engine: 'scriptwidget', sourcePath: 'missing.tsx',
        sourceFormat: 'tsx', actions: [script.hanlinWidget.actions[0]]}};
    }]
  ];
  for (const [label, change] of invalid) {
    const script = structuredClone(original);
    change(script);
    await fs.writeFile(path.join(f.project, 'script.json'), JSON.stringify(script));
    const report = await f.run('build');
    assert.equal(report.succeeded, false, label);
    assert.equal(report.preparedPackagePath, undefined, label);
    assert(report.diagnostics.some(item => item.code === 'MINIAPP_WIDGET_HOST_ACTION_INVALID'
      && item.file === 'script.json' && item.category === 'error'), label + ': ' + JSON.stringify(report));
  }
  const overflow = JSON.stringify({...original, marker: 1}).replace('"marker":1', '"marker":1e400')
    .replace('"challenge":"actual"', '"challenge":1e400');
  await fs.writeFile(path.join(f.project, 'script.json'), overflow);
  const report = await f.run('build');
  assert.equal(report.succeeded, false);
  assert(report.diagnostics.some(item => item.code === 'MINIAPP_WIDGET_HOST_ACTION_INVALID' && /finite/.test(item.message)));
  await assert.rejects(fs.stat(path.join(f.project, '.hanlin-build')), {code: 'ENOENT'});
});

test('the exported system-surface declaration is checked by the real TypeScript compiler', async t => {
  const f = await fixture(t);
  const repository = process.env.HANLIN_MINIAPP_REPOSITORY_ROOT
    ?? fileURLToPath(new URL('../../../../../../', import.meta.url));
  const directory = path.join(f.sdk, 'original/node_modules/@hanlin/system-surfaces');
  await fs.mkdir(directory, {recursive: true});
  await fs.copyFile(path.join(repository, 'Scripts/MiniApps/native-presentations.d.ts'), path.join(directory, 'index.d.ts'));
  await fs.copyFile(path.join(repository, 'Scripts/MiniApps/system-surfaces/package.json'), path.join(directory, 'package.json'));
  const manifestPath = path.join(f.sdk, 'miniapp-sdk.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath));
  manifest.engines.nativescript.packageVersions['@hanlin/system-surfaces'] = '1.0.0';
  await fs.writeFile(manifestPath, JSON.stringify(manifest));
  const valid = 'import type {WidgetAction, NativePresentationAction} from "@hanlin/system-surfaces";\n'
    + 'export const action: WidgetAction = {id:"run",kind:"hostAction",hostAction:{entrypointID:"intent",actionName:"runtime.Echo",parameters:null}};\n'
    + 'export const local: NativePresentationAction = {id:"refresh",kind:"reload"};\n';
  await fs.writeFile(f.entry, valid);
  assert.equal((await f.run('validate')).succeeded, true);
  for (const source of [
    valid.replace('parameters:null', 'parameters:()=>42'),
    valid.replace('hostAction:{', 'handler:"invented",hostAction:{'),
    valid.replace('action: WidgetAction', 'action: NativePresentationAction')
  ]) {
    await fs.writeFile(f.entry, source);
    const result = await f.run('validate');
    assert.equal(result.succeeded, false);
    assert(result.diagnostics.some(item => ['TS2322', 'TS2353'].includes(item.code)), JSON.stringify(result));
    assert(!result.diagnostics.some(item => item.code === 'TS2307'), 'The exported original declaration must resolve.');
  }
});

test('prepared capture and Spotlight actions validate against each containing app engine', async t => {
  for (const engine of ['nativescript', 'expo']) {
    const f = await fixture(t, engine);
    const file = path.join(f.project, 'script.json');
    const source = engine === 'expo' ? 'bundle.js' : 'nativescript/app/bundle.mjs';
    const script = JSON.parse(await fs.readFile(file));
    script.entrypoints = [
      {id: 'photo', kind: 'capture', sourcePath: source, exportedSymbol: 'capture.receive'},
      {id: 'find', kind: 'spotlight', sourcePath: source}
    ];
    script.actions = [{id: 'capture.receive', handler: source}];
    await fs.writeFile(file, JSON.stringify(script));
    const report = await f.run('validate');
    assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
  }
});

test('invalid prepared capture actions stop packaging with actionable source diagnostics', async t => {
  const f = await fixture(t);
  const file = path.join(f.project, 'script.json');
  const original = JSON.parse(await fs.readFile(file));
  original.entrypoints = [{id: 'photo', kind: 'capture', sourcePath: 'nativescript/app/bundle.mjs', exportedSymbol: 'capture.receive'}];
  original.actions = [{id: 'capture.receive', handler: 'nativescript/app/bundle.mjs'}];
  for (const [label, mutate] of [
    ['missing exported action', s => { delete s.entrypoints[0].exportedSymbol; }],
    ['undeclared action', s => { s.actions = []; }],
    ['wrong handler', s => { s.actions[0].handler = 'other.js'; }],
    ['duplicate action', s => { s.actions.push({...s.actions[0]}); }],
    ['invalid action ID', s => { s.entrypoints[0].exportedSymbol = s.actions[0].id = 'wrong..id'; }],
    ['Spotlight wrong action', s => { s.entrypoints[0].kind = 'spotlight'; s.actions[0].handler = 'other.js'; }]
  ]) {
    const script = structuredClone(original); mutate(script);
    await fs.writeFile(file, JSON.stringify(script));
    const report = await f.run('build');
    assert.equal(report.succeeded, false, label);
    assert.equal(report.preparedPackagePath, undefined, label);
    assert(report.diagnostics.some(d => d.code === 'MINIAPP_SYSTEM_ACTION_INVALID' &&
      d.file === 'script.json' && d.category === 'error' && d.remediation), label + ': ' + JSON.stringify(report));
  }
  await assert.rejects(fs.stat(path.join(f.project, '.hanlin-build')), {code: 'ENOENT'});
});

test('system native presentations require keyboard and notification source declarations', async t => {
  const f = await fixture(t);
  const file = path.join(f.project, 'script.json');
  const script = JSON.parse(await fs.readFile(file));
  script.entrypoints = [
    {id: 'keys', kind: 'keyboard', sourcePath: 'nativescript/app/bundle.mjs'},
    {id: 'notice', kind: 'notificationUI', sourcePath: 'nativescript/app/bundle.mjs'}
  ];
  await fs.writeFile(file, JSON.stringify(script));
  const report = await f.run('build');
  assert.equal(report.succeeded, false);
  const diagnostics = report.diagnostics.filter(d => d.code === 'MINIAPP_SYSTEM_PRESENTATION_REQUIRED');
  assert.equal(diagnostics.length, 2, JSON.stringify(report.diagnostics));
  assert(diagnostics.every(d => d.file === 'script.json' && d.category === 'error'));
  assert.equal(report.preparedPackagePath, undefined);
});

async function preparedAssistantToolManifest(f, engine) {
  const file = path.join(f.project, 'script.json');
  const script = JSON.parse(await fs.readFile(file));
  const sourcePath = engine === 'expo' ? 'bundle.js' : 'nativescript/app/bundle.mjs';
  script.entrypoints = [{id: 'summarize', kind: 'assistantTool', sourcePath, exportedSymbol: 'text.Summarize'}];
  script.actions = [{
    id: 'text.Summarize', title: 'Summarize text', summary: 'Return the requested summary.',
    description: 'The explicit summary wins over this description.', handler: sourcePath,
    inputSchema: {$schema: 'https://json-schema.org/draft/2020-12/schema', type: 'object',
      $defs: {text: {type: 'string'}}, properties: {text: {$ref: '#/$defs/text'}}, required: ['text']},
    outputSchema: {$schema: 'http://json-schema.org/draft-07/schema#', type: 'object',
      properties: {summary: {type: 'string'}}, required: ['summary']}
  }];
  await fs.writeFile(file, JSON.stringify(script));
  return script;
}

test('prepared assistant tools preserve action schemas and validate both containing app engines', async t => {
  for (const engine of ['nativescript', 'expo']) {
    const f = await fixture(t, engine);
    const script = await preparedAssistantToolManifest(f, engine);
    // Preserve the existing handler-preferred alias semantics.
    script.actions[0].entrypoint = 'unused-alias.js';
    await fs.writeFile(path.join(f.project, 'script.json'), JSON.stringify(script));
    const report = await f.run(engine === 'nativescript' ? 'build' : 'validate');
    assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
    assert.equal(report.typecheck.strict, true);
    if (report.preparedPackagePath) {
      const prepared = JSON.parse(await fs.readFile(path.join(report.preparedPackagePath, 'script.json')));
      assert.deepEqual(prepared.actions, script.actions);
      assert.deepEqual(prepared.entrypoints, script.entrypoints);
      assert.equal(prepared.entry, script.entrypoints[0].sourcePath);
      assert.equal((await fs.stat(path.join(report.preparedPackagePath, prepared.entry))).isFile(), true);
    }
    // Parameters follow the canonical function-tool object contract; results do not.
    for (const outputSchema of [{type: 'string'}, {type: 'array', items: {type: 'number'}}]) {
      script.actions[0] = {id: 'text.Summarize', entrypoint: script.entrypoints[0].sourcePath,
        inputSchema: {type: 'object'}, outputSchema};
      await fs.writeFile(path.join(f.project, 'script.json'), JSON.stringify(script));
      const alias = await f.run('validate');
      assert.equal(alias.succeeded, true, JSON.stringify(alias.diagnostics));
    }
  }
});

test('invalid prepared assistant tools reject missing or ambiguous actions and schemas before packaging', async t => {
  for (const engine of ['nativescript', 'expo']) {
    const f = await fixture(t, engine);
    const original = await preparedAssistantToolManifest(f, engine);
    for (const [label, mutate] of [
      ['missing symbol', s => { delete s.entrypoints[0].exportedSymbol; }],
      ['unknown action', s => { s.entrypoints[0].exportedSymbol = 'unknown.Action'; }],
      ['duplicate action', s => { s.actions.push({...s.actions[0]}); }],
      ['duplicate entrypoint', s => { s.entrypoints.push({...s.entrypoints[0]}); }],
      ['missing handler', s => { delete s.actions[0].handler; }],
      ['wrong handler', s => { s.actions[0].handler = 'other.js'; }],
      ['nonforeground source', s => { s.entrypoints[0].sourcePath = s.actions[0].handler = 'other.js'; }],
      ['missing input schema', s => { delete s.actions[0].inputSchema; }],
      ['missing parameter object type', s => { s.actions[0].inputSchema = {}; }],
      ['scalar parameters', s => { s.actions[0].inputSchema = {type: 'string'}; }],
      ['array parameters', s => { s.actions[0].inputSchema = {type: 'array', items: {type: 'string'}}; }],
      ['array input schema', s => { s.actions[0].inputSchema = []; }],
      ['null input schema', s => { s.actions[0].inputSchema = null; }],
      ['boolean output schema', s => { s.actions[0].outputSchema = false; }],
      ['null output schema', s => { s.actions[0].outputSchema = null; }]
    ]) {
      const script = structuredClone(original); mutate(script);
      await fs.writeFile(path.join(f.project, 'script.json'), JSON.stringify(script));
      const report = await f.run('build');
      assert.equal(report.succeeded, false, engine + ': ' + label);
      assert.equal(report.preparedPackagePath, undefined, label);
      assert(report.diagnostics.some(d => d.code === 'MINIAPP_ASSISTANT_TOOL_INVALID'
        && d.file === 'script.json' && d.category === 'error' && d.remediation), label + ': ' + JSON.stringify(report));
    }
    await assert.rejects(fs.stat(path.join(f.project, '.hanlin-build')), {code: 'ENOENT'});
  }
});

test('prepared assistant tool guide and public declarations use the real strict TypeScript compiler', async t => {
  const f = await fixture(t);
  const repository = process.env.HANLIN_MINIAPP_REPOSITORY_ROOT
    ?? fileURLToPath(new URL('../../../../../../', import.meta.url));
  const directory = path.join(f.sdk, 'original/node_modules/@hanlin/system-surfaces');
  await fs.mkdir(directory, {recursive: true});
  await fs.copyFile(path.join(repository, 'Scripts/MiniApps/native-presentations.d.ts'), path.join(directory, 'index.d.ts'));
  await fs.copyFile(path.join(repository, 'Scripts/MiniApps/system-surfaces/package.json'), path.join(directory, 'package.json'));
  const manifestPath = path.join(f.sdk, 'miniapp-sdk.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath));
  manifest.engines.nativescript.packageVersions['@hanlin/system-surfaces'] = '1.0.0';
  await fs.writeFile(manifestPath, JSON.stringify(manifest));
  const guide = await fs.readFile(path.join(repository, 'docs/miniapp-sdk/SYSTEM_SURFACE_ACTIONS.md'), 'utf8');
  const startMarker = '<!-- assistant-tool-authoring-example:start -->';
  const endMarker = '<!-- assistant-tool-authoring-example:end -->';
  assert.equal(guide.split(startMarker).length, 2);
  assert.equal(guide.split(endMarker).length, 2);
  const section = guide.split(startMarker)[1].split(endMarker)[0];
  const fence = String.fromCharCode(96).repeat(3);
  const source = section.split(fence + 'ts\n')[1]?.split(fence)[0];
  assert(source && source.trim(), 'The shipped authoring example must be present.');
  const resultSchemas = [
    'export const scalarResult: PreparedAssistantToolAction = {id:"text.Scalar",handler:"bundle.js",inputSchema:{type:"object"},outputSchema:{type:"string"}};',
    'export const arrayResult: PreparedAssistantToolAction = {id:"text.Array",handler:"bundle.js",inputSchema:{type:"object"},outputSchema:{type:"array",items:{type:"number"}}};'
  ].join('\n');
  await fs.writeFile(f.entry, source + '\n' + resultSchemas + '\n');
  const valid = await f.run('validate');
  assert.equal(valid.succeeded, true, JSON.stringify(valid.diagnostics));
  assert.equal(valid.typecheck.strict, true);
  assert.equal(valid.typecheck.skipLibCheck, false);
  const imports = 'import type {PreparedMiniAppEntrypoint, PreparedAssistantToolAction} from "@hanlin/system-surfaces";\n';
  for (const invalid of [
    'export const entry: PreparedMiniAppEntrypoint = {id:"tool",kind:"assistantTool",sourcePath:"bundle.js"};',
    'export const action: PreparedAssistantToolAction = {id:"text.Summarize",handler:"bundle.js"};',
    'export const action: PreparedAssistantToolAction = {id:"text.Summarize",handler:"bundle.js",inputSchema:[]};',
    'export const action: PreparedAssistantToolAction = {id:"text.Summarize",inputSchema:{type:"object"}};',
    'export const action: PreparedAssistantToolAction = {id:"text.Summarize",handler:"bundle.js",inputSchema:{}};',
    'export const action: PreparedAssistantToolAction = {id:"text.Summarize",handler:"bundle.js",inputSchema:{type:"string"}};',
    'export const action: PreparedAssistantToolAction = {id:"text.Summarize",handler:"bundle.js",inputSchema:{type:"array",items:{type:"string"}}};'
  ]) {
    await fs.writeFile(f.entry, imports + invalid + '\n');
    const result = await f.run('validate');
    assert.equal(result.succeeded, false, invalid);
    assert(result.diagnostics.some(d => ['TS2322', 'TS2741'].includes(d.code)), JSON.stringify(result.diagnostics));
    assert(!result.diagnostics.some(d => d.code === 'TS2307'), 'The actual public declarations must resolve.');
  }
});
