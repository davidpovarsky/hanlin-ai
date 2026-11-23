import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHostServices } from '../../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/index.mjs';

test('cross-app facade keeps each captured native session and all payload bytes', async () => {
  const seen = [];
  const bridge = id => ({
    sendRequestActionCapabilityPayloadJSONCompletion(target, operation, capability, payload, completion) {
      seen.push({ id, target, operation, capability, payload: JSON.parse(payload) });
      completion(JSON.stringify(operation === 'miniapps.context' ? { id } : { ok: true }), null);
    }
  });
  globalThis.HanlinNativeServicesBridge = { activeSessionBridge: () => bridge('first') };
  const first = createHostServices().miniapps;
  globalThis.HanlinNativeServicesBridge = { activeSessionBridge: () => bridge('second') };
  const second = createHostServices().miniapps;
  assert.deepEqual(await first.getContext(), { id: 'first' });
  assert.deepEqual(await second.getContext(), { id: 'second' });
  const output = { operation: 'replaceSelection', items: [{kind: 'text', text: 'עברית 👨‍👩‍👧'}] };
  await first.complete(output);
  await second.writeAttachment({base64: 'AP+A', name: 'מקור.bin'});
  await first.readAttachment('attachment-uuid');
  await second.cancel();
  assert.deepEqual(seen.map(x => x.id), ['first','second','first','first','second','first','second','second']);
  assert.ok(seen.every(x => x.target === 'hanlin.cross-app' && x.capability === 'miniapps'));
  assert.deepEqual(seen[2].payload, output);
  assert.equal(seen[4].payload.base64, 'AP+A');
  assert.deepEqual(seen[5].payload, { id: 'attachment-uuid' });
  delete globalThis.HanlinNativeServicesBridge;
});

test('native errors and invalid replies reject without inventing completion', async () => {
  for (const [receipt,error,expected] of [[null, 'native failure', /native failure/], [null,null,/no receipt/], ['broken',null,/invalid JSON/]]) {
    globalThis.HanlinNativeServicesBridge = { activeSessionBridge: () => ({
      sendRequestActionCapabilityPayloadJSONCompletion(target, operation, capability, payload, completion) {
        completion(receipt,error);
      }
    })};
    await assert.rejects(createHostServices().miniapps.complete('text'), expected);
  }
  delete globalThis.HanlinNativeServicesBridge;
});
