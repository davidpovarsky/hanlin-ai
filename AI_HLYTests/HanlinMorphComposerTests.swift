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
}
