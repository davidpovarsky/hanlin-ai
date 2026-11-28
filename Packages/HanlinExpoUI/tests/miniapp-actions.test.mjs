import assert from 'node:assert/strict';
import test from 'node:test';
import { serveMiniAppActions } from '../src/miniapp-actions.ts';

async function oneRequest(handler, parameters = { query: 'שלום' }) {
  const operations = [];
  let reads = 0;
  const closed = new Error('test session closed');
  const invoke = async (operation, payload) => {
    operations.push({ operation, payload });
    if (operation === 'actions.next') {
      if (reads++) throw closed;
      return { id: 'request-1', action: 'search', caller: 'hanlin.host', parameters };
    }
    return { ok: true };
  };
  await assert.rejects(serveMiniAppActions(invoke, { search: handler }), error => error === closed);
  return operations;
}

test('registers handlers and returns the actual awaited result with the same invocation id', async () => {
  const ops = await oneRequest(async request => ({ received: request.parameters.query, total: 7 }));
  assert.deepEqual(ops[0], { operation: 'actions.register', payload: { names: ['search'] } });
  assert.deepEqual(ops.find(x => x.operation === 'actions.complete'), {
    operation: 'actions.complete', payload: { id: 'request-1', value: { received: 'שלום', total: 7 } }
  });
});

test('handler rejection is a failed reply and does not claim a successful value', async () => {
  const ops = await oneRequest(async () => { throw new Error('network failed'); });
  assert.deepEqual(ops.find(x => x.operation === 'actions.complete').payload,
    { id: 'request-1', error: 'network failed' });
});

test('non-JSON and cyclic results are explicit failures rather than lossy successes', async () => {
  const cyclic = {}; cyclic.self = cyclic;
  for (const value of [undefined, NaN, Infinity, { missing: undefined }, cyclic, 1n]) {
    const ops = await oneRequest(() => value);
    const completion = ops.find(x => x.operation === 'actions.complete').payload;
    assert.equal(completion.id, 'request-1');
    assert.equal(typeof completion.error, 'string');
    assert.equal(Object.hasOwn(completion, 'value'), false);
  }
});
