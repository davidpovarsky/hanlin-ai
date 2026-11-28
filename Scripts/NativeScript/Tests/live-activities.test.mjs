import test from 'node:test';
import assert from 'node:assert/strict';
import {createHostServices} from '../../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/index.mjs';

test('Live Activity operations stay bound to their owning native session and return its actual values', async () => {
  const calls = [];
  const bridge = {
    sendRequestActionCapabilityPayloadJSONCompletion(target, action, capability, payload, done) {
      calls.push({target, action, capability, payload: JSON.parse(payload)});
      const response = action === 'liveActivities.areEnabled' ? {enabled: true}
        : action === 'liveActivities.start' ? {activityID: 'actual-native-id'}
        : action === 'liveActivities.list' ? {activityIDs: ['actual-native-id']}
        : {ok: true};
      done(JSON.stringify(response), null);
    },
  };
  globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => bridge};
  const host = createHostServices();
  globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => {
    throw new Error('A later session must never be used.');
  }};
  assert.equal(await host.liveActivities.areEnabled(), true);
  const root = {kind: 'text', properties: {text: 'שלום🙂'}};
  assert.deepEqual(await host.liveActivities.start({root, state: {count: 3}, actionEntrypointID: 'appIntents'}), {activityID: 'actual-native-id'});
  assert.deepEqual(await host.liveActivities.list(), ['actual-native-id']);
  assert.deepEqual(await host.liveActivities.update('actual-native-id', {state: {count: 4}}), {ok: true});
  assert.deepEqual(await host.liveActivities.end('actual-native-id', {dismissAfterSeconds: 0}), {ok: true});
  assert.equal(calls.length, 5);
  assert.ok(calls.every(call => call.target === 'hanlin.host-services' && call.capability === 'live-activity'));
  assert.deepEqual(calls[1].payload, {root, state: {count: 3}, actionEntrypointID: 'appIntents'});
  assert.deepEqual(calls[3].payload, {state: {count: 4}, activityID: 'actual-native-id'});
  delete globalThis.HanlinNativeServicesBridge;
});

test('The typed facade propagates an actual native failure without a fabricated activity id', async () => {
  globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => ({
    sendRequestActionCapabilityPayloadJSONCompletion(_target, _action, _capability, _payload, done) {
      done(null, 'Live Activities are disabled by the system.');
    },
  })};
  const host = createHostServices();
  await assert.rejects(host.liveActivities.start({root: {kind: 'text', properties: {text: 'test'}}}),
    /disabled by the system/);
  delete globalThis.HanlinNativeServicesBridge;
});
