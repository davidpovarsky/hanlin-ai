# Post-149101 activity and bubble correction

Task: 1220927011075841. Base: aa7b6fa862d54f2a0054e0dd6ffb20fe20efe702.

## Implemented behavior

The root activity label remains localized Thinking during active work, whether the disclosure is expanded or collapsed. A real admitted model request uses that same indicator before its first output. This is presentation state only: no invented reasoning text, stored transcript event, or duplicate Thinking leaf is created. Actual tools keep their own active indicators. Approval-only waits and completed history stop the sweep. Existing manual disclosure persistence and confirmed-final-answer collapse remain intact.

The default title sweep now uses the original HLBluefont color asset, gray letter base, full-width beam, opacity sequence 0 / .2 / .6 / 1 / .6 / .2 / 0, and two-second default cycle from ffbc4c60:AI_HLY/Views/Components/ChatViewComponents.swift. The 24 Hz TimelineView, active-scene gate, hidden-branch gate, VoiceOver/Reduce Motion behavior and explicit user motion presets remain.

Worked for duration is the semantic caption font at regular weight, with a secondary color. The root keeps its existing 46-point hit area. User-message corners stay 20 / 20 / 20 / 5, and all original spacing, color assets, width, actions and entrance motion are preserved. Clipping now precedes the native context menu, and contextMenuPreview receives exactly the same shape.

Apple's public API explicitly assigns the preview contour to contentShape(.contextMenuPreview, ...):
https://developer.apple.com/documentation/swiftui/contentshapekinds/contextmenupreview
https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)

Reviewed owner screenshots IMG_0820.jpeg, IMG_0821.jpeg and IMG_0826.png. They show the rectangular initial lift, rounded settled preview, duplicated Working/Thinking labels and overly prominent history title respectively.

## Executed evidence and limits

- EXECUTED_PASS: 232 production activity-lifetime, root/tool motion ownership, disclosure, summary and motion-policy assertions on Oracle, Swift 6.4.3 / aarch64 Linux.
- EXECUTED_PASS: git diff --check.
- No test result is reused.
- The portable harness symlinks the actual production source and test files; SwiftPM builds their required localization module and normal resource accessor. Linux emits a resource-processing warning for the Apple xcstrings type. This run does not validate localization or Apple UI.
- Native iOS compilation, activity UI, the real menu lift recording, and light/dark/RTL visual acceptance are NOT_RUN at this handoff.

The native activity lifecycle test now requires Thinking at the root in expanded, collapsed and resumed states and rejects a second reasoning-status row. The new testUserBubbleLongPressKeepsNativeActionsAndOriginalMessage executes the actual long-press, opens the existing Select Text sheet and verifies return to the unchanged message dimensions. Its retained before/menu/after screenshots and timed log markers support the native screen-recording review. A settled-menu screenshot alone does not prove the first lift frames.

These changes intentionally update the previous root-to-leaf shimmer assertions to the owner's new always-visible root requirement. They do not relax actual tool lifetime, approval, history, persistence or private-text checks.
