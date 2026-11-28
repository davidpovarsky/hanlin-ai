# Native Large Widget component pilot

Source commit 8c968dd2c38f6277216a70288991a7efa2656511 adds one bounded native UI case, a separate authored Widget fixture, its observer, and explicit route/planner ownership. It preserves all 46 existing UI methods, their helpers and assertions, all existing Matrix bytes, and the 25 original Widget producer outputs.

The whole frozen 47-method XCTest file passed one actual Apple typecheck on Xcode 27.0 / iPhoneSimulator SDK 27.0: exit 0, no diagnostics, 1.705735 seconds within the original 120-second bound. This is compilation evidence only. No app build, Simulator case, hosted 27.2 execution, recipe execution, or new portable control ran as part of this seal.

## Native evidence the new case requires

The case must create and reopen a fresh UUID-named configuration, select an actually offered Large gallery page, place its own Widget, and identify seven individual native elements: count, Add, ProgressView, Gauge, Chart, SF Symbol, and Link. It records each observed native type, label, value and frame without inventing Gauge or Chart element categories.

One real Add tap must cause exactly count/revision 0 to 1 with a fresh native nonce. The observer binds source, product, container, family, instance, placement/action times and the actual state transition. Captures include native accessibility text and PNGs. Prepared data alone cannot satisfy this pilot. The PNGs still require visual review for chart bars, progress fill and symbol appearance.

The test owns its named Widget cleanup and restores the observed prior orientation. Its new allowance is 420 seconds; the original observer 2100-second bound and paired job envelope remain unchanged. No existing test receives more time.

## Qualification and remaining gates

The eight new observer controls and one planner control are reserved for one execution in the next required full original CI on the integrated source. A previously proposed focused command remains unexecuted. Root owns the separate two-insertion workflow patch and any dispatch.

The source change has zero intersection with the retained 396 SDK inputs and 99 Host inputs, and with the current collector roots or explicit entries. This static fact does not establish a new SDK or Host run. The new Widget-only archive uses the original recipe exports; no foreground authoring CLI result is claimed.

This pilot does not close coverage for other families, system appearance, RTL, VoiceOver speech, asset images, previews, Link navigation, ActivityKit, or physical devices. Eight family metadata declarations are retained for the original package publication contract; only actual Large placement belongs to this case.

## Evidence

The source and typecheck reviews are included verbatim. Their timestamps explain the progression from a source-only frozen candidate to the later typecheck PASS; earlier records have not been rewritten. source.patch.gz is a lossless copy of the reviewed raw patch. source-validation.json records whole-original inverses and exact preimage/candidate hashes. source-seal.json binds all nine actual committed Git blobs.

The full raw typecheck packet remains immutable under widget-components-ui-typecheck-fc5ce1ba-pass-r1; its exported 23-member manifest and actual receipt are retained here without duplicating the whole UI source or binary artifacts. Root independently verified all payloads, the original command/controller relationship and unchanged source authorities.
