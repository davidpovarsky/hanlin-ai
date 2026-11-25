import test from 'node:test';
import assert from 'node:assert/strict';
import {createMiniAppAssistant} from '../src/miniapp-assistant.ts';

const request = {messages: [{role: 'user', content: 'שלום🙂'}]};

test('native schema bytes, ordered chunks and cache write/read usage survive the public facade', async () => {
  const calls = [];
  const events = [
    {type: 'structured', value: {count: 4, title: 'שלום🙂'}},
    {type: 'finish', finishReason: 'stop', usage: {inputTokens: 100, cachedInputTokens: 70, cacheWriteTokens: 20}},
  ];
  const assistant = createMiniAppAssistant(async (operation, payload) => {
    calls.push({operation, payload});
    if (operation === 'assistant.start') return {requestID: 'native-1'};
    if (operation === 'assistant.next') return {event: events.shift()};
    throw Error('No cancellation after a completed native result');
  });
  const schema = {type: 'object', properties: {count: {type: 'integer'}, title: {type: 'string'}}};
  const result = await assistant.generate({...request, responseSchema: schema});
  assert.deepEqual(result.value, {count: 4, title: 'שלום🙂'});
  assert.deepEqual(result.usage, {inputTokens: 100, cachedInputTokens: 70, cacheWriteTokens: 20});
  assert.equal(calls[0].payload.responseSchemaJSON, JSON.stringify(schema));
  assert.equal(calls[0].payload.responseSchema, undefined);
  assert.ok(calls.slice(1).every(call => call.payload.requestID === 'native-1'));
});

test('breaking iteration cancels the native producer exactly once', async () => {
  const calls = [];
  const assistant = createMiniAppAssistant(async (operation, payload) => {
    calls.push({operation, payload});
    if (operation === 'assistant.start') return {requestID: 'native-break'};
    if (operation === 'assistant.next') return {event: {type: 'text', text: 'first'}};
    if (operation === 'assistant.cancel') return {ok: true};
    throw Error(operation);
  });
  for await (const event of assistant.stream(request)) { assert.equal(event.type, 'text'); break; }
  assert.equal(calls.filter(call => call.operation === 'assistant.cancel').length, 1);
});

test('abort unblocks an in-flight native next and cleans the listener', async () => {
  let pending;
  let nextStarted;
  const reading = new Promise(resolve => { nextStarted = resolve; });
  const calls = [];
  const assistant = createMiniAppAssistant(async (operation, payload) => {
    calls.push({operation, payload});
    if (operation === 'assistant.start') return {requestID: 'native-abort'};
    if (operation === 'assistant.next') {
      nextStarted();
      return new Promise((_resolve, reject) => { pending = reject; });
    }
    if (operation === 'assistant.cancel') { pending?.(Error('native cancelled')); return {ok: true}; }
    throw Error(operation);
  });
  const controller = new AbortController();
  const task = assistant.generate(request, {signal: controller.signal});
  await reading;
  controller.abort();
  await assert.rejects(task, error => error.name === 'AbortError');
  assert.equal(calls.filter(call => call.operation === 'assistant.cancel').length, 1);
});

test('abort during admission cancels the returned native handle before consuming it', async () => {
  const calls = [];
  const controller = new AbortController();
  const assistant = createMiniAppAssistant(async (operation) => {
    calls.push(operation);
    if (operation === 'assistant.start') { controller.abort(); return {requestID: 'admitted-then-aborted'}; }
    if (operation === 'assistant.cancel') return {ok: true};
    throw Error('Must not read an aborted stream');
  });
  await assert.rejects(assistant.generate(request, {signal: controller.signal}), error => error.name === 'AbortError');
  assert.deepEqual(calls, ['assistant.start', 'assistant.cancel']);
});

test('provider errors reject and release only their original request handle', async () => {
  const cancellations = [];
  let serial = 0;
  const assistant = createMiniAppAssistant(async (operation, payload) => {
    if (operation === 'assistant.start') return {requestID: 'run-' + ++serial};
    if (operation === 'assistant.next') throw Error('sanitized native failure');
    if (operation === 'assistant.cancel') { cancellations.push(payload.requestID); return {ok: true}; }
    throw Error(operation);
  });
  const first = await assistant.start(request);
  const second = await assistant.start(request);
  await assert.rejects(async () => { for await (const _ of first.events) {} }, /sanitized native failure/);
  assert.deepEqual(cancellations, ['run-1']);
  await second.cancel();
  assert.deepEqual(cancellations, ['run-1', 'run-2']);
});

test('one native handle has one reader and manual cancellation is idempotent', async () => {
  const calls = [];
  const assistant = createMiniAppAssistant(async (operation) => {
    calls.push(operation);
    if (operation === 'assistant.start') return {requestID: 'single-reader'};
    if (operation === 'assistant.next') return {event: {type: 'text', text: 'a'}};
    return {ok: true};
  });
  const run = await assistant.start(request);
  const first = run.events[Symbol.asyncIterator]();
  await first.next();
  const other = run.events[Symbol.asyncIterator]();
  await assert.rejects(other.next(), /one reader/);
  await run.cancel();
  await run.cancel();
  await first.return();
  assert.equal(calls.filter(call => call === 'assistant.cancel').length, 1);
});
