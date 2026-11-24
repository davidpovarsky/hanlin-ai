import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {generateScriptWidgetManifest} from '../generate-scriptwidget-manifest.mjs';
import {validateScriptWidgetManifest} from '../scriptwidget/manifest-validation.mjs';
import {runMiniAppOperation, readMiniAppSDK} from '../../../AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const compilerLocation = process.env.HANLIN_AUTHORING_TYPESCRIPT ?? 'typescript';
const ts = (await import(compilerLocation)).default;
const schema = JSON.parse(await fs.readFile(path.join(root, 'Scripts/MiniApps/scriptwidget/widget-manifest.schema.json')));
const original = () => ({
  formatVersion: 2, id: 'test.focus-controls', name: 'Focus controls', version: '1.0.0',
  runtimeVersion: '1.0', minimumRuntimeVersion: '1.6', entry: 'main.jsx',
  supportedFamilies: ['systemSmall'], permissions: ['storage'], networkDomains: [],
  actions: [{id: 'toggle-focus', title: 'Focus', systemImage: 'moon', function: 'toggleFocus'}],
  controls: [{id: 'focus', type: 'toggle', title: 'Focus', systemImage: 'moon',
    actionID: 'TOGGLE-FOCUS', stateKey: 'focus.enabled'}]
});
const validate = manifest => validateScriptWidgetManifest({
  text: JSON.stringify(manifest, null, 2), entry: 'main.jsx', compiler: ts, schema, exists: async name => name === 'main.jsx'
});

