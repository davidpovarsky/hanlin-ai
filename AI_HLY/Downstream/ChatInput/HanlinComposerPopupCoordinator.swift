//
//  HanlinComposerPopupCoordinator.swift
//  AI_HLY
//
//  Shared coordinator for the integrated HanlinOrganizerDock drawer (.general, .tools)
//  and the anchored Model Picker popover (.model).
//  Enforces mutual exclusion, synchronizes drawer mode with HanlinOrganizerDockState,
//  and implements the completion-ordered two-phase expand-then-push zoom state machine (§4.8).
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
    /// Integrated OrganizerDock state for `.general` and `.tools` drawer modes.
    let dockState = HanlinOrganizerDockState()

    /// Currently active surface (`nil` when collapsed and model popover closed).
    /// Note: `.general` and `.tools` are rendered as modes of the integrated `HanlinOrganizerDock` drawer,
    /// NEVER as floating `.popover` sheets. Only `.model` is presented as a native `.popover`.
    var activePopup: ComposerPopup?

    /// Internal navigation stacks for each surface.
    var generalNavigationPath: [ComposerGeneralSubroute] = []
    var toolsNavigationPath: [ComposerToolsSubroute] = []
    var modelNavigationPath: [ComposerModelSubroute] = []

    /// InteriorOrganizerV3_3 two-phase size state:
    /// Stage 1: `frameExpanded` becomes `true` BEFORE pushing destination onto `NavigationPath`.
    /// Stage 2: `frameExpanded` returns to `false` ONLY when BOTH `navigationPath.isEmpty`
    /// AND `destinationDisappeared` are `true` (protecting against cancelled interactive swipe-back).
    var generalFrameExpanded: Bool = false
    var generalDestinationDisappeared: Bool = true
    var isGeneralAnimatingExpand: Bool = false

    var toolsFrameExpanded: Bool = false
    var toolsDestinationDisappeared: Bool = true
    var isToolsAnimatingExpand: Bool = false

    var modelFrameExpanded: Bool = false
    var modelDestinationDisappeared: Bool = true
    var isModelAnimatingExpand: Bool = false

    /// Monotonically increasing generation counter for the model popover presentation.
    /// Guards against late animation completion callbacks firing after dismissal.
    private(set) var modelPresentationGeneration: Int = 0

    /// Optional measured container size from the hosting workspace/detail column.
    var measuredContainerSize: CGSize = .zero

    /// Deterministic testing hook: when `true`, Stage 1 sets `modelFrameExpanded = true` immediately
    /// and Stage 2 (`modelNavigationPath.append`) waits until `flushPendingAnimationCompletions()` is called.
    var deferAnimationCompletionsForTesting: Bool = false
    private var pendingAnimationCompletions: [@MainActor () -> Void] = []

    /// Tracks whether the text input was focused before opening so focus can be restored cleanly if desired.
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

    // MARK: - Mutual Exclusion & Drawer Mode Synchronization

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
        modelPresentationGeneration &+= 1
        resetSubroutesAndExpansion()
        activePopup = popup

        switch popup {
        case .general:
            dockState.openMode(.general)
        case .tools:
            dockState.openMode(.tools)
        case .model:
            dockState.collapse()
        }
    }

    func presentDirectTools(isInputCurrentlyFocused: Bool = false) {
        if activePopup == .tools {
            closeAll()
            return
        }
        if activePopup == nil {
            wasInputFocusedBeforePopup = isInputCurrentlyFocused
        }
        modelPresentationGeneration &+= 1
        resetSubroutesAndExpansion()
        activePopup = .tools
        dockState.openMode(.tools)
    }

    /// Switches from General (`+`) to Tools inside the SAME expanded OrganizerDock drawer without dismissing or reopening.
    func switchFromGeneralToTools() {
        modelPresentationGeneration &+= 1
        resetSubroutesAndExpansion()
        activePopup = .tools
        dockState.openMode(.tools)
    }

    /// Switches from Tools to General (`+`) inside the SAME expanded OrganizerDock drawer without dismissing or reopening.
    func switchFromToolsToGeneral() {
        modelPresentationGeneration &+= 1
        resetSubroutesAndExpansion()
        activePopup = .general
        dockState.openMode(.general)
    }

    func close(_ popup: ComposerPopup) {
        guard activePopup == popup else { return }
        closeAll()
    }

    func closeAll() {
        modelPresentationGeneration &+= 1
        activePopup = nil
        dockState.collapse()
        resetSubroutesAndExpansion()
    }

    /// Synchronizes `activePopup` when `dockState.mode` is changed by a drawer handle tap, drag gesture, or editor resize.
    func syncFromDockModeChange(_ newMode: HanlinOrganizerDrawerMode) {
        switch newMode {
        case .collapsed:
            if activePopup == .general || activePopup == .tools {
                activePopup = nil
                resetSubroutesAndExpansion()
            }
        case .general:
            if activePopup != .general {
                modelPresentationGeneration &+= 1
                resetSubroutesAndExpansion()
                activePopup = .general
            }
        case .tools:
            if activePopup != .tools {
                modelPresentationGeneration &+= 1
                resetSubroutesAndExpansion()
                activePopup = .tools
            }
        }
    }

    func binding(for popup: ComposerPopup) -> Binding<Bool> {
        Binding(
            get: { self.activePopup == popup },
            set: { isPresented in
                if isPresented {
                    if self.activePopup != popup {
                        self.open(popup)
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

    // MARK: - V3.3 Two-Phase Expand & Shrink (General Drawer Subroutes)

    func pushGeneralSubroute(_ route: ComposerGeneralSubroute, reduceMotion: Bool = false) {
        guard !generalNavigationPath.contains(route) else { return }
        generalDestinationDisappeared = false
        if reduceMotion {
            generalFrameExpanded = true
            generalNavigationPath.append(route)
            return
        }
        withAnimation(.easeInOut(duration: 0.24)) {
            generalFrameExpanded = true
            generalNavigationPath.append(route)
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

    // MARK: - V3.3 Two-Phase Expand & Shrink (Tools Drawer Subroutes)

    func pushToolsSubroute(_ route: ComposerToolsSubroute, reduceMotion: Bool = false) {
        guard !toolsNavigationPath.contains(route) else { return }
        toolsDestinationDisappeared = false
        if reduceMotion {
            toolsFrameExpanded = true
            toolsNavigationPath.append(route)
            return
        }
        withAnimation(.easeInOut(duration: 0.24)) {
            toolsFrameExpanded = true
            toolsNavigationPath.append(route)
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

    // MARK: - V3.3 Completion-Ordered Two-Phase Expand & Shrink (Model Picker Popover, §4.8)

    /// Expands the model popover frame FIRST, and appends `route` ONLY after the expansion animation
    /// completes (using `.removed` completion criteria), matching `ContentView.swift` lines 1018-1025.
    func pushModelSubroute(_ route: ComposerModelSubroute = .allModels, reduceMotion: Bool = false) {
        guard !modelNavigationPath.contains(route), !isModelAnimatingExpand else { return }
        if activePopup != .model {
            activePopup = .model
        }
        let capturedGeneration = modelPresentationGeneration
        modelDestinationDisappeared = false

        let completeRoutePush: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            // A completion from a dismissed presentation must not clear the
            // animation flag belonging to a newly opened popover.
            guard self.modelPresentationGeneration == capturedGeneration else { return }
            guard self.activePopup == .model,
                  self.modelFrameExpanded,
                  self.modelNavigationPath.isEmpty,
                  !self.modelNavigationPath.contains(route) else {
                self.isModelAnimatingExpand = false
                return
            }
            self.isModelAnimatingExpand = false
            self.modelNavigationPath.append(route)
        }

        if deferAnimationCompletionsForTesting {
            isModelAnimatingExpand = true
            modelFrameExpanded = true
            pendingAnimationCompletions.append(completeRoutePush)
            return
        }

        if reduceMotion {
            modelFrameExpanded = true
            completeRoutePush()
            return
        }

        isModelAnimatingExpand = true
        withAnimation(.easeInOut(duration: 0.24), completionCriteria: .removed) {
            modelFrameExpanded = true
        } completion: {
            Task { @MainActor in
                completeRoutePush()
            }
        }
    }

    /// Executes any queued animation completions in deterministic unit tests (`ModelPopoverZoomOrderTests`).
    func flushPendingAnimationCompletions(firstOnly: Bool = false) {
        let count = firstOnly ? min(1, pendingAnimationCompletions.count) : pendingAnimationCompletions.count
        let completions = Array(pendingAnimationCompletions.prefix(count))
        pendingAnimationCompletions.removeFirst(count)
        for completion in completions {
            completion()
        }
    }

    /// Dynamically calculates responsive popover dimensions based on actual container geometry
    /// (when provided) or active window scene bounds, preventing clipping in narrow split view.
    func responsiveSize(
        target: CGSize,
        availableContainerSize: CGSize? = nil,
        horizontalMargin: CGFloat = 20,
        verticalMargin: CGFloat = 28
    ) -> CGSize {
        let candidateContainer = availableContainerSize ?? measuredContainerSize
        if candidateContainer.width.isFinite && candidateContainer.height.isFinite &&
            candidateContainer.width > 0 && candidateContainer.height > 0 {
            let maxWidth = max(1, candidateContainer.width - horizontalMargin)
            let maxHeight = max(1, candidateContainer.height - verticalMargin)
            return CGSize(
                width: min(target.width, maxWidth),
                height: min(target.height, maxHeight)
            )
        }
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
            let maxWidth = max(1, availableWidth - horizontalMargin)
            let maxHeight = max(1, availableHeight - verticalMargin)
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
