import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSynchronizationReceipt, awaitSynchronizedCandidate } from '../upstream-dispatch-synchronization.mjs';

const previous = 'a'.repeat(40), head = 'b'.repeat(40), base = 'c'.repeat(40);
const expected = { repository: 'owner/repo', number: 15, baseRef: 'codex/base-v3', headRef: 'codex/renovate/scoped/semver-7.x' };
const receipt = { schema: 1, ...expected, base, previous, head, changed: true };
const pull = sha => ({ number: 15, state: 'open', draft: false, base: { ref: expected.baseRef, sha: base },
  head: { ref: expected.headRef, sha, repo: { full_name: expected.repository } } });
const ref = sha => ({ ref: 'refs/heads/' + expected.headRef, object: { type: 'commit', sha } });
function adapters(pulls, refs) {
  let clock = 0, pullReads = 0, refReads = 0, waits = 0;
  return {
    readPull: async ({ timeoutMilliseconds }) => {
      assert.ok(timeoutMilliseconds > 0 && timeoutMilliseconds <= 5_000);
      return pulls[Math.min(pullReads++, pulls.length - 1)];
    },
    readHeadRef: async ({ timeoutMilliseconds }) => {
      assert.ok(timeoutMilliseconds > 0 && timeoutMilliseconds <= 5_000);
      return refs[Math.min(refReads++, refs.length - 1)];
    },
    now: () => clock, wait: async milliseconds => { waits += 1; clock += milliseconds; },
    stats: () => ({ pullReads, refReads, waits }),
  };
}

test('parse the authoritative final synchronization receipt after canonical tool logs', () => {
  assert.deepEqual(parseSynchronizationReceipt('generated pins\n' + JSON.stringify(receipt) + '\n', expected), receipt);
});
test('reject absent, inconsistent, or differently scoped synchronization receipts', () => {
  assert.throws(() => parseSynchronizationReceipt('not a receipt', expected), /Missing canonical/);
  for (const change of [{ head: 'bad' }, { previous: head }, { changed: false }, { repository: 'other/repo' },
    { number: 16 }, { baseRef: 'other-base' }, { headRef: 'other-head' }, { base: 'bad' }, { schema: 2 }]) {
    assert.throws(() => parseSynchronizationReceipt(JSON.stringify({ ...receipt, ...change }), expected), /does not match/);
  }
});
test('accept an unchanged synchronized head without waiting', async () => {
  const unchanged = parseSynchronizationReceipt(JSON.stringify({ ...receipt, previous: head, changed: false }), expected);
  const io = adapters([pull(head)], [ref(head)]);
  const result = await awaitSynchronizedCandidate(unchanged, io);
  assert.equal(result.pull.head.sha, head);
  assert.deepEqual(io.stats(), { pullReads: 1, refReads: 1, waits: 0 });
});
test('wait for the exact post-sync PR head while the authoritative ref is already current', async () => {
  const io = adapters([pull(previous), pull(head)], [ref(head)]);
  const result = await awaitSynchronizedCandidate(receipt, io);
  assert.equal(result.attempts, 2);
  assert.equal(result.pull.head.sha, head);
  assert.deepEqual(io.stats(), { pullReads: 2, refReads: 2, waits: 1 });
});
test('require Git ref convergence as well as the PR API projection', async () => {
  const io = adapters([pull(head)], [ref(previous), ref(head)]);
  const result = await awaitSynchronizedCandidate(receipt, io);
  assert.equal(result.attempts, 2);
});
test('reject another commit instead of dispatching either a stale or unexpected candidate', async () => {
  for (const [p, r] of [[pull('d'.repeat(40)), ref(head)], [pull(head), ref('d'.repeat(40))]]) {
    const io = adapters([p], [r]);
    await assert.rejects(awaitSynchronizedCandidate(receipt, io), /different head/);
    assert.equal(io.stats().waits, 0);
  }
});
test('reject closed/draft/forked/renamed/rebased candidates and mismatched refs', async () => {
  const variants = [
    { ...pull(head), state: 'closed' }, { ...pull(head), draft: true },
    { ...pull(head), number: 16 }, { ...pull(head), base: { ref: expected.baseRef, sha: previous } },
    { ...pull(head), base: { ref: 'other', sha: base } },
    { ...pull(head), head: { ...pull(head).head, ref: 'other' } },
    { ...pull(head), head: { ...pull(head).head, repo: { full_name: 'fork/repo' } } },
  ];
  for (const p of variants) {
    await assert.rejects(awaitSynchronizedCandidate(receipt, adapters([p], [ref(head)])), /source\/base changed/);
  }
  for (const r of [{ ...ref(head), ref: 'refs/heads/other' }, { ...ref(head), object: { type: 'tag', sha: head } }]) {
    await assert.rejects(awaitSynchronizedCandidate(receipt, adapters([pull(head)], [r])), /source\/base changed/);
  }
});
test('bound unresolved stale-head retries and never return a dispatchable candidate', async () => {
  const io = adapters([pull(previous)], [ref(head)]);
  await assert.rejects(awaitSynchronizedCandidate(receipt, { ...io, maxAttempts: 3 }), /did not converge/);
  assert.deepEqual(io.stats(), { pullReads: 3, refReads: 3, waits: 2 });
});
test('enforce wall-clock deadline across awaited reads without dispatch fallback', async () => {
  let clock = 0, refReads = 0;
  await assert.rejects(awaitSynchronizedCandidate(receipt, {
    now: () => clock, timeoutMilliseconds: 1_000,
    readPull: async () => { clock = 1_001; return pull(head); },
    readHeadRef: async () => { refReads += 1; return ref(head); },
  }), /deadline/);
  assert.equal(refReads, 0);
});
test('propagate real API failure and reject policy expansion', async () => {
  const io = adapters([pull(head)], [ref(head)]);
  await assert.rejects(awaitSynchronizedCandidate(receipt, { ...io, readPull: async () => { throw Error('API unavailable'); } }), /API unavailable/);
  for (const options of [{ maxAttempts: 13 }, { timeoutMilliseconds: 15_001 }, { maxAttempts: 0 }]) {
    await assert.rejects(awaitSynchronizedCandidate(receipt, { ...io, ...options }), /Unbounded/);
  }
});
