# Original HTTP callback boundary observation

Base: 602b29e303a633155fe07583e9ece28fce0ba113. This is a DEBUG-only diagnostic candidate, not a lifetime, transport or Promise repair. No native command or tests were executed while preparing it.

## Actual reason for the diagnostic

The original full603 gate on source602 ended with 602 passes and the HTTP test failing at its original five-second within-limit await, before the existing within-limit-received checkpoint. Both added Promise delivery/cancellation controls passed. The real server wrote the complete 2,097,152-byte response. The retained sample of the actual native PID90703 shows the test worker waiting on its semaphore, with main/CFNetwork and JSC helper threads idle during the sampled window. This does not prove client completion, a dropped guard or a missing continuation.

The source-bound sample is retained in handoff/original-http-602b29e3-actual-sample/observation/sample-original-http-pid-90703.txt, SHA256 e70c29c64cdd1628bb2843a9a6e0f70a0b62415e5449334bc83baa423197ea44. All earlier failed native gates remain failures.

## What is observed

Only the existing per-execution logger and fetchManagerForTesting opt-in are used. Events contain fixed boundary labels, session UUID, actual PID, monotonic uptime/wall time, task/delivery identities, booleans and byte counts. They contain no response body, URL, user input or JSValue conversion.

Fetch observations bracket the original completion entry, the original current-execution guard and the already-converted raw-string handoff. Promise observations bracket the existing finish/dispatch/deliver path, the original settled/active/current guards, presence of the two continuations at their existing reads and the unchanged optional callback call. A call-attempt or call-site-returned label does not prove a nil optional continuation executed.

The existing HTTP test snapshots only filtered logger strings after its original cancellation/cleanup and records them through its existing stage recorder. The logger has an existing 500-entry and 8-KiB-per-entry bound. The main-queue snapshot flushes previously submitted logger messages; it is not a wait for callbacks that have not arrived, nor proof that later callbacks are absent.

## Lifetime and release boundary

No stored property, registry, cancellation hook, task budget, managed reference, JS callback root or additional asynchronous JS/context/state capture is introduced. The two managed values are read once at the original lines. Observations use those existing values only before the original call, and do not extend their last use afterward. Original guard evaluation counts, lock decisions and callback scheduling are retained.

The only retained object added by the test is the existing logger, which owns strings and no VM/context/state. Its snapshot is after the original outcome and teardown, outside the five-second wait. DEBUG diagnostic work has bounded overhead and may perturb timing or allocation; a passing diagnostic run alone cannot establish that the uninstrumented cause was repaired.

Every added executable runtime statement and helper is inside #if DEBUG. The recorded release projections remove those blocks and reverse only three explicit guard-format expansions, recovering both original runtime files byte for byte. This is source equivalence, not a new Release build result.

The manifest changes only the two matching top-level localSHA256 fields; original upstream repositories, commits, blobs, adaptation history and other fields are unchanged. The exact historical392-input path intersection is the two original runtime files and this manifest. The HTTP test is outside that SDK closure. Any later artifact qualification must use the actual new source fingerprint.

The original601 assertions and the two meaningful Promise controls remain603. The real proxy/server, two-MiB positive boundary, oversized response, callback behavior and five-second executionTimeout remain unchanged. Native execution belongs solely to the Mac owner after root integration.
