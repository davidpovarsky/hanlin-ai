# Integrated Drawer & Model Popover Animation Specification

## 1. Bounded `HanlinOrganizerDock` Geometry (`ContentView.swift` lines 599–951)

`HanlinOrganizerDock` (`AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinOrganizerDock.swift`) mirrors `InteriorOrganizerV3_3`'s `organizerDock(availableHeight:)` as a single bottom-aligned `ZStack(alignment: .bottom)` with strict explicit height bounds on every layer:

1. **Outer Dock Container (`ZStack(alignment: .bottom)`)**:
   - Explicitly bounded with `.frame(height: dockState.panelHeight, alignment: .bottom)`.
   - Never expands to fill the parent `ChatView` / `HanlinCompactChatWorkspace` full-screen `ZStack`.
2. **Back Layer (`drawerLayer`)**:
   - Rounded rectangle (`cornerRadius: 27, style: .continuous`) with `GlassView(style: .systemUltraThinMaterial)` background, `0.8pt` `hlBluefont.opacity(0.22)` stroke, and `hlBlue.opacity(0.16)` shadow (`radius: 5, y: 1`).
   - Bounded by `.frame(height: dockState.panelHeight, alignment: .top)`.
   - Top handle bar (`36x4pt` capsule inside a `32pt`-tall hit target, identifier `hanlin-organizer-drawer-handle`) with tap-to-toggle, `.accessibilityAdjustableAction`, and `.highPriorityGesture(drawerDragGesture, including: .all)` using `DragGesture(minimumDistance: 20, coordinateSpace: .global)` (`translation.height < -34` expands to `lastExpandedMode`; `translation.height > 34` collapses to `.collapsed`).
   - Visible drawer content slot (`visibleContentHeight = max(0, panelHeight - composerHeight - 32)`) switching between `.general` (`HanlinComposerGeneralActionsView(embeddedInDrawer: true)`) and `.tools` (`HanlinComposerToolsRootView(embeddedInDrawer: true)`).
   - Embedded drawer subpages (`.imageSize`, `.toolsCatalog`, `.skills`, `.mcp`, `.runtime`) switch inline via `ZStack(alignment: .top)` on `coordinator.generalNavigationPath.last` / `coordinator.toolsNavigationPath.last` rather than nesting a second `NavigationStack` inside the outer workspace `NavigationStack`.
3. **Front Layer (`composerLayer`)**:
   - Rounded rectangle (`cornerRadius: 25, style: .continuous`) with `GlassView(style: .systemUltraThinMaterial)` background, `0.8pt` `hlBluefont.opacity(0.24)` stroke, and `hlBlue` shadow (`radius: 1`).
   - Bounded by `.frame(height: dockState.composerHeight, alignment: .top)` and `.clipped()`.
   - Background tap gesture (`onTapComposerBackground`) is attached strictly to the background `GlassView` inside `.background(...)` so it never intercepts button taps or text input touches inside `composerContent`.
   - Top composer resize handle (`32x4pt` capsule inside an `82x20pt` hit target, identifier `hanlin-composer-resize-handle`) with `.highPriorityGesture(composerResizeGesture, including: .all)` using `DragGesture(minimumDistance: 7, coordinateSpace: .global)` and `+/-72pt` `.accessibilityAdjustableAction`.

---

## 2. Exact Height, Inner Editor & Keyboard Accounting (`HanlinOrganizerDockState`)

- **Auto & Manual Composer Height**:
  - `clampedLines = min(max(draftLineCount, 1), 4)`
  - `attachmentExtra = attachmentOverheadHeight > 0 ? min(attachmentOverheadHeight, 440) : (hasAttachments ? 44 : 0)`
  - `autoComposerHeight = min(92 + CGFloat(clampedLines - 1) * 20 + attachmentExtra, maxComposerHeight)`
  - `maxComposerHeight = min(isExpanded ? 244 : 334, max(136, effectiveAvailableHeight - (isExpanded ? 280 : 120)))`
  - `composerHeight = min(max(manualComposerHeight ?? autoComposerHeight, 92), maxComposerHeight)`
  - `panelHeight = isExpanded ? min(composerHeight + 356, max(composerHeight + 188, effectiveAvailableHeight - 16)) : (composerHeight + 40)`
