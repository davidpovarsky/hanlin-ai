// Authored fixture controls only. Mocked facade replies below are never native
// execution evidence and are not installed in the shipping MiniApps runtime.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';

function harness(createSurfaceProof, appID, overrides = {}) {
  let state = null;
  const journals = new Map();
  const writes = [];
  const progress = [];
  const events = [];
  const api = {
    appID,
    readText: async () => state,
    writeText: async text => { state = text; writes.push(JSON.parse(text)); },
    writeInvocation: async (name, text) => {
      const value = JSON.parse(text); journals.set(name, value);
      events.push({name, phase: value.concurrency.phase, token: value.concurrency.token});
    },
    samplePresentation: (name = 'surface-proof.json') => ({
      windowID: 'unit-window', statePath: '/unit/Windows/unit-window/State/' + name,
      executionMode: 'headless-action', attached: false
    }),
    reportProgress: async value => { progress.push(value); },
    executeRuntime: async (kind, source) => {
      const marker = source.match(/hanlin\.surface\.(?:expo|nativescript):[a-z0-9-]+:[a-z0-9-]+:[0-9]+:[a-zA-Z]+:42/)?.[0];
      assert.ok(marker, 'The original runtime source must contain its exact authored marker');
      return {executionID: randomUUID(), stdout: marker + '\n', stderr: '',
        durationMilliseconds: 1, didTimeOut: false, wasCancelled: false,
        outputWasTruncated: false, exitCode: 0,
        ...(kind === 'javaScriptCore' ? {value: marker} : {})};
    },
    ...overrides
  };
  const proof = createSurfaceProof(api);
  return {proof, journals, writes, progress, events, api, state: () => state};
}

function input(challenge, token = randomUUID(), holdMilliseconds = 0) {
  return {surface: 'miniAppShortcutConcurrency', challenge,
    concurrency: {schema: 1, token, holdMilliseconds},
    typed: {text: 'שלום עולם', count: 42, enabled: true, empty: null, list: [true, 42, 'שלום']}};
}

