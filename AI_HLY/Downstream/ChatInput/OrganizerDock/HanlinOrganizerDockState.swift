//
//  HanlinOrganizerDockState.swift
//  AI_HLY
//
//  Source-faithful layout and gesture controller ported from
//  InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift (lines 586-935).
//  Controls the single integrated ZStack(alignment: .bottom) drawer + composer
//  height formulas, drag thresholds, manual editor resize, keyboard/focus
//  interactions, and per-context transient height resets.
//

import Foundation
import Observation
import SwiftUI

/// Represents the single active state of the integrated OrganizerDock drawer.
/// Only one mode can be active at any time.
enum HanlinOrganizerDrawerMode: String, Equatable, Hashable, Sendable {
    case collapsed
    case general
    case tools
}

@MainActor
@Observable
final class HanlinOrganizerDockState {
    /// Current conversation or draft context key (e.g. `"new"` or `chatRecord.id.uuidString`).
    var contextKey: String

    /// Active drawer mode (`.collapsed`, `.general`, or `.tools`).
    var mode: HanlinOrganizerDrawerMode = .collapsed

    /// Remembers the last expanded mode so dragging the handle upward reopens the user's last active mode.
    var lastExpandedMode: HanlinOrganizerDrawerMode = .general

    /// Measured text editor height (minimum 26pt in source formula).
    var measuredInputHeight: CGFloat = 26

    /// User-adjusted manual composer height from the top resize handle or accessibility action.
    var manualComposerHeight: CGFloat?

    /// Starting composer height captured at the beginning of a resize drag gesture.
    var gestureStartHeight: CGFloat?

    /// Available container height measured from the workspace/chat geometry.
    var availableHeight: CGFloat = 780

    /// Additional height required by attachment strips, detected links, prompt cards, or active mode chips.
    var attachmentOverheadHeight: CGFloat = 0

    /// Current keyboard overlap height if present.
    var keyboardHeight: CGFloat = 0

    /// Tracks whether the composer text editor currently has focus.
    var isInputFocused: Bool = false

    init(contextKey: String = "new") {
        self.contextKey = contextKey
    }

    // MARK: - Source-Faithful Height Formulas (ContentView.swift lines 603-618)

    var isExpanded: Bool {
        mode != .collapsed
    }

    /// Pure source formula: `min(226, max(126, measuredInputHeight + 99))` when no attachment strips are active,
    /// or proportionally increased when attachment/chip strips are visible.
    static func calculateAutoComposerHeight(
        measuredInputHeight: CGFloat,
        attachmentOverheadHeight: CGFloat = 0
    ) -> CGFloat {
        let clampedInput = max(26, measuredInputHeight)
        let base = min(226, max(126, clampedInput + 99))
        guard attachmentOverheadHeight > 0 else {
            return base
        }
        return min(310, base + attachmentOverheadHeight)
    }

    var autoComposerHeight: CGFloat {
        Self.calculateAutoComposerHeight(
            measuredInputHeight: measuredInputHeight,
            attachmentOverheadHeight: attachmentOverheadHeight
        )
    }

    /// Pure source formula: `max(autoComposerHeight, min(515, availableHeight * 0.76))`
    /// adapted for keyboard safe area when keyboard is visible.
    static func calculateMaxComposerHeight(
        autoComposerHeight: CGFloat,
        availableHeight: CGFloat,
        keyboardHeight: CGFloat = 0
    ) -> CGFloat {
        let effectiveAvailable = max(200, availableHeight - max(0, keyboardHeight))
        return max(autoComposerHeight, min(515, effectiveAvailable * 0.76))
    }

    var maxComposerHeight: CGFloat {
        Self.calculateMaxComposerHeight(
            autoComposerHeight: autoComposerHeight,
            availableHeight: availableHeight,
            keyboardHeight: keyboardHeight
        )
    }

    /// Pure source formula:
    /// `min(maxComposerHeight, max(autoComposerHeight, manualComposerHeight ?? autoComposerHeight))`
    var composerHeight: CGFloat {
        min(maxComposerHeight, max(autoComposerHeight, manualComposerHeight ?? autoComposerHeight))
    }

    /// Pure source formula:
    /// `isExpanded ? min(max(composerHeight + 36, availableHeight - 10), composerHeight + 321) : composerHeight + 35`
    static func calculatePanelHeight(
        isExpanded: Bool,
        composerHeight: CGFloat,
        availableHeight: CGFloat,
        keyboardHeight: CGFloat = 0
    ) -> CGFloat {
        guard isExpanded else {
            return composerHeight + 35
        }
        let effectiveAvailable = max(composerHeight + 46, availableHeight - max(0, keyboardHeight))
        return min(max(composerHeight + 36, effectiveAvailable - 10), composerHeight + 321)
    }

