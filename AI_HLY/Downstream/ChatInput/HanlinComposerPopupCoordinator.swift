//
//  HanlinComposerPopupCoordinator.swift
//  AI_HLY
//
//  Single shared popup coordinator for the two-entry native composer.
//  Guarantees mutual exclusion across General (+), Direct Tools, and Model Picker
//  popups, and implements the InteriorOrganizerV3_3 two-phase expand/shrink
//  animation state machine.
//

import Foundation
import Observation
import SwiftUI

enum ComposerPopup: String, Identifiable, Hashable, Sendable {
    case general
    case tools
    case model

    var id: String { rawValue }
}

enum ComposerGeneralSubroute: String, Hashable, Sendable {
    case prompts
    case parameters
    case imageSize
}

enum ComposerToolsSubroute: String, Hashable, Sendable {
    case toolsCatalog
    case skillsCenter
    case mcpServers
    case runtimeCenter
}

enum ComposerModelSubroute: String, Hashable, Sendable {
    case allModels
}

@MainActor
@Observable
final class HanlinComposerPopupCoordinator {
    /// Currently presented popup (`nil` when all popups are closed).
    /// Setting this guarantees that at most one popup is ever presented.
    var activePopup: ComposerPopup?

    /// Internal navigation stacks for each popup.
    var generalNavigationPath: [ComposerGeneralSubroute] = []
    var toolsNavigationPath: [ComposerToolsSubroute] = []
    var modelNavigationPath: [ComposerModelSubroute] = []

    /// InteriorOrganizerV3_3 two-phase size state per popup:
    /// Stage 1: `frameExpanded` becomes `true` BEFORE pushing destination onto `NavigationPath`.
    /// Stage 2: `frameExpanded` returns to `false` ONLY when BOTH `navigationPath.isEmpty`
    /// AND `destinationHasDisappeared` are `true` (protecting against cancelled interactive swipe-back).
    var generalFrameExpanded: Bool = false
    var generalDestinationDisappeared: Bool = true
    var isGeneralAnimatingExpand: Bool = false

    var toolsFrameExpanded: Bool = false
    var toolsDestinationDisappeared: Bool = true
    var isToolsAnimatingExpand: Bool = false

    var modelFrameExpanded: Bool = false
    var modelDestinationDisappeared: Bool = true
    var isModelAnimatingExpand: Bool = false

    /// Tracks whether the text input was focused before a popup opened so focus can be restored cleanly.
    var wasInputFocusedBeforePopup: Bool = false

    var shouldRestoreFocusAfterDismiss: Bool {
        wasInputFocusedBeforePopup
    }

    var isGeneralExpanded: Bool {
        generalFrameExpanded
    }

    var isToolsExpanded: Bool {
        toolsFrameExpanded
    }

    var isModelExpanded: Bool {
        modelFrameExpanded
    }

    init() {}

    // MARK: - Mutual Exclusion Entrypoints

    func toggle(_ popup: ComposerPopup, isInputCurrentlyFocused: Bool = false) {
        open(popup, isInputCurrentlyFocused: isInputCurrentlyFocused)
    }

    func open(_ popup: ComposerPopup, isInputCurrentlyFocused: Bool = false) {
        if activePopup == popup {
            closeAll()
            return
        }
        if activePopup == nil {
            wasInputFocusedBeforePopup = isInputCurrentlyFocused
        }
        resetSubroutesAndExpansion()
        activePopup = popup
    }

    func presentDirectTools(isInputCurrentlyFocused: Bool = false) {
        if activePopup == .tools {
            closeAll()
            return
        }
        if activePopup == nil {
            wasInputFocusedBeforePopup = isInputCurrentlyFocused
        }
        resetSubroutesAndExpansion()
        activePopup = .tools
    }

    func switchFromGeneralToTools() {
        resetSubroutesAndExpansion()
        activePopup = .tools
    }

    func close(_ popup: ComposerPopup) {
        guard activePopup == popup else { return }
        closeAll()
    }

    func closeAll() {
        activePopup = nil
        resetSubroutesAndExpansion()
    }

