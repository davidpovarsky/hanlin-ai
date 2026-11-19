# Compact workspace keyboard proposal

Status: UNAPPLIED PROPOSAL. Root owns canonical application and native dispatch. No Apple/native run, CI dispatch, Asana edit, secret operation, or canonical mutation was performed by this packet.

## Proven failure and bounded cause

Authenticated paired run 44426526923 at 90314963 ran on iPhone 18 Pro / iOS 27.2 Simulator. In decoded native accessibility attachment ax-4, the existing guide view occupies (0,62,402,778), while its keyboard-top marker remains (0,840,402,0). The actual keyboard accessibility frame is (0,590,402,226), the native editor is keyboard-focused at (107,678,225.3,60), and Send is at (327,780,32,32) with VisiblePoint=(-1,-1). Screenshot 25 confirms the dock is concealed by the docked keyboard. The guide view is not zero-sized.

This proves the current marker-derived overlap remains zero in this host while the keyboard is visible. It does not prove that ignoresSafeArea, SwiftUI, UIKit, or any particular internal layout implementation caused that marker behavior. The proposal changes the owner’s measurement source to the documented native frame, preserving one overlap writer.

The raw stdout file is 54,975,950 bytes / 448,215 lines:
SHA256 fb73438466a248b6d45584530c3fbb738afdf36a70e02ac3f9553fd448c25589.
Original member:
app-split-evidence/paired-product/Paired.xcresult/Data/data.0~ATVaPl6rKsx0Z5-V17X-5oRJ9U2fKnY4PQtDUhrj8S-m5qWxdPF8GDOPy8kyBWH04cvCQfBskSO3sccWDOttmg==

Native editor text corruption is a separate remaining failure. XCTest recorded Type 'PAIRED_OPEN_F1741B...' at t=40.53s; the expected source expression is "PAIRED_OPEN_" + UUID().uuidString. The fetched log does not retain the complete expected UUID. Native AX then repeatedly reports "P-4966-AA6D-E9A372CA0B0BB6C-0FDE" from 01:10:57.214971 through 01:11:37.455311 (18 observations). Do not reconstruct an exact expected nonce. Root owns the text/delegate diagnostics and equality assertion; this patch does not change text synchronization, keyboard defaults, focus mutations, or test text expectations.

## Ownership and geometry

The existing NativeMultilineTextEditor adds one optional lifecycle observer with a default nil value. It reports the exact existing UITextView on make/update, focus change, and dismantle. ChatViewBottom passes that observer only from the compact workspace. A workspace-owned weak registry retains no native view and rejects a late teardown from an old editor.

This is construction-based ownership of the exact editor instantiated by this workspace, rather than a private SwiftUI hierarchy walk. The observer does not claim that a make/update callback means the view is already in a window. Before writing a positive overlap, the probe separately requires the exact registered editor to be first responder in the probe’s actual key UIWindow and active UIWindowScene.

Only local keyboard frames on that scene’s exact UIScreen are cached. The frame is converted from message.screen.coordinateSpace into the actual UIWindow, then into the probe. Geometry uses their local intersection. The root background probe stays outside the padding it measures, avoiding a feedback loop.

The numeric docking policy accepts only a nonempty finite frame across the screen’s width and touching its bottom, within one display pixel. Floating and undocked keyboards do not resize the entire workspace. It also rejects a local intersection that does not reach the workspace bottom.

Hide, window replacement, key-window loss, scene deactivation, and loss of the registered editor’s first-responder ownership yield zero. Asynchronous publication rechecks the latest ownership and frame; stale queued notifications cannot restore an old overlap. Tokens and callbacks have weak ownership. A replaced observer cannot publish over the current one.

The prior guide/marker is removed, so notifications and the layout guide cannot both write padding. Existing outer stack identity, navigation, composer bindings and ignoresSafeArea ownership are preserved.

## Exact official APIs and availability

The app and HanlinPresentationSDK currently deploy to iOS 27.0. These typed messages and Foundation observation APIs require iOS 26.0 or later, verified in Apple’s rendered Markdown metadata:

- https://developer.apple.com/documentation/uikit/uiresponder/keyboardwillchangeframemessage.md
- https://developer.apple.com/documentation/uikit/uiresponder/keyboarddidchangeframemessage.md
- https://developer.apple.com/documentation/uikit/uiresponder/keyboardwillhidemessage.md
- https://developer.apple.com/documentation/uikit/uiresponder/keyboarddidhidemessage.md
- https://developer.apple.com/documentation/uikit/uiwindow/didresignkeymessage.md
- https://developer.apple.com/documentation/uikit/uiscene/willdeactivatemessage.md
- https://developer.apple.com/documentation/foundation/notificationcenter/addObserver(of:for:using:)-56bn4.md
- https://developer.apple.com/documentation/foundation/notificationcenter/observationtoken.md

