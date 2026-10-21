//
//  AutomaticWebSearchCoordinator.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

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
            return now.timeIntervalSince(timestamp) < ttl
        }
    }

    // MARK: - State

    private let providers: [WebSearchProvider]
    private var healthTable: [String: ProviderHealth] = [:]
    private var queryCache: [String: CacheEntry] = [:]
    private let clock: @Sendable () -> Date

    private let cacheTTL: TimeInterval = 300 // 5 minutes
    private let maxCacheEntries: Int = 50
    private let defaultCooldownDuration: TimeInterval = 60 // 60 seconds
    private let overallSearchDeadline: TimeInterval
    private let perProviderTimeout: TimeInterval

    // MARK: - Initialization

    init(
        providers: [WebSearchProvider]? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        overallSearchDeadline: TimeInterval = 10.0,
        perProviderTimeout: TimeInterval = 4.0
    ) {
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

        let now = clock()
        let cacheKey = canonicalCacheKey(query: trimmedQuery, count: count)

        // 1. Check local cache (unless bypassed)
        if !bypassCache, let entry = queryCache[cacheKey], entry.isValid(ttl: cacheTTL, now: now) {
            let parsed = WebSearchResult.toParsedSearchResult(entry.results)
            return (parsed, "Automatic (\(entry.backend) - cached)")
        }

        // 2. Execute bounded search across providers with structured hard deadline race
        let (rawResults, backendName) = try await executeWithStructuredDeadline(
            query: trimmedQuery,
            count: count,
            deadlineSeconds: overallSearchDeadline
        )

        // 3. Deduplicate and filter results
        let deduplicated = deduplicateResults(rawResults)
        guard !deduplicated.isEmpty else {
            throw AutomaticSearchError.emptyResults
        }

        // 4. Update local cache
        updateCache(key: cacheKey, results: deduplicated, backend: backendName, timestamp: now)

        let parsed = WebSearchResult.toParsedSearchResult(deduplicated)
        return (parsed, "Automatic (\(backendName))")
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

    private func updateCache(key: String, results: [WebSearchResult], backend: String, timestamp: Date) {
        if queryCache.count >= maxCacheEntries {
            queryCache = queryCache.filter { timestamp.timeIntervalSince($0.value.timestamp) < cacheTTL }
            if queryCache.count >= maxCacheEntries, let oldestKey = queryCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                queryCache.removeValue(forKey: oldestKey)
            }
        }
        queryCache[key] = CacheEntry(results: results, backend: backend, timestamp: timestamp)
    }
}
