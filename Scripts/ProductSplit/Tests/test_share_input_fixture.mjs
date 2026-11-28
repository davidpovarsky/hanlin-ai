// Pure authored input controls. These injected file/runtime replies are never
// installed in the product and never count as native or real OS execution.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash, randomUUID} from 'node:crypto';
import {createSurfaceProof, emptyState} from '../../../Fixtures/HostActionSurfaces/nativescript/proof.ts';

const appID = 'hanlin.surface.nativescript';
const sha = value => createHash('sha256').update(value).digest('hex');

function harness(initial = null) {
  let state = initial === null ? null : JSON.stringify(initial);
  const writes = [], reads = [];
  const proof = createSurfaceProof({
    appID, readText: async () => state,
    writeText: async value => { state = value; writes.push(JSON.parse(value)); },
    acceptInputChallenge: true,
    executeRuntime: async (kind, source) => {
      const marker = source.match(/hanlin\.surface\.nativescript:[a-z0-9-]+:[a-z0-9-]+:[0-9]+:[a-zA-Z]+:42/)?.[0];
      assert.ok(marker);
      return {executionID: randomUUID(), stdout: marker + '\n', stderr: '',
        durationMilliseconds: 1, didTimeOut: false, wasCancelled: false,
        outputWasTruncated: false, exitCode: 0,
        ...(kind === 'javaScriptCore' ? {value: marker} : {})};
    }
  });
  return {proof, writes, reads, state: () => state};
}

function payload(asText = false) {
  const runID = randomUUID(), seed = randomUUID(), challenge = 'fresh-selected-challenge';
  const input = {schema: 1, kind: 'hanlin.surface.share-input', runID, appID, seed, challenge};
  const texts = [JSON.stringify(input), 'Hanlin Share input ' + seed + ' ' + runID + ' nativescript ' + challenge + '\n'];
  const shareBatchID = randomUUID(), files = new Map();
  const items = texts.map((text, ordinal) => {
    const id = randomUUID();
    if (asText) return {id, ordinal, kind: 'text', typeIdentifier: 'public.text', text};
    const fileURL = 'file:///private/group/HanlinMiniApps/v1/ShareInbox/Batches/' + shareBatchID + '/Files/' + id;
    files.set(fileURL, text);
    return {id, ordinal, kind: 'file', typeIdentifier: 'public.text', fileURL,
      bytes: Buffer.byteLength(text), sha256: sha(text)};
  });
  return {request: {shareBatchID, items}, input, texts, files, challenge};
}

function reader(h, p) {
  return async url => {
    h.reads.push(url);
    assert.ok(p.files.has(url), 'Only the actual supplied owned file may be read');
    return p.files.get(url);
  };
}

test('actual canonical files initialize only this empty window, preserving original request/run output', async () => {
  const h = harness(), p = payload(), original = structuredClone(p.request);
  await h.proof.admitSharedInput(p.request, reader(h, p));
  assert.equal(h.writes.length, 1);
  assert.deepEqual(h.writes[0], {...emptyState(appID), challenge: p.challenge});
  assert.deepEqual(h.reads, p.request.items.map(item => item.fileURL));
  assert.deepEqual(p.request, original);
  const result = await h.proof.run(p.request, {caller: 'unit-only'});
  assert.equal(result.requestedSurface, 'external');
  assert.equal(result.challenge, p.challenge);
  assert.equal(result.counter, 1);
  assert.deepEqual(result.request, original);
  assert.deepEqual(result.receipts.map(row => row.kind), ['node', 'typeScript', 'localPython', 'javaScriptCore', 'shell']);
  assert.deepEqual(JSON.parse(h.state()).lastResult, result);
});

test('exact canonical text representations admit without opening any file', async () => {
  const h = harness(), p = payload(true);
  await h.proof.admitSharedInput(p.request, async () => assert.fail('Text representation must not open a file'));
  assert.equal(JSON.parse(h.state()).challenge, p.challenge);
});