for (const engine of ['expo', 'nativescript']) {
  const {createSurfaceProof} = await import(new URL(
    '../../../Fixtures/HostActionSurfaces/' + engine + '/proof.ts', import.meta.url));
  const appID = 'hanlin.surface.' + engine;
  const invocation = () => engine === 'expo'
    ? {caller: 'unit-control', id: randomUUID()} : {caller: 'unit-control'};

  test(engine + ': original single action retains counter/state/five outputs', async () => {
    const h = harness(createSurfaceProof, appID);
    const prepared = await h.proof.prepare();
    const result = await h.proof.run({surface: 'miniAppShortcut', challenge: prepared.challenge}, invocation());
    assert.equal(result.status, 'completed');
    assert.equal(result.counter, 1);
    assert.equal(result.concurrency, undefined);
    assert.equal(h.journals.size, 0);
    assert.equal(h.progress.length, 6);
    assert.deepEqual(JSON.parse(h.state()).lastResult, result);
    assert.deepEqual(result.receipts.map(row => row.kind),
      ['node', 'typeScript', 'localPython', 'javaScriptCore', 'shell']);
  });

  test(engine + ': optional concurrent mode bypasses only authored serial tail', {timeout: 2000}, async () => {
    const entered = new Set();
    let release;
    const ready = new Promise(resolve => { release = resolve; });
    const h = harness(createSurfaceProof, appID, {
      reportProgress: async value => {
        if (value.message.startsWith('Concurrent ')) {
          entered.add(value.message);
          if (entered.size === 2) release();
          await ready;
        }
      }
    });
    const prepared = await h.proof.prepare();
    const originalState = h.state(), originalWrites = h.writes.length;
    const [a, b] = await Promise.all([
      h.proof.run(input(prepared.challenge), invocation()),
      h.proof.run(input(prepared.challenge), invocation())
    ]);
    assert.equal(entered.size, 2);
    assert.equal(a.status, 'completed'); assert.equal(b.status, 'completed');
    assert.notEqual(a.nonce, b.nonce);
    assert.notEqual(a.concurrency.journalFile, b.concurrency.journalFile);
    assert.equal(h.journals.size, 2);
    assert.equal(h.state(), originalState);
    assert.equal(h.writes.length, originalWrites);
    assert.deepEqual(h.journals.get(a.concurrency.journalFile), a);
    assert.deepEqual(h.journals.get(b.concurrency.journalFile), b);
    assert.equal(a.counter, 1); assert.equal(b.counter, 1);
    assert.deepEqual(a.request.typed, input(prepared.challenge).typed);
    assert.ok(a.presentationSamples.every(sample => sample.statePath.endsWith('/' + a.concurrency.journalFile)));
    assert.equal(a.receipts.length, 5); assert.equal(b.receipts.length, 5);
  });

  test(engine + ': duplicate requested token retains separate actual handler journals', async () => {
    const h = harness(createSurfaceProof, appID);
    const prepared = await h.proof.prepare();
    const request = input(prepared.challenge);
    const [a, b] = await Promise.all([h.proof.run(request, invocation()), h.proof.run(request, invocation())]);
    assert.equal(a.concurrency.token, b.concurrency.token);
    assert.notEqual(a.nonce, b.nonce);
    assert.equal(h.journals.size, 2, 'Observer must see and reject duplicate actual executions');
  });

  test(engine + ': invalid challenge/token/hold cannot write an invocation', async () => {
    for (const mutate of [
      value => { value.challenge = '../../escape'; },
      value => { value.concurrency.token = '../escape'; },
      value => { value.concurrency.holdMilliseconds = true; },
      value => { value.concurrency.holdMilliseconds = 1.5; },
      value => { value.concurrency.holdMilliseconds = -1; },
      value => { value.concurrency.holdMilliseconds = 120001; },
      value => { value.concurrency.schema = 2; },
    ]) {
      const h = harness(createSurfaceProof, appID);
      const prepared = await h.proof.prepare();
      const before = h.state(), value = input(prepared.challenge);
      mutate(value);
      await assert.rejects(h.proof.run(value, invocation()));
      assert.equal(h.journals.size, 0);
      assert.equal(h.state(), before);
    }
    for (const missing of ['writeInvocation', 'reportProgress']) {
      const h = harness(createSurfaceProof, appID, {[missing]: undefined});
      const prepared = await h.proof.prepare();
      await assert.rejects(h.proof.run(input(prepared.challenge), invocation()));
      assert.equal(h.journals.size, 0);
    }
  });

  test(engine + ': incomplete facade reply cannot become five-runtime success', async () => {
    const h = harness(createSurfaceProof, appID, {
      executeRuntime: async () => ({executionID: randomUUID(), stdout: 'wrong\n',
        durationMilliseconds: 1, didTimeOut: false, wasCancelled: false, outputWasTruncated: false})
    });
    const prepared = await h.proof.prepare(), before = h.state();
    await assert.rejects(h.proof.run(input(prepared.challenge), invocation()));
    assert.equal(h.state(), before);
    assert.equal([...h.journals.values()][0].status, 'failed');
    assert.equal([...h.journals.values()][0].receipts.length, 1);
  });

  test(engine + ': provider cancellation is never fabricated as a native terminal receipt', async () => {
    const h = harness(createSurfaceProof, appID, {
      reportProgress: async () => { throw new Error('actual provider stopped'); }
    });
    const prepared = await h.proof.prepare(), before = h.state();
    await assert.rejects(h.proof.run(input(prepared.challenge), invocation()), /actual provider stopped/);
    const journal = [...h.journals.values()][0];
    assert.equal(journal.status, 'failed');
    assert.equal(journal.concurrency.phase, 'failed');
    assert.equal(journal.receipt, undefined);
    assert.equal(h.state(), before);
  });
}
