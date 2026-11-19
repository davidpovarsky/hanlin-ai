// Keep branch-dispatch receipts bound to the exact synchronized commit.
// The candidate workflow and trusted consumer still bind actual GITHUB_SHA.
const shaPattern = /^[0-9a-f]{40}$/;
const fail = message => { throw new Error(message); };

export function parseSynchronizationReceipt(output, expected) {
  const lines = String(output).trim().split(/\r?\n/);
  let receipt;
  try { receipt = JSON.parse(lines.at(-1)); } catch { fail('Missing canonical synchronization receipt'); }
  if (!receipt || receipt.schema !== 1 || receipt.repository !== expected.repository
      || String(receipt.number) !== String(expected.number)
      || receipt.baseRef !== expected.baseRef || receipt.headRef !== expected.headRef
      || !shaPattern.test(receipt.head ?? '') || !shaPattern.test(receipt.previous ?? '')
      || !shaPattern.test(receipt.base ?? '') || typeof receipt.changed !== 'boolean'
      || receipt.changed !== (receipt.head !== receipt.previous)) {
    fail('Canonical synchronization receipt does not match this candidate');
  }
  return receipt;
}

export async function awaitSynchronizedCandidate(receipt, {
  readPull, readHeadRef, wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds)),
  now = () => performance.now(), maxAttempts = 12, timeoutMilliseconds = 15_000,
}) {
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 12
      || !Number.isInteger(timeoutMilliseconds) || timeoutMilliseconds < 1 || timeoutMilliseconds > 15_000) {
    fail('Unbounded candidate convergence policy');
  }
  const deadline = now() + timeoutMilliseconds;
  const remaining = () => {
    const value = Math.floor(deadline - now());
    if (value <= 0) fail('Candidate synchronization did not converge before the deadline');
    return value;
  };
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const pull = await readPull({ timeoutMilliseconds: Math.min(5_000, remaining()) });
    const headRef = await readHeadRef({ timeoutMilliseconds: Math.min(5_000, remaining()) });
    remaining();
    if (!pull || String(pull.number) !== String(receipt.number)
        || pull.state !== 'open' || pull.draft !== false
        || pull.base?.ref !== receipt.baseRef || pull.base?.sha !== receipt.base
        || pull.head?.ref !== receipt.headRef || pull.head?.repo?.full_name !== receipt.repository
        || headRef?.ref !== 'refs/heads/' + receipt.headRef || headRef.object?.type !== 'commit') {
      fail('Candidate source/base changed during synchronization');
    }
    const observed = [pull.head.sha, headRef.object.sha];
    if (observed.some(sha => sha !== receipt.head && sha !== receipt.previous)) {
      fail('Candidate moved to a different head before dispatch');
    }
    if (observed.every(sha => sha === receipt.head)) {
      return { pull, headRef, attempts: attempt };
    }
    if (attempt < maxAttempts) await wait(Math.min(500, remaining()));
  }
  fail('Candidate PR and branch did not converge to the synchronized head');
}
