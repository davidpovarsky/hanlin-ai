# iPad interaction repairs after TestFlight 145201

Date: 2026-11-22 (Asia/Hebron). Owner-authorized continuation.

## Source and acceptance context

- Shipped baseline: 0.7.3 (145201), source `927001ac4ac2f3f3cf837df50ec3bb20a0648b48`.
- Current verified internal TestFlight release: **0.7.3 (145401)**, uploaded source `c4b80bd60e291c5f0198efb7b9384ec9ff5a39f2`; Apple reports VALID and IN_BETA_TESTING. Physical iPad acceptance remains open.
- Branch: `codex/hanlin-ipad-interactions-20261122`, parent `5b0a369dd674a96a3f2583ad331c1ba83ec03501` (shipped source plus release documentation).
- Renderer: [6e884c73352a272c4e7bf8a5917e8b2157bc952e](https://github.com/davidpovarsky/hanlin-streaming-markdown/commit/6e884c73352a272c4e7bf8a5917e8b2157bc952e), pinned consistently in the app project, Package.resolved and HanlinPresentationSDK.
- The owner reports an improvement but supplied two new crashes and concrete interaction failures. Physical acceptance remains open.
- Full Morph reference SHA-256: `51bb10cdf71ee1c10cac8108f602eee4b34e78967de23dc437985aa89db9bbbb` (1,269 lines).
- Full V17 reference SHA-256: `f984930f659c34b791d610b3716b7cfb3d9545040b2c4d567b181a4ec46cc14e` (2,391 lines).
- The new explicit instruction moves controls inside the input. It supersedes the previous external quickbar layout while preserving the plus shape, bottom anchor and three glass identities.

## Requirements and implementation

| Requirement | Change | Remaining acceptance |
| --- | --- | --- |
| Crash on activity collapse | Per-call payload projection belongs to the mounted disclosure content. Closing no longer empties entries and inserts fallback ScrollViews during the outgoing animation. Layout places the child at full finite natural height; only the outer reveal clips. | Physical collapse/expand reproduction; source repair does not prove all crashes eliminated. |
| Controls inside composer | Model picker, tools, microphone, expand and primary action share the input glass. Adaptive layout preserves the model source. Shared metrics define spacing and 44pt hit targets. | Wide/narrow, keyboard, Dynamic Type. |
| Message preview | A 1-second stationary native hold opens a bounded popover which fills actual hosting bounds, preserves RTL/locale/theme/Dynamic Type, and anchors to a live controller. Existing selections/handle drags cannot trigger it. Model headers preserve access for rich-only replies. | Actual pixels and hold/selection precedence. |
| Continuous text selection | Contiguous prose, headings and lists share native selection. Select Text provides one attributed document across rich-block boundaries. Normal rich renderers remain. Saved excerpts retain exact source identity; original/translated and full-message/part ranges stay distinct. | Cross-paragraph Hebrew/English/code, excerpts and sources. |
| Status / hierarchy shimmer | First non-interim answer text, including provisional streaming text, ends generic working status. Real concurrent tools remain active. Motion belongs to the deepest visible active node or its collapsed ancestor. Waiting for approval is distinct from execution. | Live search, concurrent tools, approvals, answer start/end. |
| Model popup / double entrance | A real UIKit toolbar item anchors the system popover morph. All Models route and target size change together, with no second matched geometry/scale entrance. Resize generations protect reopen; cancellation settles the resize instead of leaving controls disabled. | Source morph, back, resize, keyboard and reopen. |
| Mini Apps in bubble | Launch-only catalog is an internal Morph page with native search and no management/import/edit controls. Stable host owns launch and reuses the actual engine dispatch. | Open/return from installed engines. |
| Other controls close bubble | Independent model presentation preserves the general/tools page. Editor focus, attachments, settings and prompt actions retain the bubble. | Mixed interactions. |
| Mic / expanded editor | Mic and expansion remain enabled during response streaming. Voice sheet is attached to the stable composer host. Expansion grows the same native editor/glass field, with keyboard-adjusted bounds and internal scrolling. | Recording, long drafts and keyboard. |

“Working through your request” / “מטפל בבקשה שלך” is an application fallback, not a model-supplied explanation. A single active operation uses its actual display title. Completed or answering-only runs do not keep the fallback shimmering.

## Integration details

- Streaming edits compare canonical attributed content and update only the changed tail of native textStorage. No whole-document attributedText assignment on every delta. This is a source-level change, not a measured device performance claim.
- The initial portable test caught a CR-to-CRLF boundary mismatch in Foundation's composed-character result. Production code now keeps CRLF together; the failing test was retained and expanded.
- Original and translated selection sheets have one stable presenter each. The shared knowledge editor now belongs to the stable message host; saving from older/streaming replies does not rely on the last-reply action row. The selector's own knowledge action uses its visible presentation flow.
- A full-document capture uses the hanlin-message namespace and reopens that exact native selection surface. Part captures retain hanlin-part identity checks. Repeated text is never matched heuristically.
- The Mini Apps search prompt is shared between Library and composer and localized in the existing catalog. The inline control remains a real UISearchTextField using shared typography.

## Crash evidence

Both reports are Build145201 on iPad15,3 / iPadOS27.2.1 (24B156):

- `81C3E81B-B07E-4A87-AB5B-F9B84E7220A7`: 2026-11-22 01:28:47.7733 +0200.
- `D42387D9-75F7-4DC8-ADF4-A36D5C059A96`: 2026-11-22 01:29:28.3957 +0200.

Both record EXC_CRASH/SIGABRT through CALayer.setBounds, UIScrollView.setContentOffset, HostingScrollView.updateContext/flushPendingContext/didMoveToWindow during view attachment. This differs from the older143801 sensory-feedback SIGBUS. The reports alone do not name a Hanlin source line or prove an invalid numeric value. The owner's collapse reproduction plus the identified close-time subtree replacement establish the concrete repair target.

## Apple API evidence

- [UIPopoverPresentationController.sourceItem](https://developer.apple.com/documentation/uikit/uipopoverpresentationcontroller/sourceitem.md): actual bar item drives popover morphing.
- [WWDC25, Build a UIKit app with the new design,13:55](https://developer.apple.com/videos/play/wwdc2025/284/?time=835): native popover morph.
- [SwiftUI navigationTransition](https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)): stacks/sheets, distinct from popover morphing.

The apple-devtools API probe44964672060 failed before creating jobs because of a workflow-file issue. It provides **no SDK validation evidence**. Apple-framework compilation is established separately by the corrected successful signed device archive, run 44972815423.

## Impact-aware validation plan and evidence

Only changed disclosure, activity, selection, composer and popup dependency closures are in scope. Prior145201 UI acceptance and affected logic evidence are invalidated by changed source and the owner's actual failures. Cache hits do not constitute acceptance.

| Obligation | Status after corrected release workflow | Method / reason |
| --- | --- | --- |
| Activity phase, visible motion ownership, finite disclosure geometry | EXECUTED_PASS:132 assertions | Actual portable production source; Swift6.3.3 Windows, job_ab2edef42a8f; fresh after concurrent-approval correction. [Exact evidence](2026-11-22-evidence/activity-domain-result.json). No UIKit emulation claim. |
| Composer coordinator, dock, geometry, metrics | EXECUTED_PASS:148 assertions | Actual domain source on Windows, with explicit stand-ins for SwiftUI Binding/Transaction/animation plumbing. Source hashes in [composer-domain-result.json](2026-11-22-evidence/composer-domain-result.json). |
| Completed activity/composer source syntax | EXECUTED_PASS | Swift frontend parse only, not Apple module typecheck. All 19 selection scope files passed in job_87e8c171a372 before its later compilation timeout; changed header/preview and native setter passed again in job_58de3b3ef235. Model source/tests passed job_81580790750f; final Mini Apps localization edit passed job_db6c8de0159a. |
| Updated model lifecycle and per-call projection app tests | NOT_RUN | Test contract updated; no simulator execution requested during upload. |
| Native text incremental edits | EXECUTED_PASS:329 assertions | job_58de3b3ef235; actual Foundation helper, including stable attributed prefixes, RTL, combining marks, emoji, CRLF append/delete/style changes, and selection preservation. |
| Preview viewport geometry | EXECUTED_PASS:49 assertions | Independent fixture in job_920bd3580317 passed. That overall job failed on the separately reported CRLF edit-plan defect; the corrected edit-plan result supersedes it. [Exact scope/evidence](2026-11-22-evidence/selection-domain-result.json). |
| App-search localization | EXECUTED_PASS | Catalog JSON/duplicate-key check and normalized symbol collision check for hanlin.apps.search; en/he/zh-Hans. |
| Apple package resolution | EXECUTED_PASS | Renderer 6e884c73352a272c4e7bf8a5917e8b2157bc952e is pinned consistently and included in the corrected source's successful signed archive, run 44972815423. |
| Apple application compilation / signed archive | EXECUTED_PASS | Corrected source c4b80bd60e291c5f0198efb7b9384ec9ff5a39f2 archived successfully in run 44972815423. The earlier failed 145301 attempt remains recorded in [first-attempt evidence](2026-11-22-evidence/first-archive-failure-44969425818.json). |
| Runtime reuse | EXECUTED_PASS; RECEIPT_AND_IPA_READBACK_VERIFIED | CI verified producer 42926628418, the runtime bundle hash, packaged Host ZIP bytes and source/packaged Node Mach-O UUIDs. Independent readback recomputed the IPA hash, read its plist/manifest and compared the two Node UUID receipt files. No fresh engine build. [Release receipt](2026-11-22-evidence/testflight-release-145401.json). |
| TestFlight availability | EXECUTED_PASS; INDEPENDENT_READBACK_VERIFIED | Actual receipt and IPA identify 0.7.3 (145401), Apple VALID + IN_BETA_TESTING, source c4b80bd60e291c5f0198efb7b9384ec9ff5a39f2 and the confirmed internal audience from 143801. The failed candidate 145301 was not uploaded. |
| Physical iPad visual/gesture/recording/crash acceptance | NOT_RUN | Remains open until actual device evidence. |

Both attempts used target_validation_group=testflight_device_upload, passing skip_simulator_tests=true to TestFlight. The completed retry's workflow metadata records the simulator, native UI and dependent UI-proof jobs/steps as skipped; no such execution is claimed.

## Release execution and evidence

Workflow310046367, ref codex/hanlin-ipad-interactions-20261122:
testflight_upload=true; target_validation_group=testflight_device_upload;
runtime_bundle_artifact_run_id=42926628418; runtime_bundle_only=false;
runtime_publish_release=false; testflight_audience_source_build=143801.

The failed first attempt used app source `20e6bd518c15b8b9746f298506e4d5d13e96955a`. The app-only compiler fix is committed as `c4b80bd60e291c5f0198efb7b9384ec9ff5a39f2`. [Run 44972815423](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44972815423), job 137056085991, run number 1454 / attempt 1, completed successfully for build **145401**. Archive, export, signature/runtime verification, Apple validation, upload and TestFlight readiness all passed; simulator/native UI validation jobs were skipped as requested. [Authentic workflow metadata](2026-11-22-evidence/workflow-release-145401.json) records these outcomes.

The signed artifact is `ChavrusaChat-signed-ipa-145401` (ID 14735454350, 304,675,520 bytes), with GitHub artifact SHA-256 `56eed61ade11c87e00bd378b13071786b6fb2d5be0ff64bdf6436c4a39a425c8`. Independent download, receipt and IPA verification completed successfully in jobs job_79bd7b8ff8e1 and job_0c651ebb9f2b. Independent verification recomputed the full IPA checksum, read its application plist and RuntimeManifest, and compared the source/packaged Node UUID receipt files. CI's archive-verification step performed the packaged Host ZIP rehash and source/packaged Node Mach-O UUID comparison; their results are retained in runtime-distribution.json. The [verified release receipt](2026-11-22-evidence/testflight-release-145401.json) preserves the raw Apple/runtime fields and individual receipt hashes.

## First signed archive attempt: failed; corrected archive succeeded

[Run 44969425818](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44969425818) attempted candidate **145301** from source `20e6bd518c15b8b9746f298506e4d5d13e96955a` on Xcode 27.2. The retained log confirms renderer checkout and native-runtime preparation before the app compiler stopped:

`AI_HLY/Downstream/ChatPresentation/ChatMarkdownView.swift:27:25: error: failed to produce diagnostic for expression; please submit a bug report`

This is the single unique app compiler diagnostic in the retained log. It points to the combined SwiftUI body expression; it does not establish a renderer-runtime defect or validate the original iPad crash repair. The diagnostic was emitted at 2026-11-22T01:33:07.267284Z; `ARCHIVE FAILED` followed at 01:34:28.449690Z. The existing watcher ended failed at 01:34:51 UTC. Export and upload were not reached: **145301 was not uploaded to TestFlight**, and this attempt has no Apple-readiness receipt.

The remediation changes only `ChatMarkdownView.swift`: typed initializer, linked/highlighted/body composition boundaries and explicit callbacks. Its SHA-256 is `bca9926d0099a8c78c47fd01a4c37d2bb3e319fd3db4be7e529fd97d11b51744`. Frontend parse and whitespace checks passed in job_23de13982e0e (11.37 seconds). That initial check established syntax only. The corrected source subsequently passed Apple-framework compilation in the successful signed archive. Prior portable-domain evidence remains unchanged and was not rerun for this app-only composition change.

The corrected source is `c4b80bd60e291c5f0198efb7b9384ec9ff5a39f2`. Its retry keeps renderer `6e884c73352a272c4e7bf8a5917e8b2157bc952e`, runtime producer `42926628418`, audience source `143801` and simulator skipping. Final watcher job_c8b82d9e7339 successfully confirmed run 44972815423 after the earlier watcher job_41d6b06d11ab timed out. The earlier timeout concerned monitoring only; the release workflow completed successfully. Its archive, export, upload and Apple-readiness steps subsequently completed successfully. The first failure remains part of the record. Independent raw receipt and IPA readback subsequently confirmed the successful 145401 publication and original runtime reuse.

[First-attempt failure evidence](2026-11-22-evidence/first-archive-failure-44969425818.json) records the diagnostic, log hash, scoped outcomes and retry limits. Physical iPad acceptance remains **NOT_RUN**.

## Verified TestFlight and packaged-runtime receipt

Independent verification completed at **2026-11-22T02:58:16.712591+00:00**. This receipt comes from the downloaded signed artifact and actual IPA, in addition to the successful workflow metadata.

| Field | Verified value |
| --- | --- |
| Version / build | `0.7.3 (145401)` |
| App Store app ID | `6811910017` |
| App Store build ID | `ea8b309c-a0a3-4afb-b8f8-3234c0a536c1` |
| Apple processing state | `VALID` |
| Internal testing state | `IN_BETA_TESTING` |
| Internal audience source | `143801` |
| Confirmed internal group | `14fdc6a7-062e-40f6-8f11-45cbd30c6ddb` |
| Uploaded app source / verification SHA | `c4b80bd60e291c5f0198efb7b9384ec9ff5a39f2` |
| Renderer source | `6e884c73352a272c4e7bf8a5917e8b2157bc952e` |
| Workflow / job | `44972815423 / 137056085991` |
| Actual IPA SHA-256 | `751cf593dca2905344186db778b04fa7ceddfd5e60ca7aba6343b5a7c91dcf55` |
| Packaged app identifier | `com.itorah.chavrusachat` |
| Native runtime producer | `42926628418` |
| Inner runtime ZIP SHA-256 (CI-verified; receipt/manifest value) | `196a35562a31229b1bcf05afbe49f76470ced90a7fbf0494ecebd5c06d07440f` |
| Node XCFramework SHA-256 (manifest/receipt value) | `21c404e94c38e7d91ec446ce0ca07d7fed9120ec3e42b80cc8352052dd1db207` |
| CI-verified Node image UUID (matching receipt files) | `DF9F9A4D-4842-31DE-A906-BA1B61891ED5 (arm64)` |
| CI-verified packaged Runtime Host ZIP SHA-256 | `f6346b53c32bae70a040278b2290ce6b6a3526d699eea8530eb4ec95253bfa21` |
| Packaged manifest match | `true` |

The authenticated GitHub artifact digest above describes the artifact ZIP. Independent readback recomputed the IPA hash. CI verified the inner runtime ZIP and packaged Host ZIP hashes; independent readback retained those receipt/manifest values and compared the Node UUID receipt files. It did not independently rehash the packaged Host ZIP or extract a UUID from the downloaded Node Mach-O binary. Subsequent documentation commits do not change the uploaded app source.

CI signing/provisioning checks confirmed that required Extended Virtual Addressing is authorized by the profile and present in the signed app. The receipt still records `physicalAllocationVerified=false`; this is not a device memory-allocation test. Simulator/native UI jobs were skipped, and physical iPad visual, gesture, recording, selection and crash acceptance remains **NOT_RUN**.

## Physical acceptance sequence

1. In the same iPad chat, repeatedly collapse/reopen the activity hierarchy, rounds and a tool with long output while updates arrive; repeat after completion and while manually scrolled.
2. Check first answer delta, completion, approval waiting and concurrent tools; only the deepest visible active owner should shimmer.
3. Keep a tools/Skills page open; open/expand/back/dismiss the model picker, select a model, focus the editor, use microphone and expand/collapse the editor. Verify the drawer route and draft survive.
4. Compare wide/narrow iPad layouts with keyboard and larger type. Controls stay inside input glass; plus shape/location and glass connection remain intact.
5. Select across paragraphs/lists in mixed Hebrew/English, then across code boundaries in Select Text. Drag existing handles without a preview; hold stationary for one second to open the bounded preview. Repeat for translation and rich-only header access.
6. Save/reopen exact excerpts, including repeated words and whole-message captures; open knowledge editing from an older reply and from the selector.
7. Open Mini Apps inside the bubble, search and launch installed engines, then return. The catalog has no Edit/Add/Import controls.

Physical acceptance remains open and is not implied by the archive succeeding.
