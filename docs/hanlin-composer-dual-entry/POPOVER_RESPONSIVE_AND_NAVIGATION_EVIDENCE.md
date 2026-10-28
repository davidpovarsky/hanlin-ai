# Popover Responsive Geometry and Navigation Evidence

**Document Purpose**: Document the dynamic sizing calculations, race condition guards, and navigation transitions for the three composer popovers: General `+`, Direct Tools, and Model Picker.

---

## 1. Dynamic Responsive Sizing Calculation

In `HanlinComposerPopupCoordinator.swift`:

```swift
func responsiveSize(
    target: CGSize,
    horizontalMargin: CGFloat = 24,
    verticalMargin: CGFloat = 80
) -> CGSize {
    #if os(iOS)
    let screenBounds: CGRect
    let safeAreaInsets: UIEdgeInsets
    if let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
       let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
        screenBounds = keyWindow.bounds
        safeAreaInsets = keyWindow.safeAreaInsets
    } else {
        screenBounds = UIScreen.main.bounds
        safeAreaInsets = .zero
    }

    let availableWidth = max(280, screenBounds.width - safeAreaInsets.left - safeAreaInsets.right - horizontalMargin)
    let availableHeight = max(300, screenBounds.height - safeAreaInsets.top - safeAreaInsets.bottom - verticalMargin)

    let finalWidth = min(target.width, availableWidth)
    let finalHeight = min(target.height, availableHeight)
    return CGSize(width: finalWidth, height: finalHeight)
    #else
    return target
    #endif
}
```

### Application in Views
- `HanlinComposerGeneralActionsView`: `coordinator.responsiveSize(target: baseSize, horizontalMargin: 24, verticalMargin: 70)`
- `HanlinComposerToolsRootView`: `coordinator.responsiveSize(target: baseSize, horizontalMargin: 24, verticalMargin: 70)`
- `HanlinModelPickerPopover`: `coordinator.responsiveSize(target: baseSize, horizontalMargin: 20, verticalMargin: 60)`

---

## 2. Coordinator Race Guards

When a user rapidly switches popovers or dismisses during animation:

```swift
// Example in pushGeneralSubroute:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
    guard let self, self.activePopup == .general, self.frameExpanded else { return }
    self.generalNavigationPath.append(subroute)
}
```

### Verified Guards Added
1. `pushGeneralSubroute`: `guard self.activePopup == .general, self.frameExpanded else { return }`
2. `pushToolsSubroute`: `guard self.activePopup == .tools, self.frameExpanded else { return }`
3. `pushModelSubroute`: `guard self.activePopup == .model, self.frameExpanded else { return }`

This prevents pending animations from pushing subroutes into inactive or dismissed popovers.

---

## 3. Navigation Transitions and Flow

- **Two-Phase Expansion**:
  1. Root view button tapped -> Frame expands to destination size (with matched zoom where supported).
  2. Completion closure appends destination to `NavigationPath` -> Subpage slides in.
- **Return / Back Navigation**:
  1. Subpage back button removes destination from `NavigationPath`.
  2. View transitions back to root page.
  3. Frame smoothly shrinks to compact target without clipping.
- **Interrupted Navigation**:
  - Tapping outside or switching to another popover immediately closes the active coordinator, discarding pending subroute pushes.

---

## 4. Acceptance Evidence

- **Unit Sizing Verification**: Tested via `nativeMultilineTextEditorEffectiveMeasurementWidth` (#26) and responsive sizing helpers.
- **XCUI Verification**:
  - `testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap`: Validates General attachments, direct Tools entry, native tools catalog subpage and back, multiline input, and model picker exploration.
  - `testUI09DirectToolsCatalogAndSkillsNavigation`: Validates all subroutes of Tools popover (Catalog, Skills, MCP, Runtime) and their back transitions.
  - `testUI10ModelPickerSearchSelectionAndPersistence`: Validates model picker All Models expansion, search field input, selection, and dismissal.
