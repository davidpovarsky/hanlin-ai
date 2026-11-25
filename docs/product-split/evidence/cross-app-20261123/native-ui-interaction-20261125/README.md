# Native input diagnosis and isolated UI repair — 25 November 2026

The actual original 23-case gate on 4b772b5a7f0eb826c9b9204122bba516af777592
built the shipping app and all test targets successfully. The unmodified test log
reported 16 passed cases and 7 failed cases. Its original xcresult is still
finalizing through Xcode's automatic simulator diagnostics at this checkpoint;
these are observed case outcomes, not a claimed passing acceptance gate.

## First causal failures

Original XCTest accessibility snapshots report "-editedgamma" and "-editedalpha"
after the real TextView received typeText("-edited"). The context UUID, package,
initial text and native increment assertions had already passed. A center tap
placed the caret at the beginning. The actual-caret-failure.json receipt binds the
exact AX lines to the original 57,166,402-byte app console and its SHA-256.

The shared UI helper now uses the public iPad hardware keyboard Command+Right
event after focusing that one-line input, then types the same suffix. The exact
gamma-edited/alpha-edited (and all other window) value assertions, counters,
request/document identifiers, prepared callback checks, cancellation behavior and
persisted-result checks are unchanged. All four method names and all 52 assertions
in the two changed test files are preserved.

The failure screenshots and AX trees are captured before a cleanup helper closes
only request scenes actually opened by the failing test. It uses the shipping
cancel/close UI. It neither synthesizes results nor changes another request. The
async XCTest teardown explicitly performs these UI actions on MainActor.

Four later UI methods failed before their catalog became ready, with failed
request scenes still present. The new lifecycle test also met an already active
NativeScript registry; the unit host's original console shows restoration of the
failed native scene. Those methods remain failed, not passed by inference. The
singleton guard and lifecycle assertions are unchanged.

## Verification and next execution

The actual iOS 27 simulator Swift 6 UI source set typechecked in 3.824 seconds
with the two modified files in a separate preflight directory. Exit status was 0.
Existing setup actor warnings remain; this is not a warning-free compilation or
an app acceptance result. See typecheck.json for full command and source hashes.

The unchanged-product-inputs.json receipt proves that only these two existing UI
test sources changed; all other existing tracked product, SDK, dependency and
project inputs remain identical to the already compiled 4b772 source. The active
original Mac source and test bundle have not changed during its 23-case run.

The next run must rebuild the real UI test bundle, recheck the complete actual
app inventory against the immutable producer receipt, and execute the failed
native acceptance goals. No assertion, selector or success criterion is relaxed.
The original failure xcresult, logs, screenshots and AX evidence must be retained.
