# One shared application image: original failure and focused repair

## Original native result

Run [45265065184](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45265065184), attempt1, source `ade2f626e37102abde83050c94d524d19e0726bb`, failed after the real full arm64 application/test build, current-product admission, resource scan, localization scan and simulator boot passed. This is not an eligible Native18 release producer. Prepared artifact14864280939 was not acquired or published.

Smoke artifact14864733741 was acquired once:66,998,891 bytes, SHA256 `62dab969033c2f5db51bf9b9e31640521eec6f3848e08b8c20e2ee1a359679e9`. All3,482 safe unique ZIP members were streamed through CRC and SHA256 verification. Only73 original files (5,500,780 bytes) were extracted. Embedded xcresult containers, the full compile log, and unchanged framework diagnostic declarations remain in the preserved original ZIP. The earlier connector internal error did not execute or create the destination; the one actual download exited0.

The original unit JSON contains298 method nodes, including18 parameterized parents with50 argument children. It reports330 unique invocations:323 PASS and7 FAIL. Method aggregates are292 passed/6 failed; they must not be added to argument counts. The seven failed invocations are Calendar denied/timeout, failedWrite, actual EventKit owner continuation, original credential error typing, MCP descriptor persistence equality, and Share Inbox tamper rejection. Root owns reconciliation against every authored342 identity, including explicit platform exclusions. The UI result contains one infrastructure failure and zero authored UI method executions: UITargetAppPath resolves to an extensionless AI_Hanlin path.

Resource scan:PASS,37 canonical copied-resource comparisons, zero errors, two equal49-entry/45-file bundle inventories. Localization scan:PASS,177 packaged checks against3,683 catalog values, zero errors, four equal19-entry/15-file inventories. These are actual original native gates, independent of later test failure.

## Observed duplicate ownership

The original unit log contains129 duplicate-class warnings:94 pair the HanlinApplication dynamic framework with AI_Hanlin.debug.dylib;35 pair it with AI_HLYTests.xctest. They include `HanlinScriptStore.HanlinAtomicScriptStore`, `HanlinScriptDeviceServices.HanlinAppleCalendarService`, the chat UI and scripting modules, and the native Expo widget modules. The original linker commands confirm overlapping Swift module inputs in these images. Exact warnings, source hashes, linker commands and per-target product lists are in `link-analysis.json`.

The Share Inbox fixture expects the correct contract. `batch` validates metadata with `verifyFiles:false`; `ownedFile` verifies actual contents; `prepareDraft` must propagate the original typed integrityMismatch rejection before publishing attachments. Its existing catch did not match the actual thrown error at the await call. This is consistent with duplicated Swift implementation/type ownership, also seen in credential casts and Calendar error classification; native evidence after this graph correction is still required. The security assertions are retained unchanged.

## Minimal source correction

`Scripts/SDK/update_project.py` previously appended aggregate HanlinApplication links alongside all original product links. The app had49 linked products; hosted unit tests had18. Both now link the single HanlinApplication image. The actual SwiftPM target/product closure proves all removed products remain reachable through that image. Unknown or genuinely independent products and native/system file references are preserved by the updater.

The app's49 and unit target's18 `packageProductDependencies` declarations remain byte-equivalent. They retain compiler visibility and, critically, are the original input from which `generate_manifest.py` derives the full SDK implementation dependency closure. Removing those declarations would silently shrink future manifests. Only the two Frameworks-phase objects changed; all other project objects, including every extension and MiniApps target, remain equal. The original linkage validator now distinguishes declared source availability from binary image ownership and rejects any extra linked implementation beside HanlinApplication.

## Focused verification

Two new ownership regression controls failed on the original graph and updater. All three new controls then passed: single checked-in image ownership, regeneration/idempotence with original duplicate links reintroduced and all unrelated objects preserved, and full declared-product reachability with unknown products retained. The original source-linkage gate passed. The original full generator `--check` passed against the changed PBX input:44 products,108 targets,507 original application Swift files,18 package-manifest inputs,0 local package edges. Package.swift is byte-identical. No prior native suites were replayed and no CI was dispatched.

This commit does not rename a target, modify an implementation, change a dependency pin, enable native model tools, or alter test assertions. The separate Xcode host-target name collision is being repaired independently. Native post-repair compile, duplicate-warning elimination and affected acceptance remain NOT_RUN.
