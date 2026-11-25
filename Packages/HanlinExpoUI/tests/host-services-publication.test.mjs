import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import test from 'node:test';

// Exercise the actual public facade and JSON transport only. This deliberately
// does not stand in for the Apple store/renderer/installed-action acceptance.
const calls = [];
const native = {
  async invoke(operation, payload) {
    const request = JSON.parse(payload);
    calls.push({operation, request});
    return JSON.stringify(operation === 'widgets.publishPrepared'
      ? {ok: true, published: true, publication: 'prepared-expo-state', installedPackageID: 'installed.actual',
         generation: 3, revision: 7, stateCommitted: true, catalogVisible: true, reloadRequested: true, osRendered: null}
      : {ok: true, published: false, storage: 'legacy-widget-exposure', remediation: 'Use original createWidget'});
  },
};
globalThis.__hanlinPublicationFacadeTransport = native;
const hooks = registerHooks({
  resolve(specifier, context, next) {
    if (specifier === 'expo') return {url: 'hanlin-test:expo', shortCircuit: true};
    if (specifier === 'base64-js') return {url: 'hanlin-test:base64', shortCircuit: true};
    if (specifier === './miniapp-assistant') return next('./miniapp-assistant.ts', context);
    if (specifier === './miniapp-actions') return next('./miniapp-actions.ts', context);
    return next(specifier, context);
  },
  load(url, context, next) {
    if (url === 'hanlin-test:expo') return {format: 'module', shortCircuit: true,
      source: `export function requireNativeModule(name) {
        if (name !== 'HanlinHostServices') throw Error('Wrong native module');
        return globalThis.__hanlinPublicationFacadeTransport;
      }`};
    if (url === 'hanlin-test:base64') return {format: 'module', shortCircuit: true,
      source: `export function fromByteArray() {throw Error('Not a file codec test')}
        export function toByteArray() {throw Error('Not a file codec test')}`};
    return next(url, context);
  },
});
const {hostServices} = await import('../src/host-services.ts');

test('modern publication uses typed prepared props and preserves the distinct legacy transport', async () => {
  try {
    const request = {engine: 'expo', entrypointID: 'widget', variantID: 'configured-instance',
      props: {count: 19, title: 'שלום', nullable: null, flags: [true, false]}};
    const receipt = await hostServices.publishWidget(request);
    assert.deepEqual(calls.shift(), {operation: 'widgets.publishPrepared', request});
    assert.equal(receipt.publication, 'prepared-expo-state');
    assert.equal(receipt.revision, 7);
    assert.equal(receipt.osRendered, null, 'A state receipt is not an OS-render acceptance');
    const until = new Date('2026-11-24T15:00:00.125Z');
    const root = {kind: 'text', properties: {content: 'retained'}, children: []};
    const legacy = await hostServices.publishWidget('widget', 'systemMedium', root, until);
    assert.deepEqual(calls.shift(), {operation: 'widgets.publish', request: {
      entrypointID: 'widget', family: 'systemMedium', root,
      validUntil: until.toISOString(), validUntilEpochMilliseconds: until.getTime(),
    }});
    assert.equal(legacy.published, false);
    assert.equal(legacy.storage, 'legacy-widget-exposure');
    assert.equal(calls.length, 0);
  } finally {
    hooks.deregister();
    delete globalThis.__hanlinPublicationFacadeTransport;
  }
});
