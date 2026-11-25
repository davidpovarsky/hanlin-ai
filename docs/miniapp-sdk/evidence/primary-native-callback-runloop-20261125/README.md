# NativeScript main-run-loop callback correction

This checkpoint corrects background result delivery in the original Objective-C session bridge. A synchronous legacy bridge call can run inside an already executing main GCD block and pump the default main run loop. Dispatching its completed result back to main GCD cannot reenter that block, so the original call waits until its existing 20-second timeout. Scheduling the same pending native box with CFRunLoopPerformBlock in the default mode, followed by CFRunLoopWakeUp, lets the existing wait receive it on the main thread.

The pending callback's synchronized single-delivery take, weak owner, provider binding, asynchronous API and synchronous invalidation are unchanged. Queued work retains the native box; invalidation clears its JS completion before VM teardown. The original shipped NativeScript Core mainthread-helper uses this same main-run-loop scheduling mechanism. No fixture, runtime engine, runtime timeout or acceptance selector is changed.

## Retained actual failure

Attempt7 ran source fd81d602. Its NativeScript parity bundle began at 22:44:35.429 UTC. The actual JavaScriptCore job completed at 22:44:35.489 with exit0, the expected unpredictable nonce and a5ms execution duration. The next Node job did not start until about20seconds later. Original stdout, exact JSC/Node job JSON, their hashes and the bounded extraction are retained under raw/actual. These observations prove engine completion and the delayed caller boundary; they do not prove corrected application rendering.

## Focused original-bridge regression

The exact production Objective-C implementation and unchanged public header were compiled on the primary Mac against Apple's original Foundation/XCTest, using one compiler job. A controlled native provider isolates callback scheduling.

- Baseline: the real synchronous API entered from a main GCD block returned the original20-second timeout. One test failed with the expected two assertions.
- Corrected implementation: all3tests passed, zero failures or skips. The nested main-GCD synchronous call returned in0.023s. Ordinary asynchronous completion stayed on the main thread. A background result queued before invalidation lost its captured completion before invalidation returned and did not invoke it later.
- An initial harness compilation failed because its selector used the Objective-C-derived spelling instead of Swift's imported setActiveSession name. The error, initial test and state remain retained. No callback test or candidate execution occurred in that initial attempt. Only that spelling and an immutable Sendable capture token were corrected before the recorded red/green execution.

The final proof finished at 2026-11-25T00:02:37.606743Z. See receipt.json and raw/state.json for complete command arguments, toolchain, code hashes and raw log identity.

This is a callback scheduling regression, not the52-case application acceptance. The original MiniApps/AI native builds and runtime/UI acceptance still require execution with this correction embedded.
