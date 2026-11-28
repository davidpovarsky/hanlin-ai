# Share receipt-wait failure observation

The original NativeScript Share test failed its existing 120-second terminal-receipt wait in the retained ce896542 run. The recorded failure does not identify which iteration was waiting, its queue receipt, or the active runtime identity. Existing cleanup removes those transient test batches.

This test-only change records a bounded scalar snapshot at the original polling failure, before that cleanup, and rethrows the same error. The original 120-second deadline, 25-millisecond poll, initial 100-millisecond delay, both iterations, five runtime calls, 18 assertion lines, and all cleanup calls remain. Removing the explicit runtime import, the local observation helper and its catch wrapper recovers the complete original file.

## Recorded boundaries

The JSON line records the current process, iteration and batch ID; captured and current installation identities, generations and digests; active app/controller presence; the public NativeScript session identifier observations; and the existing per-ID receipt's status, attempt, failure code, lease and cancellation flags. It prints only result presence, never shared text or result contents. Error types are bounded; error messages and source are not serialized.

Generation values remain exact decimal strings. Variable strings are constructed from at most the first 256 UTF-8 bytes, and the encoded JSON must fit 16 KiB. Read or encoding failure cannot replace the original thrown error.

## Timing and ownership limits

The helper runs synchronously on the existing MainActor only after the polling loop throws. No extra Task, delay, success-path read, dispatch, retry or production API is added. Its single existing receipt read uses the unchanged store lock, which allows up to ten seconds to acquire the lock; filesystem and encoding work are not covered by a new wall-clock guarantee. Observation can therefore delay cleanup after the original failure.

These are sequential observations, not an atomic snapshot. A process-global NativeScript session ID does not prove that it belongs to this invocation. The original store API may create/open its transaction lock and decode a receipt; there is no new queue mutation or broad disk scan.

## Qualification

This is diagnostic source only. No Swift/native or synthetic test was executed for this change, and it makes no repair or root-cause claim. The exact original test and native controller remain responsible for acceptance. Production source and the current 396 SDK input paths are unchanged.

The source/API/inverse packet is retained as native-share-wait-observation-1aef1ec1. The prior failure excerpt and its authenticated authority hash are included here. source.patch.gz preserves the exact Git patch losslessly.
