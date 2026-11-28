//
//  HanlinComposerPopupCoordinator.swift
//  AI_HLY
//
//  Shared coordinator for the integrated HanlinOrganizerDock drawer (.general, .tools)
//  and the anchored Model Picker popover (.model).
//  Keeps the action drawer and model presentation independent. UIKit owns the
//  model surface animation; one route update describes its final content.
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
    case search
    case thinking
    case creative
    case prompts
    case parameters
    case imageSize
    case miniApps
    case capabilities
}

enum ComposerToolsSubroute: String, Hashable, Sendable {
    case toolsCatalog
    case skillsCenter
    case mcpServers
}

enum ComposerModelSubroute: String, Hashable, Sendable {
    case allModels
}

enum ComposerMorphRoute: Hashable {
    case general(ComposerGeneralSubroute)
    case tools(ComposerToolsSubroute?)
}

@MainActor
@Observable
final class HanlinComposerPopupCoordinator {
    /// Integrated OrganizerDock state for `.general` and `.tools` drawer modes.
    let dockState = HanlinOrganizerDockState()

    /// The in-bubble action page. Model presentation never changes this route.
    var activePopup: ComposerPopup?

    /// A model popover can be open over either action page without collapsing it.
    var isModelPresented = false

    /// Projects the existing navigation state into the Morph shell without
    /// introducing a second source of truth for the current page.
    var morphRoute: ComposerMorphRoute? {
        if activePopup == .tools { return .tools(toolsNavigationPath.last) }
        if activePopup == .general, let route = generalNavigationPath.last { return .general(route) }
        return nil
    }

    func returnFromMorphPage() {
        if activePopup == .tools {
            if toolsNavigationPath.isEmpty {
                switchFromToolsToGeneral()
            } else {
                toolsNavigationPath.removeLast()
            }
        } else if activePopup == .general && !generalNavigationPath.isEmpty {
            generalNavigationPath.removeLast()
        }
    }

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

    var modelPopoverSize: CGSize {
        responsiveSize(target: modelFrameExpanded
            ? CGSize(width: 344, height: 472) : CGSize(width: 286, height: 324))
    }

    init() {}

    // MARK: - Independent model presentation and drawer navigation

    func toggle(_ popup: ComposerPopup, isInputCurrentlyFocused: Bool = false) {
        if popup == .model {
            if isModelPresented { close(.model) }
            else { open(.model, isInputCurrentlyFocused: isInputCurrentlyFocused) }
        } else if activePopup == popup {
            close(popup)
        } else {
            open(popup, isInputCurrentlyFocused: isInputCurrentlyFocused)
        }
    }

    func open(_ popup: ComposerPopup, isInputCurrentlyFocused: Bool = false) {
        if popup == .model {
            guard !isModelPresented else { return }
            wasInputFocusedBeforePopup = isInputCurrentlyFocused
            modelPresentationGeneration &+= 1
            resetModelNavigation()
            isModelPresented = true
            return
        }
        guard activePopup != popup else { return }
        if activePopup == nil { wasInputFocusedBeforePopup = isInputCurrentlyFocused }
        resetDrawerNavigation()
        activePopup = popup
        dockState.openMode(popup == .tools ? .tools : .general)
    }

    func presentDirectTools(isInputCurrentlyFocused: Bool = false) {
        open(.tools, isInputCurrentlyFocused: isInputCurrentlyFocused)
    }

    /// Change the page within the mounted bubble. An open model popover is independent.
    func switchFromGeneralToTools() {
        open(.tools)
    }

    func switchFromToolsToGeneral() {
        open(.general)
    }

    func close(_ popup: ComposerPopup) {
        if popup == .model {
            guard isModelPresented else { return }
            modelPresentationGeneration &+= 1
            isModelPresented = false
            resetModelNavigation()
        } else if activePopup == popup {
            activePopup = nil
            dockState.collapse()
            resetDrawerNavigation()
        }
    }

    /// Explicit session/context teardown; ordinary control actions close their own surface.
    func closeAll() {
        modelPresentationGeneration &+= 1
        isModelPresented = false
        activePopup = nil
        dockState.collapse()
        resetDrawerNavigation()
        resetModelNavigation()
    }

    func syncFromDockModeChange(_ newMode: HanlinOrganizerDrawerMode) {
        let next: ComposerPopup? = switch newMode {
        case .collapsed: nil
        case .general: .general
        case .tools: .tools
        }
        guard activePopup != next else { return }
        activePopup = next
        resetDrawerNavigation()
    }

    func binding(for popup: ComposerPopup) -> Binding<Bool> {
        Binding(
            get: { popup == .model ? self.isModelPresented : self.activePopup == popup },
            set: { isPresented in
                if isPresented { self.open(popup) }
                else { self.close(popup) }
            }
        )
    }

    private func resetDrawerNavigation() {
        generalNavigationPath.removeAll()
        generalFrameExpanded = false
        generalDestinationDisappeared = true
        isGeneralAnimatingExpand = false
        toolsNavigationPath.removeAll()
        toolsFrameExpanded = false
        toolsDestinationDisappeared = true
        isToolsAnimatingExpand = false
    }

    private func resetModelNavigation() {
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

    // MARK: - One native model size transition

    /// Content and target size change together. UIKit performs the only outer
    /// transition; there is no delayed second push or inner SwiftUI zoom.
    func pushModelSubroute(_ route: ComposerModelSubroute = .allModels, reduceMotion: Bool = false) {
        guard !modelNavigationPath.contains(route) else { return }
        if !isModelPresented { open(.model) }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            modelDestinationDisappeared = false
            modelFrameExpanded = true
            modelNavigationPath = [route]
            isModelAnimatingExpand = !reduceMotion
        }
    }

    func modelFrameResizeDidComplete(presentationID: Int, size: CGSize) {
        guard presentationID == modelPresentationGeneration,
              isModelPresented, size == modelPopoverSize else { return }
        isModelAnimatingExpand = false
    }

    func popModelSubroute(reduceMotion: Bool = false) {
        guard !modelNavigationPath.isEmpty else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            modelNavigationPath.removeAll()
            modelDestinationDisappeared = true
            modelFrameExpanded = false
            isModelAnimatingExpand = !reduceMotion
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
        // One size animation, owned by the native popover presentation.
        modelFrameExpanded = false
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