    func binding(for popup: ComposerPopup) -> Binding<Bool> {
        Binding(
            get: { self.activePopup == popup },
            set: { isPresented in
                if isPresented {
                    if self.activePopup != popup {
                        self.resetSubroutesAndExpansion()
                        self.activePopup = popup
                    }
                } else if self.activePopup == popup {
                    self.closeAll()
                }
            }
        )
    }

    private func resetSubroutesAndExpansion() {
        generalNavigationPath.removeAll()
        generalFrameExpanded = false
        generalDestinationDisappeared = true
        isGeneralAnimatingExpand = false

        toolsNavigationPath.removeAll()
        toolsFrameExpanded = false
        toolsDestinationDisappeared = true
        isToolsAnimatingExpand = false

        modelNavigationPath.removeAll()
        modelFrameExpanded = false
        modelDestinationDisappeared = true
        isModelAnimatingExpand = false
    }

    // MARK: - V3.3 Two-Phase Expand & Shrink (General Popup)

    func pushGeneralSubroute(_ route: ComposerGeneralSubroute, reduceMotion: Bool = false) {
        guard !isGeneralAnimatingExpand, generalNavigationPath.isEmpty else { return }
        generalDestinationDisappeared = false
        if reduceMotion {
            generalFrameExpanded = true
            generalNavigationPath.append(route)
            return
        }
        isGeneralAnimatingExpand = true
        withAnimation(.easeInOut(duration: 0.24)) {
            generalFrameExpanded = true
        } completion: {
            self.isGeneralAnimatingExpand = false
            guard self.activePopup == .general, self.generalFrameExpanded else { return }
            self.generalNavigationPath.append(route)
        }
    }

    func handleGeneralNavPathChange(reduceMotion: Bool = false) {
        if generalNavigationPath.isEmpty {
            shrinkGeneralIfReady(reduceMotion: reduceMotion)
        } else {
            generalDestinationDisappeared = false
            if !generalFrameExpanded {
                generalFrameExpanded = true
            }
        }
    }

    func markGeneralDestinationDisappeared(reduceMotion: Bool = false) {
        generalDestinationDisappeared = true
        shrinkGeneralIfReady(reduceMotion: reduceMotion)
    }

