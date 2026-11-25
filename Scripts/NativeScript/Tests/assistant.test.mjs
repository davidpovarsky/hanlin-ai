import test from 'node:test';
import assert from 'node:assert/strict';
import {createHostServices} from '../../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/index.mjs';

test('assistant reaches the original captured NativeScript session through host-services', async () => {
  const calls = [];
  const events = [{type: 'text', text: 'native reply'}, {type: 'finish', finishReason: 'stop', usage: {cacheWriteTokens: 12}}];
  const bridge = {
    sendRequestActionCapabilityPayloadJSONCompletion(target, action, capability, payload, done) {
      calls.push({target, action, capability, payload: JSON.parse(payload)});
      const receipt = action === 'assistant.start' ? {requestID: 'native-assistant'}
        : action === 'assistant.models' ? [{id: 'configured-model', provider: 'configured-provider'}]
        : {event: events.shift()};
      done(JSON.stringify(receipt), null);
    },
  };
  globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => bridge};
  const host = createHostServices();
  globalThis.HanlinNativeServicesBridge = {activeSessionBridge: () => { throw Error('Must not change sessions'); }};
  try {
    assert.equal((await host.assistant.models())[0].id, 'configured-model');
    const result = await host.assistant.generate({messages: [{role: 'user', content: 'hello'}]});
    assert.equal(result.text, 'native reply');
    assert.equal(result.usage.cacheWriteTokens, 12);
    assert.ok(calls.every(call => call.target === 'hanlin.host-services' && call.capability === 'assistant'));
  } finally { delete globalThis.HanlinNativeServicesBridge; }
});