The keyboard structs conform to NotificationCenter.MainActorMessage and expose endFrame: CGRect, isLocal: Bool, screen: UIScreen. UIWindow.DidResignKeyMessage exposes window: UIWindow; UIScene.WillDeactivateMessage exposes scene: UIScene.

The exact Foundation overload is:
func addObserver<Message>(of subject: Message.Subject? = nil, for messageType: Message.Type, using observer: @escaping @MainActor (Message) -> Void) -> NotificationCenter.ObservationToken where Message: NotificationCenter.MainActorMessage, Message.Subject: AnyObject

Tokens must be retained while observing; releasing them ends observation. No non-Sendable Notification is transferred across actors and no assumeIsolated escape is used.

Apple’s coordinate-space contract explicitly requires converting the screen frame into the view/window for Split View, Slide Over and Stage Manager, then intersecting:
https://developer.apple.com/documentation/uikit/uiresponder/keyboardframeenduserinfokey.md

UIScreen is taken from the typed message and matched against window.windowScene.screen. UIScreen.main is not used.

## Passive native witness

Enable explicitly on the actual host XCUIApplication before launch:
app.launchEnvironment["HANLIN_COMPACT_KEYBOARD_WITNESS"] = "1"

The witness is additionally gated by DEBUG || HANLIN_TESTING. It prints only event type, rectangles, registration/focus/window/scene ownership booleans, and computed overlap. It prints no text, prompt, selection content, key, hash of user content, or injected result. The flag never changes behavior. Duplicate layout facts are suppressed. Root’s separate HANLIN_COMPOSER_EDIT_DIAGNOSTICS flag remains independent.

Add this flag at the existing host launch setup for the selected iPhone, iPad and paired tests. Setting a CI process environment variable alone is not proof that XCUIApplication receives it. No UI test action or expectation is removed.

## Validation and exact remaining native selectors

Completed:
- Swift frontend syntax parsing: all four proposed source/test files passed.
- Exact production geometry helper compiled and executed with Foundation on Windows: 9 cases passed (phone intersection, translated window, window above keyboard, floating, undocked, hidden, zero height, nonfinite frame, invalid scale).
- Isolated git apply succeeded and every result byte matches the proposed files.
- Whole canonical apply-check reports a conflict only in NativeMultilineTextEditor at line 355 because root concurrently inserted its text-edit diagnostic. The editor’s base hash is ec30c7861c69a551269407af0ce696aaba817ae4c4bb127fa9c8093ef6fad654. Separate per-file patches allow root to merge only the lifecycle hunks while retaining its diagnostic.

Not completed:
- Apple framework typecheck and Swift 6 actor-isolation check against the actual Xcode SDK.
- Actual typed-message delivery, editor ownership, keyboard animation, hiding, rotation, and window movement on iPhone/iPad.
- Physical iPad, external display, hardware keyboard assistant, floating/split keyboard and Stage Manager acceptance.

The full-width docking predicate is deliberately narrower than general keyboard-overlap avoidance. A compact hardware assistant that does not span the screen is ignored; parity with each original keyboard-guide hardware/Stage Manager case is not established by portable geometry tests. Keyboard animation timing remains a native check: this patch preserves the current coalesced async state publication and does not invent a SwiftUI animation for an unknown UIKit animation curve.

New native unit methods (four):
AI_HLYTests/HanlinCompactKeyboardGeometryTests/dockedKeyboardUsesWorkspaceIntersection()
AI_HLYTests/HanlinCompactKeyboardGeometryTests/translatedWindowUsesLocalIntersection()
AI_HLYTests/HanlinCompactKeyboardGeometryTests/floatingDismissedAndInvalidFramesDoNotResize()
AI_HLYTests/HanlinCompactKeyboardGeometryTests/lateEditorDetachPreservesCurrentOwner()

Existing original iPhone lane:
AI_HLYUITests/HanlinMorphComposerUITests/testCompactNavigationKeepsDraft
AI_HLYUITests/HanlinMorphComposerUITests/testCompactLargeTextWithAttachment

Existing original iPad keyboard routes:
AI_HLYUITests/AgentRuntimeConversationUITests/testCompactToolsManagementDestinationsPreserveDraft
AI_HLYUITests/AgentRuntimeConversationUITests/testModelPopoverZoomWithKeyboardAndDraft
AI_HLYUITests/HanlinMorphComposerUITests/testLargeTextLongDraftFitsWithKeyboardAndAfterPalette

Existing original paired cases:
AI_HLYUITests/HanlinPairedProductUITests/testCompanionCancellationReturnsWithoutChangingPrivateState
AI_HLYUITests/HanlinPairedProductUITests/testCompanionReturnsActualPrivateValueToOriginalChat

Retain pinned runtime producer 42926628418 and root’s original per-device lanes. A passing geometry helper is not native product acceptance. Paired text equality must succeed before claiming the handoff case is ready.
