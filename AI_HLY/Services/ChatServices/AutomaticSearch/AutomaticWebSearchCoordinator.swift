//
//  AutomaticWebSearchCoordinator.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Coordinates automatic three-tier web search fallback across keyless providers:
/// 1. You.com Keyless -> 2. Tavily Keyless -> 3. Keenable Public.
/// Manages ephemeral circuit breaking, local TTL caching, bounded deadlines, deduplication, and diagnostics.
public actor AutomaticWebSearchCoordinator {
    
    public static let shared = AutomaticWebSearchCoordinator()
    
    // MARK: - Types
    
    public struct DiagnosticResult: Sendable {
        public let success: Bool
        public let providerUsed: String
        public let duration: TimeInterval
        public let topSourceTitle: String
        public let topSourceURL: String
        public let errorMessage: String?
        
        public init(
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
    
    private struct ProviderHealth: Sendable {
        var failureCount: Int = 0
        var cooldownUntil: Date? = nil
        var lastLatency: TimeInterval? = nil
        var lastError: String? = nil
        
        var isAvailable: Bool {
            if let cooldown = cooldownUntil {
                return Date() >= cooldown
            }
            return true
        }
    }
    
    private struct CacheEntry: Sendable {
        let results: [WebSearchResult]
        let backend: String
        let timestamp: Date
        
        func isValid(ttl: TimeInterval) -> Bool {
            return Date().timeIntervalSince(timestamp) < ttl
        }
    }
    
    // MARK: - State
    
    private let providers: [WebSearchProvider]
    private var healthTable: [String: ProviderHealth] = [:]
    private var queryCache: [String: CacheEntry] = [:]
    
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    private let maxCacheEntries: Int = 50
    private let defaultCooldownDuration: TimeInterval = 60 // 60 seconds
    private let overallSearchDeadline: TimeInterval = 10.0
    private let perProviderTimeout: TimeInterval = 4.0
    
    // MARK: - Initialization
    
    public init(providers: [WebSearchProvider]? = nil) {
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
    
    /// Executes automatic search with fallback, caching, deduplication, and bounds.
    /// Returns: Tuple of legacy `ParsedSearchResult` and active backend description string.
    public func search(query: String, count: Int = 5) async throws -> (ParsedSearchResult, String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw AutomaticSearchError.invalidQuery
        }
        
        // Check local cache
        let cacheKey = "\(trimmedQuery.lowercased())_\(count)"
        if let entry = queryCache[cacheKey], entry.isValid(ttl: cacheTTL) {
            let parsed = WebSearchResult.toParsedSearchResult(entry.results)
            return (parsed, "Automatic (\(entry.backend) - cached)")
        }
        
        // Execute bounded search across providers
        let (rawResults, backendName) = try await executeWithFallback(query: trimmedQuery, count: count)
        
        // Deduplicate and filter results
        let deduplicated = deduplicateResults(rawResults)
        guard !deduplicated.isEmpty else {
            throw AutomaticSearchError.emptyResults
        }
        
        // Cache successful response
        updateCache(key: cacheKey, results: deduplicated, backend: backendName)
        
        let parsed = WebSearchResult.toParsedSearchResult(deduplicated)
        return (parsed, "Automatic (\(backendName))")
    }
    
    /// Runs a real diagnostic probe against the coordinator to verify end-to-end connectivity
    /// and captures honest timing, provider identity, and real top source for the settings UI.
    public func runDiagnosticTest() async -> DiagnosticResult {
        let startTime = Date()
        let testQuery = "Search today's news"
        
        do {
            let (parsed, engineName) = try await search(query: testQuery, count: 3)
            let duration = Date().timeIntervalSince(startTime)
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
            let duration = Date().timeIntervalSince(startTime)
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
    
    // MARK: - Execution & Fallback
    
    private func executeWithFallback(query: String, count: Int) async throws -> ([WebSearchResult], String) {
        var failureReasons: [String] = []
        let deadline = Date().addingTimeInterval(overallSearchDeadline)
        
        // Select order of providers: prioritize healthy ones, but if all on cooldown, try all
        let activeProviders = sortedProvidersByHealth()
        
        for provider in activeProviders {
            let remainingTime = deadline.timeIntervalSince(Date())
            guard remainingTime > 0.5 else {
                failureReasons.append("Overall deadline expired before querying \(provider.displayName)")
                break
            }
            
            let requestTimeout = min(perProviderTimeout, remainingTime)
            let providerStartTime = Date()
            
            do {
                try Task.checkCancellation()
                let results = try await provider.search(query: query, count: count, timeout: requestTimeout)
                let latency = Date().timeIntervalSince(providerStartTime)
                
                let validResults = results.filter { $0.isValid }
                if !validResults.isEmpty {
                    // Mark provider as healthy
                    recordSuccess(providerID: provider.providerID, latency: latency)
                    return (validResults, provider.displayName)
                } else {
                    let reason = "\(provider.displayName): empty or invalid result set"
                    failureReasons.append(reason)
                    recordFailure(providerID: provider.providerID, error: reason, isRateLimit: false)
                }
            } catch is CancellationError {
                throw AutomaticSearchError.cancelled
            } catch let error as AutomaticSearchError {
                let reason = "\(provider.displayName): \(error.localizedDescription)"
                failureReasons.append(reason)
                let isRateLimit: Bool
                switch error {
                case .rateLimited:
                    isRateLimit = true
                default:
                    isRateLimit = false
                }
                recordFailure(providerID: provider.providerID, error: reason, isRateLimit: isRateLimit)
            } catch {
                let reason = "\(provider.displayName): \(error.localizedDescription)"
                failureReasons.append(reason)
                recordFailure(providerID: provider.providerID, error: reason, isRateLimit: false)
            }
        }
        
        throw AutomaticSearchError.allProvidersFailed(reasons: failureReasons)
    }
    
    // MARK: - Health & Circuit Breaking
    
    private func sortedProvidersByHealth() -> [WebSearchProvider] {
        let now = Date()
        return providers.sorted { p1, p2 in
            let h1 = healthTable[p1.providerID] ?? ProviderHealth()
            let h2 = healthTable[p2.providerID] ?? ProviderHealth()
            
            let p1Avail = h1.isAvailable
            let p2Avail = h2.isAvailable
            
            if p1Avail != p2Avail {
                return p1Avail && !p2Avail
            }
            
            // Both available or both unavailable: keep default order (You -> Tavily -> Keenable)
            // or if both unavailable, prefer earliest cooldown
            if !p1Avail && !p2Avail, let c1 = h1.cooldownUntil, let c2 = h2.cooldownUntil {
                return c1 < c2
            }
            return false
        }
    }
    
    private func recordSuccess(providerID: String, latency: TimeInterval) {
        var health = healthTable[providerID] ?? ProviderHealth()
        health.failureCount = 0
        health.cooldownUntil = nil
        health.lastLatency = latency
        health.lastError = nil
        healthTable[providerID] = health
    }
    
    private func recordFailure(providerID: String, error: String, isRateLimit: Bool) {
        var health = healthTable[providerID] ?? ProviderHealth()
        health.failureCount += 1
        health.lastError = error
        
        // Cooldown escalation: rate limits immediately cooldown for at least defaultCooldownDuration
        let multiplier = min(Double(health.failureCount), 5.0)
        let cooldownDuration = isRateLimit ? defaultCooldownDuration * 2 : defaultCooldownDuration * multiplier
        health.cooldownUntil = Date().addingTimeInterval(cooldownDuration)
        
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
    
    private func updateCache(key: String, results: [WebSearchResult], backend: String) {
        if queryCache.count >= maxCacheEntries {
            // Evict expired or oldest entries
            let now = Date()
            queryCache = queryCache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
            if queryCache.count >= maxCacheEntries, let oldestKey = queryCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                queryCache.removeValue(forKey: oldestKey)
            }
        }
        queryCache[key] = CacheEntry(results: results, backend: backend, timestamp: Date())
    }
}
