//
//  AutomaticWebSearchCoordinator.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation
import LRUCache

/// Coordinates automatic three-tier web search fallback across keyless providers:
/// 1. You.com Keyless -> 2. Tavily Keyless -> 3. Keenable Public.
/// Enforces strict circuit breaking, cooldowns, structured hard deadlines,
/// topical relevance validation, canonical query caching, and diagnostic probes.
actor AutomaticWebSearchCoordinator {

    static let shared = AutomaticWebSearchCoordinator()

    // MARK: - Types

    struct DiagnosticResult: Sendable {
        let success: Bool
        let providerUsed: String
        let duration: TimeInterval
        let topSourceTitle: String
        let topSourceURL: String
        let errorMessage: String?

        init(
            success: Bool,
            providerUsed: String,
            duration: TimeInterval,
            topSourceTitle: String,
            topSourceURL: String,
            errorMessage: String?
        ) {
            self.success = success
            self.providerUsed = providerUsed
            self.duration = duration
            self.topSourceTitle = topSourceTitle
            self.topSourceURL = topSourceURL
            self.errorMessage = errorMessage
        }
    }

    struct ProviderHealth: Sendable {
        var failureCount: Int = 0
        var cooldownUntil: Date? = nil
        var lastLatency: TimeInterval? = nil
        var lastError: String? = nil

        func isAvailable(at date: Date = Date()) -> Bool {
            if let cooldown = cooldownUntil {
                return date >= cooldown
            }
            return true
        }
    }

    private struct CacheEntry: Sendable {
        let results: [WebSearchResult]
        let backend: String
        let timestamp: Date

        func isValid(ttl: TimeInterval, now: Date) -> Bool {
            let age = now.timeIntervalSince(timestamp)
            return age >= 0 && age < ttl
        }
    }

    /// Counters contain no queries, result content, credentials, or user identifiers.
    struct CacheStatistics: Sendable, Equatable {
        var hits = 0
        var misses = 0
        var coalescedRequests = 0
        var bypasses = 0
        var expirations = 0
        var invalidations = 0
        var capacityEvictions = 0
        var entries = 0
        var costBytes = 0
        var inFlightRequests = 0
        var waitingCallers = 0
    }

    private struct FlightKey: Hashable, Sendable {
        let queryKey: String
        let generation: UUID
    }

    private struct SearchOutput: Sendable {
        let results: [WebSearchResult]
        let backend: String
    }

    private struct InFlightSearch {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<SearchOutput, any Error>]
    }

    // MARK: - State

    private let providers: [WebSearchProvider]
    private var healthTable: [String: ProviderHealth] = [:]
    private let queryCache: LRUCache<String, CacheEntry>
    private var inFlight: [FlightKey: InFlightSearch] = [:]
    private var cacheGeneration = UUID()
    private var cacheCounters = CacheStatistics()
    private let clock: @Sendable () -> Date

    private let cacheTTL: TimeInterval
    private let defaultCooldownDuration: TimeInterval = 60 // 60 seconds
    private let overallSearchDeadline: TimeInterval
    private let perProviderTimeout: TimeInterval

    // MARK: - Initialization

    init(
        providers: [WebSearchProvider]? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        overallSearchDeadline: TimeInterval = 10.0,
        perProviderTimeout: TimeInterval = 4.0,
        cacheTTL: TimeInterval = 300,
        maxCacheEntries: Int = 50,
        maxCacheBytes: Int = 4 * 1024 * 1024
    ) {
        self.cacheTTL = cacheTTL.isFinite ? max(0, cacheTTL) : 0
        self.queryCache = LRUCache(
            totalCostLimit: max(0, maxCacheBytes),
            countLimit: max(0, maxCacheEntries)
        )
        self.clock = clock
        self.overallSearchDeadline = overallSearchDeadline
        self.perProviderTimeout = perProviderTimeout
        if let customProviders = providers {
            self.providers = customProviders
        } else {
            self.providers = [
                YouKeylessSearchAdapter(),
                TavilyKeylessSearchAdapter(),
                KeenablePublicSearchAdapter()
            ]
        }
        for provider in self.providers {
            healthTable[provider.providerID] = ProviderHealth()
        }
    }

    // MARK: - Public API

    /// Executes automatic search with fallback, caching, deduplication, relevance checks, and hard bounds.
    /// Returns: Tuple of legacy `ParsedSearchResult` and active backend description string.
    func search(
        query: String,
        count: Int = 5,
        bypassCache: Bool = false
    ) async throws -> (ParsedSearchResult, String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw AutomaticSearchError.invalidQuery
        }

        try Task.checkCancellation()
        let cacheKey = canonicalCacheKey(query: trimmedQuery, count: count)
        let generation = cacheGeneration

        if !bypassCache, let entry = queryCache.value(forKey: cacheKey) {
            if entry.isValid(ttl: cacheTTL, now: clock()) {
                cacheCounters.hits += 1
                return (WebSearchResult.toParsedSearchResult(entry.results), "Automatic (\(entry.backend) - cached)")
            }
            queryCache.removeValue(forKey: cacheKey)
            cacheCounters.expirations += 1
        }

        let output: SearchOutput
        if bypassCache {
            // A diagnostic/refresh must perform its own request, even while an
            // equivalent ordinary search is in flight.
            cacheCounters.bypasses += 1
            output = try await freshSearch(query: trimmedQuery, count: count)
            try Task.checkCancellation()
            if generation == cacheGeneration {
                updateCache(key: cacheKey, output: output)
            }
        } else {
            cacheCounters.misses += 1
            let key = FlightKey(queryKey: cacheKey, generation: generation)
            let waiterID = UUID()
            output = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    joinSearch(key: key, waiterID: waiterID, query: trimmedQuery, count: count, continuation: continuation)
                }
            } onCancel: {
                // Cancellation belongs to this caller. Other callers keep the
                // shared provider request until the final waiter leaves.
                Task { await self.cancelWaiter(key: key, waiterID: waiterID) }
            }
            try Task.checkCancellation()
        }

        return (WebSearchResult.toParsedSearchResult(output.results), "Automatic (\(output.backend))")
    }

    /// Removes reproducible results. Already-running callers can finish, but
    /// their old generation cannot populate this cache or serve new callers.
    func invalidateCache() {
        cacheGeneration = UUID()
        queryCache.removeAll()
        cacheCounters.invalidations += 1
    }

    func cacheStatistics() -> CacheStatistics {
        var statistics = cacheCounters
        statistics.entries = queryCache.count
        statistics.costBytes = queryCache.totalCost
        statistics.inFlightRequests = inFlight.count
        statistics.waitingCallers = inFlight.values.reduce(0) { $0 + $1.waiters.count }
        return statistics
    }

    private func joinSearch(
        key: FlightKey,
        waiterID: UUID,
        query: String,
        count: Int,
        continuation: CheckedContinuation<SearchOutput, any Error>
    ) {
        if var existing = inFlight[key] {
            existing.waiters[waiterID] = continuation
            inFlight[key] = existing
            cacheCounters.coalescedRequests += 1
            return
        }
        let flightID = UUID()
        let worker = Task {
            let result: Result<SearchOutput, any Error>
            do {
                let output = try await self.freshSearch(query: query, count: count)
                try Task.checkCancellation()
                result = .success(output)
            } catch {
                result = .failure(error)
            }
            self.finishSearch(key: key, flightID: flightID, result: result)
        }
        inFlight[key] = InFlightSearch(id: flightID, task: worker, waiters: [waiterID: continuation])
    }

    private func cancelWaiter(key: FlightKey, waiterID: UUID) {
        guard var flight = inFlight[key],
              let waiter = flight.waiters.removeValue(forKey: waiterID) else { return }
        if flight.waiters.isEmpty {
            inFlight.removeValue(forKey: key)
            flight.task.cancel()
        } else {
            inFlight[key] = flight
        }
        waiter.resume(throwing: CancellationError())
    }

    private func finishSearch(key: FlightKey, flightID: UUID, result: Result<SearchOutput, any Error>) {
        // A cancelled worker must not remove a replacement flight with the
        // same query or write a late result after invalidation.
        guard let flight = inFlight[key], flight.id == flightID else { return }
        inFlight.removeValue(forKey: key)
        if case .success(let output) = result, key.generation == cacheGeneration {
            updateCache(key: key.queryKey, output: output)
        }
        for continuation in flight.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func freshSearch(query: String, count: Int) async throws -> SearchOutput {
        let (rawResults, backend) = try await executeWithStructuredDeadline(
            query: query, count: count, deadlineSeconds: overallSearchDeadline
        )
        try Task.checkCancellation()
        let results = deduplicateResults(rawResults)
        guard !results.isEmpty else { throw AutomaticSearchError.emptyResults }
        return SearchOutput(results: results, backend: backend)
    }

    /// Runs a real diagnostic probe against the coordinator with cache bypass
    /// to verify end-to-end live connectivity and capture honest timing and real top source.
    func runDiagnosticTest() async -> DiagnosticResult {
        let startTime = clock()
        let testQuery = "Search today's news"

        do {
            let (parsed, engineName) = try await search(query: testQuery, count: 3, bypassCache: true)
            let duration = clock().timeIntervalSince(startTime)
            let topTitle = parsed.titles.first ?? "No title"
            let topLink = parsed.links.first ?? "No URL"

            return DiagnosticResult(
                success: true,
                providerUsed: engineName,
                duration: duration,
                topSourceTitle: topTitle,
                topSourceURL: topLink,
                errorMessage: nil
            )
        } catch {
            let duration = clock().timeIntervalSince(startTime)
            return DiagnosticResult(
                success: false,
                providerUsed: "None",
                duration: duration,
                topSourceTitle: "",
                topSourceURL: "",
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Inspection API for testing and status
    func getProviderHealth(providerID: String) -> ProviderHealth? {
        return healthTable[providerID]
    }

    // MARK: - Structured Concurrency & Hard Deadline

    private func executeWithStructuredDeadline(
        query: String,
        count: Int,
        deadlineSeconds: TimeInterval
    ) async throws -> ([WebSearchResult], String) {
        try await withThrowingTaskGroup(of: ([WebSearchResult], String).self) { group in
            group.addTask {
                try await self.executeFallbackLoop(query: query, count: count)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadlineSeconds * 1_000_000_000))
                throw AutomaticSearchError.timeout
            }

            do {
                guard let firstCompleted = try await group.next() else {
                    throw AutomaticSearchError.timeout
                }
                group.cancelAll()
                return firstCompleted
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    // MARK: - Fallback Loop & Circuit Breaking

    private func executeFallbackLoop(query: String, count: Int) async throws -> ([WebSearchResult], String) {
        var failureReasons: [String] = []
        let now = clock()

        // 1. Filter out cooled-down providers strictly
        let availableProviders = providers.filter {
            let health = self.healthTable[$0.providerID] ?? ProviderHealth()
            return health.isAvailable(at: now)
        }

        // If all providers are on cooldown, do NOT retry them. Enforce circuit breaker!
        if availableProviders.isEmpty {
            let earliestCooldown = providers.compactMap { self.healthTable[$0.providerID]?.cooldownUntil }.min()
            let waitSeconds = earliestCooldown.map { max(1.0, $0.timeIntervalSince(now)) } ?? defaultCooldownDuration
            throw AutomaticSearchError.allProvidersOnCooldown(retryAfter: waitSeconds)
        }

        for provider in availableProviders {
            let providerStartTime = clock()
            do {
                try Task.checkCancellation()

                let results = try await provider.search(query: query, count: count, timeout: self.perProviderTimeout)
                let latency = clock().timeIntervalSince(providerStartTime)

                // 2. Validate structural validity
                let structurallyValid = results.filter { $0.isValid }
                guard !structurallyValid.isEmpty else {
                    let reason = "\(provider.displayName): empty or malformed result set"
                    failureReasons.append(reason)
                    recordFailure(providerID: provider.providerID, error: reason, retryAfter: nil, isRateLimit: false)
                    continue
                }

                // 3. Validate topical relevance / intent mismatch
                let relevantResults = WebSearchRelevanceEvaluator.evaluate(results: structurallyValid, for: query)
                guard !relevantResults.isEmpty else {
                    let reason = "\(provider.displayName): results rejected due to topic/intent mismatch"
                    failureReasons.append(reason)
                    // Irrelevant results don't mean rate limit, but should trigger next fallback provider
                    recordFailure(providerID: provider.providerID, error: reason, retryAfter: nil, isRateLimit: false)
                    continue
                }

                // Success: mark provider healthy and return
                recordSuccess(providerID: provider.providerID, latency: latency)
                return (relevantResults, provider.displayName)

            } catch is CancellationError {
                throw AutomaticSearchError.cancelled
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw AutomaticSearchError.cancelled
            } catch AutomaticSearchError.cancelled {
                throw AutomaticSearchError.cancelled
            } catch let error as AutomaticSearchError {
                if Task.isCancelled {
                    throw AutomaticSearchError.cancelled
                }
                let reason = "\(provider.displayName): \(error.localizedDescription)"
                failureReasons.append(reason)

                switch error {
                case .rateLimited(let retryAfter):
                    recordFailure(providerID: provider.providerID, error: reason, retryAfter: retryAfter, isRateLimit: true)
                case .providerUnavailable:
                    // 401/403 or policy block: extended cooldown (1 hour)
                    recordFailure(providerID: provider.providerID, error: reason, retryAfter: 3600.0, isRateLimit: false)
                default:
                    recordFailure(providerID: provider.providerID, error: reason, retryAfter: nil, isRateLimit: false)
                }
            } catch {
                if Task.isCancelled {
                    throw AutomaticSearchError.cancelled
                }
                let reason = "\(provider.displayName): \(error.localizedDescription)"
                failureReasons.append(reason)
                recordFailure(providerID: provider.providerID, error: reason, retryAfter: nil, isRateLimit: false)
            }
        }

        throw AutomaticSearchError.allProvidersFailed(reasons: failureReasons)
    }

    private func recordSuccess(providerID: String, latency: TimeInterval) {
        var health = healthTable[providerID] ?? ProviderHealth()
        health.failureCount = 0
        health.cooldownUntil = nil
        health.lastLatency = latency
        health.lastError = nil
        healthTable[providerID] = health
    }

    private func recordFailure(providerID: String, error: String, retryAfter: TimeInterval?, isRateLimit: Bool) {
        var health = healthTable[providerID] ?? ProviderHealth()
        health.failureCount += 1
        health.lastError = error

        let now = clock()
        let cooldownDuration: TimeInterval
        if let explicitRetry = retryAfter, explicitRetry > 0 {
            cooldownDuration = min(max(explicitRetry, 5.0), 3600.0) // Sane bound: 5s to 1h
        } else {
            let multiplier = min(Double(health.failureCount), 5.0)
            cooldownDuration = isRateLimit ? defaultCooldownDuration * 2 : defaultCooldownDuration * multiplier
        }
        health.cooldownUntil = now.addingTimeInterval(cooldownDuration)
        healthTable[providerID] = health
    }

    // MARK: - Deduplication & Cache

    private func deduplicateResults(_ results: [WebSearchResult]) -> [WebSearchResult] {
        var seenURLs = Set<String>()
        var unique: [WebSearchResult] = []

        for item in results where item.isValid {
            let canonical = item.canonicalURLString
            if !seenURLs.contains(canonical) {
                seenURLs.insert(canonical)
                unique.append(item)
            }
        }
        return unique
    }

    private func canonicalCacheKey(query: String, count: Int) -> String {
        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let canonical = tokens.joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return "\(canonical)_\(count)"
    }

    private func updateCache(key: String, output: SearchOutput) {
        // Freshness starts when the successful search completes, not when a
        // slow provider request starts. Failed/cancelled searches never arrive.
        let now = clock()
        // Walk in LRU order so inspecting expiry preserves the existing recency order.
        for existingKey in queryCache.orderedKeys {
            if let entry = queryCache.value(forKey: existingKey),
               !entry.isValid(ttl: cacheTTL, now: now) {
                queryCache.removeValue(forKey: existingKey)
                cacheCounters.expirations += 1
            }
        }
        guard cacheTTL > 0 else { return }
        let cost = output.results.reduce(key.utf8.count + output.backend.utf8.count) { total, result in
            total + result.title.utf8.count + result.url.utf8.count + result.snippet.utf8.count
                + result.icon.utf8.count + result.sourceBackend.utf8.count + (result.publishedDate?.utf8.count ?? 0)
        }
        // Keep existing useful entries when a single result exceeds the budget.
        // The caller still receives the complete fresh result.
        guard cost <= queryCache.totalCostLimit, queryCache.countLimit > 0 else { return }
        let previousCount = queryCache.count
        let replacesExisting = queryCache.hasValue(forKey: key)
        queryCache.setValue(
            CacheEntry(results: output.results, backend: output.backend, timestamp: now),
            forKey: key, cost: cost
        )
        cacheCounters.capacityEvictions += max(0, previousCount + (replacesExisting ? 0 : 1) - queryCache.count)
    }
}