- **Inner `NativeMultilineTextEditor` Frame Height (`effectiveEditorFrameHeight`)**:
  - `editorMaxHeight = max(44, composerHeight - (62 + min(attachmentOverheadHeight > 0 ? attachmentOverheadHeight : (hasAttachments ? 40 : 0), 220)))`
  - When `manualComposerHeight != nil`, `effectiveEditorFrameHeight(intrinsicHeight:minimumInteractiveHeight:)` returns `max(clampedIntrinsic, editorMaxHeight)`, so dragging `hanlin-composer-resize-handle` upward or downward proportionally expands and shrinks the actual `UITextView` frame (`hanlin-chat-input`) even when the text draft is empty.
- **Keyboard Overlap Double-Subtraction Guard (`updateKeyboardOverlap`)**:
  - `ChatViewBottom` subscribes to `UIResponder.keyboardWillChangeFrameNotification` and `UIResponder.keyboardWillHideNotification`.
  - `updateKeyboardOverlap(_:baselineContainerHeight:)` compares `baselineContainerHeight` against `availableHeight` and subtracts any safe-area shrinkage SwiftUI already applied (`alreadyReduced = max(0, baseline - availableHeight)`), ensuring `effectiveAvailableHeight` never double-subtracts the keyboard height.
- **Spring Curves**:
  - Drawer expansion & mode swap: `.spring(response: 0.48, dampingFraction: 0.87)` (instant when `accessibilityReduceMotion` is enabled).
  - Composer height resize: `.spring(response: 0.38, dampingFraction: 0.88)` (instant when `accessibilityReduceMotion` is enabled).

---

## 3. Two-Phase Model Popover Expansion & Matched Zoom (`ContentView.swift` lines 1221–1503)

The Model Picker is the **only** floating `.popover` on the composer:
1. **Capsule-to-Popover Zoom**:
   - The model capsule (`hanlin-composer-model-picker`) is anchored inside the bottom composer dock (`y > 900pt` on iPad) and attaches `.matchedTransitionSource(id: "model-popover", in: modelPopoverZoom)`.
   - The `.popover` content attaches `.navigationTransition(.zoom(sourceID: "model-popover", in: modelPopoverZoom))`.
   - Because the composer is bounded at the bottom of the screen, UIKit presents the popover cleanly above the model capsule with `arrowDirection = .down`, leaving the model capsule unobstructed for outside-tap dismissal.
2. **Completion-Driven Two-Phase Expansion to `All Models`**:
   - Tapping `All Models` (`hanlin-model-picker-all-models-button`) invokes `coordinator.pushModelSubroute(.allModels, reduceMotion: reduceMotion)` from a single `Button`.
   - **Phase 1**: `withAnimation(.easeInOut(duration: 0.24), completionCriteria: .removed) { modelFrameExpanded = true }` expands the popover frame (`340x380` -> `380x480`) while `modelNavigationPath` remains `[]`.
   - **Phase 2**: Only inside the completion handler (guarded by `modelExpansionGeneration == generation && activePresentation == .model && modelFrameExpanded`) is `.allModels` appended to `modelNavigationPath`, triggering `.navigationTransition(.zoom(sourceID: "all-models", in: modelZoomNamespace))` inside the already-expanded popover bounds.
   - **Cancelled Interactive Swipe-Back Protection**: `markModelDestinationDisappeared(reduceMotion:)` shrinks `modelFrameExpanded = false` only after the subpage genuinely disappears while `modelNavigationPath.isEmpty`.
