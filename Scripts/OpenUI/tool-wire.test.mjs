import test from 'node:test';
import assert from 'node:assert/strict';
import { createHostToolProviders } from './tool-wire.mjs';

test('React MCP requests reach the original Host and retain structured results', async () => {
  const calls = [];
  const result = { title: 'שלום', rows: [{ accepted: true, amount: 7, optional: null }] };
  const { reactToolProvider } = createHostToolProviders(async body => {
    calls.push(body); return result;
  });
  const response = await reactToolProvider.callTool({
    name: 'lookup', arguments: { query: 'שלום', options: [true, 7, null] },
  });
  assert.deepEqual(calls, [{
    kind: 'tool', name: 'lookup', args: { query: 'שלום', options: [true, 7, null] },
  }]);
  assert.deepEqual(response, { structuredContent: result });
});

test('native lang-core preserves its positional request and raw Host result', async () => {
  const calls = [], result = { title: 'Original host result' };
  const { nativeToolProvider } = createHostToolProviders(async body => {
    calls.push(body); return result;
  });
  assert.equal(await nativeToolProvider.callTool('lookup', { query: 'native' }), result);
  assert.deepEqual(calls, [{ kind: 'tool', name: 'lookup', args: { query: 'native' } }]);
});

test('React omitted arguments are an empty Host object', async () => {
  const calls = [];
  const { reactToolProvider } = createHostToolProviders(async body => {
    calls.push(body); return null;
  });
  assert.deepEqual(await reactToolProvider.callTool({ name: 'clock' }), { structuredContent: null });
  assert.deepEqual(calls, [{ kind: 'tool', name: 'clock', args: {} }]);
});

test('both renderers preserve a rejected Host permission without a success envelope', async () => {
  const denial = new Error('Original host denied the request'), calls = [];
  const { nativeToolProvider, reactToolProvider } = createHostToolProviders(async body => {
    calls.push(body); throw denial;
  });
  await assert.rejects(reactToolProvider.callTool({ name: 'write', arguments: { value: 1 } }),
    error => error === denial);
  await assert.rejects(nativeToolProvider.callTool('write', { value: 2 }),
    error => error === denial);
  assert.deepEqual(calls, [
    { kind: 'tool', name: 'write', args: { value: 1 } },
    { kind: 'tool', name: 'write', args: { value: 2 } },
  ]);
});
