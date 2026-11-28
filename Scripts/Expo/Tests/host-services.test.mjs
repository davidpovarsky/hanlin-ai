import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import vm from 'node:vm';
import ts from '../node_modules/typescript/lib/typescript.js';

const require = createRequire(new URL('../package.json', import.meta.url));
const moduleSources = new Map(await Promise.all(
  ['host-services', 'miniapp-actions', 'miniapp-assistant'].map(async name => [
    './' + name,
    await readFile(new URL('../../../Packages/HanlinExpoUI/src/' + name + '.ts', import.meta.url), 'utf8'),
  ])));
function facade(native) {
  const modules = new Map();
  function load(name) {
    if (name === 'base64-js') return require(name);
    if (name === 'expo') return {requireNativeModule(name) {
      assert.equal(name, 'HanlinHostServices'); return native;
    }};
    if (modules.has(name)) return modules.get(name);
    assert.ok(moduleSources.has(name), 'Unexpected facade dependency: ' + name);
    const compiled = ts.transpileModule(moduleSources.get(name), {reportDiagnostics: true,
      compilerOptions: {strict: true, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}});
    assert.equal(compiled.diagnostics.length, 0);
    const exports = {};
    modules.set(name, exports);
    // Load the real shared facade modules. Deliberately no browser atob/btoa or Node Buffer.
    vm.runInNewContext(compiled.outputText, {exports, Uint8Array, Date, require: load});
    return exports;
  }
  return load('./host-services').hostServices;
}

test('file bytes roundtrip without browser globals, including empty and all byte values', async () => {
  const files = new Map();
  const host = facade({async invoke(operation, json) {
    const payload = JSON.parse(json);
    assert.equal(payload.area, 'documents');
    if (operation === 'files.write') { files.set(payload.path, payload.base64); return '{"ok":true}'; }
    assert.equal(operation, 'files.read');
    return JSON.stringify({base64: files.get(payload.path) ?? null});
  }});
  for (const bytes of [new Uint8Array(0), Uint8Array.from({length: 256}, (_, i) => i),
    Uint8Array.from({length: 131_073}, (_, i) => i % 256)]) {
    await host.writeFile('roundtrip.bin', bytes, 'documents');
    const actual = await host.readFile('roundtrip.bin', 'documents');
    assert.deepEqual([...actual], [...bytes]);
  }
  assert.equal(await host.readFile('missing.bin', 'documents'), null);
});

test('native rejection is preserved; absent Base64 stays distinct from empty data', async () => {
  const expected = new Error('native fixture rejection');
  await assert.rejects(facade({async invoke() { throw expected; }}).writeFile('x', new Uint8Array()), error => error === expected);
  assert.equal(await facade({async invoke() { return '{}'; }}).readFile('missing'), null);
  assert.deepEqual([...await facade({async invoke() { return '{"base64":""}'; }}).readFile('empty')], []);
});

test('Expo assistant uses the actual shared facade through the bound native module', async () => {
  const calls = [];
  const events = [{type: 'text', text: 'native reply'},
    {type: 'finish', finishReason: 'stop', usage: {cachedInputTokens: 8, cacheWriteTokens: 3}}];
  const host = facade({async invoke(operation, json) {
    calls.push({operation, payload: JSON.parse(json)});
    return JSON.stringify(operation === 'assistant.start' ? {requestID: 'expo-owned'} : {event: events.shift()});
  }});
  const result = await host.assistant.generate({messages: [{role: 'user', content: 'hello'}]});
  assert.equal(result.text, 'native reply');
  assert.equal(result.usage.cachedInputTokens, 8);
  assert.equal(result.usage.cacheWriteTokens, 3);
  assert.deepEqual(calls.map(call => call.operation), ['assistant.start', 'assistant.next', 'assistant.next']);
  assert.ok(calls.slice(1).every(call => call.payload.requestID === 'expo-owned'));
});