    private func shrinkGeneralIfReady(reduceMotion: Bool) {
        guard generalNavigationPath.isEmpty, generalDestinationDisappeared, generalFrameExpanded else { return }
        if reduceMotion {
            generalFrameExpanded = false
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                generalFrameExpanded = false
            }
        }
    }

    // MARK: - V3.3 Two-Phase Expand & Shrink (Tools Popup)

    func pushToolsSubroute(_ route: ComposerToolsSubroute, reduceMotion: Bool = false) {
        guard !isToolsAnimatingExpand, toolsNavigationPath.isEmpty else { return }
        toolsDestinationDisappeared = false
        if reduceMotion {
            toolsFrameExpanded = true
            toolsNavigationPath.append(route)
            return
        }
        isToolsAnimatingExpand = true
        withAnimation(.easeInOut(duration: 0.24)) {
            toolsFrameExpanded = true
        } completion: {
            self.isToolsAnimatingExpand = false
            guard self.activePopup == .tools, self.toolsFrameExpanded else { return }
            self.toolsNavigationPath.append(route)
        }
    }

    func handleToolsNavPathChange(reduceMotion: Bool = false) {
        if toolsNavigationPath.isEmpty {
            shrinkToolsIfReady(reduceMotion: reduceMotion)
        } else {
            toolsDestinationDisappeared = false
            if !toolsFrameExpanded {
                toolsFrameExpanded = true
            }
        }
    }

    func markToolsDestinationDisappeared(reduceMotion: Bool = false) {
        toolsDestinationDisappeared = true
        shrinkToolsIfReady(reduceMotion: reduceMotion)
    }

    private func shrinkToolsIfReady(reduceMotion: Bool) {
        guard toolsNavigationPath.isEmpty, toolsDestinationDisappeared, toolsFrameExpanded else { return }
        if reduceMotion {
            toolsFrameExpanded = false
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                toolsFrameExpanded = false
            }
        }
    }

    // MARK: - V3.3 Two-Phase Expand & Shrink (Model Picker Popup)

    func pushModelSubroute(_ route: ComposerModelSubroute = .allModels, reduceMotion: Bool = false) {
        guard !isModelAnimatingExpand, modelNavigationPath.isEmpty else { return }
        modelDestinationDisappeared = false
        if reduceMotion {
            modelFrameExpanded = true
            modelNavigationPath.append(route)
            return
        }
        isModelAnimatingExpand = true
        withAnimation(.easeInOut(duration: 0.24)) {
            modelFrameExpanded = true
        } completion: {
            self.isModelAnimatingExpand = false
            guard self.activePopup == .model, self.modelFrameExpanded else { return }
            self.modelNavigationPath.append(route)
        }
    }

    /// Dynamically calculates responsive popover dimensions based on available window/screen space
    /// and safe area insets, preventing clipping in narrow split view or landscape keyboard-up states.
    func responsiveSize(
        target: CGSize,
        horizontalMargin: CGFloat = 20,
        verticalMargin: CGFloat = 28
    ) -> CGSize {
        #if canImport(UIKit)
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first {
            let bounds = window.bounds
            let insets = window.safeAreaInsets
            let availableWidth = bounds.width - insets.left - insets.right
            let availableHeight = bounds.height - insets.top - insets.bottom
            let maxWidth = max(240, availableWidth - horizontalMargin)
            let maxHeight = max(260, availableHeight - verticalMargin)
            return CGSize(
                width: min(target.width, maxWidth),
                height: min(target.height, maxHeight)
            )
        }
        #endif
        return target
    }

    func handleModelNavPathChange(reduceMotion: Bool = false) {
        if modelNavigationPath.isEmpty {
            shrinkModelIfReady(reduceMotion: reduceMotion)
        } else {
            modelDestinationDisappeared = false
            if !modelFrameExpanded {
                modelFrameExpanded = true
            }
        }
    }

    func markModelDestinationDisappeared(reduceMotion: Bool = false) {
        modelDestinationDisappeared = true
        shrinkModelIfReady(reduceMotion: reduceMotion)
    }

    private func shrinkModelIfReady(reduceMotion: Bool) {
        guard modelNavigationPath.isEmpty, modelDestinationDisappeared, modelFrameExpanded else { return }
        if reduceMotion {
            modelFrameExpanded = false
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                modelFrameExpanded = false
            }
        }
    }

    // MARK: - Deterministic Synchronous Helpers for Tests & Direct State Transitions

    func navigateToGeneralSubpage(_ route: ComposerGeneralSubroute) {
        generalDestinationDisappeared = false
        generalFrameExpanded = true
        if !generalNavigationPath.contains(route) {
            generalNavigationPath.append(route)
        }
    }

    func popGeneralToRoot() {
        generalNavigationPath.removeAll()
        syncGeneralShrinkState()
    }

    func syncGeneralShrinkState() {
        shrinkGeneralIfReady(reduceMotion: true)
    }

    func navigateToToolsSubpage(_ route: ComposerToolsSubroute) {
        toolsDestinationDisappeared = false
        toolsFrameExpanded = true
        if !toolsNavigationPath.contains(route) {
            toolsNavigationPath.append(route)
        }
    }

    func popToolsToRoot() {
        toolsNavigationPath.removeAll()
        syncToolsShrinkState()
    }

    func syncToolsShrinkState() {
        shrinkToolsIfReady(reduceMotion: true)
    }

    func navigateToModelSubpage(_ route: ComposerModelSubroute = .allModels) {
        modelDestinationDisappeared = false
        modelFrameExpanded = true
        if !modelNavigationPath.contains(route) {
            modelNavigationPath.append(route)
        }
    }

    func popModelToRoot() {
        modelNavigationPath.removeAll()
        syncModelShrinkState()
    }

    func syncModelShrinkState() {
        shrinkModelIfReady(reduceMotion: true)
    }
}
