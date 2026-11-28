# Actual receiver inspection and repaired-import observation

The focused19-v7 original repair case ran source f6bb035f2828ec24a683bb2f5f1dddb27143dc4a with SDK19. AI build-for-testing passed in 121.2856520839996 seconds. The original repair case executed and failed: 0 passed, 1 failed, 0 skipped, 251.326 seconds. The failure was the diagnostic-sheet absence assertion at MiniAppAuthoringUITests.swift:92 after MiniApps had returned to the foreground. Xcode returned 65. This packet preserves that failure.

## Completed build and received package

The actual AI Node build job 1e001f77 completed at 14:08:19.477 UTC with exit code 0 in 51.672 seconds. Its report has succeeded=true, strict=true, no diagnostics, no timeout and no cancellation. The built archive is 7,247 bytes, SHA-256 74db9d447035e1b8e000394a515093094b99f18a5587be54048a766232306727. The same bytes exist in the build output and the outgoing installation transfer. Its 16 ZIP entries pass CRC verification; its retained source and compiled module match the descriptor hashes.

Transfer 7d064eea reached status received at 14:08:34.434519 UTC. It did not reach installed in this captured evidence and has no installedPackageID. MiniApps started its own original validation job aebbeb51 at 14:08:35.008. The retained record has state=running, zero output and a null result. Test teardown then terminated the applications and the owned simulator was shut down. These are historical persisted observations, not a claim that a process is still running.

## Why the UI observation was premature

The actual failure screenshot and accessibility tree show Inspecting… beneath the still-present diagnostic sheet. That sheet shows Errors 0, Warnings 0, the validation-pending explanation and the previous repair-submission message. These observations do not establish a new compiler rejection, installation success or a production sheet-lifecycle defect.

The test had treated the always-present import-picker button as proof of completed installation. Source review shows that button also exists while preview is nil during receiver inspection. The earlier foreground return and picker existence therefore did not establish receiver completion.

## Exact test-only correction

Commit 7bf0c2fdc2f7168d6b98dda66f443ae032fe1c11 changes only AI_HLYUITests/MiniAppAuthoringUITests.swift. The receiver observation now waits up to 120 seconds for the composite UI condition: picker present, no Inspecting… or Installing… progress, no Install preview button and no diagnostic sheet. The subsequent actual installed-card wait increases from 30 to 90 seconds. The card remains the positive catalog assertion; native result 42 and the agent reading an actual installed receipt remain required.

The original 600-second whole-case allowance, 420-second foreground wait, production importer/compiler behavior, SDK and final outcome assertions are retained. No production error suppression, fabricated receipt or V8 success is claimed here. The next actual native case must establish the correction's outcome.

## Accounting and raw evidence

All six actual focused charges are retained: 366.7222996670025, 977.134837125006, 39.67624695900304, 713.0760274589993, 544.1797895409982 and 443.2465754169971 seconds. Their cumulative total is 3084.035776168006 seconds. The original 3600-second ledger and primary cumulative time 18556.947548752043 are unchanged.

Both V7 controller layers record empty cleanupErrors and sourceErrors. The child confirmed Shutdown with no owned runners; the outer observed Shutdown and an empty owned group. Its repeated shutdown command returned 149 because the simulator was already shut down, and that original response is preserved.

The three complete immutable source packets retain their relative member paths and byte-identical source-receipt.json files. Identical overlapping files are intentionally retained under both original packet paths and share Git blob storage. The exact V7 controllers and recovery inputs, source patch, bindings and derived timeline are included. This evidence proves the real completed build and receiver inspection boundary; it does not prove Repair PASS, original52 PASS, NS5 acceptance or OS-event delivery.
