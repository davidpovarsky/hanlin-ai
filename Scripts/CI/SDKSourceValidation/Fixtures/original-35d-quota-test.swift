import Foundation
import Testing
@testable import HanlinChatUI

#if canImport(CryptoKit)
@Suite("Original code-fence retained payload ownership")
struct ChatCodeFencePayloadRetentionTests: Sendable {
    @Test func countsUTF8OutputBytesOnceAcrossInlineAndExpandedCopies() throws {
        let budget = ChatCodeFencePayloadRetention(maximumBytes: 1_024, maximumPayloads: 4)
        var payload: ChatCodeFencePayload? = makePayload(html: "שלום", css: "é", display: "👩🏽‍💻")
        let expected = "שלום".utf8.count + "é".utf8.count + "👩🏽‍💻".utf8.count
        #expect(payload?.retain(in: budget) == true)
        var copies = [try #require(payload), try #require(payload)]
        payload = nil
        let retainedCopy = copies[0].retain(in: budget)
        #expect(retainedCopy)
        withExtendedLifetime(copies) {
            #expect(budget.snapshot == .init(bytes: expected, payloads: 1))
        }
        copies.removeFirst()
        withExtendedLifetime(copies) {
            #expect(budget.snapshot == .init(bytes: expected, payloads: 1))
        }
        copies.removeAll()
        #expect(budget.snapshot == .init(bytes: 0, payloads: 0))
    }

    @Test func cacheEvictionDoesNotFreeInlineOwnershipAndRemountDoesNotDoubleCharge() throws {
        let budget = ChatCodeFencePayloadRetention(maximumBytes: 1_024, maximumPayloads: 4)
        let cache = NSCache<NSString, Box>()
        var payload: ChatCodeFencePayload? = makePayload(html: "native-result")
        #expect(payload?.retain(in: budget) == true)
        cache.setObject(Box(try #require(payload)), forKey: "original")
        var inline: ChatCodeFencePayload? = cache.object(forKey: "original")?.payload
        payload = nil
        let retained = budget.snapshot
        cache.removeAllObjects()
        withExtendedLifetime(inline) { #expect(budget.snapshot == retained) }
        var expanded: ChatCodeFencePayload? = inline
        inline = nil
        #expect(expanded?.retain(in: budget) == true)
        withExtendedLifetime(expanded) { #expect(budget.snapshot == retained) }
        expanded = nil
        #expect(budget.snapshot == .init(bytes: 0, payloads: 0))
    }

    @Test func byteAndCountExhaustionPreserveExistingPayloadAndPermitLaterReuse() throws {
        let budget = ChatCodeFencePayloadRetention(maximumBytes: 20, maximumPayloads: 2)
        var held = [makePayload(html: String(repeating: "a", count: 10)),
                    makePayload(html: String(repeating: "b", count: 10))]
        let firstHeldRetained = held[0].retain(in: budget)
        #expect(firstHeldRetained)
        let secondHeldRetained = held[1].retain(in: budget)
        #expect(secondHeldRetained)
        var next: ChatCodeFencePayload? = makePayload(html: "c")
        #expect(next?.retain(in: budget) == false)
        #expect(next?.html == "c") // Failure does not truncate or rewrite original source/output.
        withExtendedLifetime(held) { #expect(budget.snapshot == .init(bytes: 20, payloads: 2)) }
        held.removeLast()
        #expect(next?.retain(in: budget) == true)
        withExtendedLifetime((held, next)) { #expect(budget.snapshot == .init(bytes: 11, payloads: 2)) }
        held.removeAll(); next = nil
        #expect(budget.snapshot == .init(bytes: 0, payloads: 0))

        let countBudget = ChatCodeFencePayloadRetention(maximumBytes: 1_024, maximumPayloads: 1)
        var first: ChatCodeFencePayload? = makePayload(html: "x")
        var second = makePayload(html: "y")
        #expect(first?.retain(in: countBudget) == true)
        let secondRetainedWhileFull = second.retain(in: countBudget)
        #expect(!secondRetainedWhileFull)
        first = nil
        let secondRetainedAfterRelease = second.retain(in: countBudget)
        #expect(secondRetainedAfterRelease)
    }

    @Test(.timeLimit(.minutes(1))) func cancelledUnpublishedResultKeepsLeaseUntilActualWorkDrains() async throws {
        let budget = ChatCodeFencePayloadRetention(maximumBytes: 1_024, maximumPayloads: 1)
        let entered = Latch(), release = Latch()
        let task = Task { () async throws -> ChatCodeFencePayload in
            var payload = makePayload(html: "owned-before-publication")
            guard payload.retain(in: budget) else { throw CancellationError() }
            await entered.open()
            await release.wait()
            try Task.checkCancellation()
            return payload
        }
        await entered.wait()
        task.cancel()
        #expect(budget.snapshot.payloads == 1)
        var other = makePayload(html: "next")
        let otherRetainedWhileDraining = other.retain(in: budget)
        #expect(!otherRetainedWhileDraining)
        await release.open()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(budget.snapshot == .init(bytes: 0, payloads: 0))
        let otherRetainedAfterDrain = other.retain(in: budget)
        #expect(otherRetainedAfterDrain)
    }

    @Test func distinctBudgetsCannotAdoptAnAlreadyOwnedPayloadAndInvalidCostsDoNotOverflow() {
        let original = ChatCodeFencePayloadRetention(maximumBytes: 16, maximumPayloads: 2)
        let other = ChatCodeFencePayloadRetention(maximumBytes: 16, maximumPayloads: 2)
        var payload = makePayload(html: "original")
        let retainedByOriginal = payload.retain(in: original)
        #expect(retainedByOriginal)
        let retainedByOther = payload.retain(in: other)
        #expect(!retainedByOther)
        withExtendedLifetime(payload) {
            #expect(original.snapshot == .init(bytes: 8, payloads: 1))
            #expect(other.snapshot == .init(bytes: 0, payloads: 0))
        }
        #expect(other.acquire(bytes: 0) == nil)
        #expect(other.acquire(bytes: -1) == nil)
        #expect(other.acquire(bytes: Int.max) == nil)
        #expect(other.snapshot == .init(bytes: 0, payloads: 0))
    }

    @Test(.timeLimit(.minutes(1))) func simultaneousOwnersCannotExceedOneSharedQuota() async {
        let budget = ChatCodeFencePayloadRetention(maximumBytes: 70, maximumPayloads: 7)
        var leases: [ChatCodeFencePayloadRetention.Lease] = []
        await withTaskGroup(of: ChatCodeFencePayloadRetention.Lease?.self) { group in
            for _ in 0..<64 { group.addTask { budget.acquire(bytes: 10) } }
            for await lease in group { if let lease { leases.append(lease) } }
        }
        withExtendedLifetime(leases) {
            #expect(leases.count == 7)
            #expect(budget.snapshot == .init(bytes: 70, payloads: 7))
        }
        leases.removeAll()
        #expect(budget.snapshot == .init(bytes: 0, payloads: 0))
    }

    private func makePayload(html: String, css: String = "", display: String? = nil) -> ChatCodeFencePayload {
        .init(html: html, css: css, width: 100, height: 100, fontSize: 16, dark: false, displayHTML: display)
    }

    private final class Box: NSObject {
        let payload: ChatCodeFencePayload
        init(_ payload: ChatCodeFencePayload) { self.payload = payload }
    }

    private actor Latch {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func open() {
            opened = true
            let original = waiters; waiters.removeAll()
            for waiter in original { waiter.resume() }
        }
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}
#endif
