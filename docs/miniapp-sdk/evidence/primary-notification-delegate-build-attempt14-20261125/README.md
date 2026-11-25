# Actual notification delegate compiler failure and signature proof

This immutable packet records the SDK14 consumer attempt on b0cf26a668a698682f5307252f14cf0af8c6d00a. The MiniApps build failed before any of the original 25 + 27 acceptance cases executed. Its complete compiler log is retained losslessly, together with the actual command/controller status and cleanup evidence.

The compiler reported both a non-matching optional UNUserNotificationCenterDelegate requirement at line 37 and an Int?-to-UNNotificationPresentationOptions? conversion error at line 42. Retaining both diagnostics matters: a raw-value conversion alone would leave the method outside the actual imported optional requirement.

The sole Mac owner then compiled a focused signature probe against the actual installed iOS 27 arm64 simulator SDK, Swift 6 and C++ interoperability, treating warnings as errors. The probe uses async Int, forwards the prior optional raw Int unchanged with nil fallback 0, and asks the compiler for its Objective-C selector. The actual probe completed successfully with an empty diagnostics file. Its raw source, exact command/timing state, and installed SDK header are retained here.

The corresponding minimal production correction is b10bd9746b06edc88e5d5b525f1ef0eb1b4317bc, source SHA eacf5e748287603ef4e6796d2f2d0016b7563aa5de62bca4478a693d2b82eb83. This raw record supplies the independently verified packet that was still transferring when the critical source commit was sealed. It does not alter that earlier report or the frozen successful SDK14 preparation snapshot.

All 17 original packet members and the original receipt were verified by size/SHA-256. Large text files are retained as deterministic lossless gzip; retained-members.json binds every stored object to its full original bytes and identity. No native query, compiler, generator, test, source mutation or SDK repack was run by this evidence-only reconciliation.

The original 52 cases remain NOT_RUN_BUILD_FAILED at this frozen checkpoint. A successful signature probe is distinct from a successful full consumer build, runtime handler execution, OS callback delivery, APNs provider delivery, or physical-device acceptance. Those outcomes belong in separately timestamped later evidence.
