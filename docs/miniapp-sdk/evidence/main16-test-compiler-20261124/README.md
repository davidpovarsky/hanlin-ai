# MAIN16 — two test-source compiler corrections

Status: source corrections independently reviewed; native validation pending. Only `HanlinNativePresentationTests.swift` and `HanlinOriginalExpoWidgetTests.swift` change outside this evidence directory.

MAIN16 completed the real MiniApps build-for-testing successfully, then the AI test build stopped with two compiler errors. No application acceptance case ran. The exact diagnostic excerpts and authenticated AI log hash are retained here; the parent owns the full run artifact and complete build evidence.

The text-collection helper now gives flatMap an explicit `[String]` result and explicitly returns each existing branch. The original prepared-node declaration proves the child element/string shapes; recursive ordering and ignored nonstring handling are preserved.

The original Expo storage assertion now writes a UUID-scoped sentinel through the declared app-group UserDefaults suite and reads it through the genuine original `WidgetsStorage.getString` API. It requires exact value equality and defers removal of only that owned key. This verifies actual suite reachability without directly reading mutable nonisolated static state or introducing concurrency suppression. The original storage implementation is unchanged.

All six method names and the ordered 27+28 XCTAssert calls are preserved. The first draft placed fixture setup after the runtime assertion; the source-order inventory caught that ordering difference. Final fixture setup occurs before the replacement suite equality, retaining the original assertion order. No native execution was involved in that source inventory check.

Independent read-only review confirmed both final source hashes, real type/API compatibility and assertion semantics. The fresh primary-Mac check at 2026-11-24T16:38:32.423398Z showed Xcode27.0/Swift6.4 with three active xcodebuild processes. No focused probe was started, no slot was requested, and no other owner's process was changed. Root explicitly directed sealing the reviewed correction for its next full Xcode27.2 gate.

This receipt does not report successful compilation or execution of the corrected tests. It retains the exact source correction, original definitions, assertion inventory, peer review and truthful focused-check NOT_RUN boundary.
