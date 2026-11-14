import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import vm from 'node:vm';
import ts from '../node_modules/typescript/lib/typescript.js';

const require = createRequire(new URL('../package.json', import.meta.url));
const source = await readFile(new URL('../../../Packages/HanlinExpoUI/src/host-services.ts', import.meta.url), 'utf8');
function facade(native) {
  const compiled = ts.transpileModule(source, {reportDiagnostics: true,
    compilerOptions: {strict: true, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}});
  assert.equal(compiled.diagnostics.length, 0);
  const exports = {};
  // Deliberately no browser atob/btoa and no Node Buffer in the JS context.
  vm.runInNewContext(compiled.outputText, {exports, Uint8Array, Date, require(name) {
    if (name === 'base64-js') return require(name);
    assert.equal(name, 'expo');
    return {requireNativeModule(name) { assert.equal(name, 'HanlinHostServices'); return native; }};
  }});
  return exports.hostServices;
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
