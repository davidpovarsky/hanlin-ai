# SDK20 original native dependency preparation

This is dependency preparation for source `7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f`, not an application-build or runtime-test result. Both current application builds, one new original 25+27 run, the original OS-notification case and a separate current NativeScript five-engine case remain pending at this checkpoint.

## Actual result

The original native dependency chain reached PREPARED at 2026-11-25T22:12:07.026124Z. All 15 required framework targets were inventoried. The original NativeScript metadata generator was compiled under Xcode 27.0, using the existing Python 3.12.16 and original CMake 4.5.1 tool installation. The four final original commands all exited zero: NativeScript preparation, NativeAPI artifact verification, NativeAPI metadata verification and NativeAPI preflight.

The 235 SDK20 source inputs and both exact RuntimeHostResources archives retained their prior identities. Host SHA256: `ed18d93a88a1020bc2140417cea3847daf3d03472cdd4769d9a5ac4e44f48a22`. SDK manifest SHA256: `6f11ed8da3df18627f05932d47b5b68dec54eb26ac396151a21cbc8c3e65800e`. Tracked source remained unchanged and the prepared tracked diff is empty.

## Preserved failures and recovery

1. The first four original commands passed: Expo tooling installation, NativeScript tooling installation, exact type preparation and original Expo native preparation. NativeScript then failed before its compiler because PATH selected Xcode Python 3.9.6, whose tar extraction API did not support the existing original builder invocation. That phase remains FAILED, with all five raw logs retained.
2. The next original NativeScript invocation used the existing Python 3.12.16. It reached CMake invocation, then stopped because CMake was absent. This second phase remains FAILED.
3. Existing Homebrew installed only the missing CMake tool. Auto-update and cleanup were disabled. Actual version, binary hash, command output and elapsed charge are retained.
4. The final continuation reused the original first four successful commands and ran only NativeScript plus the three original verifiers. Genuine NativeScript C++ metadata compilation passed. No source implementation, assertion, dependency lock, original test or SDK payload was edited to avoid either environment error.

The independent receipt verifies all 29 raw packet members, including losslessly decompressed logs, against their original bytes and digests. Original warnings remain in those logs.

## Accounting and launch prerequisites

The four actual preparation charges are 188.837976625, 5.938364417001139, 7.347363291992224 and 101.68132462500944 seconds, totaling 303.8050289590028 seconds under the same original 1800-second preparation allowance. These operational figures do not impose application limits. Prior runtime, OS, restoration, unit and Oracle SDK ledgers are not reset or added to this total.

The current original workflow generated the missing 217-byte Config.xcconfig (`03d96d520f785e34d85b643e31bcb4a424e46e76a81c6b4c245f91eaac3e110f`). A later read-only launch readiness observation recorded 121,385,590,784 free bytes and an absent new DerivedData directory. It is a launch precondition, not evidence of a build or test.

See each phase's original receipt/state/logs, the three exact preparation controllers/plans, `independent-verification.json`, the final phase's `prepared-frameworks.json` and readiness/config authorities. Original raw paths are preserved for provenance; this folder contains their exact copied bytes.