    var panelHeight: CGFloat {
        Self.calculatePanelHeight(
            isExpanded: isExpanded,
            composerHeight: composerHeight,
            availableHeight: availableHeight,
            keyboardHeight: keyboardHeight
        )
    }

    /// Visible drawer height above the front composer shell (`35pt` handle lip when collapsed; up to `321pt` when expanded).
    var visibleDrawerRegionHeight: CGFloat {
        max(35, panelHeight - composerHeight)
    }

    /// Dynamic max height passed to `NativeMultilineTextEditor` so manual composer resize genuinely expands usable UITextView space.
    var editorMaxHeight: CGFloat {
        let usable = composerHeight - 88 - attachmentOverheadHeight
        return max(140, usable)
    }

    // MARK: - Mode Transitions (R2 & R3)

    func toggleMode(_ target: HanlinOrganizerDrawerMode) {
        guard target != .collapsed else {
            collapse()
            return
        }
        if mode == target {
            mode = .collapsed
        } else {
            lastExpandedMode = target
            isInputFocused = false
            mode = target
        }
    }

    func openMode(_ target: HanlinOrganizerDrawerMode) {
        if target == .collapsed {
            mode = .collapsed
        } else {
            lastExpandedMode = target
            isInputFocused = false
            mode = target
        }
    }

    func collapse() {
        mode = .collapsed
    }

    func handleDrawerHandleTap() {
        if isExpanded {
            mode = .collapsed
        } else {
            isInputFocused = false
            mode = lastExpandedMode
        }
    }

    // MARK: - Gesture Handlers (ContentView.swift lines 675-683 & 906-933)

    /// Handles the top drawer drag gesture (`minimumDistance: 20`).
    /// Upward drag (`< -34`) expands the drawer; downward drag (`> 34`) collapses it.
    func handleDrawerDragEnded(translationHeight: CGFloat, minimumDistance: CGFloat = 20) {
        guard abs(translationHeight) >= minimumDistance else { return }
        if translationHeight < -34 {
            isInputFocused = false
            if mode == .collapsed {
                mode = lastExpandedMode
            }
        } else if translationHeight > 34 {
            mode = .collapsed
        }
    }

    /// Handles the composer resize drag gesture (`minimumDistance: 7`).
    /// Clamps height between `autoComposerHeight` and `maxComposerHeight`, and collapses the drawer
    /// when resized beyond `autoComposerHeight + 12`.
    func handleComposerResizeChanged(translationHeight: CGFloat) {
        let start = gestureStartHeight ?? composerHeight
        if gestureStartHeight == nil {
            gestureStartHeight = start
        }
        let proposed = start - translationHeight
        manualComposerHeight = min(maxComposerHeight, max(autoComposerHeight, proposed))
        if proposed > autoComposerHeight + 12 && isExpanded {
            mode = .collapsed
        }
    }

    func handleComposerResizeEnded() {
        gestureStartHeight = nil
        if let manualComposerHeight, manualComposerHeight < autoComposerHeight + 10 {
            self.manualComposerHeight = nil
        }
    }

    /// Accessibility adjustable action (`+72` / `-72` points) from `ContentView.swift` lines 922-927.
    func adjustComposerHeightByAccessibility(increment: Bool) {
        let step: CGFloat = increment ? 72 : -72
        let next = min(maxComposerHeight, max(autoComposerHeight, composerHeight + step))
        manualComposerHeight = next <= autoComposerHeight + 6 ? nil : next
        if let manualComposerHeight, manualComposerHeight > autoComposerHeight + 12 && isExpanded {
            mode = .collapsed
        }
    }

    // MARK: - Context, Draft, and Focus Lifecycle (ContentView.swift lines 621-635)

    /// Resets only transient layout/expansion state when switching conversation context; NEVER clears draft text or attachments.
    func handleContextKeyChange(_ newKey: String) {
        guard newKey != contextKey else { return }
        contextKey = newKey
        manualComposerHeight = nil
        gestureStartHeight = nil
        measuredInputHeight = 26
        isInputFocused = false
        mode = .collapsed
    }

    func handleDraftTextChange(_ text: String) {
        if text.isEmpty {
            manualComposerHeight = nil
        }
    }

    func handleInputFocusChange(_ focused: Bool) {
        isInputFocused = focused
        if focused && isExpanded {
            mode = .collapsed
        }
    }
}
