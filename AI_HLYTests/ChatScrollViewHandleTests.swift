import Testing
import UIKit
@testable import AI_Hanlin

@MainActor
@Suite("Transcript native viewport lifetime")
struct ChatScrollViewHandleTests {
    @Test func positiveGeometryWithoutAWindowCannotPositionATranscript() {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        handle.bind(scrollView, conversationID: conversationID)
        handle.activate(conversationID: conversationID)
        #expect(handle.layout(conversationID: conversationID) == nil)
    }

    @Test func everyReadRechecksWindowDimensionsAndConversation() throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        window.addSubview(scrollView)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        handle.bind(scrollView, conversationID: conversationID)
        handle.activate(conversationID: conversationID)
        let initialLayout = try #require(handle.layout(conversationID: conversationID))
        #expect(initialLayout.hasScrollableContent)
        #expect(handle.layout(conversationID: UUID()) == nil)

        scrollView.bounds.size.height = 0
        #expect(handle.layout(conversationID: conversationID) == nil)
        scrollView.bounds.size.height = 600
        #expect(handle.layout(conversationID: conversationID) != nil)
        // No bridge callback is needed for the execution-time window guard.
        scrollView.removeFromSuperview()
        #expect(handle.layout(conversationID: conversationID) == nil)
    }

    @Test func detachAndReplacementInvalidateCapturedRequestsWithoutRetainingViews() {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        weak var releasedScrollView: UIScrollView?
        do {
            let scrollView = UIScrollView()
            releasedScrollView = scrollView
            handle.bind(scrollView, conversationID: conversationID)
        }
        #expect(releasedScrollView == nil)
        handle.activate(conversationID: conversationID)
        let previous = handle.generation
        handle.deactivate()
        #expect(handle.generation != previous)
        let detached = handle.generation
        handle.bind(UIScrollView(), conversationID: conversationID)
        #expect(handle.generation != detached)
        #expect(handle.layout(conversationID: conversationID) == nil)
    }

    @Test func lateWindowAttachmentDeliversOneDeferredReadinessCallback() async throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        var calls = 0
        #expect(handle.whenReady(conversationID: conversationID) { calls += 1 } == nil)
        window.addSubview(scrollView)
        let attached = try #require(handle.whenReady(conversationID: conversationID) { calls += 1 })
        #expect(calls == 0, "Never publish SwiftUI changes inside the UIKit layout callback")
        await attached.value
        #expect(calls == 1)
        #expect(handle.whenReady(conversationID: conversationID) { calls += 1 } == nil)
    }

    @Test func cancelledReadinessCannotRestoreAPreviousConversation() async throws {
        let conversationID = UUID()
        let replacementID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        window.addSubview(scrollView)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        var staleCalls = 0
        let stale = try #require(handle.whenReady(conversationID: conversationID) { staleCalls += 1 })
        handle.deactivate()
        handle.activate(conversationID: replacementID)
        handle.bind(scrollView, conversationID: replacementID)
        var currentCalls = 0
        let current = try #require(handle.whenReady(conversationID: replacementID) { currentCalls += 1 })
        await stale.value
        await current.value
        #expect(staleCalls == 0 && currentCalls == 1)
        #expect(handle.layout(conversationID: conversationID) == nil)
    }
}
