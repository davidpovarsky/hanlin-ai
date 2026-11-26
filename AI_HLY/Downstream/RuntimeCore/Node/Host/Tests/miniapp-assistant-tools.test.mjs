import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readFile, rm} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {pathToFileURL} from 'node:url';
import {assistantToolSourceEntries, assistantToolWrapper, validateAssistantToolManifest, validateComposerConfiguration} from '../miniapp-assistant-tools.mjs';

function manifest(engine = 'expo') {
  return {
    entry: engine === 'expo' ? 'bundle.js' : 'nativescript/app/bundle.mjs',
    entrypoints: [{
      id: 'echo-tool', kind: 'assistantTool',
      sourcePath: 'assistant/echo/' + (engine === 'expo' ? 'bundle.js' : 'bundle.mjs'),
      assistantTool: {
        title: 'Echo', summary: 'Echo the configured request',
        actions: [{id: 'echo', title: 'Echo', summary: 'Echo arguments and configuration',
          inputSchema: {type: 'object', properties: {query: {type: 'string'}}, required: ['query']}}],
        configuration: {panels: [{id: 'search', title: 'Search', fields: [
          {key: 'scope', title: 'Scope', kind: 'choice', required: true, defaultValue: 'user-picked',
            options: [{id: 'user-picked', title: 'Selected collection'}]}
        ]}]}
      }
    }]
  };
}

test('both engines require dedicated source declarations and a real optional renderer ID', () => {
  for (const engine of ['expo', 'nativescript']) {
    const script = manifest(engine);
    assert.deepEqual(validateAssistantToolManifest(script, engine), []);
    assert.equal(assistantToolSourceEntries(script, {entry: 'index.ts', assistantTools: {'echo-tool': 'echo.ts'}}, engine).entries[0].source, 'echo.ts');
    assert.ok(assistantToolSourceEntries(script, {entry: 'index.ts', assistantTools: {'echo-tool': 'index.ts'}}, engine).diagnostics.length);
    script.entrypoints[0].assistantTool.actions[0].embeddedResultID = 'missing';
    assert.ok(validateAssistantToolManifest(script, engine).length);
    script.entrypoints.push({id: 'missing', kind: 'embeddedResult', sourcePath: script.entry});
    assert.deepEqual(validateAssistantToolManifest(script, engine), []);
    script.entrypoints[0].sourcePath = script.entry;
    assert.ok(validateAssistantToolManifest(script, engine).length);
  }
});

test('malformed IDs, action schemas and renderer metadata cannot become attachable capabilities', () => {
  for (const mutate of [
    action => { action.id = 'non+canonical'; },
    action => { action.id = 'searchText\n'; },
    action => { action.id = 'שאל'; },
    action => { action.id = 'A'.repeat(256); },
    action => { action.id = 'two..separators'; },
    action => { action.inputSchema = {type: 'array'}; },
    action => { action.exportedSymbol = ''; },
    action => { action.outputSchema = []; },
    action => { action.embeddedResultID = 'unknown'; }
  ]) {
    const script = manifest(); mutate(script.entrypoints[0].assistantTool.actions[0]);
    assert.ok(validateAssistantToolManifest(script, 'expo').length);
  }
  const script = manifest();
  script.entrypoints[0].assistantTool.actions = [];
  assert.ok(validateAssistantToolManifest(script, 'expo').length);
  assert.ok(validateAssistantToolManifest(manifest(), 'scriptwidget').length);
});

