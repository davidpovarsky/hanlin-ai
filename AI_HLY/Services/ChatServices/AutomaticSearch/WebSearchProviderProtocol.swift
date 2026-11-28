//
//  WebSearchProviderProtocol.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Protocol for isolated web search backend adapters.
public protocol WebSearchProvider: Sendable {
    /// Unique stable identifier for the provider (e.g. "you", "tavily", "keenable").
    var providerID: String { get }
    
    /// User-facing display name for the backend.
    var displayName: String { get }
    
    /// Executes a search query with requested count and bounded timeout.
    func search(query: String, count: Int, timeout: TimeInterval) async throws -> [WebSearchResult]
}

/// Errors thrown by search providers and coordinator.
public enum AutomaticSearchError: LocalizedError, Sendable, Equatable {
    case invalidQuery
    case networkError(String)
    case httpError(statusCode: Int, message: String)
    case rateLimited(retryAfter: TimeInterval?)
    case decodingError(String)
    case emptyResults
    case irrelevantResults(reason: String)
    case providerUnavailable(String)
    case allProvidersOnCooldown(retryAfter: TimeInterval)
    case allProvidersFailed(reasons: [String])
    case cancelled
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is empty or invalid."
        case .networkError(let message):
            return "Network connection error: \(message)"
        case .httpError(let statusCode, let message):
            return "Search provider returned HTTP \(statusCode): \(message)"
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Search rate limit exceeded. Retry after \(Int(retry))s."
            }
            return "Search rate limit exceeded. Please wait a moment."
        case .decodingError(let message):
            return "Failed to decode search response: \(message)"
        case .emptyResults:
            return "No search results were returned."
        case .irrelevantResults(let reason):
            return "Results rejected due to topic mismatch: \(reason)"
        case .providerUnavailable(let provider):
            return "Provider '\(provider)' is temporarily unavailable or on cooldown."
        case .allProvidersOnCooldown(let retryAfter):
            return "All search backends are currently rate-limited. Next available in \(Int(retryAfter))s."
        case .allProvidersFailed(let reasons):
            return "All keyless search backends failed. Details: " + reasons.joined(separator: "; ")
        case .cancelled:
            return "The search task was cancelled."
        case .timeout:
            return "Search request timed out."
        }
    }
}

/// Helper for HTTP headers parsing
public enum HTTPHeaderParser {
    /// Parses Retry-After header supporting both delta-seconds ("120") and HTTP-date ("Wed, 21 Oct 2026 07:28:00 GMT").
    public static func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !header.isEmpty else {
            return nil
        }
        
        // 1. Try delta-seconds
        if let seconds = Double(header), seconds >= 0 {
            return min(seconds, 3600.0) // Sane bound: max 1 hour
        }
        
        // 2. Try HTTP-date (RFC 7231 / RFC 2822 / RFC 850)
        let formatters: [DateFormatter] = [
            {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                return df
            }(),
            {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "EEEE, dd-MMM-yy HH:mm:ss zzz"
                return df
            }(),
            {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "EEE MMM d HH:mm:ss yyyy"
                return df
            }()
        ]
        
        for df in formatters {
            if let date = df.date(from: header) {
                let interval = date.timeIntervalSince(Date())
                return interval > 0 ? min(interval, 3600.0) : 1.0
            }
        }
        
        return nil
    }
}
