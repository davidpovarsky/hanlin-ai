import CoreGraphics
import Testing
@testable import AI_Hanlin

@Suite("Morph composer reference geometry")
struct HanlinMorphComposerTests {
    @Test("Natural page height is bounded by the reference viewport")
    func heightAndOverflow() {
        let limit = HanlinMorphGeometry.viewportLimit(availableHeight: 500)
        #expect(limit == 360)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: 180, maxHeight: limit) == 180)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: 600, maxHeight: limit) == limit)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: nil, maxHeight: limit) == nil)
        #expect(HanlinMorphGeometry.viewportLimit(availableHeight: 20) == 80)
    }

    @Test("Page budget accounts for keyboard-adjusted space, editor, accessories and toolbar")
    func remainingViewportBudget() {
        let ordinary = HanlinMorphGeometry.pageBudget(availableHeight: 800, accessoryHeight: 0, inputHeight: 120, toolbarHeight: 44)
        let expanded = HanlinMorphGeometry.pageBudget(availableHeight: 800, accessoryHeight: 130, inputHeight: 260, toolbarHeight: 44)
        let keyboard = HanlinMorphGeometry.pageBudget(availableHeight: 400, accessoryHeight: 130, inputHeight: 260, toolbarHeight: 60)
        #expect(ordinary == 545)
        #expect(expanded == 275)
        #expect(keyboard == 0)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: 900, maxHeight: expanded) == expanded)
        #expect(HanlinMorphGeometry.accessoryBudget(availableHeight: 400, inputHeight: 260, toolbarHeight: 60, isExpanded: true) == 0)
        #expect(HanlinMorphGeometry.accessoryBudget(availableHeight: 800, inputHeight: 260, toolbarHeight: 44, isExpanded: true) == 405)
    }

    @Test("Editor budget shares the bubble viewport with measured controls, attachments and expanded panel")
    func editorAndShellShareViewport() {
        let roomy = HanlinMorphGeometry.editorBudget(availableHeight: 800, accessoryHeight: 60, inputHeight: 260, editorHeight: 180, toolbarHeight: 44, isExpanded: false)
        #expect(roomy == 628)
        #expect(roomy > 226, "A large font may grow past the old fixed composer cap")
        let keyboard = HanlinMorphGeometry.editorBudget(availableHeight: 400, accessoryHeight: 100, inputHeight: 300, editorHeight: 200, toolbarHeight: 60, isExpanded: true)
        #expect(keyboard == 49)
        #expect(keyboard + (300 - 200) + 100 + 119 + 32 == 400)
        #expect(HanlinMorphGeometry.editorBudget(availableHeight: 100, accessoryHeight: 100, inputHeight: 300, editorHeight: 200, toolbarHeight: 60, isExpanded: true) == 0)
    }

    @Test("The source back gesture requires a predominantly horizontal leftward drag")
    func backSwipeThreshold() {
        #expect(HanlinMorphGeometry.isBackSwipe(horizontal: -66, vertical: 10))
        #expect(!HanlinMorphGeometry.isBackSwipe(horizontal: -65, vertical: 10))
        #expect(!HanlinMorphGeometry.isBackSwipe(horizontal: 100, vertical: 0))
        #expect(!HanlinMorphGeometry.isBackSwipe(horizontal: -100, vertical: 90))
    }

    @Test("Home and detail tags remain distinct across page changes")
    func pageIdentity() {
        let home = HanlinMorphPageID<String>.home
        let first = HanlinMorphPageID.detail("tools")
        let second = HanlinMorphPageID.detail("skills")
        #expect(home != first)
        #expect(first != second)
        #expect(first == HanlinMorphPageID.detail("tools"))
    }

    @MainActor
    @Test("Inner navigation returns through live coordinator without closing the bubble")
    func coordinatorNavigationPreservesOpenState() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.open(.general)
        #expect(coordinator.morphRoute == nil)
        coordinator.pushGeneralSubroute(.prompts, reduceMotion: true)
        #expect(coordinator.morphRoute == .general(.prompts))
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == nil)
        #expect(coordinator.activePopup == .general)

        coordinator.switchFromGeneralToTools()
        #expect(coordinator.morphRoute == .tools(nil))
        coordinator.pushToolsSubroute(.skillsCenter, reduceMotion: true)
        #expect(coordinator.morphRoute == .tools(.skillsCenter))
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == .tools(nil))
        #expect(coordinator.activePopup == .tools)
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == nil)
        #expect(coordinator.activePopup == .general)
    }

    @MainActor
    @Test("Each capability settings route stays in the same open bubble")
    func capabilityRoutesReturnToOpenHome() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.open(.general)
        for route in [ComposerGeneralSubroute.search, .thinking, .creative] {
            coordinator.pushGeneralSubroute(route, reduceMotion: true)
            #expect(coordinator.morphRoute == .general(route))
            #expect(coordinator.activePopup == .general)
            coordinator.returnFromMorphPage()
            #expect(coordinator.morphRoute == nil)
            #expect(coordinator.activePopup == .general)
        }
        coordinator.switchFromGeneralToTools()
        coordinator.pushToolsSubroute(.mcpServers, reduceMotion: true)
        #expect(coordinator.morphRoute == .tools(.mcpServers))
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == .tools(nil))
        #expect(coordinator.activePopup == .tools)
    }
}