test('case-distinct assistant action IDs dispatch separately through both generated wrappers', async t => {
  for (const engine of ['nativescript', 'expo']) {
    const script = manifest(engine), entry = script.entrypoints[0];
    const action = entry.assistantTool.actions[0];
    entry.assistantTool.actions = [
      {...action, id: 'searchText'},
      {...action, id: 'searchtext', exportedSymbol: 'lowerHandler'}
    ];
    assert.deepEqual(validateAssistantToolManifest(script, engine), []);
    const duplicate = structuredClone(script);
    duplicate.entrypoints[0].assistantTool.actions[1].id = 'searchText';
    assert.ok(validateAssistantToolManifest(duplicate, engine).length);

    const root = await mkdtemp(path.join(os.tmpdir(), 'hanlin-assistant-case-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    await writeFile(path.join(root, 'tool.mjs'),
      'export function searchText(args, context) { globalThis.__hanlinAssistantCaseFixture.calls++; return {handler:"camel", args, ...context}; }\n'
      + 'export function lowerHandler(args, context) { globalThis.__hanlinAssistantCaseFixture.calls++; return {handler:"lower", args, ...context}; }\n');
    await writeFile(path.join(root, 'index.mjs'), 'throw new Error("APP_ENTRYPOINT_MUST_NOT_RUN");\n');
    await writeFile(path.join(root, 'bundle.mjs'), assistantToolWrapper(entry, './tool.mjs', engine));

    // Stub only the existing transports; execute the original generated wrapper
    // without rewriting its imports, registrations or action-dispatch function.
    const state = {handlers: new Map(), calls: 0, componentName: null, component: null};
    const previousState = globalThis.__hanlinAssistantCaseFixture;
    const previousBridge = globalThis.HanlinNativeServicesBridge;
    globalThis.__hanlinAssistantCaseFixture = state;
    globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => ({
      registerRequestHandlerCapabilityHandler: (id, capability, handler) => {
        assert.equal(capability, 'assistant-tool'); state.handlers.set(id, handler);
      }
    })};
    try {
      if (engine === 'expo') {
        const packages = [
          ['react-native', 'export const AppRegistry = {registerComponent(name, provider) { const state = globalThis.__hanlinAssistantCaseFixture; state.componentName = name; state.component = provider(); }};\n'],
          ['@hanlin/expo-ui', 'export const hostServices = {actions: {register(handlers) { globalThis.__hanlinAssistantCaseFixture.handlers = new Map(Object.entries(handlers)); return Promise.resolve(); }}};\n']
        ];
        for (const [name, source] of packages) {
          const directory = path.join(root, 'node_modules', name);
          await mkdir(directory, {recursive: true});
          await writeFile(path.join(directory, 'package.json'), JSON.stringify({name, type: 'module', exports: './index.mjs'}));
          await writeFile(path.join(directory, 'index.mjs'), source);
        }
      }
      await import(pathToFileURL(path.join(root, 'bundle.mjs')).href);
      assert.deepEqual([...state.handlers.keys()], ['searchText', 'searchtext']);
      assert.equal(state.calls, 0);
      if (engine === 'expo') {
        assert.equal(state.componentName, 'HanlinAssistantTool');
        assert.equal(state.component(), null);
      }
      const envelope = {arguments: {query: 'text'}, configuration: {scope: 'user-picked'}};
      const call = id => engine === 'expo'
        ? state.handlers.get(id)({caller: 'case-test', parameters: envelope})
        : new Promise((resolve, reject) => state.handlers.get(id)('case-test', JSON.stringify(envelope),
          (result, error) => error ? reject(new Error(error)) : resolve(JSON.parse(result))));
      for (const [id, handler] of [['searchText', 'camel'], ['searchtext', 'lower']]) {
        assert.deepEqual(await call(id), {
          handler, args: envelope.arguments, configuration: envelope.configuration, actionID: id, caller: 'case-test'
        });
      }
      assert.equal(state.calls, 2);
      assert.equal(state.handlers.has('SearchText'), false);
      assert.equal(state.handlers.has('lowerHandler'), false);
    } finally {
      if (previousState === undefined) delete globalThis.__hanlinAssistantCaseFixture;
      else globalThis.__hanlinAssistantCaseFixture = previousState;
      if (previousBridge === undefined) delete globalThis.HanlinNativeServicesBridge;
      else globalThis.HanlinNativeServicesBridge = previousBridge;
    }
  }
});

test('configuration validates nested catalogs, unique keys and geographic bounds', () => {
  const configuration = {schemaVersion: 1, panels: [{id: 'map', title: 'Map', fields: [
    {key: 'area', title: 'Area', kind: 'location', defaultValue: {latitude: 31, longitude: 35, radiusMeters: 1000}, minimum: 100, maximum: 5000},
    {key: 'books', title: 'Books', kind: 'catalog', defaultValue: ['genesis'],
      options: [{id: 'torah', title: 'Torah', children: [{id: 'genesis', title: 'Genesis'}]}]}
  ]}]};
  assert.deepEqual(validateComposerConfiguration(configuration), []);
  configuration.panels[0].fields[0].defaultValue.latitude = 91;
  assert.ok(validateComposerConfiguration(configuration).some(message => message.includes('coordinate')));
  configuration.panels[0].fields[1].defaultValue = ['missing'];
  assert.ok(validateComposerConfiguration(configuration).some(message => message.includes('catalog')));
  configuration.panels.push({id: 'another', title: 'Another', fields: [{key: 'area', title: 'Repeated', kind: 'text'}]});
  assert.ok(validateComposerConfiguration(configuration).some(message => message.includes('unique')));
  configuration.schemaVersion = 2;
  assert.ok(validateComposerConfiguration(configuration).some(message => message.includes('schemaVersion')));
});

