import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const bundle = readFileSync(new URL('../../../DemoMiniApps/hanlin-script-parity/nativescript/app/bundle.mjs', import.meta.url), 'utf8');
const operations = [
  { helper: 'runJS', completion: 'executeJavaScriptCompletion', short: 'executeJavaScript', key: 'hostService.executeJavaScript', args: ['JSC source'] },
  { helper: 'runNode', completion: 'executeNodeCompletion', short: 'executeNode', key: 'hostService.executeNode', args: ['Node source'] },
  { helper: 'runPython', completion: 'executePythonCompletion', short: 'executePython', key: 'hostService.executePython', args: ['Python source'] },
  { helper: 'fetchHTTPS', completion: 'fetchURLCompletion', short: 'fetchURL', key: 'hostService.fetchURL', args: ['https://example.test/proof'] },
  { helper: 'sendInterApp', completion: 'sendRequestActionCapabilityPayloadJSONCompletion', short: 'sendRequest', key: 'hostService.sendRequest:destination:share.value:inter-app.share', args: ['destination', 'share.value', 'inter-app.share', '{"nonce":"unmodified"}'] },
];

function load(bridge) {
  // Evaluate the shipped bundle's actual helpers through its existing headless
  // mode. These bridge doubles verify dispatch/lifetime only, not native engines.
  const context = vm.createContext({
    HanlinNativeServicesBridge: bridge,
    NSProcessInfo: { processInfo: { environment: {
      objectForKey: name => name === 'HANLIN_EXECUTION_MODE' ? 'headless-action' : null,
    } } },
    console: { log() {}, warn() {}, error() {} },
  });
  vm.runInContext(bundle, context, { filename: 'hanlin-script-parity/bundle.mjs' });
  return context;
}

for (const operation of operations) {
  for (const selector of [operation.completion, operation.short]) {
    test(operation.helper + ' starts pending ' + selector + ' before any synchronous compatibility call', () => {
      const callbacks = [];
      const syncCalls = [];
      const received = [];
      const instance = {
        [selector](...args) {
          callbacks.push(args.pop());
          received.push(args);
        },
      };
      // The class comes first; its synchronous route must not mask an async
      // selector on a later bound instance.
      const bridge = {
        sharedBridge: () => instance,
        roundTripValueKey(value, key) {
          if (key === operation.key) {
            syncCalls.push([value, key]);
            return 'Err: synchronous startup would block presentation';
          }
          return null;
        },
      };
      const context = load(bridge);
      const results = [];
      context[operation.helper](...operation.args, (value, error) => results.push([value, error]));
      assert.deepEqual(syncCalls, []);
      assert.equal(callbacks.length, 1);
      assert.deepEqual(received, [operation.args]);
      assert.deepEqual(results, [], 'invocation must return while the native operation is pending');
      callbacks[0]('actual callback result', null);
      assert.deepEqual(results, [['actual callback result', null]]);
    });
  }

  test(operation.helper + ' preserves compatibility results and errors when async APIs are absent', () => {
    for (const [raw, expected] of [
      ['compatible result', ['compatible result', null]],
      ['Err: actual native failure', [null, 'actual native failure']],
    ]) {
      const context = load({
        roundTripValueKey(value, key) { return key === operation.key ? raw : null; },
      });
      const results = [];
      context[operation.helper](...operation.args, (value, error) => results.push([value, error]));
      assert.deepEqual(results, [expected]);
    }
  });
}
