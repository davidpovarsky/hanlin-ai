# Original paired products — native45133337462

**The actual Hanlin MiniApps shipping target built successfully. The paired UI cases did not run.** The full Hanlin test build failed in the thin widget host, before either app could be installed for the three cross-product tests.

The [original run](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45133337462) used source`6772dce6304fc6761a2200314f7d2020dc782e47`, Xcode27.2, Swift6.4.2 and an iPhone18Pro simulator on iOS27.2. `HanlinMiniApps` built with its original simulator ad-hoc entitlements in1975.645s; the subsequent `AI_HLY` build-for-testing failed after862.151s. [Original command receipts](commands.jsonl) retain both exit codes, exact arguments, durations and log hashes.

## Exact failure and existing repair

The only failing Swift diagnostics in the actual AI build are unresolved `Widget`, `WidgetBundle` and derived `@main` in `HanlinScriptingWidgets/HanlinScriptingWidgets.swift`. The [diagnostic excerpt](ai-build-diagnostics.txt) preserves original line locations. Root source`9e4fbcbdeed05aa8dea0ab3c55997a73383f92b4` already restores exactly the missing original `import SwiftUI`. This receipt creates no duplicate fix.

`testCompanionReturnsActualPrivateValueToOriginalChat`, `testCompanionCancellationReturnsWithoutChangingPrivateState` and `testOriginalPackageAndSavedStateTransferThenRollback` are all **NOT_RUN**. There is no actual UI assertion failure or visual acceptance from this attempt. The optional environment screenshot is not a substitute for an app screenshot.

## Passing evidence retained with correct scope

The [native foreground result](foreground-results.json) records53/53 executed route/ledger cases on the actual Mac, with compiled binary/source provenance and original output. Those are Apple native contract tests, not the three iOS UI cases.

The workflow's original reuse guard independently authenticated Host prerequisites from run44351078724@0c822902: focused7/7 and Host152 passed of153, with one original skipped case. [The reuse receipt](host-reuse.json) retains origin artifact14454531510 and its verified digest. These were **REUSED_VERIFIED_PASS**, not rerun on the current source. The standalone baseline20+7 was not dispatched.

The [MiniApps build success excerpt](mini-build-success.txt) and the original `MiniBuild.xcresult` establish compilation of the actual shipping target, including the current shared catalog/provider/resource closure. This does not establish catalog rendering or transfer behavior.

## Existing incremental compilation path

The run saved1,110,940,442bytes of compatible compiler state after failure, as permitted by the existing workflow. From6772dce6 to0dae98f7, none of the graph/lock/tooling inputs forming its cache-prefix key changed. The two changed Swift source-key inputs are the original Composer bridge alias and the new shared draft owner.

The original workflow restores the compatible toolchain/graph-prefix cache, then restores prior input timestamps only where file SHA256/size and directory-entry digests match. It still invokes normal `xcodebuild`, so changed input is recompiled. Cache availability and duration are not promised before the next actual runner. There is no supported separate compiled-app artifact/skip-build mode, and no new reuse infrastructure is added. [The bounded review](compiler-cache-reuse-review.json) records exact keys and changed inputs.

## Artifact

`app-split-45133337462`, ID14803354012,18,239,253bytes, SHA256`83ecd7184113a12e058b5211637105ef10ec151abd0e9058686af90df567ca50` was downloaded once and matched the API size/digest. The verified ZIP on Oracle and original GitHub artifact retain complete7.25MB/8.44MB build logs and both native result bundles. This small Git receipt retains the relevant excerpts, source/binary provenance and exact hashes instead of duplicating the archive or compiler cache.

The paired acceptance remains open until its three actual original UI cases execute on the corrected qualified source. No physical-device or distribution result is claimed.