test('prepared, completed or activity-owning state cannot be overwritten even by the same challenge', async () => {
  const p = payload();
  for (const change of [{challenge: p.challenge}, {challenge: 'other-owner-challenge'}, {counter: 1},
                        {lastResult: {status: 'completed'}}, {activityID: 'actual-existing-activity'}]) {
    const h = harness({...emptyState(appID), ...change}), before = h.state();
    await assert.rejects(h.proof.admitSharedInput(p.request, reader(h, p)), /empty newly-created window/);
    assert.equal(h.state(), before);
    assert.equal(h.writes.length, 0);
    assert.equal(h.reads.length, 0);
  }
});

test('all other original routes leave the state and actual file reader untouched', async () => {
  for (const request of [null, [], 'text', {surface: 'foreground'},
                         {surface: 'miniAppShortcut', challenge: 'original-ui-challenge'},
                         {surface: 'miniAppShortcutConcurrency', challenge: 'original-ui-challenge'},
                         {query: 'selected text', source: 'translationUI'}]) {
    const h = harness({...emptyState(appID), challenge: 'existing-owner-challenge'}), before = h.state();
    await h.proof.admitSharedInput(request, async () => assert.fail('An unrelated action cannot read Share input'));
    assert.equal(h.state(), before);
    assert.equal(h.writes.length, 0);
  }
});

test('malformed batch/item identities, counts and unsafe file URLs fail before mutation', async () => {
  for (const mutate of [
    p => { p.request.shareBatchID = '../other'; },
    p => { p.request.challenge = p.challenge; },
    p => { p.request.items.pop(); },
    p => { p.request.items[1].id = p.request.items[0].id; },
    p => { p.request.items[0].ordinal = false; },
    p => { p.request.items[0].kind = 'rejected'; },
    p => { p.request.items[0].failure = 'providerFailed'; },
    p => { p.request.items[0].bytes = true; },
    p => { p.request.items[0].bytes = 65537; },
    p => { p.request.items[0].fileURL = 'file:///private/data/Windows/sibling/State/surface-proof.json'; },
    p => { p.request.items[0].fileURL = p.request.items[0].fileURL.replace('/private/', '/private/../'); },
    p => { p.request.items[0].fileURL += '?redirect=other'; },
  ]) {
    const h = harness(), p = payload(); mutate(p);
    await assert.rejects(h.proof.admitSharedInput(p.request, reader(h, p)));
    assert.equal(h.state(), null);
    assert.equal(h.writes.length, 0);
  }
});

test('wrong or missing JSON identity and mismatched second input cannot initialize a window', async () => {
  for (const mutate of [
    value => { value.appID = 'hanlin.surface.expo'; },
    value => { value.schema = true; },
    value => { value.kind = 'other'; },
    value => { delete value.runID; },
    value => { value.seed = '../escape'; },
    value => { value.challenge = 'not valid'; },
    value => { value.extra = 'unexpected'; },
  ]) {
    const h = harness(), p = payload(true); mutate(p.input);
    p.request.items[0].text = JSON.stringify(p.input);
    await assert.rejects(h.proof.admitSharedInput(p.request, reader(h, p)));
    assert.equal(h.state(), null);
    assert.equal(h.writes.length, 0);
  }
  for (const text of ['different note', payload(true).texts[1], payload(true).texts[0]]) {
    const h = harness(), p = payload(true); p.request.items[1].text = text;
    await assert.rejects(h.proof.admitSharedInput(p.request, reader(h, p)));
    assert.equal(h.writes.length, 0);
  }
});

test('missing/unreadable actual supplied files cannot seed state or become successful runtime output', async () => {
  const h = harness(), p = payload();
  await assert.rejects(h.proof.admitSharedInput(p.request, async () => { throw new Error('actual file unavailable'); }),
                       /actual file unavailable/);
  assert.equal(h.writes.length, 0);
  await assert.rejects(h.proof.run(p.request, {caller: 'unit-only'}), /Prepare challenge/);
  assert.equal(h.state(), null);
});
