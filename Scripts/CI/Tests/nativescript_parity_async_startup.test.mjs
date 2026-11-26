import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import vm from 'node:vm';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const source = readFileSync(resolve(root, 'DemoMiniApps/hanlin-script-parity/nativescript/app/bundle.mjs'), 'utf8');
const start = source.indexOf('// Helpers to invoke bridge methods');
const end = source.indexOf('// Storage helpers', start);
assert.ok(start >= 0 && end > start, 'The actual shipped host-service helpers must be found');
const helperSource = source.slice(start, end);

const operations = [
  { name: 'runJS', selector: 'executeJavaScriptCompletion', alias: 'executeJavaScript', args: ['jsc source'] },
  { name: 'runNode', selector: 'executeNodeCompletion', alias: 'executeNode', args: ['node source'] },
  { name: 'runPython', selector: 'executePythonCompletion', alias: 'executePython', args: ['python source'] },
  { name: 'fetchHTTPS', selector: 'fetchURLCompletion', alias: 'fetchURL', args: ['https://example.test/'] },
  { name: 'sendInterApp', selector: 'sendRequestActionCapabilityPayloadJSONCompletion', alias: 'sendRequest', args: ['target', 'action', 'capability', '{"nonce":"unpredictable"}'] },
];

function loadHelpers(targets, compatibilityResult = 'sync result') {
  const synchronousCalls = [];
  const helpers = vm.runInNewContext(
    helperSource + '\n({ runJS, runNode, runPython, fetchHTTPS, sendInterApp })',
    {
      getBridgeCandidates: () => targets,
      invokeCompat: (...args) => {
        synchronousCalls.push(args);
        return compatibilityResult;
      },
      invokeObjC: () => undefined,
    },
  );
  return { helpers, synchronousCalls };
}

for (const operation of operations) {
  test(operation.name + ' accepts an asynchronous void result without invoking a synchronous fallback', () => {
    let pending;
    let calls = 0;
    let fallbackCalls = 0;
    const target = {
      [operation.selector](...args) {
        assert.equal(this, target);
        calls += 1;
        pending = args.pop();
        assert.deepEqual(args, operation.args);
        return undefined;
      },
    };
    const alternate = {
      [operation.selector]() { fallbackCalls += 1; },
    };
    const { helpers, synchronousCalls } = loadHelpers([target, alternate]);
    const results = [];
    helpers[operation.name](...operation.args, (result, error) => results.push({ result, error }));
    assert.equal(calls, 1);
    assert.equal(fallbackCalls, 0);
    assert.equal(synchronousCalls.length, 0);
    assert.equal(results.length, 0, 'The helper must return while actual work is still pending');
    pending('actual async result', null);
    assert.deepEqual(results, [{ result: 'actual async result', error: null }]);
    assert.equal(fallbackCalls, 0);
    assert.equal(synchronousCalls.length, 0);
  });

  test(operation.name + ' uses the existing asynchronous alias on a later bridge candidate', () => {
    let pending;
    const { helpers, synchronousCalls } = loadHelpers([
      {},
      { [operation.alias](...args) { pending = args.at(-1); } },
    ]);
    const results = [];
    helpers[operation.name](...operation.args, (result, error) => results.push({ result, error }));
    assert.equal(synchronousCalls.length, 0);
    assert.equal(results.length, 0);
    pending(null, 'actual async failure');
    assert.deepEqual(results, [{ result: null, error: 'actual async failure' }]);
    assert.equal(synchronousCalls.length, 0, 'An asynchronous error must not execute the request a second time');
  });

  test(operation.name + ' preserves compatibility results when no asynchronous selector exists', () => {
    for (const [compatibilityResult, expected] of [
      ['sync result', { result: 'sync result', error: null }],
      ['Err: actual sync failure', { result: null, error: 'actual sync failure' }],
    ]) {
      const { helpers, synchronousCalls } = loadHelpers([{}], compatibilityResult);
      const results = [];
      helpers[operation.name](...operation.args, (result, error) => results.push({ result, error }));
      assert.deepEqual(results, [expected]);
      assert.equal(synchronousCalls.length, 1);
    }
  });
}
