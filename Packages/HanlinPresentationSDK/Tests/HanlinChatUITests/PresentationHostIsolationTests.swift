import Foundation
import Testing
import HanlinChatUI

@MainActor
@Suite("Original presentation host isolation")
struct PresentationHostIsolationTests {
    @Test func traceSinkAndScrollStateStayWithTheCreatingHost() {
        var firstEvents: [String] = []
        var secondEvents: [String] = []
        var observedMode: String?
        let first = ChatAutoFollowController(onTrace: { event, fields in
            firstEvents.append(event)
            observedMode = fields["autoFollowMode"] as? String
        })
        let second = ChatAutoFollowController(onTrace: { event, _ in
            secondEvents.append(event)
        })
        first.pauseFollowing(reason: "selection")
        #expect(first.mode == .pausedByUser)
        #expect(second.mode == .following)
        #expect(firstEvents == ["autoFollowPausedByUser"])
        #expect(secondEvents.isEmpty)
        #expect(observedMode == "pausedByUser")
        second.beginRun()
        #expect(first.mode == .pausedByUser)
        #expect(secondEvents == ["autoFollowEnabled"])
    }

    @Test func hostWithoutDiagnosticsUsesTheSameOriginalLifecycle() {
        let controller = ChatAutoFollowController()
        controller.updateNearBottom(false)
        controller.userInteractionBegan()
        controller.userInteractionEnded()
        #expect(controller.mode == .pausedByUser)
        controller.resumeFollowing()
        #expect(controller.mode == .following)
        #expect(controller.shouldRequestScrollForVisualUpdate())
    }
}
