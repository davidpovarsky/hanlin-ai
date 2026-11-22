# iPad interaction repairs after TestFlight 145201

Date: 2026-11-22 (Asia/Hebron). Owner-authorized continuation.

## Source and acceptance context

- Shipped baseline: 0.7.3 (145201), source `927001ac4ac2f3f3cf837df50ec3bb20a0648b48`.
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

The apple-devtools API probe44964672060 failed before creating jobs because of a workflow-file issue. It provides **no SDK validation evidence**. Apple-framework compilation is assigned to the project's signed device archive.

## Impact-aware validation plan and evidence

Only changed disclosure, activity, selection, composer and popup dependency closures are in scope. Prior145201 UI acceptance and affected logic evidence are invalidated by changed source and the owner's actual failures. Cache hits do not constitute acceptance.

| Obligation | Status before signed archive | Method / reason |
| --- | --- | --- |
| Activity phase, visible motion ownership, finite disclosure geometry | EXECUTED_PASS:132 assertions | Actual portable production source; Swift6.3.3 Windows, job_ab2edef42a8f; fresh after concurrent-approval correction. [Exact evidence](2026-11-22-evidence/activity-domain-result.json). No UIKit emulation claim. |
| Composer coordinator, dock, geometry, metrics | EXECUTED_PASS:148 assertions | Actual domain source on Windows, with explicit stand-ins for SwiftUI Binding/Transaction/animation plumbing. Source hashes in [composer-domain-result.json](2026-11-22-evidence/composer-domain-result.json). |
| Completed activity/composer source syntax | EXECUTED_PASS | Swift frontend parse only, not Apple module typecheck. All 19 selection scope files passed in job_87e8c171a372 before its later compilation timeout; changed header/preview and native setter passed again in job_58de3b3ef235. Model source/tests passed job_81580790750f; final Mini Apps localization edit passed job_db6c8de0159a. |
| Updated model lifecycle and per-call projection app tests | NOT_RUN | Test contract updated; no simulator execution requested during upload. |
| Native text incremental edits | EXECUTED_PASS:329 assertions | job_58de3b3ef235; actual Foundation helper, including stable attributed prefixes, RTL, combining marks, emoji, CRLF append/delete/style changes, and selection preservation. |
| Preview viewport geometry | EXECUTED_PASS:49 assertions | Independent fixture in job_920bd3580317 passed. That overall job failed on the separately reported CRLF edit-plan defect; the corrected edit-plan result supersedes it. [Exact scope/evidence](2026-11-22-evidence/selection-domain-result.json). |
| App-search localization | EXECUTED_PASS | Catalog JSON/duplicate-key check and normalized symbol collision check for hanlin.apps.search; en/he/zh-Hans. |
| Apple compilation, package resolution, signed archive | NEEDS_TEST | Source-frozen signed device archive on Xcode27 runner. |
| Runtime reuse | REUSE_REQUESTED | Producer42926628418; workflow must verify original manifest/identity/hashes. No fresh engine build. |
| TestFlight availability | NEEDS_TEST | Require Apple VALID + IN_BETA_TESTING and verified internal audience. |
| Physical iPad visual/gesture/recording/crash acceptance | NOT_RUN | Remains open until actual device evidence. |

No simulator tests will run in the upload workflow. target_validation_group=testflight_device_upload passes skip_simulator_tests=true to TestFlight.

## Release plan

Workflow310046367, ref codex/hanlin-ipad-interactions-20261122:
testflight_upload=true; target_validation_group=testflight_device_upload;
runtime_bundle_artifact_run_id=42926628418; runtime_bundle_only=false;
runtime_publish_release=false; testflight_audience_source_build=143801.

Renderer pin is recorded above. App source SHA, workflow receipt and Apple build IDs will be recorded after dispatch/upload. This checkpoint does not claim a new available build.

## Physical acceptance sequence

1. In the same iPad chat, repeatedly collapse/reopen the activity hierarchy, rounds and a tool with long output while updates arrive; repeat after completion and while manually scrolled.
2. Check first answer delta, completion, approval waiting and concurrent tools; only the deepest visible active owner should shimmer.
3. Keep a tools/Skills page open; open/expand/back/dismiss the model picker, select a model, focus the editor, use microphone and expand/collapse the editor. Verify the drawer route and draft survive.
4. Compare wide/narrow iPad layouts with keyboard and larger type. Controls stay inside input glass; plus shape/location and glass connection remain intact.
5. Select across paragraphs/lists in mixed Hebrew/English, then across code boundaries in Select Text. Drag existing handles without a preview; hold stationary for one second to open the bounded preview. Repeat for translation and rich-only header access.
6. Save/reopen exact excerpts, including repeated words and whole-message captures; open knowledge editing from an older reply and from the selector.
7. Open Mini Apps inside the bubble, search and launch installed engines, then return. The catalog has no Edit/Add/Import controls.

Physical acceptance remains open and is not implied by the archive succeeding.
