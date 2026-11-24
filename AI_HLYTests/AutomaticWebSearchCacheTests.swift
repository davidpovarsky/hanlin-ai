import Foundation
import Synchronization
import Testing
#if canImport(HanlinCacheProof)
@testable import HanlinCacheProof
#else
@testable import AI_Hanlin
#endif

@Suite("Automatic search cache lifecycle", .timeLimit(.minutes(1)))
struct AutomaticWebSearchCacheTests {
    private final class TestClock: Sendable {
        private let storage = Mutex(Date(timeIntervalSince1970: 1_000_000))
        var now: Date { storage.withLock { $0 } }
        func advance(_ seconds: TimeInterval) {
            storage.withLock { $0 = $0.addingTimeInterval(seconds) }
        }
    }

    private actor Provider: WebSearchProvider {
        let providerID = "cache-test"
        let displayName = "Cache Test"
        private(set) var calls = 0
        private var pending: [Int: CheckedContinuation<[WebSearchResult], any Error>] = [:]
        private let controlled: Bool

        init(controlled: Bool = false) { self.controlled = controlled }

        func search(query: String, count: Int, timeout: TimeInterval) async throws -> [WebSearchResult] {
            calls += 1
            let index = calls
            if !controlled { return Self.results(query: query, index: index) }
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    pending[index] = continuation
                }
            } onCancel: {
                Task { await self.cancel(index) }
            }
        }

        func finish(_ index: Int, query: String = "cache alpha") {
            pending.removeValue(forKey: index)?.resume(returning: Self.results(query: query, index: index))
        }

        func fail(_ index: Int) {
            pending.removeValue(forKey: index)?.resume(throwing: AutomaticSearchError.emptyResults)
        }

        private func cancel(_ index: Int) {
            pending.removeValue(forKey: index)?.resume(throwing: CancellationError())
        }

        private static func results(query: String, index: Int) -> [WebSearchResult] {
            [.init(title: "\(query) result \(index)", url: "https://example.com/\(index)",
                   snippet: "Verified source for \(query)", sourceBackend: "cache-test")]
        }
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await condition()), ContinuousClock.now < deadline {
            try Task.checkCancellation()
            await Task.yield()
        }
        try #require(await condition(), "A controlled asynchronous operation did not reach its expected state")
    }

    @Test func cacheHitExpiryAndClockRollback() async throws {
        let clock = TestClock(), provider = Provider()
        let cache = AutomaticWebSearchCoordinator(providers: [provider], clock: { clock.now }, cacheTTL: 10)
        _ = try await cache.search(query: "cache alpha")
        clock.advance(9)
        let (_, hit) = try await cache.search(query: "CACHE   ALPHA")
        #expect(hit.contains("cached"))
        #expect(await provider.calls == 1)
        clock.advance(1)
        _ = try await cache.search(query: "cache alpha")
        #expect(await provider.calls == 2)
        clock.advance(-1)
        _ = try await cache.search(query: "cache alpha")
        #expect(await provider.calls == 3)
        let statistics = await cache.cacheStatistics()
        #expect(statistics.hits == 1 && statistics.expirations == 2)
    }

    @Test func freshnessStartsWhenProviderCompletes() async throws {
        let clock = TestClock(), provider = Provider(controlled: true)
        let cache = AutomaticWebSearchCoordinator(providers: [provider], clock: { clock.now }, cacheTTL: 10)
        let initial = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 1 }
        clock.advance(30)
        await provider.finish(1)
        _ = try await initial.value
        clock.advance(9)
        let (_, backend) = try await cache.search(query: "cache alpha")
        #expect(backend.contains("cached"))
        #expect(await provider.calls == 1)
    }

    @Test func originalLRULibraryEvictsLeastRecentlyUsedEntry() async throws {
        let provider = Provider()
        let cache = AutomaticWebSearchCoordinator(providers: [provider], maxCacheEntries: 2)
        _ = try await cache.search(query: "cache alpha")
        _ = try await cache.search(query: "cache beta")
        _ = try await cache.search(query: "cache alpha")
        _ = try await cache.search(query: "cache gamma")
        let (_, retained) = try await cache.search(query: "cache alpha")
        #expect(retained.contains("cached"))
        let (_, evicted) = try await cache.search(query: "cache beta")
        #expect(!evicted.contains("cached"))
        #expect(await provider.calls == 4)
        let statistics = await cache.cacheStatistics()
        #expect(statistics.entries == 2 && statistics.capacityEvictions == 2)
    }

    @Test func oversizedResultsReturnWithoutEvictingUsefulEntries() async throws {
        let provider = Provider()
        let cache = AutomaticWebSearchCoordinator(providers: [provider], maxCacheBytes: 300)
        _ = try await cache.search(query: "cache alpha")
        let largeQuery = "cache " + String(repeating: "large ", count: 100)
        let (result, _) = try await cache.search(query: largeQuery)
        #expect(!result.titles.isEmpty)
        let (_, retained) = try await cache.search(query: "cache alpha")
        #expect(retained.contains("cached"))
        let statistics = await cache.cacheStatistics()
        #expect(statistics.entries == 1 && statistics.costBytes <= 300)
    }

    @Test func simultaneousEquivalentSearchesShareOneProviderCall() async throws {
        let provider = Provider(controlled: true)
        let cache = AutomaticWebSearchCoordinator(providers: [provider])
        let first = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 1 }
        let second = Task { try await cache.search(query: "CACHE   ALPHA") }
        try await waitUntil { await cache.cacheStatistics().waitingCallers == 2 }
        #expect(await provider.calls == 1)
        await provider.finish(1)
        let firstValue = try await first.value, secondValue = try await second.value
        #expect(firstValue.0.links == secondValue.0.links)
        let statistics = await cache.cacheStatistics()
        #expect(statistics.coalescedRequests == 1 && statistics.inFlightRequests == 0)
    }

    @Test func cancellingOneWaiterPreservesTheOtherWaiter() async throws {
        let provider = Provider(controlled: true)
        let cache = AutomaticWebSearchCoordinator(providers: [provider])
        let first = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 1 }
        let second = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await cache.cacheStatistics().waitingCallers == 2 }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await cache.cacheStatistics().waitingCallers == 1)
        await provider.finish(1)
        let value = try await second.value
        #expect(value.0.links == ["https://example.com/1"])
        #expect(await provider.calls == 1)
    }

    @Test func cancellingAllWaitersCancelsTheFlightAndAllowsFreshRequest() async throws {
        let provider = Provider(controlled: true)
        let cache = AutomaticWebSearchCoordinator(providers: [provider])
        let first = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 1 }
        let second = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await cache.cacheStatistics().waitingCallers == 2 }
        first.cancel()
        second.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await cache.cacheStatistics().entries == 0)
        let replacement = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 2 }
        await provider.finish(2)
        let result = try await replacement.value
        #expect(result.0.links == ["https://example.com/2"])
    }

    @Test func bypassDoesNotJoinAnOrdinaryFlight() async throws {
        let provider = Provider(controlled: true)
        let cache = AutomaticWebSearchCoordinator(providers: [provider])
        let first = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 1 }
        let bypass = Task { try await cache.search(query: "cache alpha", bypassCache: true) }
        try await waitUntil { await provider.calls == 2 }
        await provider.finish(1)
        await provider.finish(2)
        _ = try await first.value
        _ = try await bypass.value
        #expect(await cache.cacheStatistics().bypasses == 1)
    }

    @Test func invalidationSeparatesGenerationsAndPreventsLateRepopulation() async throws {
        let provider = Provider(controlled: true)
        let cache = AutomaticWebSearchCoordinator(providers: [provider])
        let first = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 1 }
        await cache.invalidateCache()
        let second = Task { try await cache.search(query: "cache alpha") }
        try await waitUntil { await provider.calls == 2 }
        await provider.finish(1)
        _ = try await first.value
        #expect(await cache.cacheStatistics().entries == 0)
        await provider.finish(2)
        _ = try await second.value
        let (result, _) = try await cache.search(query: "cache alpha")
        #expect(result.links == ["https://example.com/2"])
    }

    @Test func failuresAreNotCachedAndDifferentCountsAreSeparateRequests() async throws {
        let clock = TestClock(), provider = Provider(controlled: true)
        let cache = AutomaticWebSearchCoordinator(providers: [provider], clock: { clock.now })
        let first = Task { try await cache.search(query: "cache alpha", count: 3) }
        try await waitUntil { await provider.calls == 1 }
        await provider.fail(1)
        await #expect(throws: AutomaticSearchError.self) { try await first.value }
        #expect(await cache.cacheStatistics().entries == 0)
        clock.advance(61)
        let three = Task { try await cache.search(query: "cache alpha", count: 3) }
        try await waitUntil { await provider.calls == 2 }
        let five = Task { try await cache.search(query: "cache alpha", count: 5) }
        try await waitUntil { await provider.calls == 3 }
        await provider.finish(2)
        await provider.finish(3)
        _ = try await three.value
        _ = try await five.value
        #expect(await cache.cacheStatistics().entries == 2)
    }
}
