# Integrated Drawer & Model Popover Animation Specification

## 1. Integrated `HanlinOrganizerDock` Geometry & Springs (`ContentView.swift` lines 586–935)

`HanlinOrganizerDock` is a single bottom-aligned `ZStack(alignment: .bottom)` combining:
1. **Back Layer (`drawerLayer`)**:
   - Rounded rectangle (`cornerRadius: 27, style: .continuous`) with `GlassView(style: .systemUltraThinMaterial)` background, `0.8pt` `hlBluefont.opacity(0.22)` stroke, and `hlBlue.opacity(0.16)` shadow (`radius: 5, y: 1`).
   - Top handle bar (`36x4pt` capsule inside a `32pt`-tall hit target, identifier `hanlin-organizer-drawer-handle`) supporting tap-to-toggle and `DragGesture(minimumDistance: 20)` (`translation.height < -34` expands to `lastExpandedMode`; `translation.height > 34` collapses to `.collapsed`).
   - Content slot (`visibleContentHeight = max(0, panelHeight - composerHeight - 32)`) switching between `.general` (`HanlinComposerGeneralActionsView(embeddedInDrawer: true)`) and `.tools` (`HanlinComposerToolsRootView(embeddedInDrawer: true)`) with `.transition(.opacity.combined(with: .move(edge: .bottom)))`.
   - Bottom `Spacer(minLength: dockState.composerHeight)` so the drawer content sits cleanly above the front composer layer.
2. **Front Layer (`composerLayer`)**:
   - Rounded rectangle (`cornerRadius: 25, style: .continuous`) with `GlassView(style: .systemUltraThinMaterial)` background, `0.8pt` `hlBluefont.opacity(0.24)` stroke, and `hlBlue` shadow (`radius: 1`).
   - Top composer resize handle (`32x4pt` capsule inside an `82x20pt` hit target, identifier `hanlin-composer-resize-handle`) with `DragGesture(minimumDistance: 7)` and `+/-72pt` `.accessibilityAdjustableAction`.
3. **Exact Height Formulas (`HanlinOrganizerDockState`)**:
   - `clampedLines = min(max(draftLineCount, 1), 4)`
   - `autoComposerHeight = 92 + CGFloat(clampedLines - 1) * 20 + (hasAttachments ? 44 : 0)`
   - `maxComposerHeight = isExpanded ? 244 : 334`
   - `composerHeight = max(autoComposerHeight, min(manualComposerHeight, maxComposerHeight))`
   - `panelHeight = isExpanded ? (composerHeight + 356) : (composerHeight + 40)`
   - `editorMaxHeight = max(120, composerHeight - (hasAttachments ? 84 : 40))`
4. **Spring Curves**:
   - Drawer expansion & mode swap: `.spring(response: 0.48, dampingFraction: 0.87)` (instant when `accessibilityReduceMotion` is enabled).
   - Composer height resize: `.spring(response: 0.38, dampingFraction: 0.88)` (instant when `accessibilityReduceMotion` is enabled).

## 2. Two-Phase Model Popover Expansion & Matched Zoom (`ContentView.swift` lines 937–1154)

The Model Picker is the **only** floating `.popover` on the composer:
1. **Capsule-to-Popover Zoom**:
   - The model capsule (`hanlin-composer-model-picker`) attaches `.matchedTransitionSource(id: "model-popover", in: modelPopoverZoom)`.
   - The `.popover` content attaches `.navigationTransition(.zoom(sourceID: "model-popover", in: modelPopoverZoom))`.
2. **Completion-Driven Two-Phase Expansion to `All Models`**:
   - Tapping `All Models` (`hanlin-model-picker-all-models-button`) invokes `coordinator.pushModelSubroute(.allModels, reduceMotion: reduceMotion)` from a single `Button` (never a double-pushing `NavigationLink + simultaneousGesture`).
   - **Phase 1**: `withAnimation(.easeInOut(duration: 0.24), completionCriteria: .removed) { isModelPopoverExpanded = true }` expands the popover frame first while `modelPath` remains `[]`.
   - **Phase 2**: Only inside the completion handler (guarded by `modelPresentationGeneration == generation && activePopup == .modelPicker && isModelPopoverExpanded`) is `.allModels` appended to `modelPath`, triggering `.navigationTransition(.zoom(sourceID: "all-models", in: zoomNamespace))` inside the already-expanded popover bounds.
   - **Cancelled Interactive Swipe-Back Protection**: `syncModelShrinkState()` shrinks `isModelPopoverExpanded = false` only when `modelPath.isEmpty && modelSubpageDidDisappear` both hold.