test('generated NativeScript wrapper registers only declared actions and preserves separate configuration', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'hanlin-assistant-wrapper-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const source = 'export function echo(args, context) { return {args, configuration:context.configuration, actionID:context.actionID, caller:context.caller}; }\n'
    + 'export function notDeclared() { throw new Error("UNDECLARED"); }\n';
  await writeFile(path.join(root, 'tool.mjs'), source);
  await writeFile(path.join(root, 'index.mjs'), 'throw new Error("APP_ENTRYPOINT_MUST_NOT_RUN");\n');
  await writeFile(path.join(root, 'bundle.mjs'), assistantToolWrapper(manifest('nativescript').entrypoints[0], './tool.mjs', 'nativescript'));
  const handlers = new Map();
  const previous = globalThis.HanlinNativeServicesBridge;
  globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => ({
    registerRequestHandlerCapabilityHandler: (id, capability, callback) => {
      assert.equal(capability, 'assistant-tool'); handlers.set(id, callback);
    }
  })};
  t.after(() => { if (previous === undefined) delete globalThis.HanlinNativeServicesBridge; else globalThis.HanlinNativeServicesBridge = previous; });
  await import(pathToFileURL(path.join(root, 'bundle.mjs')).href);
  assert.deepEqual([...handlers.keys()], ['echo']);
  const response = await new Promise((resolve, reject) => handlers.get('echo')('test-caller',
    JSON.stringify({arguments: {query: 'text', configuration: 'model-guess'}, configuration: {scope: 'user-picked'}}),
    (result, error) => error ? reject(new Error(error)) : resolve(JSON.parse(result))));
  assert.deepEqual(response, {args: {query: 'text', configuration: 'model-guess'}, configuration: {scope: 'user-picked'}, actionID: 'echo', caller: 'test-caller'});
});

test('missing exports remain error handlers and non-JSON output is rejected', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'hanlin-assistant-errors-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  await writeFile(path.join(root, 'tool.mjs'), 'export function bad() { return {value:undefined}; }\n');
  const entry = manifest('nativescript').entrypoints[0];
  entry.assistantTool.actions.push({...entry.assistantTool.actions[0], id: 'bad'});
  await writeFile(path.join(root, 'bundle.mjs'), assistantToolWrapper(entry, './tool.mjs', 'nativescript'));
  const handlers = new Map(), previous = globalThis.HanlinNativeServicesBridge;
  globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => ({
    registerRequestHandlerCapabilityHandler: (id, _capability, callback) => handlers.set(id, callback)
  })};
  t.after(() => { if (previous === undefined) delete globalThis.HanlinNativeServicesBridge; else globalThis.HanlinNativeServicesBridge = previous; });
  await import(pathToFileURL(path.join(root, 'bundle.mjs')).href);
  const call = id => new Promise(resolve => handlers.get(id)('caller', '{"arguments":{},"configuration":{}}',
    (result, error) => resolve({result, error})));
  assert.match((await call('echo')).error, /Missing assistant action export/);
  assert.match((await call('bad')).error, /JSON/);
});

test('public and canonical JSON schemas share the exact assistant configuration contract', async () => {
  const repository = process.env.HANLIN_MINIAPP_REPOSITORY_ROOT
    ? pathToFileURL(path.resolve(process.env.HANLIN_MINIAPP_REPOSITORY_ROOT) + path.sep)
    : new URL('../../../../../../', import.meta.url);
  const published = JSON.parse(await readFile(new URL('Scripts/MiniApps/assistant-tools.schema.json', repository), 'utf8'));
  const canonical = JSON.parse(await readFile(new URL('Packages/HanlinPlatform/Sources/HanlinPlatformContracts/Resources/HanlinAppManifest.schema.json', repository), 'utf8'));
  for (const [name, definition] of Object.entries(published.$defs)) assert.deepEqual(canonical.$defs[name], definition, name);
  assert.deepEqual(published.$defs.assistantToolAction.properties.id, {$ref: '#/$defs/actionIdentifier'});
  const actionPattern = new RegExp(published.$defs.actionIdentifier.pattern);
  for (const id of ['searchText', 'searchtext', 'HTTPGet', 'A', 'a-B.C_D']) assert.ok(actionPattern.test(id), id);
  for (const id of ['', 'two..separators', 'searchText\n', 'שאל', 'name+suffix']) assert.equal(actionPattern.test(id), false, id);
  assert.equal(published.$defs.actionIdentifier.maxLength, 255);
  assert.equal(new RegExp(canonical.$defs.identifier.pattern).test('searchText'), false, 'General identifiers remain lowercase');
});
