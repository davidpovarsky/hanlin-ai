import test from 'node:test';
import assert from 'node:assert/strict';
import {createHostServicesForBridge} from '../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/index.mjs';

// These are facade boundary tests; the Apple test runs the actual original VM.
function provider() {
  const handlers = new Map();
  return {
    handlers,
    registerRequestHandlerCapabilityHandler(action, capability, handler) {
      handlers.set(action, {capability, handler});
    },
  };
}
function invoke(provider, action, parameters) {
  const entry = provider.handlers.get(action);
  assert.ok(entry);
  const replies = [];
  return new Promise(resolve => {
    entry.handler('hanlin.host', parameters, (value, error) => {
      replies.push({value, error});
      resolve({value, error, replies});
    });
  });
}

test('bound action handlers retain their provider across overlapping async results', async () => {
  const first = provider(), second = provider();
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  createHostServicesForBridge(first).registerRequestHandler('probe', 'inter-app.share', async request => {
    await gate;
    return {owner: 'first', caller: request.caller, parameters: request.parameters};
  });
  createHostServicesForBridge(second).registerRequestHandler('probe', 'inter-app.share',
    request => ({owner: 'second', parameters: request.parameters}));
  const pending = invoke(first, 'probe', '{"nonce":"a","nested":[true,null,{"n":2}]}');
  const secondReply = await invoke(second, 'probe', '{"nonce":"b"}');
  assert.deepEqual(JSON.parse(secondReply.value), {owner: 'second', parameters: {nonce: 'b'}});
  release();
  const firstReply = await pending;
  assert.deepEqual(JSON.parse(firstReply.value), {owner: 'first', caller: 'hanlin.host',
    parameters: {nonce: 'a', nested: [true, null, {n: 2}]}});
  assert.equal(first.handlers.get('probe').capability, 'inter-app.share');
  assert.equal(firstReply.replies.length, 1);
  assert.equal(secondReply.replies.length, 1);
});

test('malformed input and synchronous or asynchronous handler failures return one owned error', async () => {
  for (const [parameters, handler, expected] of [
    ['{', () => { throw new Error('must not execute malformed input'); }, /JSON|property|position/],
    ['{}', () => { throw new Error('synchronous probe'); }, /synchronous probe/],
    ['{}', async () => { throw new Error('asynchronous probe'); }, /asynchronous probe/],
  ]) {
    const owner = provider();
    createHostServicesForBridge(owner).registerRequestHandler('probe', 'inter-app.share', handler);
    const reply = await invoke(owner, 'probe', parameters);
    assert.equal(reply.value, null);
    assert.match(reply.error, expected);
    await Promise.resolve();
    assert.equal(reply.replies.length, 1);
  }
});

test('untyped invalid output is rejected at the existing native JSON boundary', async () => {
  const owner = provider();
  createHostServicesForBridge(owner).registerRequestHandler('probe', 'inter-app.share', () => undefined);
  const reply = await invoke(owner, 'probe', '{}');
  assert.equal(reply.value, null);
  assert.match(reply.error, /must return a JSON value/);
  assert.equal(reply.replies.length, 1);
});
