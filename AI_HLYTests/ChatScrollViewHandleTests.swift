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

    @Test func resizedViewportRejectsARequestBeforeTheNextBridgeCallback() throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        window.addSubview(scrollView)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        let beforeResize = handle.generation
        #expect(handle.layout(conversationID: conversationID,
                              expectedGeneration: beforeResize) != nil)

        // Reproduce the interval between UIKit's resize and the configuration
        // view's layout callback: the old generation still appears current.
        scrollView.bounds.size = CGSize(width: 400, height: 320)
        #expect(handle.generation == beforeResize)
        #expect(handle.layout(conversationID: conversationID,
                              expectedGeneration: beforeResize) == nil)
        #expect(handle.generation != beforeResize)
        let current = try #require(handle.layout(conversationID: conversationID))
        #expect(current.viewportHeight == 320)

        let beforeInset = handle.generation
        scrollView.contentInset.bottom = 220
        #expect(handle.layout(conversationID: conversationID,
                              expectedGeneration: beforeInset) == nil)
    }

    @Test func movingTheSameScrollViewToAnotherWindowInvalidatesQueuedPositioning() {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let firstWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let secondWindow = UIWindow(frame: firstWindow.bounds)
        let scrollView = UIScrollView(frame: firstWindow.bounds)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        firstWindow.addSubview(scrollView)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        let previous = handle.generation
        secondWindow.addSubview(scrollView)
        #expect(handle.layout(conversationID: conversationID,
                              expectedGeneration: previous) == nil)
        #expect(handle.layout(conversationID: conversationID) != nil)
    }

    @Test func contentGrowthAndUserScrollingKeepTheViewportLifetime() {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        window.addSubview(scrollView)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        let previous = handle.generation
        scrollView.contentSize.height = 2_400
        scrollView.contentOffset.y = 300
        handle.bind(scrollView, conversationID: conversationID)
        #expect(handle.generation == previous)
        #expect(handle.layout(conversationID: conversationID,
                              expectedGeneration: previous)?.contentHeight == 2_400)
        #expect(scrollView.contentOffset.y == 300, "Inspection must preserve the user's history position")
    }

    @Test func outgoingConversationCallbacksCannotUnbindOrCancelTheCurrentViewport() async throws {
        let previousConversation = UUID()
        let currentConversation = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        window.addSubview(scrollView)
        handle.activate(conversationID: currentConversation)
        handle.bind(scrollView, conversationID: currentConversation)
        var calls = 0
        let pending = try #require(handle.whenReady(conversationID: currentConversation) { calls += 1 })
        let currentGeneration = handle.generation
        handle.bind(nil, conversationID: previousConversation)
        handle.deactivate(conversationID: previousConversation)
        #expect(handle.whenReady(conversationID: previousConversation) {
            Issue.record("An outgoing conversation cannot become ready again")
        } == nil)
        #expect(handle.generation == currentGeneration)
        await pending.value
        #expect(calls == 1)
        #expect(handle.layout(conversationID: currentConversation) != nil)
    }

    @Test func deferredReadinessRechecksResizeAndCanRecoverAtTheNewViewport() async throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        window.addSubview(scrollView)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        var calls = 0
        let stale = try #require(handle.whenReady(conversationID: conversationID) { calls += 1 })
        scrollView.bounds.size.height = 300
        await stale.value
        #expect(calls == 0)
        let current = try #require(handle.whenReady(conversationID: conversationID) { calls += 1 })
        await current.value
        #expect(calls == 1)
    }

    @Test func settledPositionReadsTheCurrentOffsetWithoutMutatingTheViewport() throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        window.addSubview(scrollView)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        scrollView.contentInset.bottom = 20
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        let generation = handle.generation

        scrollView.contentOffset.y = 600
        let reading = try #require(handle.position(conversationID: conversationID))
        #expect(reading.isNearBottom == false)
        scrollView.contentOffset.y = 1_420
        let bottom = try #require(handle.position(conversationID: conversationID))
        #expect(bottom.isNearBottom == true)
        #expect(handle.generation == generation)
        #expect(scrollView.contentOffset.y == 1_420)
        #expect(handle.position(conversationID: UUID()) == nil)

        scrollView.removeFromSuperview()
        #expect(handle.position(conversationID: conversationID) == nil)
    }

    @Test func diagnosticPeekCannotAdvanceGenerationOrCancelPendingReadiness() async throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        window.addSubview(scrollView)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        scrollView.contentInset.bottom = 20
        scrollView.contentOffset.y = 300
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        let generation = handle.generation
        var calls = 0
        let pending = try #require(handle.whenReady(conversationID: conversationID) { calls += 1 })

        // UIKit has resized, but the bridge has not refreshed the lifetime yet.
        scrollView.bounds.size.height = 320
        let observed = try #require(handle.peekPosition(conversationID: conversationID))
        #expect(observed.layout.viewportHeight == 320 && observed.contentOffsetY == 300)
        #expect(handle.generation == generation && !pending.isCancelled)
        #expect(scrollView.contentOffset.y == 300)
        #expect(handle.peekPosition(conversationID: UUID()) == nil)
        scrollView.bounds.size.height = 0
        #expect(handle.peekPosition(conversationID: conversationID) == nil)
        #expect(handle.generation == generation && !pending.isCancelled)
        scrollView.bounds.size.height = 320

        // Only the normal admission read advances generation and rejects work
        // captured for the old viewport. Diagnostics cannot do that first.
        #expect(handle.position(conversationID: conversationID, expectedGeneration: generation) == nil)
        #expect(handle.generation != generation && pending.isCancelled)
        await pending.value
        #expect(calls == 0)
        #expect(handle.position(conversationID: conversationID) == observed)
        let current = try #require(handle.whenReady(conversationID: conversationID) { calls += 1 })
        await current.value
        #expect(calls == 1)
    }

    @Test func incomingBindingBeforeActivationDoesNotNeedAnotherBridgeCallback() throws {
        let previousConversation = UUID(), currentConversation = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let previous = UIScrollView(frame: window.bounds)
        let incoming = UIScrollView(frame: window.bounds)
        previous.contentSize = CGSize(width: 800, height: 2_000)
        incoming.contentSize = CGSize(width: 800, height: 3_000)
        window.addSubview(previous)
        window.addSubview(incoming)
        handle.activate(conversationID: previousConversation)
        handle.bind(previous, conversationID: previousConversation)
        handle.bind(incoming, conversationID: currentConversation)
        #expect(handle.layout(conversationID: previousConversation)?.contentHeight == 2_000)
        handle.activate(conversationID: currentConversation)
        handle.bind(nil, conversationID: previousConversation)
        let current = try #require(handle.layout(conversationID: currentConversation))
        #expect(current.contentHeight == 3_000)
    }

    @Test func postLayoutReadReconcilesLazyContentAtTheSameOffsetWithoutAnotherIdle() async throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let controller = ChatAutoFollowController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 702))
        let scrollView = UIScrollView(frame: window.bounds)
        window.addSubview(scrollView)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 420, height: 5_840)
        scrollView.contentOffset.y = 4_335
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        let generation = handle.generation
        let ready = try #require(handle.whenReady(conversationID: conversationID) {})
        await ready.value

        controller.updatePosition(try #require(handle.position(conversationID: conversationID)))
        controller.pauseFollowing(reason: "manualReading")
        #expect(controller.showsScrollToBottomButton)
        var deliveries = 0
        var deliveredPosition: ChatAutoFollowPosition?
        let pending = try #require(handle.readPositionAfterLayout(conversationID: conversationID) { position in
            deliveries += 1
            deliveredPosition = position
            controller.updateNearBottom(position.isNearBottom == true)
        })
        let coalesced = try #require(handle.readPositionAfterLayout(conversationID: conversationID) { position in
            deliveries += 1
            deliveredPosition = position
            controller.updateNearBottom(position.isNearBottom == true)
        })
        #expect(deliveries == 0, "Never publish inside the native layout callback")
        scrollView.contentSize.height = 5_037
        // The recorded SwiftUI viewport still reports 563 rather than the
        // native 702. It admits layout growth but cannot determine bottom truth.
        let swiftUILayout = ChatAutoFollowLayout(contentHeight: 5_037, viewportHeight: 563,
                                                 topInset: 139, bottomInset: 0)
        #expect(swiftUILayout.isNearBottom(contentOffsetY: 4_335) == false)
        controller.updateLayout(swiftUILayout)
        await pending.value
        await coalesced.value
        #expect(deliveries == 1 && !controller.showsScrollToBottomButton)
        #expect(deliveredPosition?.layout.viewportHeight == 702)
        #expect(controller.latestLayout == swiftUILayout, "Native position must preserve fresh growth admission")
        #expect(controller.mode == .pausedByUser, "Observation must not resume a paused reader")
        #expect(scrollView.contentOffset.y == 4_335 && handle.generation == generation)
        #expect(handle.whenReady(conversationID: conversationID) {} == nil,
                "Position reconciliation must not replay attachment readiness")

        scrollView.contentSize.height = 5_840
        let grew = try #require(handle.readPositionAfterLayout(conversationID: conversationID) { position in
            controller.updateNearBottom(position.isNearBottom == true)
        })
        await grew.value
        #expect(controller.showsScrollToBottomButton && controller.mode == .pausedByUser)

        // Only an actual manual idle transition ends the interaction after the
        // same native read. A later unrelated content resize cannot do this.
        controller.userInteractionBegan()
        let manualEnd = try #require(handle.readPositionAfterLayout(conversationID: conversationID) { position in
            controller.updateNearBottom(position.isNearBottom == true)
            controller.userInteractionEnded()
        })
        scrollView.contentSize.height = 5_037
        await manualEnd.value
        #expect(controller.mode == .following && !controller.state.isUserInteracting)
        #expect(!controller.showsScrollToBottomButton && scrollView.contentOffset.y == 4_335)
    }

    @Test func olderFittingNativePositionCannotCancelAlreadyAdmittedGrowth() async throws {
        let conversationID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 702))
        let scrollView = UIScrollView(frame: window.bounds)
        window.addSubview(scrollView)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 420, height: 500)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        let generation = handle.generation
        let (gate, release) = AsyncStream<Void>.makeStream()
        let controller = ChatAutoFollowController(waitBeforeScroll: {
            var iterator = gate.makeAsyncIterator()
            _ = await iterator.next()
        })
        let growth = ChatAutoFollowLayout(contentHeight: 1_200, viewportHeight: 563,
                                         topInset: 139, bottomInset: 0)
        controller.updateLayout(growth)
        var calls = 0
        let pending = try #require(controller.scheduleScroll(animated: false) { _ in
            guard handle.layout(conversationID: conversationID,
                                expectedGeneration: generation)?.hasScrollableContent == true else { return }
            calls += 1
        })
        let observed = try #require(handle.readPositionAfterLayout(conversationID: conversationID) { position in
            #expect(!position.layout.hasScrollableContent)
            controller.updateNearBottom(position.isNearBottom == true)
        })
        await observed.value
        #expect(controller.latestLayout == growth && calls == 0)
        #expect(!controller.showsScrollToBottomButton)
        // UIKit commits the content before the already scheduled request is
        // admitted again against the real current viewport at execution time.
        scrollView.contentSize.height = 1_200
        release.yield(())
        release.finish()
        await pending.value
        #expect(calls == 1 && handle.generation == generation)
    }

    @Test func postLayoutReadRejectsStaleViewportAndConversation() async throws {
        let conversationID = UUID(), replacementID = UUID()
        let handle = ChatScrollViewHandle()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scrollView = UIScrollView(frame: window.bounds)
        window.addSubview(scrollView)
        scrollView.contentSize = CGSize(width: 800, height: 2_000)
        handle.activate(conversationID: conversationID)
        handle.bind(scrollView, conversationID: conversationID)
        var staleCalls = 0
        let resized = try #require(handle.readPositionAfterLayout(conversationID: conversationID) { _ in
            staleCalls += 1
        })
        scrollView.bounds.size.height = 300
        await resized.value
        #expect(staleCalls == 0)

        let replaced = try #require(handle.readPositionAfterLayout(conversationID: conversationID) { _ in
            staleCalls += 1
        })
        handle.deactivate()
        handle.activate(conversationID: replacementID)
        handle.bind(scrollView, conversationID: replacementID)
        var currentCalls = 0
        let current = try #require(handle.readPositionAfterLayout(conversationID: replacementID) { position in
            currentCalls += 1
            #expect(position.layout.viewportHeight == 300)
        })
        #expect(handle.readPositionAfterLayout(conversationID: conversationID) { _ in
            staleCalls += 1
        } == nil)
        await replaced.value
        await current.value
        #expect(staleCalls == 0 && currentCalls == 1)
    }
}
