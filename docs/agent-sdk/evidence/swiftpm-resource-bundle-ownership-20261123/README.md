# SwiftPM resource bundle ownership — original app continuation

[Run45246711373](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45246711373), source36d3c51bdba93ada2c2722ed0e9b99109d84a616, **passed the full arm64 app/test build, current-product validation and runtime-copy signature verification**. It then failed the original resource scanner because the same SwiftPM bundle name appeared in two normal locations: the main app and its HanlinApplication package-product framework. Both original Xcode copy commands use the same built resource-product source. The smoke evidence does not contain the complete resource bundles, so their native post-copy equality is not inferred.

All342 selected test invocations remained **NOT_RUN**. Prepared Native assets from the failed run remain ineligible.

## Repair

The original scanner now recognizes one resource-bundle identity with multiple copies only when every relative entry, directory/file/link kind, file length, SHA256 and safe resolved link target agrees. Bundle names must match. Each bundle and resource target must remain inside its permitted owner. A conflicting copy fails with its first differing entry and recorded values. The main-app copy is selected deterministically when present.

The original canonical-source checks then run unchanged: each declared copied file must exist inside the selected SDK bundle and match its source bytes. A loose main-app resource cannot mask missing SDK content. Processed and otherwise unlisted resources participate in duplicate equality, so a stale Assets.car cannot be ignored. Successful output records every copy path and complete inventory digest.

No application, SDK Swift source, resource payload, package graph, native dependency or test assertion was changed by this repair. Original compiled app/test sources remain identical to the successful36d build; later integration changes are Motion preparation and evidence.

## Focused verification

The new normal two-copy fixture reproduced the original count rejection before the repair: one method, one ERROR, exit1. Afterward all8 affected controls PASS: the3 original tests and5 new controls for identical copies, changed copied content, changed processed content, missing canonical content in identical copies, and a resource link escaping its owner.

These are portable fixture controls, not Apple resource-byte or application test execution. The actual new scanner and all342 original invocations still require the next native continuation. Raw before/after output and precise source hashes are retained here.
