# MiniApps catalog readiness: owned Spotlight maintenance

Status: independently reviewed source change. Apple compilation, the affected XCTest suite, original app/OS acceptance, and the fresh SDK producer are NOT_RUN for this candidate.

Source commit: 2e1909d61c1ca31e8783c97dd694156c518883db, based on 4d6809376bcdd65666c1410aa2c35ddc1f27e86b. The source commit contains exactly two product files and the existing DiscoveryAndCapture test file. This separate commit contains technical proof only.

The source change addresses an observed readiness dependency: the installed catalog waited for CoreSpotlight to acknowledge deletion after its durable snapshot was already published. Retained hosted failures reached that exact await. Other retained launches returned successfully after different amounts of time. This is not evidence that every launch hangs or that a callback cycle caused the failures.

The actual change and its review limits follow. References to added tests describe their assertions, not executed results.

## Evidence and intended behavior

The actual hosted Editor/State evidence binds six failed app PIDs to Loading apps, successful durable snapshot publication, and an outstanding write.delete.begin with no retained return. Separate Gallery evidence contains three such failed launches, one measured 7.0289-second delete/return interval, and a successful return at 41.225 seconds of the write span whose beginning lies outside the capture. These observations establish a variable-latency readiness dependency. They do not establish a permanent OS hang or a reindex callback cycle.

The candidate removes only Spotlight acknowledgment from catalog readiness. The original publication path still awaits durable widget publication, LiveActivity reconciliation, synchronous current system-record projection, the existing Capture reconcile/coalescing path, and compact configuration publication. Provider/query/UI paths and the entire Capture coordinator remain unchanged.

## Ownership and ordering

1. Publish current records synchronously from the same installed package snapshots and artifact-root resolver. Request a single retained MainActor Spotlight worker before yielding. Additional publications update current records and its requested flag.
2. Keep the caller's existing Capture owner/coalescing loop. The original owner still awaits Capture; already-coalesced callers retain their existing fast-return behavior. No new Capture read/write, selection, window, photo, inbox or listener operation is introduced.
3. The worker snapshots the latest desired Spotlight records each iteration, serializes the real delete/index through the existing previous-write task chain, and checks for a newer publication after actual return or error. No repeated task per publication, detached task, timer, sleep, deadline or automatic same-input retry is added.
4. Invalidate the success cache immediately before a possibly partial real write. Commit only after actual success inside the serialized task, before a successor is released. An old caller resuming late cannot overwrite the cache for a newer successful generation. A failed deletion/index cannot leave an old success cache that suppresses repair.
5. The existing explicit reindex callbacks still await real OS completion and throw real failures. If records change during that await, reindex completes the then-current projection before returning. Its entry/type/product semantics remain, with an explicit busy rejection during product transfer. Query callbacks and their acknowledgment order are byte-unchanged.
6. hasPendingWork counts the original Capture owner, retained Spotlight worker, and queued/active explicit writes. Platform's existing transfer admission adds only that predicate. Ownership is registered before the first suspension and released on success/error. The completed serialization tail alone is not busy.
7. Window departure does not cancel process-wide maintenance. Worker ownership deliberately lasts until the real system operation returns; no timeout, forced cancellation, fake success, or discarded OS acknowledgment is introduced. Transfer remains busy if an OS write remains genuinely pending.

## Test seams and controlled coverage

All seams are internal to the existing internal MainActor class. Production call sites use defaults: actual Bundle product identifier, existing shared Platform transfer state, original CoreSpotlight delete/index implementation, and original shared Capture reconciliation. The installed-data overload uses the same original catalog function and a nonescaping artifact-root resolver. The internal drain method observes the owned worker for deterministic cleanup; catalog readiness does not invoke it.

Six additive methods in the existing XCTest suite use actual installed-package snapshot/catalog contracts and controlled asynchronous operation boundaries:

- Held index and held Capture assert that publication waits for Capture but not index completion.
- Three publications while a write is held assert that only the first and latest generation are written, with one active write.
- A potentially partial failed deletion followed by restoration of the previous desired records asserts that the success cache cannot suppress repair or lose newer publication.
- Failure remains visible, no autonomous retry occurs, explicit callback failures propagate, and a later actual successful request clears the failure.
- Explicit reindex stays unacknowledged until the latest generation actually finishes, and writes remain serialized.
- Pending worker/write ownership blocks transfer admission; a completed tail does not; callbacks/publications cannot start during a transfer.

The nine original XCTest methods, all their assertions/helpers/deadlines, and all original UI selectors remain exact. The six new test gates release outstanding continuations even on an assertion failure and use the suite's existing three-second expectation style. They are source-only controls until the Apple test host actually compiles and executes them.

## Validation and remaining limits

Only three source paths change; two are in the measured 396-input SDK set. Packages and original native 619 tests are untouched. The source proof mechanically replays/reverses every production substitution and removes one test insertion to recover entire original files. It also binds unchanged Capture/provider/entity/view/catalog files, real case receipts, and exact selectors.

No Swift compile, test, Simulator, app build, SDK producer or native retry was executed in this lane. Mac/root own the original affected native command and current SDK qualification. Actual OS catalog/Spotlight/Capture/transfer acceptance remains required. The OS operation itself can still be slow or fail; Capture/LiveActivity/configuration waits deliberately remain. No callback deadlock or native latency improvement is claimed from this source candidate.

## Exact preservation and review

The one Platform transfer-admission predicate is the only change in that entire file. Its durable publication, LiveActivity, Capture call, configuration, engine and lifecycle bodies remain exact after removing that predicate. The entire Capture/provider/entity-query/view/catalog files remain byte-identical. Removing the single test insertion recovers all nine original methods and their assertions, helpers and deadlines.

The internal drain joins only the retained worker. Explicit reindex callers separately await their own operation; the explicit acknowledgment test does so. No test is credited as actual product transfer or real CoreSpotlight acceptance.

Both independent review receipts are included verbatim. The lossless source patch and committed-object source hashes are included. The SDK admission summary compares all 396 accepted inputs and all 99 Host test inputs against the actual donor Git objects: 394 SDK inputs are unchanged, two changed, and all 99 Host inputs are exact. This makes a fresh original SDK13 qualification necessary; it does not itself qualify a new archive or renew a native PASS.

The private original failure/positive timing packets remain immutable and are identified by SHA256 in source-qualification.json. This proof does not replace them or rewrite prior outcomes.
