import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Original-chat scroll coalescing", .timeLimit(.minutes(1)))
struct ChatAutoFollowTests {
    @Test func sustainedRequestsKeepOneTimerAndMergeAnimationWithoutStarvation() async {
        let gate = Gate()
        let controller = ChatAutoFollowController(waitBeforeScroll: { await gate.wait() })
        controller.updateLayout(Self.longLayout)
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        controller.scheduleScroll(animated: false) { continuation.yield($0) }
        await gate.waitForStart(1)
        for index in 0..<100 {
            controller.scheduleScroll(animated: index == 50) { continuation.yield($0) }
            await Task.yield()
        }
        #expect(gate.starts == 1)
        gate.release()
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == true)
        controller.scheduleScroll(animated: false) { continuation.yield($0) }
        await gate.waitForStart(2)
        gate.release()
        #expect(await iterator.next() == false)
        continuation.finish()
    }

    @Test func interactionCancelsScheduledScrollAndStaleTimerCannotClearNewOne() async {
        let gate = Gate()
        let controller = ChatAutoFollowController(waitBeforeScroll: { await gate.wait() })
        controller.updateLayout(Self.longLayout)
        var staleCalls = 0
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        controller.scheduleScroll(animated: false) { _ in staleCalls += 1 }
        await gate.waitForStart(1)
        controller.userInteractionBegan()
        controller.updateNearBottom(false)
        controller.userInteractionEnded()
        #expect(controller.mode == .pausedByUser)
        controller.resumeFollowing()
        controller.scheduleScroll(animated: true) { continuation.yield($0) }
        await gate.waitForStart(2)
        gate.release()
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == true)
        #expect(staleCalls == 0)
        continuation.finish()
    }

    @Test func selectionPauseRejectsLayoutWorkUntilAnExplicitResume() async {
        let gate = Gate()
        let controller = ChatAutoFollowController(waitBeforeScroll: { await gate.wait() })
        controller.updateLayout(Self.longLayout)
        controller.pauseFollowing(reason: "textSelection")
        controller.scheduleScroll(animated: false) { _ in Issue.record("Paused layout must not scroll") }
        #expect(gate.starts == 0 && !controller.shouldRequestScrollForVisualUpdate())
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        controller.resumeFollowing()
        controller.scheduleScroll(animated: true, force: true) { continuation.yield($0) }
        await gate.waitForStart(1)
        gate.release()
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == true)
        continuation.finish()
    }

    @Test func aNewRunRejectsThePreviousPendingScroll() async {
        let gate = Gate()
        let controller = ChatAutoFollowController(waitBeforeScroll: { await gate.wait() })
        controller.updateLayout(Self.longLayout)
        var staleCalls = 0
        controller.scheduleScroll(animated: false) { _ in staleCalls += 1 }
        await gate.waitForStart(1)
        controller.beginRun()
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        controller.scheduleScroll(animated: false) { continuation.yield($0) }
        await gate.waitForStart(2)
        gate.release()
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == false)
        #expect(staleCalls == 0 && controller.mode == .following)
        continuation.finish()
    }

    private static let longLayout = ChatAutoFollowLayout(
        contentHeight: 2_000, viewportHeight: 1_318, topInset: 108, bottomInset: 0)

    @Test func measuredScrollRangeIncludesOriginalInsetsWithoutDuplicateComposerClearance() {
        #expect(!ChatAutoFollowLayout(contentHeight: 700, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0).hasScrollableContent)
        #expect(!ChatAutoFollowLayout(contentHeight: 1_210, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0).hasScrollableContent)
        #expect(ChatAutoFollowLayout(contentHeight: 1_230, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0).hasScrollableContent)
        #expect(ChatAutoFollowLayout(contentHeight: 1_200, viewportHeight: 1_318,
            topInset: 108, bottomInset: 24).hasScrollableContent)
        #expect(!ChatAutoFollowLayout(contentHeight: .nan, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0).hasScrollableContent)
        #expect(!ChatAutoFollowLayout(contentHeight: 700, viewportHeight: 0,
            topInset: 108, bottomInset: 0).hasScrollableContent)
    }

    @Test func unmeasuredAndFittingTranscriptsNeverScheduleEvenForcedScrolling() {
        let gate = Gate()
        let controller = ChatAutoFollowController(waitBeforeScroll: { await gate.wait() })
        let unmeasured = controller.scheduleScroll(animated: true, force: true) { _ in
            Issue.record("Unknown viewport geometry must not reposition the original transcript")
        }
        #expect(unmeasured == nil)
        controller.updateLayout(.init(contentHeight: 700, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0))
        let fitting = controller.scheduleScroll(animated: true, force: true) { _ in
            Issue.record("A fully visible short transcript must not be scrolled")
        }
        #expect(fitting == nil && gate.starts == 0)
    }

    @Test func pendingLongTranscriptRequestRechecksGeometryAfterContentShrinks() async throws {
        let gate = Gate()
        let controller = ChatAutoFollowController(waitBeforeScroll: { await gate.wait() })
        controller.updateLayout(Self.longLayout)
        var calls = 0
        let pending = try #require(controller.scheduleScroll(animated: true, force: true) { _ in calls += 1 })
        await gate.waitForStart(1)
        controller.updateLayout(.init(contentHeight: 700, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0))
        gate.release()
        await pending.value
        #expect(calls == 0, "A completion or collapsed disclosure cannot retain an obsolete scroll range")
    }

    @Test func growingTranscriptCanFollowAgainWhileUserPauseRemainsAuthoritative() async throws {
        let gate = Gate()
        let controller = ChatAutoFollowController(waitBeforeScroll: { await gate.wait() })
        controller.updateLayout(.init(contentHeight: 700, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0))
        var calls = 0
        #expect(controller.scheduleScroll(animated: false) { _ in calls += 1 } == nil)
        controller.updateLayout(Self.longLayout)
        let pending = try #require(controller.scheduleScroll(animated: false) { _ in calls += 1 })
        await gate.waitForStart(1)
        gate.release()
        await pending.value
        #expect(calls == 1)
        controller.pauseFollowing(reason: "textSelection")
        controller.updateLayout(.init(contentHeight: 2_400, viewportHeight: 1_318,
            topInset: 108, bottomInset: 0))
        #expect(controller.scheduleScroll(animated: true) { _ in calls += 1 } == nil)
        #expect(calls == 1 && controller.mode == .pausedByUser)
    }

    @MainActor private final class Gate {
        private(set) var starts = 0
        private var releases: [CheckedContinuation<Void, Never>] = []
        private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

        func wait() async {
            starts += 1
            let ready = observers.filter { $0.0 <= starts }
            observers.removeAll { $0.0 <= starts }
            for observer in ready { observer.1.resume() }
            await withCheckedContinuation { releases.append($0) }
        }
        func waitForStart(_ count: Int) async {
            if starts >= count { return }
            await withCheckedContinuation { observers.append((count, $0)) }
        }
        func release() {
            let pending = releases
            releases.removeAll()
            for continuation in pending { continuation.resume() }
        }
    }
}
