import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import ts from '../node_modules/typescript/lib/typescript.js';

const source = await readFile(new URL('../host-services.ts', import.meta.url), 'utf8');
function facade(bridge) {
  const compiled = ts.transpileModule(source, {reportDiagnostics: true,
    compilerOptions: {strict: true, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}});
  assert.equal(compiled.diagnostics.length, 0);
  const exports = {};
  vm.runInNewContext(compiled.outputText, {exports, HanlinNativeServicesBridge: {activeSessionBridge: () => bridge}});
  return exports;
}
const receipt = () => ({executionID: 'beef1234-1234-1234-1234-123456789abc', stdout: '', stderr: '',
  durationMilliseconds: 0, didTimeOut: false, wasCancelled: false, outputWasTruncated: false});

test('Swift-shaped receipts preserve all values, binary-output descriptors and failure exit codes', () => {
  const body = {...receipt(), value: {nested: [null, true, 3, 'value']}, exitCode: -9,
    outputFiles: {stdout: {path: 'job/stdout.bin', bytes: 256, sha256: 'a'.repeat(64)}}};
  assert.equal(JSON.stringify(facade(null).parseRuntimeExecutionResult(JSON.stringify(body))), JSON.stringify(body));
});

test('valid JSON with malformed required, optional or artifact fields is rejected', () => {
  const parse = facade(null).parseRuntimeExecutionResult;
  for (const body of [null, [], {}, {...receipt(), executionID: ''}, {...receipt(), stdout: 0},
    {...receipt(), didTimeOut: 0}, {...receipt(), durationMilliseconds: -1},
    {...receipt(), exitCode: 1.5}, {...receipt(), value: Infinity}, {...receipt(), outputFiles: null},
    {...receipt(), outputFiles: {x: {path: 'x', bytes: -1, sha256: 'a'.repeat(64)}}},
    {...receipt(), outputFiles: {x: {path: 'x', bytes: 1, sha256: 'missing'}}}]) {
    // JSON converts Infinity to null; use an actual JSON overflow number.
    const json = body?.value === Infinity ? JSON.stringify(body).replace('"value":null', '"value":1e400') : JSON.stringify(body);
    assert.throws(() => parse(json), /invalid/i);
  }
  assert.throws(() => parse('{'), /invalid receipt JSON/);
});

test('production facade validates callback receipts and preserves bound native errors', async () => {
  for (const [body, nativeError, message] of [['{}', null, /invalid execution receipt/],
    [null, null, /no execution receipt/], ['{', null, /invalid receipt JSON/],
    [JSON.stringify(receipt()), 'Native failure', /Native failure/]]) {
    const host = facade({executeRuntimeCompletion(payload, completion) { completion(body, nativeError); return 'request-1'; }}).createHostServices();
    await assert.rejects(host.executeRuntime('node', '42'), message);
  }
});

test('request and cancellation stay on the captured session bridge', async () => {
  const cancelled = [];
  let callback;
  const host = facade({executeRuntimeCompletion(payload, completion) {
    assert.deepEqual(JSON.parse(payload), {kind: 'typeScript', source: '42', arguments: ['x']});
    callback = completion;
    return 'owned-request';
  }, cancelRuntime(id) { cancelled.push(id); return true; }}).createHostServices();
  const handle = host.startRuntime('typeScript', '42', {arguments: ['x']});
  assert.equal(handle.requestID, 'owned-request');
  assert.equal(handle.cancel(), true);
  assert.deepEqual(cancelled, ['owned-request']);
  callback(JSON.stringify(receipt()), null);
  assert.equal((await handle.result).executionID, receipt().executionID);
});