async function fixture(t) {
  const temporary = await fs.mkdtemp(path.join(process.env.HANLIN_AUTHORING_TMP ?? os.tmpdir(), 'scriptwidget-controls-'));
  t.after(() => fs.rm(temporary, {recursive: true, force: true}));
  const sdk = path.join(temporary, 'sdk'), project = path.join(temporary, 'project');
  await fs.mkdir(project);
  await fs.mkdir(sdk);
  await fs.cp(path.join(root, 'Scripts/MiniApps/scriptwidget'), path.join(sdk, 'scriptwidget'), {recursive: true});
  await fs.writeFile(path.join(sdk, 'miniapp-sdk.json'), JSON.stringify({
    schemaVersion: 1, engines: {scriptwidget: {
      toolingRoot: 'scriptwidget', tsconfigPath: 'scriptwidget/tsconfig.json',
      packageVersions: {'everettjf/scriptwidget': schema['x-original-contract'].sources[0].commit},
      docs: ['docs/miniapp-sdk/SCRIPTWIDGET_CONTROLS.md'],
      packageManifestSchemaPath: 'scriptwidget/widget-manifest.schema.json',
      packageManifestValidatorPath: 'scriptwidget/manifest-validation.mjs'
    }}
  }));
  await fs.writeFile(path.join(project, 'script.json'), JSON.stringify({
    name: 'Focus controls', version: '1.0.0', kind: 'widget', widgetEngine: 'scriptwidget',
    hanlinRuntime: 'scripting-jsc', entry: 'main.jsx',
    hanlinWidget: {abiVersion: 1, sourceFormat: 'jsx', families: ['systemSmall'], actions: []}
  }));
  await fs.writeFile(path.join(project, 'hanlin.authoring.json'), JSON.stringify({
    schemaVersion: 1, engine: 'scriptwidget', entry: 'main.jsx', resources: ['data']
  }));
  await fs.writeFile(path.join(project, 'tsconfig.json'), JSON.stringify({
    compilerOptions: {strict: true, checkJs: false, skipLibCheck: false},
    include: ['*.jsx', '*.ts']
  }));
  const manifest = {...original(), preview: 'images/preview.png'};
  const manifestText = JSON.stringify(manifest, null, 4) + '\n\n';
  await fs.writeFile(path.join(project, 'widget.json'), manifestText);
  await fs.mkdir(path.join(project, 'images'));
  await fs.writeFile(path.join(project, 'images/preview.png'), Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6uCYAAAAASUVORK5CYII=', 'base64'));
  await fs.mkdir(path.join(project, 'data'));
  await fs.writeFile(path.join(project, 'data/config.json'), '{"actual":"resource"}\n');
  await fs.writeFile(path.join(project, 'main.jsx'), [
    '// @ts-check',
    '/** @type {(string | undefined)[]} */',
    'const controlValues = [$widget["action-source"], $widget["action-id"], $widget["control-id"], $widget["control-value"], $widget["action-value"]];',
    '/** @type {string[]} */',
    'const controlEnvironment = [$getenv("action-source"), $getenv("control-id"), $getenv("control-value"), $getenv("action-value")];',
    'function toggleFocus() {',
    '  const enabled = $getenv("control-value");',
    '  $storage.setString("focus.enabled", enabled);',
    '}',
    '$render(<vstack><text>{$storage.getString("focus.enabled") ?? "false"}</text></vstack>);', ''
  ].join('\n'));
  const run = (operation, extra = {}) => runMiniAppOperation({
    operation, projectRoot: project, ...extra
  }, {sdkRoot: sdk, compiler: ts});
  return {temporary, sdk, project, run, manifestText};
}

test('manifest declarations/schema match the installed original source and provenance', async () => {
  const result = await generateScriptWidgetManifest({root, check: true});
  assert.equal(result.runtimeVersion, '1.0');
  assert.equal(result.nativeRuntimeVersion, '1.6');
  assert.ok(schema.$defs.WidgetPackagePermission.enum.includes('storage'));
  assert.equal(schema.$defs.WidgetPackageManifest.additionalProperties, false);
  assert.deepEqual(schema.$defs.WidgetPackageControlType.enum, ['button', 'toggle']);
});

test('genuine action references, legacy controls and nullable optional fields validate', async () => {
  const manifest = original();
  manifest.controls.push({id: 'legacy', type: 'button', title: 'Legacy', systemImage: 'play',
    action: 'legacyAction', actionID: null, stateKey: null});
  const result = await validate(manifest);
  assert.deepEqual(result.diagnostics, []);
});

test('original semantic and JSON shape errors include precise manifest locations', async () => {
  const cases = [
    ['missing_control_action', m => { m.controls[0].actionID = 'missing'; }],
    ['ambiguous_control_action', m => { m.controls[0].action = 'toggleFocus'; }],
    ['invalid_control_state', m => { delete m.controls[0].stateKey; }],
    ['control_storage', m => { m.permissions = []; }],
    ['button_control_state', m => { m.controls[0].type = 'button'; }],
    ['duplicate_controls', m => { m.controls.push({...m.controls[0], id: 'FOCUS'}); }],
    ['duplicate_actions', m => { m.actions.push({...m.actions[0], id: 'TOGGLE-FOCUS'}); }],
    ['unknown_manifest_field', m => { m.controls[0].inventedHandler = 'ignored'; }],
    ['unknown_manifest_field', m => { m.$schema = 'unsupported-in-original-widget.json'; }],
    ['invalid_manifest_field', m => { m.controls[0].type = 'slider'; }],
    ['invalid_entry_type', m => { m.entry = 'main.tsx'; }],
    ['entry_mismatch', m => { m.entry = 'other.jsx'; }],
    ['invalid_control_action', m => { delete m.controls[0].actionID; m.controls[0].action = 'not.a.function'; }]
  ];
  for (const [code, mutate] of cases) {
    const manifest = original(); mutate(manifest);
    const result = await validate(manifest);
    const diagnostic = result.diagnostics.find(item => item.originalCode === code);
    assert.ok(diagnostic, code + ': ' + JSON.stringify(result.diagnostics));
    assert.equal(diagnostic.file, 'widget.json');
    assert.ok(diagnostic.line > 0 && diagnostic.column > 0 && diagnostic.jsonPath);
  }
  const malformed = await validateScriptWidgetManifest({text: '{\n"controls": [}', entry: 'main.jsx', compiler: ts, schema});
  assert.equal(malformed.diagnostics[0].originalCode, 'invalid_manifest_json');
  assert.ok(malformed.diagnostics[0].line >= 2);
});

test('build keeps exact root widget.json, original JSX, declared assets and preview in a real archive', async t => {
  const f = await fixture(t);
  const archive = path.join(f.temporary, 'controls.zip');
  const cli = spawnSync(process.execPath, [path.join(root, 'Scripts/MiniApps/miniapp.mjs'), 'build',
    '--sdk', f.sdk, '--project', f.project, '--archive', archive], {
    encoding: 'utf8', env: {...process.env, HANLIN_AUTHORING_TYPESCRIPT: compilerLocation}
  });
  assert.equal(cli.status, 0, cli.stdout + cli.stderr);
  const result = JSON.parse(cli.stdout);
  assert.equal(result.succeeded, true);
  assert.equal(result.typecheck.checkJs, true);
  assert.equal(result.typecheck.strict, true);
  assert.equal(result.typecheck.skipLibCheck, false);
  const stage = result.preparedPackagePath;
  assert.equal(await fs.readFile(path.join(stage, 'widget.json'), 'utf8'), f.manifestText);
  assert.equal(await fs.readFile(path.join(stage, 'source/widget.json'), 'utf8'), f.manifestText);
  assert.deepEqual(await fs.readFile(path.join(stage, 'images/preview.png')),
    await fs.readFile(path.join(f.project, 'images/preview.png')));
  const listing = spawnSync('python3', ['-c',
    'import json,sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); print(json.dumps(z.namelist()))', archive], {encoding: 'utf8'});
  assert.equal(listing.status, 0, listing.stderr);
  for (const name of ['widget.json', 'main.jsx', 'source/widget.json', 'data/config.json', 'images/preview.png'])
    assert.ok(JSON.parse(listing.stdout).includes(name), name);
  const author = JSON.parse(await fs.readFile(path.join(stage, 'hanlin.authoring.json')));
  assert.ok(author.compiledHashes['widget.json']);
  const check = await f.run('validate', {projectRoot: stage});
  assert.equal(check.succeeded, true, JSON.stringify(check));
  const sdk = await readMiniAppSDK(f.sdk, {engine: 'scriptwidget'});
  assert.equal(sdk.selectedEngine.packageManifestSchemaPath, 'scriptwidget/widget-manifest.schema.json');
});

test('original JSX semantic errors use the actual TypeScript compiler even with checkJs disabled in project config', async t => {
  const f = await fixture(t);
  await fs.appendFile(path.join(f.project, 'main.jsx'), '\n/** @type {number} */\nconst wrong = "wrong";\n');
  const result = await f.run('build');
  const error = result.diagnostics.find(item => item.code === 'TS2322');
  assert.ok(error, JSON.stringify(result));
  assert.equal(error.file, 'main.jsx');
  assert.ok(error.line >= 8);
  assert.equal(result.preparedPackagePath, undefined);
});

test('manifest declarations reject incorrect control shapes in the authoring type environment', async t => {
  const f = await fixture(t);
  await fs.writeFile(path.join(f.project, 'contract.ts'), [
    'const manifest: WidgetPackageManifest = ' + JSON.stringify(original()) + ';',
    'const broken: WidgetPackageControl = {id:"x", type:"toggle", title:"X", systemImage:"moon", actionID:"toggle-focus"};',
    ''
  ].join('\n'));
  const result = await f.run('validate');
  assert.equal(result.succeeded, false);
  assert.ok(result.diagnostics.some(item => item.file === 'contract.ts' && item.line === 2 && item.code === 'TS2322'), JSON.stringify(result));
  assert.ok(!result.diagnostics.some(item => item.file === 'contract.ts' && item.line === 1), JSON.stringify(result));
});


test('changed original semantic rules cannot silently publish a stale authoring validator', async t => {
  const temporary = await fs.mkdtemp(path.join(process.env.HANLIN_AUTHORING_TMP ?? os.tmpdir(), 'scriptwidget-manifest-drift-'));
  t.after(() => fs.rm(temporary, {recursive: true, force: true}));
  const relative = 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Common';
  await fs.mkdir(path.join(temporary, relative), {recursive: true});
  for (const name of ['ScriptMetadata.swift', 'ScriptWidgetPackage.swift']) {
    const originalSource = await fs.readFile(path.join(root, relative, name), 'utf8');
    await fs.writeFile(path.join(temporary, relative, name), originalSource.replace('actions.count > 16', 'actions.count > 17'));
  }
  await assert.rejects(generateScriptWidgetManifest({root: temporary}), /manifest validation changed/);
});
