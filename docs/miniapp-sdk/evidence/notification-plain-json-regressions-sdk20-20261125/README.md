# Notification plain JSON regressions — actual Mac PASS

The original HanlinNotificationInvocationTests suite executed on source dff3b45c99a57bf8fe8ec721db3fa1fafce7134b using Xcode27.0 build27A266a / Apple Swift6.4 on the owned Mac. All11 test functions passed, including the three new independently authored APNs wire regressions; the original engine-parameterized function exercised Expo and NativeScript, for12 body invocations. There were0 failures and0 skips.

The compiler command completed at2026-11-25T21:16:50.257711UTC. Measured phase time86.5407380000106seconds; actual build70.12seconds and Swift Testing suite0.075seconds. Source/cleanup checks were clean. Actual warnings are retained in both raw log and acceptance.json. This is not a zero-warning claim.

The requested xUnit file was not emitted by the actual Swift Testing invocation. Acceptance is based on all11 unique positive raw test records, the2 parameter markers and the actual exit0 command state. No result file was invented and no repeat was run merely to change output format.

The regression tests verify external plain null/scalars/arrays/objects, an ordinary type/value user object, plain external emission, preserved internal tagged Codable, all required envelope fields and malformed values. Existing queue/receipt tests are unchanged. Root independently hashed all5 original raw members and matched all11 positive records exactly.

This unit pass is independent of the still-required rebuilt application/full52 and original OS notification delivery case. It does not turn the earlier real OS failure into a pass. Runtime code is unchanged between dff and the SDK20 generated-source carrier7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f; intervening commits contain evidence and three generated documentation outputs only.
