# Canvas native confirmation dismissal

## Result

UNAPPLIED TEST-ONLY proposal. Canonical source untouched by this agent. Root owns application/publication/CI.

Patch: canvas-confirmation-popover-fix.diff
SHA256: 779eee26d729324d7db9fd5cfb3e8c8c2c8f59f3795e04edeaf76d5d568d0100
Bytes: 2,667
Base test SHA256: 86c2b77736d7a0de549e040614f95ae42aef9ebbe187aede02d61a959c09bb27
Base HEAD: 8a505675eca035fbca3877afd1f8776f00f629d0

Swift syntax and current git apply --check passed. No native test or Apple framework typecheck was run for the proposal. This fix is not an accepted Canvas result.

## Authenticated source evidence

Run 44428104345 at the root-recorded source d6cb7d0b, iPad Pro 13-inch (M5), iOS 27.2 Simulator.
Outer artifact 14491709009:
64,595,152 bytes
SHA256 5fa7aa96391838a2abad823e592e6f0edd0f1c0df0d8e5ae3197dbbc71b2f750
1,518 ZIP members; 136,855,477 uncompressed bytes.

The complete ZIP was read locally and hashed after root's owned background download. No second download was started. The partial 50-second file was left intact.

Raw UI results: four cases, exactly two passes and two failures.
- PASS testNativePartialSelectionSaveAndOriginalLongPressPreview(), 124.691805s.
- PASS testUI04CollapsedProgressAndInspectorWithoutRawCoT(), 79.886302s.
- FAIL testUI01UnifiedHistoryPinSearchSwitchDraftPreservation(), 60.178269s: expected "Draft preserved across switch", actual "Deserved across switchraf".
- FAIL testOriginalCanvasRunsEmbeddedPythonAndRetainsSourceAfterRelaunch(), 36.461575s: Cancel button lookup at original line 54.

Raw selected unit results: two passes:
- ClassicChatRestorationTests/agentReasoningNeverLeaksRawCoTToViews()
- ClassicChatRestorationTests/expandedReasoningUsesApprovedSummaryProjection()

authenticated-test-results.json contains exact selectors, durations, source paths and raw JSON hashes. These are results for their recorded source, not proof for later edits.

## Actual Canvas UI

The raw UI database contains 26 attachments total, nine associated with Canvas. Canvas supplies one plain-text AX hierarchy, one screen recording, one legacy snapshot, and six synthesized-event attachments. There is no separate Canvas PNG attachment; the reviewed still frame was decoded from the authenticated original recording.

All retained evidence is under:
C:\Users\DAVID\Code\Hanlin-Continuation-Evidence-20261119\run-44428104345\canvas

- attachment-18.txt: native AX, 30,982 bytes; SHA256 3a429cc2e7a6964f73abbc37343ca24c7f8faa5177cda4a528236c440b23b295.
- canvas-original-screen-recording.mp4: 6,738,073 bytes; SHA256 fb20c82b8d9f8f4fc902e5090e7c46823d564be7f19521088f31cf7c2b8172b3.
- canvas-consent-video-t30_7.png: exact-size original-video frame at timestamp 30.7s, 2064x2752, 403,050 bytes; SHA256 1402fc033a3e95c2e338988f7e008d40fad00bbc3976679ce1e4d0418e87a5c9.
- canvas-local-output-video-t29_5.png: earlier original-video frame showing the computed local output before the remote popover appears.
- decoded-provenance.json, video-provenance.json and frame-provenance.json retain original payload member identities and hashes.

The viewed final frame shows the original Canvas source print('CANVAS_LOCAL_RESULT_' + str(6 * 7)), its computed CANVAS_LOCAL_RESULT_42 output, and the remote disclosure popover with one Run on Piston action and no Cancel button.

The AX hierarchy independently confirms:
- Canvas container (226,358,580,660).
- Output (253,732.5,177,34), label CANVAS_LOCAL_RESULT_42 followed by newline.
- Remote confirmation Popover (372,91,288,267).
- emkc.org disclosure.
- Run on Piston / hanlin-canvas-python-remote-confirm.
- No Cancel action.

Three PopoverDismissRegion nodes are present because more than one native presentation exists. A first-match dismissal-region lookup is therefore unsuitable.

## Cause and correction

The test assumes that every native confirmation dialog shows a Cancel button. Apple's SwiftUI documentation says regular-width iOS confirmation dialogs render as popovers and use an outside tap in place of the standard dismiss action:
https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:)
https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:)

The actual screenshot and AX match this documented behavior. No product defect in dialog dismissal is established, so this patch changes only the original UI test.

When a hittable Cancel exists, the original tap remains. Otherwise the test requires the native popover that contains the exact remote-confirm button. It measures the current local-output center, requires that point to lie inside the application window and outside the confirmation popover, then taps that noninteractive Canvas output area. The coordinates are measured at runtime; the numbers from this artifact are not hardcoded.

It subsequently requires the confirmation to disappear, the original Canvas to remain present, the computed output to remain identical, the Python menu to remain enabled, and no running-Python cancel control to exist. The pre-dismissal disclosure screenshot is now retained separately.

All original local Python, explicit consent/disclosure, output preservation, Done, cold termination/relaunch, and recomputation checks remain. The remote-confirm action is never tapped.

## Scope of no-remote evidence

The original test had no independent HTTP request counter or captured network trace. Its unchanged-output/menu assertions are preserved and strengthened with no-running-execution UI state. Source inspection shows executePython(remotely: true) only in the explicit Run on Piston action; entry synchronously clears the prior output and sets isExecutingPython before the asynchronous Piston call.

These UI and source observations must not be described as a packet capture proving zero network traffic. The proposal does not add a mocked network response, an injected success, or a product-only test switch.

## Required native rerun

Retain the original selector and device lane:
AI_HLYUITests/HanlinCanvasRuntimeUITests/testOriginalCanvasRunsEmbeddedPythonAndRetainsSourceAfterRelaunch

Use root's reviewed combined source and pinned runtime producer 42926628418. Acceptance still requires actual dismissal, no unintended execution, and successful cold reopening/recomputation. The prior run stopped before those steps.
